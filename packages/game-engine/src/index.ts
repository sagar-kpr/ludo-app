import { SAFE_CELLS, trackIndex } from './board';
export type Color = 'coral' | 'sun' | 'mint' | 'violet';
export type Token = { id: string; color: Color; position: number };
export type Player = { id: string; name: string; color: Color; ready: boolean };
export type GameState = {
  players: Player[];
  tokens: Token[];
  currentPlayer: string;
  dice: number | null;
  phase: 'lobby' | 'rolling' | 'moving' | 'finished';
  winner?: string;
  version: number;
};

export const COLORS: Color[] = ['coral', 'sun', 'mint', 'violet'];
export const PATH_LENGTH = 57;
export const HOME = 58;

export function createGame(players: Player[]): GameState {
  const active = players.slice(0, 4);
  return {
    players: active,
    tokens: active.flatMap((player) => [0, 1, 2, 3].map((n) => ({ id: `${player.id}-${n}`, color: player.color, position: 0 }))),
    currentPlayer: active[0]?.id ?? '', dice: null, phase: 'lobby', version: 0,
  };
}

export function rollDice(state: GameState, random = Math.random): GameState {
  if (state.phase !== 'rolling') return state;
  const dice = Math.floor(random() * 6) + 1;
  const color = state.players.find((p) => p.id === state.currentPlayer)?.color;
  const movable = state.tokens.some((token) => token.color === color && canMove(token, dice));
  const nextPlayer = state.players[(state.players.findIndex((p) => p.id === state.currentPlayer) + 1) % state.players.length];
  return { ...state, dice: movable ? dice : null, phase: movable ? 'moving' : 'rolling', currentPlayer: movable ? state.currentPlayer : nextPlayer.id, version: state.version + 1 };
}

export function canMove(token: Token, dice: number | null): boolean {
  if (!dice) return false;
  if (token.position === 0) return dice === 6;
  return token.position + dice <= HOME;
}

export function autoMoveToken(state: GameState): Token | undefined {
  if (state.phase !== 'moving' || !state.dice || state.dice === 6) return undefined;
  const color = state.players.find((player) => player.id === state.currentPlayer)?.color;
  const legal = state.tokens.filter((token) => token.color === color && canMove(token, state.dice));
  return legal.length === 1 ? legal[0] : undefined;
}

export function moveToken(state: GameState, tokenId: string): GameState {
  if (state.phase !== 'moving' || !state.dice) return state;
  const token = state.tokens.find((item) => item.id === tokenId);
  if (!token || token.color !== state.players.find((p) => p.id === state.currentPlayer)?.color || !canMove(token, state.dice)) return state;
  const nextPosition = token.position === 0 ? 1 : token.position + state.dice;
  const destination = trackIndex({ ...token, position: nextPosition });
  let captured = false;
  const tokens = state.tokens.map((item) => {
    if (item.id === tokenId) return { ...item, position: nextPosition };
    if (destination !== null && !SAFE_CELLS.includes(destination) && item.color !== token.color && trackIndex(item) === destination) {
      captured = true;
      return { ...item, position: 0 };
    }
    return item;
  });
  const won = tokens.filter((item) => item.color === token.color && item.position === HOME).length === 4;
  const rolledSix = state.dice === 6;
  const currentIndex = state.players.findIndex((p) => p.id === state.currentPlayer);
  const nextPlayer = state.players[(currentIndex + 1) % state.players.length];
  return { ...state, tokens, dice: null, phase: won ? 'finished' : 'rolling', winner: won ? state.currentPlayer : undefined, currentPlayer: rolledSix || captured || nextPosition === HOME || won ? state.currentPlayer : nextPlayer.id, version: state.version + 1 };
}

export function startGame(state: GameState): GameState {
  if (state.players.length < 2 || state.phase !== 'lobby') return state;
  return { ...state, phase: 'rolling', version: state.version + 1 };
}
