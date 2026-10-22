import { expect, it } from 'vitest';
import { canMove, createGame, HOME, moveToken, restartGame, rollDice, startGame, type GameState } from '../../../packages/game-engine/src/index';
import { chooseComputerToken } from './computer-player';

function moving(dice: number, positions: number[]): GameState {
  const state = startGame(createGame([
    { id: 'human', name: 'Human', color: 'coral', ready: true },
    { id: 'cpu', name: 'Computer', color: 'mint', ready: true, isComputer: true },
  ]));
  return { ...state, currentPlayer: 'cpu', phase: 'moving', dice,
    tokens: state.tokens.map(token => token.color === 'mint' ? { ...token, position: positions[Number(token.id.at(-1))] } : token) };
}

it('chooses only a legal pawn belonging to the current player without mutating state', () => {
  const state = moving(2, [56, 2, 4, HOME]);
  const before = structuredClone(state);
  const token = chooseComputerToken(state)!;
  expect(token.color).toBe('mint');
  expect(token.id).toBe('cpu-2'); // First overshoots; second would stack with the third.
  expect(canMove(token, state.dice, state.tokens)).toBe(true);
  expect(state).toEqual(before);
});

it('prioritizes an exact finish over a capture', () => {
  const state = moving(3, [54, 1, 0, 0]);
  state.tokens[0].position = 30;
  expect(chooseComputerToken(state)?.id).toBe('cpu-0');
});

it('captures when there is no finishing move', () => {
  const state = moving(2, [1, 10, 0, 0]);
  state.tokens[0].position = 29;
  const token = chooseComputerToken(state)!;
  expect(token.id).toBe('cpu-0');
  expect(moveToken(state, token.id).tokens[0].position).toBe(0);
});

it('can prefer a safe star to an ordinary advance', () => {
  expect(chooseComputerToken(moving(3, [6, 15, 0, 0]))?.id).toBe('cpu-0');
});

it('makes no move outside the moving phase or when all pawns are blocked', () => {
  expect(chooseComputerToken(moving(3, [0, 0, 0, 0]))).toBeUndefined();
  expect(chooseComputerToken({ ...moving(6, [0, 0, 0, 0]), phase: 'rolling' })).toBeUndefined();
});

it('completes legal games with the existing dice, captures, wins and restart rules', () => {
  for (const seed of [7, 47, 121]) {
    let randomState = seed;
    const random = () => { randomState = (Math.imul(randomState, 1664525) + 1013904223) >>> 0; return randomState / 2 ** 32; };
    let state = startGame(createGame([
      { id: 'human', name: 'Human', color: 'coral', ready: true },
      { id: 'cpu', name: 'Computer', color: 'mint', ready: true, isComputer: true },
    ]));
    for (let action = 0; action < 5000 && state.phase !== 'finished'; action++) {
      if (state.phase === 'rolling') state = rollDice(state, random);
      else {
        const token = chooseComputerToken(state)!;
        expect(token).toBeDefined();
        expect(canMove(token, state.dice, state.tokens)).toBe(true);
        state = moveToken(state, token.id);
      }
      expect(Object.values(state.consecutiveSixes ?? {}).every(count => count <= 2)).toBe(true);
      expect(state.tokens.every(token => token.position >= 0 && token.position <= HOME)).toBe(true);
      expect(state.timeoutLives).toEqual({ human: 5, cpu: 5 });
    }
    expect(state.phase).toBe('finished');
    const winner = state.players.find(player => player.id === state.winner)!;
    expect(state.tokens.filter(token => token.color === winner.color).every(token => token.position === HOME)).toBe(true);
    const restarted = restartGame(state);
    expect(restarted.phase).toBe('rolling');
    expect(restarted.tokens.every(token => token.position === 0)).toBe(true);
    expect(restarted.players[1].isComputer).toBe(true);
  }
});
