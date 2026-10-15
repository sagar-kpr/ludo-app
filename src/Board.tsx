import React from 'react';
import { Crown } from 'lucide-react';
import { canMove, COLORS, type Color, type GameState, type Token } from '../packages/game-engine/src/index';
import { TRACK, SAFE_CELLS, tokenCoordinate } from '../packages/game-engine/src/board';
import { moveWaypoints, STEP_MS } from '../packages/game-engine/src/motion';

const palette: Record<Color, string> = { coral: '#ff6e73', sun: '#ffbf4b', mint: '#55d8b5', violet: '#9175ff' };
export function Board({ state, onMove, preview = false, connected = false, highlightColor = null }: { state: GameState; onMove?: (id: string) => void; preview?: boolean; connected?: boolean; highlightColor?: Color | null }) {
  const own = state.players.find((p) => p.id === 'you')?.color;
  const square = (row: number, col: number): React.CSSProperties => ({ position: 'absolute', top: row/15*100+'%', left: col/15*100+'%', width: 100/15+'%', height: 100/15+'%' });
  return <div className={preview ? 'preview' : ''} style={{ width: preview ? 300 : '100%', maxWidth: 590, aspectRatio: '1', position: 'relative', background: '#f7f6fc', borderRadius: 15, overflow: 'hidden' }}>
    {COLORS.map((color,i) => <div key={color} style={{ position: 'absolute', top: (i < 2 ? 0 : 60)+'%', left: (i === 0 || i === 3 ? 0 : 60)+'%', width: '40%', height: '40%', background: palette[color], padding: '6.66%' }}><div style={{ width: '100%', height: '100%', background: '#ffffffdd', borderRadius: 15 }} /></div>)}
    {TRACK.map(([row,col],i) => <div key={i} style={{ ...square(row,col), border: '1px solid #ccc', color: '#696079', display: 'grid', placeItems: 'center', background: i%13 === 0 ? palette[COLORS[Math.floor(i/13)]] : '#f7f6fc' }}>{SAFE_CELLS.includes(i) ? '★' : ''}</div>)}
    {COLORS.flatMap((color,i) => [1,2,3,4,5,6].map((n) => <div key={color+n} style={{ ...square(i === 0 || i === 2 ? 7 : i === 1 ? n : 14-n, i === 1 || i === 3 ? 7 : i === 0 ? n : 14-n), background: palette[color], border: '1px solid #ffffff66' }} />))}
    <div style={{ position: 'absolute', top: '40%', left: '40%', width: '20%', height: '20%', background: '#252943', display: 'grid', placeItems: 'center', color: '#ffbf4b' }}><Crown /></div>
    {state.tokens.map((token) => {
      const index = Number(token.id.slice(token.id.lastIndexOf('-')+1));
      const legal = connected && state.currentPlayer === 'you' && token.color === own && state.phase === 'moving' && canMove(token, state.dice, state.tokens);
      return <Pawn key={token.id} token={token} index={index} legal={legal && !preview} highlighted={!preview && token.color === highlightColor && state.phase === 'moving' && canMove(token, state.dice, state.tokens)} onMove={onMove} />;
    })}
  </div>;
}

const Pawn = React.memo(function Pawn({ token, index, legal, highlighted, onMove }: { token: Token; index: number; legal: boolean; highlighted: boolean; onMove?: (id: string) => void }) {
  const [row,col] = tokenCoordinate(token,index);
  const ref = React.useRef<HTMLButtonElement>(null);
  const previous = React.useRef(token.position);
  const queue = React.useRef<{ frames: Keyframe[]; duration: number; target: string }[]>([]);
  const active = React.useRef<Animation | null>(null);
  React.useEffect(() => () => { queue.current = []; active.current?.cancel(); }, []);
  React.useLayoutEffect(() => {
    const from = previous.current;
    previous.current = token.position;
    const element = ref.current;
    if (!element) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      queue.current = []; active.current?.cancel(); active.current = null; return;
    }
    const points = moveWaypoints(token, from, index);
    if (!points.length) return;
    const [startRow,startCol] = tokenCoordinate({ ...token, position: from }, index);
    const frames: Keyframe[] = [{ transform: 'translate('+startCol*100+'%, '+startRow*100+'%)', offset: 0 }];
    let lastRow = startRow, lastCol = startCol;
    points.forEach(([r,c], step) => {
      frames.push({ transform: 'translate('+((lastCol+c)/2)*100+'%, '+((lastRow+r)/2)*100+'%) translateY(-6px)', offset: (step+.5)/points.length, easing: 'ease-in' });
      frames.push({ transform: 'translate('+c*100+'%, '+r*100+'%)', offset: (step+1)/points.length, easing: 'ease-out' });
      lastRow = r; lastCol = c;
    });
    queue.current.push({ frames, duration: points.length*(token.position < from ? 240 : STEP_MS), target: 'translate('+col*100+'%, '+row*100+'%)' });
    const playNext = () => {
      if (active.current) return;
      const move = queue.current.shift();
      if (!move) return;
      const animation = element.animate(move.frames, { duration: move.duration, fill: 'both', easing: 'linear' });
      active.current = animation;
      animation.onfinish = () => {
        element.style.transform = move.target;
        animation.cancel(); active.current = null; playNext();
      };
    };
    playNext();
  }, [token.position,token.color,index,row,col]);
  return <button ref={ref} className={'pawn-hit ' + (legal ? 'pawn-legal' : '')} disabled={!legal} aria-label={token.color + ' pawn ' + (index+1) + (legal ? ', tap to move' : '')} onClick={() => onMove?.(token.id)} style={{ '--pawn-color': palette[token.color], transform: 'translate('+col*100+'%, '+row*100+'%)' } as React.CSSProperties}>
    {highlighted && <span className="pawn-glow" aria-hidden="true" />}
    <span className="pawn-shadow" /><span className="pawn-base" /><span className="pawn-body" /><span className="pawn-head" /><span className="pawn-number">{index+1}</span>
  </button>;
});
