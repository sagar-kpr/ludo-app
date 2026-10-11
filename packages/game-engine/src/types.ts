export type Color = 'coral' | 'sun' | 'mint' | 'violet';
export type Token = { id: string; color: Color; position: number };
export type Player = { id: string; name: string; color: Color; ready: boolean };
export type GameState = {
  players: Player[];
  tokens: Token[];
  currentPlayer: string;
  dice: number | null;
  phase: 'lobby' | 'rolling' | 'moving' | 'finished';
  winner?: string;
  finishOrder?: string[];
  version: number;
};

export const COLORS: Color[] = ['coral', 'sun', 'mint', 'violet'];
export const PATH_LENGTH = 57;
export const HOME = 58;
