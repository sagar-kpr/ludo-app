import { expect, it } from 'vitest';
import { HOME, createGame, startGame, rollDice, moveToken, canMove } from '../../../packages/game-engine/src/index';
import { turnTimeoutAction } from './turn-clock';
const players = [{id:'a',name:'A',color:'coral' as const,ready:true},{id:'b',name:'B',color:'sun' as const,ready:true}];
it('requests a roll instead of skipping an unrolled turn', () => {
  const before = startGame(createGame(players));
  expect(turnTimeoutAction(before)).toEqual({type:'roll'});
  expect(before.tokens.every(token => token.position === 0)).toBe(true);
});
it('chooses a valid random pawn for every selection bucket', () => {
  const before = rollDice(startGame(createGame(players)),()=>5/6);
  for (let index=0; index<4; index++) {
    expect(turnTimeoutAction(before, () => (index+0.5)/4)).toEqual({type:'move',tokenId:`a-${index}`});
  }
});
it('filters completed, overshooting, base-blocked and opponent pawns before choosing', () => {
  const state = startGame(createGame(players));
  state.phase = 'moving'; state.dice = 3;
  state.tokens = state.tokens.map(token => token.id === 'a-0' ? {...token,position:HOME-2} : token.id === 'a-1' ? {...token,position:HOME} : token.id === 'a-2' ? {...token,position:20} : token.color === 'sun' ? {...token,position:10} : token);
  for (const random of [0,0.4,0.99999]) {
    const action = turnTimeoutAction(state,()=>random);
    expect(action).toEqual({type:'move',tokenId:'a-2'});
    if (action?.type === 'move') expect(canMove(state.tokens.find(token=>token.id === action.tokenId)!,state.dice)).toBe(true);
  }
});
it('passes without moving when no legal choice remains and skips finished players', () => {
  const third = {id:'c',name:'C',color:'mint' as const,ready:true};
  const state = startGame(createGame([...players,third]));
  state.phase = 'moving'; state.dice = 4;
  state.tokens = state.tokens.map(token => token.color === 'sun' ? {...token,position:HOME} : token.id === 'a-0' ? {...token,position:HOME-2} : token);
  const action = turnTimeoutAction(state,()=>{throw new Error('No legal move cannot choose a random pawn');});
  expect(action?.type).toBe('pass');
  if (action?.type !== 'pass') throw new Error('Expected pass');
  expect(action.state.currentPlayer).toBe('c');
  expect(action.state.phase).toBe('rolling');
  expect(action.state.dice).toBeNull();
  expect(action.state.tokens).toEqual(state.tokens);
  expect(action.state.version).toBe(state.version+1);
});
it('uses the normal finish bonus for a timeout-selected move', () => {
  const state = startGame(createGame(players));
  state.phase='moving'; state.dice=2;
  state.tokens[0].position=HOME-2;
  const action = turnTimeoutAction(state,()=>0);
  if (action?.type !== 'move') throw new Error('Expected move');
  const next = moveToken(state,action.tokenId);
  expect(next.tokens[0].position).toBe(HOME);
  expect(next.currentPlayer).toBe('a');
  expect(next.phase).toBe('rolling');
});
it('never acts in a lobby or finished match', () => {
  const lobby = createGame(players);
  expect(turnTimeoutAction(lobby)).toBeUndefined();
  expect(turnTimeoutAction({...lobby,phase:'finished',winner:'a'})).toBeUndefined();
});
