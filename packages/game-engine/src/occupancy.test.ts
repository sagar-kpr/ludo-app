import { describe, expect, it } from 'vitest';
import { COLORS, HOME, autoMoveToken, canMove, createGame, moveToken, rollDice, startGame, type GameState } from './index';
import { SAFE_CELLS, trackIndex } from './board';
import { turnTimeoutAction } from '../../../apps/game-server/src/turn-clock';

const players = COLORS.map((color, index) => ({ id: String(index), name: color, color, ready: true }));
function fixture(seat: number, positions: number[], dice: number): GameState {
  const state = startGame(createGame(players));
  return { ...state, currentPlayer: String(seat), phase: 'moving', dice,
    tokens: state.tokens.map(token => token.color === players[seat].color
      ? { ...token, position: positions[Number(token.id.split('-')[1])] } : token) };
}

describe('same-player occupancy and exact finishing', () => {
  for (const [seat, color] of COLORS.entries()) {
    it(`${color}: automatically moves one of the only two pawns sharing a safe star, including on six`, () => {
      for (let position = 1; position <= 51; position++) {
        const square = trackIndex({ id: 'probe', color, position });
        if (square === null || !SAFE_CELLS.includes(square)) continue;
        for (let dice = 1; dice <= 6; dice++) {
          const state = fixture(seat, [position, position, HOME, HOME], dice);
          const selected = autoMoveToken(state)!;
          expect(selected.id).toBe(`${seat}-0`);
          const moved = moveToken(state, selected.id);
          expect(moved.tokens.filter(token => token.color === color && token.position === position)).toHaveLength(1);
          expect(moved.tokens.find(token => token.id === selected.id)?.position).toBe(position + dice);
        }
      }
    });
    it(`${color}: preserves choices when a base pawn or another position can also move`, () => {
      expect(autoMoveToken(fixture(seat, [1, 1, 0, HOME], 6))).toBeUndefined();
      expect(autoMoveToken(fixture(seat, [1, 1, 10, HOME], 6))).toBeUndefined();
      expect(autoMoveToken(fixture(seat, [1, 1, 9, 9], 6))).toBeUndefined();
      // Malformed ordinary-tile stacks do not gain the star-only shortcut.
      expect(autoMoveToken(fixture(seat, [2, 2, HOME, HOME], 6))).toBeUndefined();
    });
    it(`${color}: rejects every non-star occupied destination and permits star squares and finish docks`, () => {
      for (let position = 1; position < HOME; position++) {
        for (let dice = 1; dice <= 6; dice++) {
          const destination = position + dice;
          if (destination > HOME) continue;
          const state = fixture(seat, [position, destination, HOME, HOME], dice);
          const token = state.tokens.find(t => t.id === `${seat}-0`)!;
          const square = trackIndex({ ...token, position: destination });
          const allowed = destination === HOME || (square !== null && SAFE_CELLS.includes(square));
          expect(canMove(token, dice, state.tokens)).toBe(allowed);
          if (allowed) expect(moveToken(state, token.id).tokens.find(t => t.id === token.id)?.position).toBe(destination);
          else expect(moveToken(state, token.id)).toBe(state);
        }
      }
    });
    it(`${color}: never highlights or auto-selects an overshoot (needs three, rolled five)`, () => {
      const state = fixture(seat, [HOME - 3, HOME, HOME, HOME], 5);
      const token = state.tokens.find(t => t.id === `${seat}-0`)!;
      expect(canMove(token, 5, state.tokens)).toBe(false);
      expect(autoMoveToken(state)).toBeUndefined();
      expect(moveToken(state, token.id)).toBe(state);
      expect(turnTimeoutAction(state)?.type).toBe('pass');
      const rolled = rollDice({ ...state, phase: 'rolling', dice: null }, () => 4 / 6);
      expect(rolled.phase).toBe('rolling');
      expect(rolled.currentPlayer).not.toBe(String(seat));
      expect(rolled.tokens).toEqual(state.tokens);
      expect(moveToken({ ...state, dice: 3 }, token.id).tokens.find(t => t.id === token.id)?.position).toBe(HOME);
    });
  }
  it('excludes a blocked pawn from automatic and timeout choices', () => {
    const state = fixture(0, [2, 5, HOME, HOME], 3);
    expect(autoMoveToken(state)?.id).toBe('0-1');
    for (const random of [0, 0.5, 0.99999]) expect(turnTimeoutAction(state, () => random)).toEqual({ type: 'move', tokenId: '0-1' });
  });
  it('excludes a home-lane clash before rolling and still blocks that move directly', () => {
    const state = fixture(0, [HOME - 3, HOME - 1, HOME, HOME], 2);
    const rolled = rollDice({ ...state, phase: 'rolling', dice: null }, () => 1 / 6);
    expect(rolled.dice).not.toBe(2);
    expect(rolled.currentPlayer).toBe('0');
    expect(rolled.phase).toBe('moving');
    expect(autoMoveToken(state)).toBeUndefined();
    expect(turnTimeoutAction(state)?.type).toBe('pass');
  });
  it('allows star entry from base and movement past a friendly pawn', () => {
    const entry = fixture(0, [0, 1, HOME, HOME], 6);
    expect(canMove(entry.tokens[0], 6, entry.tokens)).toBe(true);
    const passing = fixture(0, [1, 3, HOME, HOME], 4);
    expect(canMove(passing.tokens[0], 4, passing.tokens)).toBe(true);
  });
  it('keeps opponent capture on non-star squares', () => {
    const state = fixture(0, [2, HOME, HOME, HOME], 3);
    state.tokens = state.tokens.map(token => token.id === '1-0' ? { ...token, position: 44 } : token);
    expect(trackIndex(state.tokens[4])).toBe(4);
    const next = moveToken(state, '0-0');
    expect(next.tokens[0].position).toBe(5);
    expect(next.tokens[4].position).toBe(0);
    expect(next.currentPlayer).toBe('0');
  });
});
