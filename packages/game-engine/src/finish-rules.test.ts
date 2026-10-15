import { describe, expect, it } from 'vitest';
import { COLORS, HOME, autoMoveToken, canMove, createGame, moveToken, rollDice, startGame, type GameState } from './index';

const players = COLORS.map((color, index) => ({id: String(index), name: color, color, ready: true}));
function fixture(seat: number, positions: number[]): GameState {
  const state = startGame(createGame(players));
  return {...state, currentPlayer: players[seat].id, tokens: state.tokens.map(token => token.color === players[seat].color ? {...token, position: positions[Number(token.id.split('-')[1])]} : token)};
}

describe('exact finish and automatic movement', () => {
  for (const [seat, color] of COLORS.entries()) {
    it(`${color}: accepts only the available distance and rejects overshoots without consuming the turn`, () => {
      for (const distance of [1,2,3,4,5,6]) {
        const state = fixture(seat, [HOME-distance, HOME, HOME, HOME]);
        const token = state.tokens.find(token => token.id === `${seat}-0`)!;
        for (const dice of [1,2,3,4,5,6]) {
          expect(canMove(token, dice)).toBe(dice <= distance);
          const rolled = rollDice(state, () => (dice-1)/6);
          if (dice > distance) {
            expect(rolled.phase).toBe('rolling');
            expect(rolled.currentPlayer).toBe(players[(seat+1)%4].id);
            expect(rolled.dice).toBeNull();
            expect(rolled.tokens).toEqual(state.tokens);
            const malicious = {...state, phase:'moving' as const, dice};
            expect(moveToken(malicious, token.id)).toBe(malicious);
          } else {
            expect(autoMoveToken(rolled)?.id).toBe(token.id);
            expect(moveToken(rolled, token.id).tokens.find(t => t.id === token.id)?.position).toBe(HOME-distance+dice);
          }
        }
      }
    });
    it(`${color}: finishing each of the first three pawns returns the turn, including automatic finishes`, () => {
      for (let completed=0; completed<3; completed++) {
        for (const dice of [1,2,3,4,5,6]) {
          const positions = Array.from({length:4}, (_,index) => index < completed ? HOME : index === completed ? HOME-dice : 0);
          const state = fixture(seat, positions);
          const rolled = rollDice(state, () => (dice-1)/6);
          const id = `${seat}-${completed}`;
          if (dice !== 6) expect(autoMoveToken(rolled)?.id).toBe(id);
          const next = moveToken(rolled, id);
          expect(next.tokens.find(token => token.id === id)?.position).toBe(HOME);
          expect(next.currentPlayer).toBe(state.currentPlayer);
          expect(next.phase).toBe('rolling');
          expect(next.dice).toBeNull();
          expect(next.finishOrder).not.toContain(state.currentPlayer);
          expect(next.version).toBe(state.version+2);
        }
      }
    });
    it(`${color}: automatically advances its sole remaining pawn on every legal roll, including six`, () => {
      const state = fixture(seat, [20, HOME, HOME, HOME]);
      for (const dice of [1,2,3,4,5,6]) {
        const rolled = rollDice(state, () => (dice-1)/6);
        expect(autoMoveToken(rolled)?.id).toBe(`${seat}-0`);
      }
      const last = fixture(seat, [HOME-2, HOME, HOME, HOME]);
      const next = moveToken(rollDice(last, () => 1/6), `${seat}-0`);
      expect(next.finishOrder).toEqual([String(seat)]);
      expect(next.currentPlayer).toBe(players[(seat+1)%4].id);
    });
  }
  it('counts only legal choices, including base entry and overshoot restrictions', () => {
    expect(autoMoveToken(rollDice(fixture(0, [0,HOME,HOME,HOME]), () => 5/6))?.id).toBe('0-0');
    expect(autoMoveToken(rollDice(fixture(0, [10,HOME-2,HOME,HOME]), () => 3/6))?.id).toBe('0-0');
    expect(autoMoveToken(rollDice(fixture(0, [10,0,HOME,HOME]), () => 5/6))).toBeUndefined();
    expect(autoMoveToken(rollDice(fixture(0, [10,11,HOME,HOME]), () => 2/6))).toBeUndefined();
  });
});
