export type Color = 'coral' | 'sun' | 'mint' | 'violet';
export type Token = { id: string; color: Color; position: number };
export type Player = { id: string; name: string; color: Color; ready: boolean };
export type GameState = {
  players: Player[];
  departedPlayers?: Player[];
  tokens: Token[];
  currentPlayer: string;
  dice: number | null;
  timeoutLives?: Record<string, number>;
  consecutiveSixes?: Record<string, number>;
  phase: 'lobby' | 'rolling' | 'moving' | 'finished';
  winner?: string;
  finishOrder?: string[];
  version: number;
};

export const MAX_TIMEOUT_LIVES = 5;
export const COLORS: Color[] = ['coral', 'sun', 'mint', 'violet'];
// 1–51: shared track; 52–56: home lane; 57: colored center triangle.
export const PATH_LENGTH = 56;
export const HOME = 57;
