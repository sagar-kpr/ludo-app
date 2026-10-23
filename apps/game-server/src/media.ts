import { AccessToken, RoomServiceClient } from 'livekit-server-sdk';

function configuration() {
  const url = process.env.LIVEKIT_URL?.trim();
  const key = process.env.LIVEKIT_API_KEY?.trim();
  const secret = process.env.LIVEKIT_API_SECRET?.trim();
  if (!url || !key || !secret) throw new Error('Video calls are not configured on this game server yet.');
  const endpoint = new URL(url);
  if (endpoint.username || endpoint.password) throw new Error('Video calls require server-side credentials.');
  if (endpoint.protocol !== 'wss:' && !(endpoint.protocol === 'ws:' && ['localhost', '127.0.0.1', '[::1]'].includes(endpoint.hostname))) {
    throw new Error('Video calls require a secure LiveKit server URL.');
  }
  return { url, key, secret };
}

export const mediaRoomName = (instance: string, roomCode: string) => `rally-${instance}-${roomCode}`;

export async function createMediaToken(instance: string, roomCode: string, player: { id: string; name: string }) {
  const config = configuration();
  const token = new AccessToken(config.key, config.secret, { identity: player.id, name: player.name, ttl: 120 });
  token.addGrant({ roomJoin: true, room: mediaRoomName(instance, roomCode), canPublish: true, canSubscribe: true, canPublishData: false });
  return { url: config.url, token: await token.toJwt(), identity: player.id, roomCode };
}

export async function removeMediaParticipant(instance: string, roomCode: string, playerId: string) {
  try {
    const config = configuration();
    const service = new RoomServiceClient(config.url.replace(/^ws/, 'http'), config.key, config.secret);
    await service.removeParticipant(mediaRoomName(instance, roomCode), playerId);
  } catch {
    // A player may never have joined media. Do not expose credentials or SDK URLs.
  }
}
