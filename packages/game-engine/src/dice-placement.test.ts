import { describe, expect, it } from 'vitest';
import { COLORS, HOME, canMove, createGame, diceValuesForRoll, rollDice, startGame, type GameState } from './index';
import { turnTimeoutAction } from '../../../apps/game-server/src/turn-clock';
import { SAFE_CELLS, trackIndex } from './board';

const players = COLORS.map((color,index) => ({id:String(index),name:color,color,ready:true}));
function fixture(seat: number, positions: number[]): GameState {
  const state = startGame(createGame(players));
  return {...state,currentPlayer:String(seat),tokens:state.tokens.map(token => token.color === players[seat].color
    ? {...token,position:positions[Number(token.id.split('-')[1])]} : token)};
}

describe('placement-aware dice candidates', () => {
  it('excludes yellow six when an active pawn would hit another yellow pawn', () => {
    const state = fixture(2,[0,1,7,9]);
    expect(canMove(state.tokens[8],6,state.tokens)).toBe(true); // Base entry is safe.
    expect(canMove(state.tokens[9],6,state.tokens)).toBe(false);
    expect(diceValuesForRoll(state)).not.toContain(6);
  });
  it('excludes red four even if a different red pawn could use it', () => {
    const state = fixture(0,[0,7,11,HOME]);
    expect(canMove(state.tokens[1],4,state.tokens)).toBe(false);
    expect(canMove(state.tokens[2],4,state.tokens)).toBe(true);
    expect(diceValuesForRoll(state)).not.toContain(4);
  });
  for (const [seat,color] of COLORS.entries()) {
    it(`${color}: checks every destination while preserving star stacking and finish docks`, () => {
      for(let from=1;from<HOME;from++) for(let value=1;value<=6;value++) {
        const destination=from+value;
        if(destination>HOME)continue;
        const state=fixture(seat,[from,destination,HOME,HOME]);
        const token=state.tokens[seat*4];
        const square=trackIndex({...token,position:destination});
        const safe=destination===HOME || (square!==null && SAFE_CELLS.includes(square));
        expect(diceValuesForRoll(state).includes(value)).toBe(safe);
      }
    });
  }
  it('does not mistake passing, waiting in base, or opponents for friendly clashes', () => {
    expect(diceValuesForRoll(fixture(0,[0,0,0,0]))).toEqual([1,2,3,4,5,6]);
    expect(diceValuesForRoll(fixture(0,[1,3,HOME,HOME]))).toContain(4);
    const state=fixture(0,[2,HOME,HOME,HOME]);
    state.tokens[4].position=44;
    expect(diceValuesForRoll(state)).toContain(3); // Enemy capture remains valid.
  });
  it('never restores a third six when the placement filter removes other values', () => {
    const state=fixture(0,[2,3,5,7]);
    expect(diceValuesForRoll(state)).toEqual([6]);
    state.consecutiveSixes={0:2};
    expect(diceValuesForRoll(state)).toEqual([]);
  });
  it('selects every permitted face with equal-size buckets and never returns an excluded face', () => {
    const state=fixture(0,[0,7,11,HOME]);
    const values=diceValuesForRoll(state);
    for(const [index,value] of values.entries()) {
      for(const fraction of [0.01,0.5,0.99]) {
        const rolled=rollDice(state,()=> (index+fraction)/values.length);
        expect(rolled.dice).toBe(value);
      }
    }
  });
  it('passes an entirely blocked turn without rolling a forbidden face or changing the streak', () => {
    const state=fixture(0,[2,3,6,8]);
    state.consecutiveSixes={0:2};
    const rolled=rollDice(state,()=> {throw new Error('No random draw is needed');});
    expect(rolled.currentPlayer).toBe('1');
    expect(rolled.phase).toBe('rolling');
    expect(rolled.dice).toBeNull();
    expect(rolled.consecutiveSixes).toEqual(state.consecutiveSixes);
    expect(rolled.tokens).toEqual(state.tokens);
    expect(rolled.version).toBe(state.version+1);
    const timeout=turnTimeoutAction(state);
    expect(timeout).toEqual({type:'pass',state:rolled});
    expect(rolled.timeoutLives).toEqual(state.timeoutLives);
  });
  it('detects a board where every dice value would cause a friendly clash', () => {
    expect(diceValuesForRoll(fixture(0,[2,3,6,8]))).toEqual([]);
  });
});
