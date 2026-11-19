import crypto from 'node:crypto';

/**
 * Suunto Cloud API client (apizone.suunto.com). Access needs Suunto's partner
 * program: a client id + secret (OAuth app) and an API subscription key with
 * the Workout API and the 247 Data API. With any of them missing
 * `suuntoConfig()` returns null and every Suunto route answers "not
 * available": the app then hides the "Connect Suunto" button.
 *
 * From Suunto's API pages (read 2026-11-19: SUUNTO AUTHORISATION API,
 * SUUNTO WORKOUT API, SUUNTO 247 DATA API, how-to-start):
 *   authorize  GET  https://cloudapi-oauth.suunto.com/oauth/authorize?response_type=code&client_id=…&redirect_uri=…
 *   token      POST https://cloudapi-oauth.suunto.com/oauth/token?grant_type=authorization_code&code=…&redirect_uri=…
 *              POST …/oauth/token?grant_type=refresh_token&refresh_token=…   (Basic client:secret)
 *              → { access_token (JWT, claim `user`), refresh_token, expires_in }
 *   disconnect GET  https://cloudapi-oauth.suunto.com/oauth/deauthorize?client_id=…  (Bearer)
 *   workouts   GET  https://cloudapi.suunto.com/v3/workouts?since=&until=&limit=&filter-by-modification-time=false
 *              → { payload: [{ workoutKey, activityId, startTime (ms), totalTime (s), hrdata: { workoutAvgHR } … }] }
 *   sleep      GET  https://cloudapi.suunto.com/247samples/sleep?from=&to=  (ms, at most 28 days)
 *              → [{ timestamp, entryData: { Duration (s asleep), BedtimeStart, BedtimeEnd, IsNap, AvgHRV, HRMin … } }]
 * Every Cloud API call carries Bearer + Ocp-Apim-Subscription-Key.
 */
export const SUUNTO_OAUTH = 'https://cloudapi-oauth.suunto.com/oauth';
export const SUUNTO_API = 'https://cloudapi.suunto.com';

export function suuntoConfig(env = process.env) {
  const clientId = env.SUUNTO_CLIENT_ID;
  const clientSecret = env.SUUNTO_CLIENT_SECRET;
  const subscriptionKey = env.SUUNTO_SUBSCRIPTION_KEY;
  if (!clientId || !clientSecret || !subscriptionKey) return null;
  return {
    clientId,
    clientSecret,
    subscriptionKey,
    redirectUri: env.SUUNTO_REDIRECT_URI || 'https://api.lejacob.dev/fitness/suunto/callback',
    // Where the browser goes when the connection is done: the app's own scheme.
    appReturn: env.SUUNTO_APP_RETURN || 'athleteos://suunto',
  };
}

// ── state: who started the connection (signed, 15 minutes) ────────────────

export function signState(athleteId, secret, now = Date.now()) {
  const body = Buffer.from(JSON.stringify({ a: athleteId, e: now + 15 * 60_000, n: crypto.randomBytes(8).toString('hex') })).toString('base64url');
  const mac = crypto.createHmac('sha256', `suunto-state|${secret}`).update(body).digest('base64url');
  return `${body}.${mac}`;
}

export function verifyState(state, secret, now = Date.now()) {
  if (typeof state !== 'string') return null;
  const [body, mac] = state.split('.');
  if (!body || !mac) return null;
  const expected = crypto.createHmac('sha256', `suunto-state|${secret}`).update(body).digest('base64url');
  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const data = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (typeof data.a !== 'string' || typeof data.e !== 'number' || data.e < now) return null;
    return data.a;
  } catch {
    return null;
  }
}

// ── tokens at rest: AES-256-GCM, key derived from SESSION_SECRET ──────────

function key(secret) {
  return crypto.createHash('sha256').update(`suunto-tokens|${secret}`).digest();
}

export function seal(text, secret) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(secret), iv);
  const data = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), data].map((b) => b.toString('base64url')).join('.');
}

export function open(sealed, secret) {
  const [iv, tag, data] = String(sealed).split('.').map((p) => Buffer.from(p ?? '', 'base64url'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(secret), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}

/** The `user` claim of Suunto's access token (its username); never verified, only read. */
export function tokenUser(jwt) {
  try {
    const payload = JSON.parse(Buffer.from(String(jwt).split('.')[1] ?? '', 'base64url').toString('utf8'));
    return typeof payload.user === 'string' ? payload.user : typeof payload.sub === 'string' ? payload.sub : null;
  } catch {
    return null;
  }
}

// ── OAuth ─────────────────────────────────────────────────────────────────

export function authorizeUrl(config, state) {
  const url = new URL(`${SUUNTO_OAUTH}/authorize`);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', config.clientId);
  url.searchParams.set('redirect_uri', config.redirectUri);
  url.searchParams.set('state', state);
  return url.toString();
}

async function tokenRequest(config, params, fetchImpl) {
  // Suunto documents the parameters in the query string.
  const url = new URL(`${SUUNTO_OAUTH}/token`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const response = await fetchImpl(url.toString(), {
    method: 'POST',
    headers: { authorization: `Basic ${Buffer.from(`${config.clientId}:${config.clientSecret}`).toString('base64')}` },
  });
  if (!response.ok) throw new SuuntoError('token_failed', response.status);
  const json = await response.json();
  if (typeof json.access_token !== 'string') throw new SuuntoError('token_failed', response.status);
  return {
    accessToken: json.access_token,
    refreshToken: typeof json.refresh_token === 'string' ? json.refresh_token : null,
    expiresAt: new Date(Date.now() + (Number(json.expires_in) > 0 ? Number(json.expires_in) : 86_400) * 1000),
    user: typeof json.user === 'string' ? json.user : null,
  };
}

export function exchangeCode(config, code, fetchImpl = fetch) {
  return tokenRequest(config, { grant_type: 'authorization_code', code, redirect_uri: config.redirectUri }, fetchImpl);
}

export function refreshTokens(config, refreshToken, fetchImpl = fetch) {
  return tokenRequest(config, { grant_type: 'refresh_token', refresh_token: refreshToken }, fetchImpl);
}

export class SuuntoError extends Error {
  constructor(code, status) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

/** Tell Suunto the athlete disconnected (best effort). */
export async function deauthorize(config, accessToken, fetchImpl = fetch) {
  const url = new URL(`${SUUNTO_OAUTH}/deauthorize`);
  url.searchParams.set('client_id', config.clientId);
  try { await fetchImpl(url.toString(), { headers: { authorization: `Bearer ${accessToken}` } }); } catch { /* best effort */ }
}

async function cloudGet(config, accessToken, url, fetchImpl) {
  const response = await fetchImpl(url.toString(), {
    headers: { authorization: `Bearer ${accessToken}`, 'ocp-apim-subscription-key': config.subscriptionKey },
  });
  if (response.status === 401) throw new SuuntoError('unauthorized', 401);
  if (!response.ok) throw new SuuntoError('suunto_unavailable', response.status);
  return response.json();
}

// ── workouts ──────────────────────────────────────────────────────────────

export async function listWorkouts(config, accessToken, since, fetchImpl = fetch) {
  const url = new URL(`${SUUNTO_API}/v3/workouts`);
  url.searchParams.set('since', String(since.getTime()));
  url.searchParams.set('limit', '50');
  // Filter by when the workout started, not when it was last edited.
  url.searchParams.set('filter-by-modification-time', 'false');
  const json = await cloudGet(config, accessToken, url, fetchImpl);
  const list = Array.isArray(json?.payload) ? json.payload : Array.isArray(json) ? json : [];
  return list.map(mapWorkout).filter((w) => w && new Date(w.start) >= since);
}

const num = (...values) => values.map(Number).find((v) => Number.isFinite(v) && v > 0);

/** Suunto App activity ids (Suunto's Activities.pdf), the ones worth naming. */
export const SUUNTO_ACTIVITIES = {
  0: 'Walk', 1: 'Run', 2: 'Ride', 3: 'Cross-country ski', 10: 'Mountain bike', 11: 'Hike', 12: 'Roller skate',
  13: 'Downhill ski', 14: 'Paddle', 15: 'Row', 16: 'Golf', 17: 'Indoor sports', 19: 'Ball game', 20: 'Outdoor gym',
  21: 'Swim', 22: 'Trail run', 23: 'Gym', 24: 'Nordic walk', 29: 'Climb', 30: 'Snowboard', 31: 'Ski tour',
  32: 'Fitness class', 33: 'Soccer', 34: 'Tennis', 35: 'Basketball', 36: 'Badminton', 37: 'Baseball', 38: 'Volleyball',
  39: 'Football', 40: 'Table tennis', 41: 'Racquetball', 42: 'Squash', 43: 'Floorball', 44: 'Handball', 45: 'Softball',
  47: 'Cricket', 48: 'Rugby', 49: 'Ice skate', 50: 'Ice hockey', 51: 'Yoga', 52: 'Indoor ride', 53: 'Treadmill run',
  54: 'CrossFit', 55: 'Cross trainer', 56: 'Roller ski', 57: 'Indoor row', 58: 'Stretching', 59: 'Track and field',
  60: 'Orienteering', 62: 'Combat sport', 63: 'Kettlebell', 64: 'Dance', 68: 'Multisport', 69: 'Aerobics',
  73: 'Circuit training', 74: 'Triathlon', 75: 'Padel', 76: 'Cheerleading', 77: 'Boxing', 81: 'Gymnastics',
  85: 'Open-water swim', 91: 'Surf', 99: 'Gravel ride', 102: 'Jump rope', 103: 'Track run', 104: 'Calisthenics',
  107: 'Backcountry ski', 111: 'Biathlon', 113: 'Field hockey', 116: 'Ski mountaineering', 117: 'Skate ski',
  118: 'Classic ski', 120: 'Pilates', 121: 'Yoga',
};

/** One Suunto workout as the phone's ExternalWorkout: start, end, activity, average heart rate. */
export function mapWorkout(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const start = num(raw.startTime);
  if (!start) return null;
  const seconds = num(raw.totalTime);
  const stop = num(raw.stopTime) ?? (seconds ? start + seconds * 1000 : undefined);
  if (!stop || stop <= start) return null;
  const hr = raw.hrdata ?? {};
  return {
    start: new Date(start).toISOString(),
    end: new Date(stop).toISOString(),
    activity: SUUNTO_ACTIVITIES[raw.activityId] ?? 'Workout',
    averageHeartRate: num(hr.workoutAvgHR, hr.avg) ?? null,
  };
}

// ── sleep (247 Data API) ──────────────────────────────────────────────────

export async function listSleep(config, accessToken, from, to, fetchImpl = fetch) {
  const url = new URL(`${SUUNTO_API}/247samples/sleep`);
  url.searchParams.set('from', String(from.getTime()));
  url.searchParams.set('to', String(to.getTime()));
  const json = await cloudGet(config, accessToken, url, fetchImpl);
  const list = Array.isArray(json) ? json : Array.isArray(json?.samples) ? json.samples : Array.isArray(json?.payload) ? json.payload : [];
  return list.map(mapNight).filter(Boolean);
}

/** One night: when it ended (the morning it belongs to) and hours actually asleep. Naps are left out. */
export function mapNight(raw) {
  const e = raw?.entryData;
  if (!e || e.IsNap === true) return null;
  const seconds = num(e.Duration) ?? ((num(e.DeepSleepDuration) ?? 0) + (num(e.LightSleepDuration) ?? 0) + (num(e.REMSleepDuration) ?? 0));
  const end = Date.parse(e.BedtimeEnd ?? '');
  const start = Date.parse(e.BedtimeStart ?? raw.timestamp ?? '');
  if (!seconds || !Number.isFinite(end)) return null;
  return {
    start: Number.isFinite(start) ? new Date(start).toISOString() : null,
    end: new Date(end).toISOString(),
    hours: Math.round((seconds / 3600) * 100) / 100,
  };
}
