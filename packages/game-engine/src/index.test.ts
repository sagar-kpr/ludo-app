import { describe, expect, it } from 'vitest';
import { autoMoveToken, canMove, createGame, moveToken, rollDice, startGame, removePlayer, COLORS, HOME } from './index';
import { tokenCoordinate } from './board';

const players = [
  { id: 'a', name: 'You', color: 'coral' as const, ready: true },
  { id: 'b', name: 'Maya', color: 'sun' as const, ready: true },
];

describe('ludo engine', () => {
  it('awards the remaining player the match when their opponent leaves', () => {
    const next = removePlayer(startGame(createGame(players)), 'b');
    expect(next.phase).toBe('finished');
    expect(next.winner).toBe('a');
    expect(next.players.map(player => player.id)).toEqual(['a']);
    expect(next.tokens).toHaveLength(4);
    expect(next.tokens.every(token => token.color === 'coral')).toBe(true);
  });
  it('continues a multiplayer match in turn order after the current player leaves', () => {
    const all = [...players, { id: 'c', name: 'Sam', color: 'mint' as const, ready: true }];
    const next = removePlayer(rollDice(startGame(createGame(all)), () => 0.99), 'a');
    expect(next.phase).toBe('rolling');
    expect(next.currentPlayer).toBe('b');
    expect(next.dice).toBeNull();
    expect(next.tokens).toHaveLength(8);
  });
  it('preserves a remaining player’s pending dice and ends when only one unranked player remains', () => {
    const all = [...players, { id: 'c', name: 'Sam', color: 'mint' as const, ready: true }];
    const pending = rollDice(startGame(createGame(all)), () => 0.99);
    expect(removePlayer(pending, 'c').dice).toBe(6);
    const next = removePlayer({ ...pending, finishOrder: ['b'] }, 'c');
    expect(next.phase).toBe('finished');
    expect(next.finishOrder).toEqual(['b', 'a']);
  });
  it('auto-selects exactly one legal token; six still allows a choice when base pawns remain', () => {
    const state = startGame(createGame(players));
    state.tokens[0].position = 10;
    for (const dice of [1,2,3,4,5]) expect(autoMoveToken(rollDice(state, () => (dice-1)/6))?.id).toBe('a-0');
    expect(autoMoveToken(rollDice(state, () => 5/6))).toBeUndefined();
    state.tokens[1].position = 12;
    expect(autoMoveToken(rollDice(state, () => 2/6))).toBeUndefined();
	state.tokens[1].position = 58;
    expect(autoMoveToken(rollDice(state, () => 3/6))?.id).toBe('a-0');
    expect(autoMoveToken(createGame(players))).toBeUndefined();
  });
  it('keeps dice resolution separate from applying the selected move', () => {
    for (const dice of [1,2,3,4,5,6]) {
      const state = startGame(createGame(players));
      state.tokens[0].position = 10;
      const rolled = rollDice(state, () => (dice-1)/6);
      expect(rolled.phase).toBe('moving');
      expect(rolled.tokens[0].position).toBe(10);
      expect(moveToken(rolled, 'a-0').tokens[0].position).toBe(10+dice);
    }
  });
  it('requires a six to leave base', () => {
    expect(canMove({ id: 'a-0', color: 'coral', position: 0 }, 5)).toBe(false);
    expect(canMove({ id: 'a-0', color: 'coral', position: 0 }, 6)).toBe(true);
  });
  it('starts and rolls a deterministic dice', () => {
    const state = rollDice(startGame(createGame(players)), () => 0.99);
    expect(state.dice).toBe(6);
    expect(state.phase).toBe('moving');
  });
  it('moves a token and advances the turn', () => {
    const started = startGame(createGame(players));
    const state = rollDice({ ...started, tokens: started.tokens.map((token) => token.id === 'a-0' ? { ...token, position: 1 } : token) }, () => 0.5);
    const next = moveToken(state, 'a-0');
    expect(next.tokens.find((token) => token.id === 'a-0')?.position).toBe(5);
    expect(next.currentPlayer).toBe('b');
  });
  it('automatically passes the turn if no tokens can move', () => {
    const state = rollDice(startGame(createGame(players)), () => 0);
    expect(state.currentPlayer).toBe('b');
    expect(state.phase).toBe('rolling');
    expect(state.dice).toBeNull();
  });
  it('does not restart an active match', () => {
    const state = startGame(createGame(players));
    expect(startGame(state)).toBe(state);
  });
  it('captures opponents on unsafe cells and grants another turn', () => {
    const state = startGame(createGame(players));
    state.phase = 'moving'; state.dice = 1;
    state.tokens = state.tokens.map((t) => t.id === 'a-0' ? { ...t, position: 14 } : t.id === 'b-0' ? { ...t, position: 2 } : t);
    const next = moveToken(state, 'a-0');
    expect(next.tokens.find((t) => t.id === 'b-0')?.position).toBe(0);
    expect(next.currentPlayer).toBe('a');
  });
  it('protects opponents on safe cells', () => {
    const state = startGame(createGame(players));
    state.phase = 'moving'; state.dice = 1;
    state.tokens = state.tokens.map((t) => t.id === 'a-0' ? { ...t, position: 13 } : t.id === 'b-0' ? { ...t, position: 1 } : t);
    expect(moveToken(state, 'a-0').tokens.find((t) => t.id === 'b-0')?.position).toBe(1);
  });
	it('finishes a token on the center endpoint and detects all four finished tokens', () => {
    const state = startGame(createGame(players));
		state.phase = 'moving'; state.dice = 1;
    state.tokens = state.tokens.map((t) => t.color === 'coral' ? { ...t, position: t.id === 'a-0' ? HOME - 1 : HOME } : t);
		const next = moveToken(state, 'a-0');
		expect(next.tokens.find((token) => token.id === 'a-0')?.position).toBe(HOME);
    expect(next.winner).toBe('a');
    expect(next.phase).toBe('finished');
  });
  it.each(COLORS)('finishes %s immediately on its colored center triangle', (color) => {
    const owner = { ...players[0], color };
    const opponent = { ...players[1], color: COLORS.find(candidate => candidate !== color)! };
    const state = startGame(createGame([owner, opponent]));
    state.phase = 'moving'; state.dice = 1;
    state.tokens[0].position = HOME - 1;
    const next = moveToken(state, 'a-0');
    const finished = next.tokens[0];
    expect(finished.position).toBe(57);
    expect(tokenCoordinate(finished, 0)).toEqual([[7,6],[6,7],[7,8],[8,7]][COLORS.indexOf(color)]);
    for (const dice of [1,2,3,4,5,6]) expect(canMove(finished, dice)).toBe(false);
    expect(next.currentPlayer).toBe('a'); // Existing bonus for finishing is retained.
    expect(next.phase).toBe('rolling');
  });
  it('never reactivates a completed pawn when the next dice is one', () => {
    const state = startGame(createGame(players));
    state.phase = 'moving'; state.dice = 1;
    state.tokens[0].position = HOME - 1;
    state.tokens[1].position = 10;
    const completed = moveToken(state, 'a-0');
    const nextRoll = rollDice(completed, () => 0);
    expect(nextRoll.dice).toBe(1);
    expect(nextRoll.phase).toBe('moving');
    expect(autoMoveToken(nextRoll)?.id).toBe('a-1');
    expect(moveToken(nextRoll, 'a-0')).toBe(nextRoll);
    expect(nextRoll.tokens[0].position).toBe(HOME);
  });
  it('passes a roll of one when all other pawns are still in base', () => {
    const state = startGame(createGame(players));
    state.phase = 'moving'; state.dice = 1;
    state.tokens[0].position = HOME - 1;
    const nextRoll = rollDice(moveToken(state, 'a-0'), () => 0);
    expect(nextRoll.currentPlayer).toBe('b');
    expect(nextRoll.phase).toBe('rolling');
    expect(nextRoll.tokens[0].position).toBe(HOME);
  });
  it('keeps legacy position-58 completed pawns terminal', () => {
    const token = { id: 'a-0', color: 'coral' as const, position: 58 };
    expect(canMove(token, 1)).toBe(false);
    expect(tokenCoordinate(token, 0)).toEqual([7,6]);
  });
});
