import assert from 'node:assert/strict';
import test from 'node:test';

import { renderSummary, weeklySummary } from '../src/routes/parent.js';

test('the parent summary never shows anything the athlete wrote', async () => {
  const today = new Date(Date.UTC(2026, 10, 18));
  const game = { date: Date.UTC(2026, 10, 21) / 1000, kind: 'GAME', isHome: true, notes: 'nervous about the coach' };
  const prisma = {
    checkIn: { findMany: async () => [] },
    session: { findMany: async () => [] },
    syncedState: { findMany: async () => [{ key: 'competitions', value: [game] }] },
  };
  const summary = await weeklySummary(prisma, 'a1', today);
  assert.equal(summary.games.length, 1);
  assert.equal('notes' in summary.games[0], false);
  const html = renderSummary(summary);
  assert.match(html, /Coming up/);
  assert.doesNotMatch(html, /nervous/);
});
