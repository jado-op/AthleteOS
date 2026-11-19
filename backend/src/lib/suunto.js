import crypto from 'node:crypto';

/**
 * Suunto Cloud API client (apizone.suunto.com). Access needs Suunto's partner
 * program: a client id + secret (OAuth app) and an API subscription key. With
 * any of them missing `suuntoConfig()` returns null and every Suunto route
 * answers "not available" — the app then hides the "Connect Suunto" button.
 *
 * Verified from Suunto's own pages (how-to-start, FAQ, 2026-11-19):
 *   authorize  https://cloudapi-oauth.suunto.com/oauth/authorize?response_type=code&client_id=…&redirect_uri=…
 *   token      https://cloudapi-oauth.suunto.com/oauth/token  (Basic client:secret, form body)
 *   response   { access_token (JWT, claim `user` = Suunto username), refresh_token, expires_in }
 *   workouts   GET https://cloudapi.suunto.com/v2/workouts  (Bearer + Ocp-Apim-Subscription-Key)
 *              startTime / stopTime in epoch milliseconds
 * Not stated by Suunto, so written defensively: the refresh request (standard
 * OAuth grant_type=refresh_token), the `since` query parameter, and the
 * workout field names for activity and heart rate.
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
  const response = await fetchImpl(`${SUUNTO_OAUTH}/token`, {
    method: 'POST',
    headers: {
      authorization: `Basic ${Buffer.from(`${config.clientId}:${config.clientSecret}`).toString('base64')}`,
      'content-type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(params).toString(),
  });
  if (!response.ok) throw new SuuntoError('token_failed', response.status);
  const json = await response.json();
  if (typeof json.access_token !== 'string') throw new SuuntoError('token_failed', response.status);
  return {
    accessToken: json.access_token,
    refreshToken: typeof json.refresh_token === 'string' ? json.refresh_token : null,
    expiresAt: new Date(Date.now() + (Number(json.expires_in) > 0 ? Number(json.expires_in) : 86_400) * 1000),
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

// ── workouts ──────────────────────────────────────────────────────────────

export async function listWorkouts(config, accessToken, since, fetchImpl = fetch) {
  const url = new URL(`${SUUNTO_API}/v2/workouts`);
  url.searchParams.set('since', String(since.getTime()));
  const response = await fetchImpl(url.toString(), {
    headers: { authorization: `Bearer ${accessToken}`, 'ocp-apim-subscription-key': config.subscriptionKey },
  });
  if (response.status === 401) throw new SuuntoError('unauthorized', 401);
  if (!response.ok) throw new SuuntoError('suunto_unavailable', response.status);
  const json = await response.json();
  const list = Array.isArray(json) ? json : Array.isArray(json?.payload) ? json.payload : Array.isArray(json?.workouts) ? json.workouts : [];
  return list.map(mapWorkout).filter((w) => w && new Date(w.start) >= since);
}

const num = (...values) => values.map(Number).find((v) => Number.isFinite(v) && v > 0);

/**
 * One Suunto workout as the phone's ExternalWorkout: start, end, activity,
 * average heart rate. Tolerant of field names Suunto hasn't documented.
 */
export function mapWorkout(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const start = num(raw.startTime);
  if (!start) return null;
  const seconds = num(raw.totalTime, raw.duration);
  const stop = num(raw.stopTime) ?? (seconds ? start + seconds * 1000 : undefined);
  if (!stop || stop <= start) return null;
  const hr = raw.hrdata ?? raw.hrData ?? {};
  const averageHeartRate = num(hr.workoutAvgHR, hr.avg, hr.average, raw.avgHR, raw.averageHeartRate) ?? null;
  const name = [raw.activityName, raw.sport, raw.activity].find((v) => typeof v === 'string' && v.trim());
  return {
    start: new Date(start).toISOString(),
    end: new Date(stop).toISOString(),
    activity: name ? name.trim() : 'Workout',
    averageHeartRate,
  };
}
