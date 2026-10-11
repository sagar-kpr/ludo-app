import { SAFE_CELLS, trackIndex } from './board';
import { HOME, type Token, type Player, type GameState } from './types';
export * from './types';

export function createGame(players: Player[]): GameState {
  const active = players.slice(0, 4);
  return {
    players: active,
    tokens: active.flatMap((player) => [0, 1, 2, 3].map((n) => ({ id: `${player.id}-${n}`, color: player.color, position: 0 }))),
    currentPlayer: active[0]?.id ?? '', dice: null, phase: 'lobby', version: 0, finishOrder: [],
  };
}

export function rollDice(state: GameState, random = Math.random): GameState {
  if (state.phase !== 'rolling') return state;
  const dice = Math.floor(random() * 6) + 1;
  const color = state.players.find((p) => p.id === state.currentPlayer)?.color;
  const movable = state.tokens.some((token) => token.color === color && canMove(token, dice));
  return { ...state, dice: movable ? dice : null, phase: movable ? 'moving' : 'rolling', currentPlayer: movable ? state.currentPlayer : nextUnfinishedPlayer(state), version: state.version + 1 };
}

export function canMove(token: Token, dice: number | null): boolean {
  if (!dice) return false;
	if (token.position >= HOME) return false;
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
  const finishOrder = [...(state.finishOrder ?? [])];
  if (won && !finishOrder.includes(state.currentPlayer)) finishOrder.push(state.currentPlayer);
  const finished = finishOrder.length >= state.players.length - 1;
  if (finished) for (const player of state.players) if (!finishOrder.includes(player.id)) finishOrder.push(player.id);
  const ranked = { ...state, finishOrder };
  return { ...ranked, tokens, dice: null, phase: finished ? 'finished' : 'rolling', winner: finishOrder[0], currentPlayer: finished ? state.currentPlayer : !won && (rolledSix || captured || nextPosition === HOME) ? state.currentPlayer : nextUnfinishedPlayer(ranked), version: state.version + 1 };
}

export function nextUnfinishedPlayer(state: GameState): string {
  const current = state.players.findIndex(player => player.id === state.currentPlayer);
  for (let offset = 1; offset <= state.players.length; offset++) {
    const player = state.players[(current + offset) % state.players.length];
    if (!(state.finishOrder ?? []).includes(player.id)) return player.id;
  }
  return state.currentPlayer;
}

export function restartGame(state: GameState): GameState {
  if (state.phase !== 'finished') return state;
  return { ...createGame(state.players), phase: 'rolling', version: state.version + 1 };
}

export function startGame(state: GameState): GameState {
  if (state.players.length < 2 || state.phase !== 'lobby') return state;
  return { ...state, phase: 'rolling', version: state.version + 1 };
}
