export const DICE_ROLL_MS = 600;
export const DICE_SETTLE_MS = 490;
export const DICE_FACE_TIMES = [45,100,165,245,340,425];
export const DICE_PIPS: Record<number, number[]> = {
  1: [4], 2: [0,8], 3: [0,4,8], 4: [0,2,6,8], 5: [0,2,4,6,8], 6: [0,2,3,5,6,8],
};

// Hold the board snapshot until the dice settles. The server result is never
// guessed locally, and repeated snapshots during the roll resolve to the latest.
export function createDicePresentation<T extends { type: string }>(onEvent: (event: T) => void, onSettled: () => void) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let snapshot: T | undefined;
  return {
    receive(event: T) {
      if (event.type === 'DICE_ROLLED') {
        if (timer) clearTimeout(timer);
        timer = setTimeout(() => {
          timer = undefined;
          if (snapshot) { const latest = snapshot; snapshot = undefined; onEvent(latest); }
          onSettled();
        }, DICE_ROLL_MS);
      }
      if (event.type === 'STATE' && timer) { snapshot = event; return; }
      onEvent(event);
    },
    dispose() { if (timer) clearTimeout(timer); timer = undefined; snapshot = undefined; },
  };
}
