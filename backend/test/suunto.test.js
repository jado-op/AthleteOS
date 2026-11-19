import assert from 'node:assert/strict';
import test from 'node:test';

import { createApp } from '../src/app.js';
import { signSessionToken } from '../src/lib/sessionToken.js';
import { mapNight, mapWorkout, open, seal, signState, tokenUser, verifyState } from '../src/lib/suunto.js';

const SESSION_SECRET = 'test-session-secret';
const CONFIG = { clientId: 'cid', clientSecret: 'csecret', subscriptionKey: 'skey', redirectUri: 'https://api.example/suunto/callback', appReturn: 'athleteos://suunto' };

function jwt(payload) {
  return `x.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.y`;
}

function fakePrisma() {
  const rows = [];
  return {
    rows,
    suuntoLink: {
      async findUnique({ where }) { return rows.find((r) => r.athleteId === where.athleteId) ?? null; },
      async upsert({ where, create, update }) {
        const row = rows.find((r) => r.athleteId === where.athleteId);
        if (row) Object.assign(row, update); else rows.push({ ...create });
      },
      async update({ where, data }) { Object.assign(rows.find((r) => r.athleteId === where.athleteId), data); },
      async deleteMany({ where }) {
        const before = rows.length;
        for (let i = rows.length - 1; i >= 0; i -= 1) if (rows[i].athleteId === where.athleteId) rows.splice(i, 1);
        return { count: before - rows.length };
      },
    },
  };
}

/** Suunto's two hosts, faked. */
function fakeSuunto() {
  const calls = [];
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const u = new URL(String(url));
    if (u.pathname === '/oauth/token') {
      const fresh = u.searchParams.get('grant_type') === 'refresh_token';
      return Response.json({ access_token: jwt({ user: 'skier1', fresh }), refresh_token: 'r2', expires_in: 86400, user: 'skier1' });
    }
    if (u.pathname === '/oauth/deauthorize') return new Response(null, { status: 200 });
    if (u.origin + u.pathname === 'https://cloudapi.suunto.com/v3/workouts') {
      return Response.json({ error: null, payload: [
        { workoutKey: 'abc', activityId: 13, startTime: Date.now() - 3_600_000, totalTime: 2700, hrdata: { workoutAvgHR: 151, workoutMaxHR: 175 } },
        { workoutKey: 'old', activityId: 1, startTime: Date.now() - 30 * 86_400_000, totalTime: 1800 },
      ], metadata: { workoutcount: '2' } });
    }
    if (u.origin + u.pathname === 'https://cloudapi.suunto.com/247samples/sleep') {
      return Response.json([
        { timestamp: '2026-11-18T21:54:52.217Z', entryData: { Duration: 28126, BedtimeStart: '2026-11-18T21:54:52.217Z', BedtimeEnd: '2026-11-19T05:43:38.217Z', IsNap: false, AvgHRV: 47 } },
        { timestamp: '2026-11-19T13:00:00Z', entryData: { Duration: 1800, BedtimeStart: '2026-11-19T13:00:00Z', BedtimeEnd: '2026-11-19T13:30:00Z', IsNap: true } },
      ]);
    }
    return new Response('nope', { status: 404 });
  };
  return { calls, fetchImpl };
}

async function serve(prisma, suunto) {
  const app = createApp({ prisma, sessionSecret: SESSION_SECRET, packsDir: undefined, suunto });
  const server = await new Promise((resolve) => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
  const url = `http://127.0.0.1:${server.address().port}`;
  const call = (athleteId, method, path) => fetch(`${url}${path}`, {
    method,
    redirect: 'manual',
    headers: athleteId ? { authorization: `Bearer ${signSessionToken(athleteId, { secret: SESSION_SECRET })}` } : {},
  });
  return { call, close: () => new Promise((r) => server.close(r)) };
}

test('suunto: without keys the app is told it is not available', async () => {
  const { call, close } = await serve(fakePrisma(), { config: null });
  try {
    assert.deepEqual(await (await call('a1', 'GET', '/suunto/status')).json(), { available: false, connected: false });
    assert.equal((await call('a1', 'POST', '/suunto/connect')).status, 503);
  } finally { await close(); }
});

test('suunto: connect, read workouts, disconnect', async () => {
  const prisma = fakePrisma();
  const suunto = fakeSuunto();
  const { call, close } = await serve(prisma, { config: CONFIG, fetchImpl: suunto.fetchImpl });
  try {
    assert.deepEqual(await (await call('a1', 'GET', '/suunto/status')).json(), { available: true, connected: false });
    const { url } = await (await call('a1', 'POST', '/suunto/connect')).json();
    const authorize = new URL(url);
    assert.equal(authorize.origin + authorize.pathname, 'https://cloudapi-oauth.suunto.com/oauth/authorize');
    assert.equal(authorize.searchParams.get('client_id'), 'cid');
    const state = authorize.searchParams.get('state');

    const back = await call(null, 'GET', `/suunto/callback?code=c1&state=${encodeURIComponent(state)}`);
    assert.equal(back.status, 302);
    assert.equal(back.headers.get('location'), 'athleteos://suunto?connected=1');
    const token = suunto.calls.find((c) => c.url.includes('/oauth/token'));
    assert.equal(new URL(token.url).searchParams.get('grant_type'), 'authorization_code');
    assert.equal(new URL(token.url).searchParams.get('code'), 'c1');
    assert.equal(token.init.headers.authorization, `Basic ${Buffer.from('cid:csecret').toString('base64')}`);
    assert.equal(prisma.rows[0].suuntoUser, 'skier1');
    assert.ok(!prisma.rows[0].accessToken.includes('skier1'), 'tokens are sealed at rest');

    const { workouts } = await (await call('a1', 'GET', '/suunto/workouts?days=3')).json();
    assert.equal(workouts.length, 1, 'older than the window is dropped');
    assert.equal(workouts[0].averageHeartRate, 151);
    assert.equal(workouts[0].activity, 'Downhill ski');
    assert.equal(new Date(workouts[0].end) - new Date(workouts[0].start), 2_700_000);
    const api = suunto.calls.find((c) => c.url.includes('/v3/workouts'));
    assert.equal(new URL(api.url).searchParams.get('filter-by-modification-time'), 'false');
    assert.equal(api.init.headers['ocp-apim-subscription-key'], 'skey');
    assert.match(api.init.headers.authorization, /^Bearer /);

    const { nights } = await (await call('a1', 'GET', '/suunto/sleep?days=7')).json();
    assert.deepEqual(nights.map((n) => n.hours), [7.81], 'naps left out');
    const sleep = suunto.calls.find((c) => c.url.includes('/247samples/sleep'));
    assert.ok(Number(new URL(sleep.url).searchParams.get('to')) - Number(new URL(sleep.url).searchParams.get('from')) <= 7 * 86_400_000 + 1000);

    assert.equal((await call('a1', 'DELETE', '/suunto/connection')).status, 204);
    assert.ok(suunto.calls.some((c) => c.url.includes('/oauth/deauthorize?client_id=cid')), 'Suunto is told');
    assert.deepEqual(await (await call('a1', 'GET', '/suunto/status')).json(), { available: true, connected: false });
  } finally { await close(); }
});

test('suunto: an expired token is refreshed; a forged state is refused', async () => {
  const prisma = fakePrisma();
  const suunto = fakeSuunto();
  prisma.rows.push({ athleteId: 'a2', suuntoUser: 'x', accessToken: seal('old', SESSION_SECRET), refreshToken: seal('r1', SESSION_SECRET), expiresAt: new Date(Date.now() - 1000) });
  const { call, close } = await serve(prisma, { config: CONFIG, fetchImpl: suunto.fetchImpl });
  try {
    assert.equal((await call('a2', 'GET', '/suunto/workouts')).status, 200);
    const refresh = suunto.calls.find((c) => c.url.includes('/oauth/token'));
    assert.equal(new URL(refresh.url).searchParams.get('grant_type'), 'refresh_token');
    assert.equal(new URL(refresh.url).searchParams.get('refresh_token'), 'r1');
    assert.equal(tokenUser(open(prisma.rows[0].accessToken, SESSION_SECRET)), 'skier1');

    const forged = await call(null, 'GET', '/suunto/callback?code=c1&state=abc.def');
    assert.equal(forged.headers.get('location'), 'athleteos://suunto?error=expired');
  } finally { await close(); }
});

test('suunto: state expires, workouts map tolerantly', () => {
  const state = signState('a1', 's', 0);
  assert.equal(verifyState(state, 's', 1000), 'a1');
  assert.equal(verifyState(state, 's', 16 * 60_000), null);
  assert.equal(verifyState(state, 'other', 1000), null);
  assert.equal(mapWorkout({ startTime: 1000, totalTime: 60 }).end, new Date(61_000).toISOString());
  assert.equal(mapWorkout({ startTime: 1000, totalTime: 60, activityId: 999 }).activity, 'Workout');
  assert.equal(mapNight({ entryData: { DeepSleepDuration: 3600, LightSleepDuration: 3600, BedtimeEnd: '2026-11-19T06:00:00Z' } }).hours, 2);
  assert.equal(mapNight({ entryData: { Duration: 100 } }), null);
  assert.equal(mapWorkout({ stopTime: 5 }), null);
});
