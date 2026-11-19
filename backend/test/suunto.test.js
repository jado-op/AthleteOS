import assert from 'node:assert/strict';
import test from 'node:test';

import { createApp } from '../src/app.js';
import { signSessionToken } from '../src/lib/sessionToken.js';
import { mapWorkout, open, seal, signState, tokenUser, verifyState } from '../src/lib/suunto.js';

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
    if (String(url).endsWith('/oauth/token')) {
      const body = new URLSearchParams(init.body);
      const fresh = body.get('grant_type') === 'refresh_token';
      return Response.json({ access_token: jwt({ user: 'skier1', fresh }), refresh_token: 'r2', expires_in: 86400 });
    }
    if (String(url).startsWith('https://cloudapi.suunto.com/v2/workouts')) {
      return Response.json({ error: null, payload: [
        { workoutKey: 'abc', activityId: 3, startTime: Date.now() - 3_600_000, stopTime: Date.now() - 600_000, hrdata: { workoutAvgHR: 151 } },
        { workoutKey: 'old', startTime: Date.now() - 30 * 86_400_000, totalTime: 1800 },
      ] });
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
    const token = suunto.calls.find((c) => c.url.endsWith('/oauth/token'));
    assert.equal(token.init.headers.authorization, `Basic ${Buffer.from('cid:csecret').toString('base64')}`);
    assert.equal(prisma.rows[0].suuntoUser, 'skier1');
    assert.ok(!prisma.rows[0].accessToken.includes('skier1'), 'tokens are sealed at rest');

    const { workouts } = await (await call('a1', 'GET', '/suunto/workouts?days=3')).json();
    assert.equal(workouts.length, 1, 'older than the window is dropped');
    assert.equal(workouts[0].averageHeartRate, 151);
    const api = suunto.calls.find((c) => c.url.includes('/v2/workouts'));
    assert.equal(api.init.headers['ocp-apim-subscription-key'], 'skey');
    assert.match(api.init.headers.authorization, /^Bearer /);

    assert.equal((await call('a1', 'DELETE', '/suunto/connection')).status, 204);
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
    const refresh = suunto.calls.find((c) => c.url.endsWith('/oauth/token'));
    assert.equal(new URLSearchParams(refresh.init.body).get('grant_type'), 'refresh_token');
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
  assert.equal(mapWorkout({ stopTime: 5 }), null);
});
