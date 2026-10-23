import { afterEach, expect, it, vi } from 'vitest';
import { TokenVerifier } from 'livekit-server-sdk';
import { createMediaToken, mediaRoomName } from './media';

afterEach(() => vi.unstubAllEnvs());

it('reports missing media infrastructure without returning any credentials', async () => {
  for (const key of ['LIVEKIT_URL','LIVEKIT_API_KEY','LIVEKIT_API_SECRET']) vi.stubEnv(key,'');
  await expect(createMediaToken('instance','ABCD-1234',{id:'guest_1',name:'Player'})).rejects.toThrow('not configured');
});

it('grants a short-lived, room-scoped identity with no room administration', async () => {
  vi.stubEnv('LIVEKIT_URL','wss://media.example.test');
  vi.stubEnv('LIVEKIT_API_KEY','test-key');
  vi.stubEnv('LIVEKIT_API_SECRET','test-secret-with-at-least-32-characters');
  const result = await createMediaToken('server-one','ABCD-1234',{id:'guest_1',name:'Player'});
  const claims = await new TokenVerifier(process.env.LIVEKIT_API_KEY!,process.env.LIVEKIT_API_SECRET!).verify(result.token);
  expect(claims.sub).toBe('guest_1');
  expect(claims.video).toMatchObject({roomJoin:true,room:mediaRoomName('server-one','ABCD-1234'),canPublish:true,canSubscribe:true,canPublishData:false});
  expect(claims.video?.roomAdmin).not.toBe(true);
  expect(claims.exp! - Math.floor(Date.now()/1000)).toBeLessThanOrEqual(120);
  expect(result).not.toHaveProperty('secret');
  expect(mediaRoomName('server-two','ABCD-1234')).not.toBe(claims.video?.room);
});

it('requires encryption outside localhost development', async () => {
  vi.stubEnv('LIVEKIT_URL','ws://public.example.test');
  vi.stubEnv('LIVEKIT_API_KEY','test-key');
  vi.stubEnv('LIVEKIT_API_SECRET','test-secret');
  await expect(createMediaToken('server','ROOM',{id:'id',name:'Player'})).rejects.toThrow('secure');
});
