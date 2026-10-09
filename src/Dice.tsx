import React from 'react';
import { DICE_FACE_TIMES, DICE_PIPS, DICE_ROLL_MS, DICE_SETTLE_MS } from '../packages/shared/src/dice';
import './dice.css';

export function Dice({ value, rolling }: { value: number | null; rolling: boolean }) {
  const [face,setFace] = React.useState(value || 1);
  React.useEffect(() => {
    if (!rolling || window.matchMedia('(prefers-reduced-motion: reduce)').matches) { setFace(value || 1); return; }
    const timers = DICE_FACE_TIMES.map((time,index) => setTimeout(() => setFace(index%6+1), time));
    timers.push(setTimeout(() => setFace(value || 1), DICE_SETTLE_MS));
    return () => timers.forEach(clearTimeout);
  }, [rolling,value]);
  return <span role="img" aria-label={rolling ? 'Dice rolling' : 'Dice shows '+face} className={'real-dice'+(rolling ? ' rolling' : '')} style={{ animationDuration: DICE_ROLL_MS+'ms' }}>
    {DICE_PIPS[face].map((pip) => <i key={pip} className="dice-pip" style={{ left: 7+pip%3*11, top: 7+Math.floor(pip/3)*11 }} />)}
  </span>;
}
