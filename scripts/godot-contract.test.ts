import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';
import { TRACK, SAFE_CELLS, START_OFFSETS } from '../packages/game-engine/src/board';
import { COLORS, HOME } from '../packages/game-engine/src/types';

it('Godot coordinate adapter retains the authoritative engine track and seat order', () => {
  const source = readFileSync('apps/godot/scripts/board_math.gd', 'utf8');
  const track = source.match(/const TRACK = (\[[\s\S]*?\n\])/);
  const colors = source.match(/const COLORS = (\[[^\n]+\])/);
  const offsets = source.match(/const OFFSETS = (\{[^\n]+\})/);
  const safe = source.match(/const SAFE = (\[[^\n]+\])/);
  const home = source.match(/const HOME = (\d+)/);
  expect(JSON.parse(track![1])).toEqual(TRACK);
  expect(JSON.parse(colors![1])).toEqual(COLORS);
  expect(JSON.parse(offsets![1])).toEqual(START_OFFSETS);
  expect(JSON.parse(safe![1])).toEqual(SAFE_CELLS);
  expect(Number(home![1])).toBe(HOME);
});

it('Godot deployment is separate from the existing live Expo configuration', () => {
  const godot = JSON.parse(readFileSync('firebase.godot.json', 'utf8'));
  const current = JSON.parse(readFileSync('firebase.json', 'utf8'));
  expect(godot.hosting.public).toBe('apps/godot/dist');
  expect(current.hosting.public).toBe('apps/mobile/dist');
});
