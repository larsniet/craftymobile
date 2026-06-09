/*
 * crafty-relay — zero-knowledge APNs relay for CraftyMobile, on Cloudflare Workers.
 *
 * It NEVER sees a user's Crafty URL or API token. Flow:
 *   1. The app registers its APNs device token  → POST /register {token, code?}
 *      and gets back a random pairing `code`.
 *   2. The user pastes  https://<relay>/hook/<code>  into their Crafty webhook.
 *   3. On a server event, Crafty POSTs to /hook/<code>; the relay looks up the
 *      device token(s) for that code and sends an APNs push (alert + a
 *      content-available flag so the app also refreshes its widget — the app
 *      fetches live data from Crafty itself, so the token stays on-device).
 *
 * Secrets (wrangler secret put):  APNS_KEY (.p8 contents), APNS_KEY_ID, APNS_TEAM_ID
 * Vars (wrangler.toml):           APNS_BUNDLE_ID, APNS_ENV (sandbox|production)
 * KV binding:                     DEVICES
 */

let cachedJWT = null; // { token, iat } — persists per isolate

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/health') {
      return json({ status: 'ok', apns: env.APNS_ENV || 'sandbox' });
    }
    if (request.method === 'POST' && url.pathname === '/register') {
      return handleRegister(request, env);
    }
    if (request.method === 'POST' && url.pathname.startsWith('/hook/')) {
      return handleHook(request, env, decodeURIComponent(url.pathname.slice('/hook/'.length)));
    }
    return new Response('not found', { status: 404 });
  },
};

// --- Endpoints --------------------------------------------------------------

async function handleRegister(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400); }

  const token = String(body.token || '').toLowerCase();
  if (!/^[0-9a-f]{32,}$/.test(token)) return json({ error: 'invalid device token' }, 400);

  // Reuse the app's existing code (so the user never re-pastes the webhook),
  // otherwise mint a new one.
  let code = (typeof body.code === 'string' && /^[a-z0-9]{12,40}$/i.test(body.code)) ? body.code : randomCode();

  const key = `code:${code}`;
  const entry = (await env.DEVICES.get(key, 'json')) || { tokens: [] };
  if (!entry.tokens.includes(token)) entry.tokens.push(token);
  entry.tokens = entry.tokens.slice(-10); // cap per code
  await env.DEVICES.put(key, JSON.stringify(entry));

  return json({ code, hook: `/hook/${code}` });
}

async function handleHook(request, env, code) {
  if (!/^[a-z0-9]{12,40}$/i.test(code)) return json({ error: 'bad code' }, 400);

  const entry = await env.DEVICES.get(`code:${code}`, 'json');
  if (!entry || !entry.tokens.length) return json({ error: 'unknown code' }, 404);

  // Tolerant body parsing — Crafty's webhook body is user-templated.
  const raw = await request.text();
  let b = {};
  try { b = JSON.parse(raw); } catch { /* not JSON */ }
  const title = b.title || b.server_name || b.server || 'Crafty';
  const message = b.message || b.body || b.content
    || (raw && !raw.trim().startsWith('{') ? raw.trim() : 'Server status changed');

  const payload = {
    aps: { alert: { title: String(title).slice(0, 120), body: String(message).slice(0, 240) },
           sound: 'default', 'content-available': 1 },
  };

  const remaining = [];
  for (const token of entry.tokens) {
    const status = await sendPush(env, token, payload);
    if (status !== 410) remaining.push(token); // 410 = token dead → prune
  }
  if (remaining.length !== entry.tokens.length) {
    await env.DEVICES.put(`code:${code}`, JSON.stringify({ tokens: remaining }));
  }
  return json({ sent: remaining.length });
}

// --- APNs -------------------------------------------------------------------

async function sendPush(env, token, payload) {
  const host = env.APNS_ENV === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
  const jwt = await apnsToken(env);
  const res = await fetch(`https://${host}/3/device/${token}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'apns-topic': env.APNS_BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  if (res.status !== 200) {
    console.log(`APNs ${res.status} for …${token.slice(-8)}: ${await res.text()}`);
  }
  return res.status;
}

async function apnsToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.iat < 3000) return cachedJWT.token; // reuse ~50 min
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now })));
  const signingInput = `${header}.${claims}`;
  const key = await importPrivateKey(env.APNS_KEY);
  // Web Crypto ECDSA returns the raw R||S signature JWT/JOSE expects.
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key,
    new TextEncoder().encode(signingInput));
  const token = `${signingInput}.${b64url(new Uint8Array(sig))}`;
  cachedJWT = { token, iat: now };
  return token;
}

async function importPrivateKey(pem) {
  const der = pemToArrayBuffer(pem);
  return crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
}

// --- helpers ----------------------------------------------------------------

function pemToArrayBuffer(pem) {
  const base64 = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  const bin = atob(base64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function b64url(bytes) {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function randomCode() {
  const bytes = new Uint8Array(10);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
