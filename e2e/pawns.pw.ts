import { test, expect, type Page } from '@playwright/test';
import { tokenCoordinate } from '../packages/game-engine/src/board';

async function trace(page: Page) {
  await page.addInitScript(() => {
    const w = window as any;
    w.gameEvents = [];
    const Socket = window.WebSocket;
    w.WebSocket = class extends Socket {
      constructor(url: string | URL, protocols?: string | string[]) {
        super(url, protocols);
        this.addEventListener('message', (message) => {
          try { w.gameEvents.push(JSON.parse(String(message.data))); } catch { /* not a game event */ }
        });
      }
    };
  });
}
async function latest(page: Page, type: string) {
  return page.evaluate((type) => (window as any).gameEvents.filter((e: any) => e.type === type).at(-1), type);
}

test('Expo home preserves inline name and room joining with the board preview', async ({ page }) => {
  await trace(page);
  await page.goto('http://127.0.0.1:4174');
  await expect(page.getByRole('button', { name: 'Create a new room', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Join room', exact: true })).toBeVisible();
  await expect(page.getByLabel('Room code', { exact: true })).toBeVisible();
  await page.getByLabel('Your display name', { exact: true }).fill('Aria');
  await page.screenshot({ path: 'test-results/home-mobile.png', fullPage: true });
  await page.setViewportSize({ width: 320, height: 800 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({ path: 'test-results/home-small.png', fullPage: true });
  await page.setViewportSize({ width: 1280, height: 900 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({ path: 'test-results/home-desktop.png', fullPage: true });
  await expect(page.getByLabel('Your display name', { exact: true })).toHaveValue('Aria');
  await expect.poll(() => latest(page, 'CONNECTED')).toBeTruthy();
  await page.getByRole('button', { name: 'Create a new room', exact: true }).click();
  await expect.poll(() => latest(page, 'ROOM_CREATED')).toBeTruthy();
  await expect.poll(async () => (await latest(page, 'STATE'))?.state.players[0].name).toBe('Aria');
});

test('Expo and web animate dice and automatically move the only legal pawn except on six', async ({ browser }) => {
  test.setTimeout(60000);
  const web = await browser.newPage();
  const expo = await browser.newPage();
  await trace(web); await trace(expo);
  const errors: string[] = [];
  web.on('pageerror', (e) => errors.push(e.message));
  expo.on('pageerror', (e) => errors.push(e.message));
  await web.goto('http://127.0.0.1:4173');
  await expo.goto('http://127.0.0.1:4174');
  await expect.poll(() => latest(web, 'CONNECTED')).toBeTruthy();
  await expect.poll(() => latest(expo, 'CONNECTED')).toBeTruthy();
  await web.getByRole('button', { name: /Create a room/ }).click();
  await expect.poll(() => latest(web, 'ROOM_CREATED')).toBeTruthy();
  const code = (await latest(web, 'ROOM_CREATED')).roomCode;
  await expo.getByLabel('Your display name', { exact: true }).fill('Maya');
  await expo.getByLabel('Room code', { exact: true }).fill(code);
  await expo.getByRole('button', { name: 'Join room', exact: true }).click();
  await expect.poll(() => latest(expo, 'ROOM_JOINED')).toBeTruthy();
  await expect.poll(async () => (await latest(expo, 'STATE'))?.state.players.some((p: any) => p.name === 'Maya')).toBe(true);
  await web.getByRole('button', { name: /Start the game/ }).click();
  await expect.poll(async () => (await latest(expo, 'STATE'))?.state.phase).toBe('rolling');
  const hostId = (await latest(web, 'CONNECTED')).playerId;
  let checked = false;
  for (let attempt = 0; attempt < 80 && !checked; attempt++) {
    const snapshot = await latest(web, 'STATE');
    const state = snapshot.state;
    const active = state.currentPlayer === hostId ? web : expo;
    const color = state.players.find((p: any) => p.id === state.currentPlayer).color;
    const diceButton = active === web ? active.getByRole('button', { name: /ROLL DICE/ }) : active.getByLabel('Roll dice', { exact: true });
    await expect(diceButton).toBeEnabled();
    await diceButton.click();
    await expect.poll(async () => (await latest(web, 'STATE'))?.state.version).toBeGreaterThan(state.version);
    const dice = await latest(web, 'DICE_ROLLED');
    const afterRoll = await latest(web, 'STATE');
    await expect(web.getByRole('img', { name: 'Dice rolling', exact: true })).toBeVisible();
    expect(dice.color).toBe(color);
    await expect(web.locator('.pawn-glow')).toHaveCount(4);
    await expect(expo.locator('[data-testid^="token-glow-"]')).toHaveCount(4);
    const turnColors: Record<string,string> = { coral: 'rgb(255, 110, 115)', sun: 'rgb(255, 191, 75)', mint: 'rgb(85, 216, 181)', violet: 'rgb(145, 117, 255)' };
    await expect.poll(() => web.locator('.dice-button').evaluate((el) => getComputedStyle(el).backgroundColor)).toBe(turnColors[color]);
    await expect.poll(() => expo.getByRole('button', { name: 'Roll dice', exact: true }).evaluate((el) => getComputedStyle(el).backgroundColor)).toBe(turnColors[color]);
    const diceDuration = await web.locator('.real-dice').evaluate((el) => getComputedStyle(el).animationDuration);
    expect(diceDuration).toBe('1.2s');
    if (attempt === 0) {
      await web.screenshot({ path: 'test-results/roll-highlight-web.png', fullPage: true });
      await expo.screenshot({ path: 'test-results/roll-highlight-expo.png', fullPage: true });
    }
    if (dice.automatic || afterRoll.state.phase === 'moving') {
      if (!dice.automatic) expect(afterRoll.state.tokens).toEqual(state.tokens);
      if (dice.value === 6) expect(dice.automatic).toBe(false);
      const tokens = state.tokens.filter((t: any) => t.color === color && (t.position === 0 ? dice.value === 6 : t.position+dice.value <= 58));
      const token = tokens.find((t: any) => t.position > 0) || tokens[0];
      const index = Number(token.id.slice(token.id.lastIndexOf('-')+1));
      if (!dice.automatic) {
        await active.getByLabel(new RegExp('^'+color+' pawn '+(index+1))).click();
        await expect.poll(async () => (await latest(web, 'STATE'))?.state.version).toBeGreaterThan(afterRoll.state.version);
      } else {
        expect(dice.value).not.toBe(6);
        expect(tokens).toHaveLength(1);
      }
      const moved = (await latest(web, 'STATE')).state;
      await expect.poll(async () => (await latest(expo, 'STATE'))?.state.version).toBe(moved.version);
      expect((await latest(expo, 'STATE')).state.tokens).toEqual(moved.tokens);
      expect(moved.tokens.find((t: any) => t.id === token.id).position).toBe(token.position === 0 ? 1 : token.position+dice.value);
      if (dice.automatic && token.position > 0 && dice.value > 1) {
        const pawn = web.getByLabel(color+' pawn '+(index+1), { exact: true });
        await expect.poll(() => pawn.evaluate((element) => element.getAnimations().length), { intervals: [50] }).toBeGreaterThan(0);
        const frames = await pawn.evaluate((element) => element.getAnimations().flatMap((animation) => (animation.effect as KeyframeEffect).getKeyframes()));
        expect(frames).toHaveLength(2*dice.value+1);
        expect(frames.some((frame) => String(frame.transform).includes('translateY(-6px)'))).toBe(true);
        await expect(pawn.locator('.pawn-head')).toHaveCount(1);
        await expect(web.getByRole('img', { name: 'Dice shows '+dice.value, exact: true })).toBeVisible();
        await expect(web.locator('.real-dice .dice-pip')).toHaveCount(dice.value);
        await expect(expo.getByLabel('Dice shows '+dice.value, { exact: true })).toBeVisible();
        const targetToken = moved.tokens.find((t: any) => t.id === token.id);
        const [row,col] = tokenCoordinate(targetToken, index);
        const nativePawn = expo.getByLabel(color+' pawn '+(index+1), { exact: true });
        await expect.poll(() => nativePawn.evaluate((element, target) => {
          const box = element.getBoundingClientRect();
          const board = element.parentElement!.parentElement!.getBoundingClientRect();
          const cell = box.width;
          const offset = (target.index%2)*cell*.12;
          return Math.abs(box.x-(board.x+target.col*cell+offset)) < 2 && Math.abs(box.y-(board.y+target.row*cell+offset)) < 2;
        }, { row,col,index })).toBe(true);
        await web.screenshot({ path: 'test-results/pawns-web.png', fullPage: true });
        await expo.screenshot({ path: 'test-results/pawns-expo.png', fullPage: true });
        checked = true;
      } else {
        await new Promise((resolve) => setTimeout(resolve, 1100));
      }
    }
  }
  expect(checked).toBe(true);
  expect(errors).toEqual([]);
  await web.close(); await expo.close();
});
