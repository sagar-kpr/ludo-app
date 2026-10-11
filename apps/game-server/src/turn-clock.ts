import type { GameState } from '../../../packages/game-engine/src/types';
import { nextUnfinishedPlayer } from '../../../packages/game-engine/src/index';

export function expireTurn(state: GameState): GameState {
  if (state.phase === 'lobby' || state.phase === 'finished') return state;
  return { ...state, phase: 'rolling', dice: null, currentPlayer: nextUnfinishedPlayer(state), version: state.version + 1 };
}
