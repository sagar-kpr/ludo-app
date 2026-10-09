import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Player } from '../../../packages/game-engine/src/index';

const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const db: SupabaseClient | null = url && serviceKey ? createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } }) : null;

export function persistenceEnabled() { return Boolean(db); }

export async function persistRoom(roomCode: string, players: Player[], state: unknown) {
  if (!db) return;
  const { data: room, error } = await db.from('rooms').upsert({ code: roomCode, status: (state as { phase?: string }).phase === 'lobby' ? 'lobby' : 'playing', capacity: 4 }, { onConflict: 'code' }).select('id').single();
  if (error || !room) { console.warn('[supabase] room persistence skipped:', error?.message); return; }
  for (const player of players) await db.from('room_members').upsert({ room_id: room.id, display_name: player.name, color: player.color, ready: player.ready }, { onConflict: 'room_id,display_name' });
}

export async function persistChat(roomCode: string, playerId: string, text: string) {
  if (!db) return;
  const { data: room } = await db.from('rooms').select('id').eq('code', roomCode).maybeSingle();
  if (room) await db.from('chat_messages').insert({ room_id: room.id, sender_id: playerId, sender_name: playerId, body: text });
}
