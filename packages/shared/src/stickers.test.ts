import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';
import { EMOTION_STICKERS, STICKERS } from './stickers';

it('keeps every picker reaction in the server-approved catalog', () => {
  const source = readFileSync('apps/godot/scripts/sticker_art.gd', 'utf8');
  const catalog = JSON.parse(source.match(/const CATALOG = (\[[^\n]+\])/)![1]);
  const emotions = JSON.parse(source.match(/const EMOTIONS = (\[[^\n]+\])/)![1]);
  expect(catalog).toEqual(STICKERS);
  expect(emotions).toEqual(EMOTION_STICKERS);
  expect(new Set(STICKERS).size).toBe(24);
});
