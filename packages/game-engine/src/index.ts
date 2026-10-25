import { SAFE_CELLS, trackIndex } from './board';
import { HOME, MAX_TIMEOUT_LIVES, type Token, type Player, type GameState } from './types';
export * from './types';

export function createGame(players: Player[]): GameState {
  const active = players.slice(0, 4);
  return {
    players: active,
    tokens: active.flatMap((player) => [0, 1, 2, 3].map((n) => ({ id: `${player.id}-${n}`, color: player.color, position: 0 }))),
    currentPlayer: active[0]?.id ?? '', dice: null, phase: 'lobby', version: 0, finishOrder: [], consecutiveSixes: {},
    timeoutLives: Object.fromEntries(active.map(player => [player.id, MAX_TIMEOUT_LIVES])),
  };
}

// Track each player's own rolls independently, including across turn changes.
export function diceSidesForRoll(state: GameState): 5 | 6 {
  return (state.consecutiveSixes?.[state.currentPlayer] ?? 0) >= 2 ? 5 : 6;
}

// A face is excluded if any otherwise eligible pawn would land on a friendly
// pawn outside a safe star. Base entry, exact finishes and passing are unchanged.
export function diceValuesForRoll(state: GameState): number[] {
  const color = state.players.find(player => player.id === state.currentPlayer)?.color;
  const own = state.tokens.filter(token => token.color === color);
  return Array.from({ length: diceSidesForRoll(state) }, (_, index) => index+1)
    .filter(value => !own.some(token => canMove(token, value) && !canMove(token, value, state.tokens)));
}

export function rollDice(state: GameState, random = Math.random): GameState {
  if (state.phase !== 'rolling') return state;
  // Older/recovered rooms may contain terminal pawns without a ranking entry.
  // Preserve recorded ranks and recover only missing finishers from the board.
  const finishOrder = completedOrder(state);
  if (finishOrder.length >= state.players.length - 1) {
    for (const player of state.players) if (!finishOrder.includes(player.id)) finishOrder.push(player.id);
    return { ...state, finishOrder, winner: finishOrder[0], phase: 'finished', dice: null, version: state.version + 1 };
  }
  const ranked = { ...state, finishOrder, winner: finishOrder[0] };
  if (finishOrder.includes(state.currentPlayer)) {
    return { ...ranked, currentPlayer: nextUnfinishedPlayer(ranked), dice: null, version: state.version + 1 };
  }
  const values = diceValuesForRoll(ranked);
  if (!values.length) {
    // No die was rolled: pass without inventing a forbidden face or changing
    // the player's six streak. A later turn can resume after the board changes.
    return { ...ranked, dice: null, phase: 'rolling', currentPlayer: nextUnfinishedPlayer(ranked), version: state.version + 1 };
  }
  const bucket = Math.max(0, Math.min(values.length-1, Math.floor(random()*values.length)));
  const dice = values[bucket];
  const consecutiveSixes = { ...state.consecutiveSixes,
    [state.currentPlayer]: dice === 6 ? (state.consecutiveSixes?.[state.currentPlayer] ?? 0) + 1 : 0 };
  const color = state.players.find((p) => p.id === state.currentPlayer)?.color;
  const movable = state.tokens.some((token) => token.color === color && canMove(token, dice, state.tokens));
  return { ...ranked, consecutiveSixes, dice: movable ? dice : null, phase: movable ? 'moving' : 'rolling', currentPlayer: movable ? state.currentPlayer : nextUnfinishedPlayer(ranked), version: state.version + 1 };
}

function playerCompleted(state: GameState, player: Player): boolean {
  const tokens = state.tokens.filter(token => token.color === player.color);
  return tokens.length === 4 && tokens.every(token => token.position >= HOME);
}

function completedOrder(state: GameState): string[] {
  const order = [...(state.finishOrder ?? [])];
  for (const player of state.players) {
    if (!order.includes(player.id) && playerCompleted(state, player)) order.push(player.id);
  }
  return order;
}

export function canMove(token: Token, dice: number | null, tokens: readonly Token[] = []): boolean {
  if (!dice || !Number.isInteger(dice) || dice < 1 || dice > 6) return false;
  if (token.position >= HOME || (token.position === 0 && dice !== 6)) return false;
  const destination = token.position === 0 ? 1 : token.position + dice;
  if (destination > HOME) return false;
  // Finished pawns have separate docks in the center, outside the playing path.
  if (destination === HOME) return true;
  const square = trackIndex({ ...token, position: destination });
  if (square !== null && SAFE_CELLS.includes(square)) return true;
  return !tokens.some(other => other.id !== token.id && other.color === token.color && other.position === destination);
}

export function autoMoveToken(state: GameState): Token | undefined {
  if (state.phase !== 'moving' || !state.dice) return undefined;
  const color = state.players.find((player) => player.id === state.currentPlayer)?.color;
  const legal = state.tokens.filter((token) => token.color === color && canMove(token, state.dice, state.tokens));
  const first = legal[0];
  if (!first || legal.length === 1) return first;
  // Same-color pawns sharing a safe star are interchangeable. Only skip the
  // choice when every legal move starts there; base entry remains a choice.
  const square = trackIndex(first);
  return square !== null && SAFE_CELLS.includes(square) && legal.every(token => token.position === first.position)
    ? first : undefined;
}

export function moveToken(state: GameState, tokenId: string): GameState {
  if (state.phase !== 'moving' || !state.dice) return state;
  const token = state.tokens.find((item) => item.id === tokenId);
  if (!token || token.color !== state.players.find((p) => p.id === state.currentPlayer)?.color || !canMove(token, state.dice, state.tokens)) return state;
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
  const won = tokens.filter((item) => item.color === token.color && item.position >= HOME).length === 4;
  const rolledSix = state.dice === 6;
  const finishOrder = completedOrder({ ...state, tokens });
  if (won && !finishOrder.includes(state.currentPlayer)) finishOrder.push(state.currentPlayer);
  const finished = finishOrder.length >= state.players.length - 1;
  if (finished) for (const player of state.players) if (!finishOrder.includes(player.id)) finishOrder.push(player.id);
  const ranked = { ...state, finishOrder };
  // A pawn reaching HOME earns another roll; completing all four retires
  // the player instead. This applies equally to automatic and manual moves.
  const bonusTurn = !won && (rolledSix || captured || nextPosition === HOME);
  return { ...ranked, tokens, dice: null, phase: finished ? 'finished' : 'rolling', winner: finishOrder[0], currentPlayer: finished || bonusTurn ? state.currentPlayer : nextUnfinishedPlayer(ranked), version: state.version + 1 };
}

export function nextUnfinishedPlayer(state: GameState): string {
  const current = state.players.findIndex(player => player.id === state.currentPlayer);
  for (let offset = 1; offset <= state.players.length; offset++) {
    const player = state.players[(current + offset) % state.players.length];
    if (!(state.finishOrder ?? []).includes(player.id) && !playerCompleted(state, player)) return player.id;
  }
  return state.currentPlayer;
}

export function restartGame(state: GameState): GameState {
  if (state.phase !== 'finished') return state;
  return { ...createGame(state.players), phase: 'rolling', version: state.version + 1 };
}

export function removePlayer(state: GameState, playerId: string): GameState {
  const departed = state.players.find(player => player.id === playerId);
  if (!departed) return state;
  const players = state.players.filter(player => player.id !== playerId);
  const consecutiveSixes = { ...state.consecutiveSixes };
  delete consecutiveSixes[playerId];
  const tokens = state.tokens.filter(token => token.color !== departed.color);
  const finishOrder = (state.finishOrder ?? []).filter(id => id !== playerId);
  const remaining = players.filter(player => !finishOrder.includes(player.id));
  const finished = state.phase !== 'lobby' && remaining.length <= 1;
  if (finished) finishOrder.push(...remaining.map(player => player.id));
  const index = state.players.findIndex(player => player.id === playerId);
  const following = state.players.slice(index + 1).concat(state.players.slice(0, index));
  const currentPlayer = state.currentPlayer === playerId
    ? (following.find(player => !finishOrder.includes(player.id))?.id ?? players[0]?.id ?? '')
    : state.currentPlayer;
  return { ...state, players, tokens, finishOrder, consecutiveSixes,
    departedPlayers: [...(state.departedPlayers ?? []), departed],
    currentPlayer: finished ? (finishOrder[0] ?? '') : currentPlayer,
    phase: finished ? 'finished' : state.currentPlayer === playerId && state.phase !== 'lobby' ? 'rolling' : state.phase,
    dice: finished || state.currentPlayer === playerId ? null : state.dice,
    winner: finishOrder[0], version: state.version + 1 };
}


export function startGame(state: GameState): GameState {
  if (state.players.length < 2 || state.phase !== 'lobby') return state;
  return { ...state, phase: 'rolling', version: state.version + 1 };
}
