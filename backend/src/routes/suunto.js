import express from 'express';

import { requireAuth } from '../lib/requireAuth.js';
import {
  authorizeUrl, exchangeCode, listWorkouts, open, refreshTokens, seal, signState, suuntoConfig, SuuntoError, tokenUser, verifyState,
} from '../lib/suunto.js';

const MAX_DAYS = 14;
const CACHE_MS = 30 * 60_000;

/**
 * The athlete's Suunto account (Cloud API). Only tokens are stored; workouts
 * pass through to the phone and are cached in memory for 30 minutes, because
 * Suunto's developer tier allows very few calls a week.
 *
 *   GET    /suunto/status       → { available, connected }
 *   POST   /suunto/connect      → { url }  the Suunto sign-in page to open
 *   GET    /suunto/callback     Suunto sends the browser here; redirects to athleteos://suunto?connected=1 (or ?error=…)
 *   GET    /suunto/workouts?days=3 → { workouts: [{ start, end, activity, averageHeartRate }] }
 *   DELETE /suunto/connection   forget the Suunto account
 */
export function suuntoRouter({ prisma, sessionSecret, config = suuntoConfig(), fetchImpl = fetch }) {
  const router = express.Router();
  const auth = requireAuth({ sessionSecret });
  const cache = new Map();

  const unavailable = (res) => res.status(503).json({ error: 'suunto_not_available' });

  router.get('/status', auth, async (req, res) => {
    if (!config) {
      res.json({ available: false, connected: false });
      return;
    }
    const link = await prisma.suuntoLink.findUnique({ where: { athleteId: req.athleteId } });
    res.json({ available: true, connected: Boolean(link) });
  });

  router.post('/connect', auth, (req, res) => {
    if (!config) return unavailable(res);
    res.json({ url: authorizeUrl(config, signState(req.athleteId, sessionSecret)) });
  });

  router.get('/callback', async (req, res) => {
    const back = (query) => res.redirect(302, `${config?.appReturn ?? 'athleteos://suunto'}?${query}`);
    if (!config) return back('error=not_available');
    const athleteId = verifyState(req.query.state, sessionSecret);
    if (!athleteId) return back('error=expired');
    if (typeof req.query.code !== 'string' || !req.query.code) return back('error=denied');
    try {
      const tokens = await exchangeCode(config, req.query.code, fetchImpl);
      const suuntoUser = tokenUser(tokens.accessToken) ?? 'unknown';
      const data = {
        suuntoUser,
        accessToken: seal(tokens.accessToken, sessionSecret),
        refreshToken: seal(tokens.refreshToken ?? '', sessionSecret),
        expiresAt: tokens.expiresAt,
      };
      await prisma.suuntoLink.upsert({ where: { athleteId }, create: { athleteId, ...data }, update: data });
      cache.delete(athleteId);
      back('connected=1');
    } catch {
      back('error=failed');
    }
  });

  /** A valid access token, refreshed when it is about to run out. */
  async function accessToken(link) {
    if (link.expiresAt.getTime() - Date.now() > 5 * 60_000) return open(link.accessToken, sessionSecret);
    const refresh = open(link.refreshToken, sessionSecret);
    if (!refresh) throw new SuuntoError('unauthorized', 401);
    const tokens = await refreshTokens(config, refresh, fetchImpl);
    await prisma.suuntoLink.update({
      where: { athleteId: link.athleteId },
      data: {
        accessToken: seal(tokens.accessToken, sessionSecret),
        refreshToken: seal(tokens.refreshToken ?? refresh, sessionSecret),
        expiresAt: tokens.expiresAt,
      },
    });
    return tokens.accessToken;
  }

  router.get('/workouts', auth, async (req, res) => {
    if (!config) return unavailable(res);
    const link = await prisma.suuntoLink.findUnique({ where: { athleteId: req.athleteId } });
    if (!link) {
      res.status(404).json({ error: 'not_connected' });
      return;
    }
    const days = Math.min(MAX_DAYS, Math.max(1, Number.parseInt(req.query.days, 10) || 3));
    const key = `${req.athleteId}|${days}`;
    const hit = cache.get(key);
    if (hit && Date.now() - hit.at < CACHE_MS) {
      res.json({ workouts: hit.workouts });
      return;
    }
    try {
      const since = new Date(Date.now() - days * 86_400_000);
      const workouts = await listWorkouts(config, await accessToken(link), since, fetchImpl);
      cache.set(key, { at: Date.now(), workouts });
      res.json({ workouts });
    } catch (err) {
      if (err instanceof SuuntoError && err.code === 'unauthorized') {
        // Suunto no longer accepts the tokens (revoked in the Suunto app): connect again.
        await prisma.suuntoLink.deleteMany({ where: { athleteId: req.athleteId } });
        res.status(404).json({ error: 'not_connected' });
        return;
      }
      res.status(502).json({ error: 'suunto_unavailable' });
    }
  });

  router.delete('/connection', auth, async (req, res) => {
    await prisma.suuntoLink.deleteMany({ where: { athleteId: req.athleteId } });
    for (const key of cache.keys()) if (key.startsWith(`${req.athleteId}|`)) cache.delete(key);
    res.status(204).end();
  });

  return router;
}
