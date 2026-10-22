import { canMove, HOME, moveToken, type GameState, type Token } from '../../../packages/game-engine/src/index';
import { SAFE_CELLS, trackIndex } from '../../../packages/game-engine/src/board';

// Evaluate only legal moves using the real engine. Dice are rolled separately
// by the room's normal cryptographic roll path, never by this decision maker.
export function chooseComputerToken(state: GameState): Token | undefined {
  if (state.phase !== 'moving' || !state.dice) return;
  const color = state.players.find(player => player.id === state.currentPlayer)?.color;
  let best: Token | undefined;
  let bestScore = -Infinity;
  for (const token of state.tokens) {
    if (token.color !== color || !canMove(token, state.dice, state.tokens)) continue;
    const next = moveToken(state, token.id);
    const destination = next.tokens.find(item => item.id === token.id)!;
    const captured = state.tokens.filter(item => item.color !== color && item.position > 0 && next.tokens.find(after => after.id === item.id)?.position === 0);
    const square = trackIndex(destination);
    const safe = square !== null && SAFE_CELLS.includes(square);
    let score = destination.position;
    if (destination.position === HOME) score += 10000;
    score += captured.reduce((total, item) => total + 1000 + item.position * 5, 0);
    if (safe) score += 180;
    if (token.position === 0) score += 100;
    if (destination.position > 51 && destination.position < HOME) score += 220;
    if (square !== null && !safe) {
      for (const opponent of state.tokens) {
        const from = trackIndex(opponent);
        if (opponent.color !== color && from !== null && !captured.some(item => item.id === opponent.id)) {
          const distance = (square - from + 52) % 52;
          if (distance >= 1 && distance <= 6 && canMove(opponent, distance, next.tokens)) score -= 70;
        }
      }
    }
    if (score > bestScore) { best = token; bestScore = score; }
  }
  return best;
}
