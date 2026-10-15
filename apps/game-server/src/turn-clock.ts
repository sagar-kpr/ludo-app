import type { GameState } from '../../../packages/game-engine/src/types';
import { canMove, nextUnfinishedPlayer } from '../../../packages/game-engine/src/index';

export type TimeoutAction = { type: 'roll' } | { type: 'move'; tokenId: string } | { type: 'pass'; state: GameState };

// Choose the action only. The room applies it through the same roll/move
// broadcasters as manual input so everyone receives the normal animations.
export function turnTimeoutAction(state: GameState, random = Math.random): TimeoutAction | undefined {
  if (state.phase === 'rolling') return { type: 'roll' };
  if (state.phase !== 'moving') return undefined;
  const color = state.players.find(player => player.id === state.currentPlayer)?.color;
  const legal = state.tokens.filter(token => token.color === color && canMove(token, state.dice, state.tokens));
  if (legal.length) return { type: 'move', tokenId: legal[Math.floor(random()*legal.length)].id };
  return { type: 'pass', state: { ...state, phase: 'rolling', dice: null, currentPlayer: nextUnfinishedPlayer(state), version: state.version + 1 } };
}
