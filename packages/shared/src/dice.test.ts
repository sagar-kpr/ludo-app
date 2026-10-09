import { afterEach, expect, it, vi } from 'vitest';
import { createDicePresentation, DICE_PIPS, DICE_ROLL_MS } from './dice';
afterEach(() => vi.useRealTimers());
it('renders the correct number of distinct dots on each dice face', () => {
  for (const face of [1,2,3,4,5,6]) expect(new Set(DICE_PIPS[face]).size).toBe(face);
});
it('settles the dice before presenting the latest board snapshot', () => {
  vi.useFakeTimers();
  const seen: unknown[] = [];
  const settled = vi.fn();
  const presentation = createDicePresentation<{ type: string; version?: number }>((event) => seen.push(event), settled);
  presentation.receive({ type: 'DICE_ROLLED' });
  presentation.receive({ type: 'STATE', version: 1 });
  presentation.receive({ type: 'STATE', version: 2 });
  expect(seen).toEqual([{ type: 'DICE_ROLLED' }]);
  vi.advanceTimersByTime(DICE_ROLL_MS);
  expect(seen).toEqual([{ type: 'DICE_ROLLED' }, { type: 'STATE', version: 2 }]);
  expect(settled).toHaveBeenCalledOnce();
  presentation.dispose();
});
