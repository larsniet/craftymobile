#!/usr/bin/env node
/*
 * crafty-push — companion push server for the CraftyMobile app.
 *
 * Polls a Crafty Controller instance and sends APNs pushes to registered
 * devices so the app's widget stays current and crash/recovery alerts arrive
 * instantly. Pure Node.js — no npm dependencies.
 *
 *   - Alert push  (status change up/down/crash): delivered immediately.
 *   - Silent push (routine data refresh):         rate-limited (APNs throttles
 *                                                 background pushes anyway).
 * Every push embeds the latest snapshot, so the app updates the widget without
 * calling back to Crafty.
 *
 * Config via environment (see .env.example). Run:  node crafty-push.js
 */

'use strict';

const http = require('http');
const https = require('https');
const http2 = require('http2');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

// ---- Minimal .env loader (no dependency) -----------------------------------

(function loadDotEnv() {
  const envPath = path.join(__dirname, '.env');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^\s*([\w.]+)\s*=\s*(.*)\s*$/);
    if (!m || line.trim().startsWith('#')) continue;
    let val = m[2].trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (process.env[m[1]] === undefined) process.env[m[1]] = val;
  }
})();

const CFG = {
  craftyURL: (process.env.CRAFTY_URL || '').replace(/\/+$/, ''),
  craftyToken: process.env.CRAFTY_TOKEN || '',
  allowSelfSigned: (process.env.CRAFTY_ALLOW_SELF_SIGNED || 'true') === 'true',
  apnsKeyPath: process.env.APNS_KEY_PATH || '',
  apnsKeyId: process.env.APNS_KEY_ID || '',
  apnsTeamId: process.env.APNS_TEAM_ID || '',
  bundleId: process.env.APNS_BUNDLE_ID || 'com.larsniet.CraftyMobile',
  apnsEnv: process.env.APNS_ENV || 'sandbox', // 'sandbox' for dev/sideloaded builds
  port: parseInt(process.env.PORT || '8099', 10),
  pollSeconds: parseInt(process.env.POLL_INTERVAL_SECONDS || '30', 10),
  silentMinSeconds: parseInt(process.env.SILENT_PUSH_MIN_SECONDS || '300', 10),
  tokensFile: process.env.TOKENS_FILE || path.join(__dirname, 'tokens.json'),
};

const APNS_HOST = CFG.apnsEnv === 'production'
  ? 'api.push.apple.com'
  : 'api.sandbox.push.apple.com';

function required(name, value) {
  if (!value) { console.error(`Missing required config: ${name}`); process.exit(1); }
}
required('CRAFTY_URL', CFG.craftyURL);
required('CRAFTY_TOKEN', CFG.craftyToken);
required('APNS_KEY_PATH', CFG.apnsKeyPath);
required('APNS_KEY_ID', CFG.apnsKeyId);
required('APNS_TEAM_ID', CFG.apnsTeamId);

// ---- Token storage ---------------------------------------------------------

function loadTokens() {
  try { return new Set(JSON.parse(fs.readFileSync(CFG.tokensFile, 'utf8'))); }
  catch { return new Set(); }
}
function saveTokens(set) {
  try { fs.writeFileSync(CFG.tokensFile, JSON.stringify([...set], null, 2)); }
  catch (e) { console.error('Could not save tokens:', e.message); }
}
let tokens = loadTokens();

// ---- APNs JWT (ES256, signed with the .p8 key) -----------------------------

let cachedJWT = { token: null, iat: 0 };
function apnsAuthToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT.token && now - cachedJWT.iat < 3000) return cachedJWT.token; // reuse ~50 min
  const key = fs.readFileSync(CFG.apnsKeyPath, 'utf8');
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: CFG.apnsKeyId }));
  const payload = base64url(JSON.stringify({ iss: CFG.apnsTeamId, iat: now }));
  const signingInput = `${header}.${payload}`;
  // dsaEncoding 'ieee-p1363' yields the raw R||S signature JOSE/JWT expects.
  const signature = crypto.sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });
  const jwt = `${signingInput}.${base64url(signature)}`;
  cachedJWT = { token: jwt, iat: now };
  return jwt;
}
function base64url(input) {
  return Buffer.from(input).toString('base64')
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

// ---- Send one push to one device -------------------------------------------

function sendPush(token, payload, { alert }) {
  return new Promise((resolve) => {
    const client = http2.connect(`https://${APNS_HOST}`);
    client.on('error', (e) => { resolve({ ok: false, error: e.message }); });

    const body = Buffer.from(JSON.stringify(payload));
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      'authorization': `bearer ${apnsAuthToken()}`,
      'apns-topic': CFG.bundleId,
      'apns-push-type': alert ? 'alert' : 'background',
      'apns-priority': alert ? '10' : '5',
      'content-type': 'application/json',
      'content-length': body.length,
    });

    let status = 0, data = '';
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (d) => { data += d; });
    req.on('end', () => {
      client.close();
      // 410 = token no longer valid; prune it.
      if (status === 410) { tokens.delete(token); saveTokens(tokens); }
      if (status !== 200) console.error(`APNs ${status} for ${token.slice(0, 8)}…: ${data}`);
      resolve({ ok: status === 200, status });
    });
    req.on('error', (e) => { client.close(); resolve({ ok: false, error: e.message }); });
    req.end(body);
  });
}

async function broadcast(payload, opts) {
  for (const token of [...tokens]) {
    await sendPush(token, payload, opts);
  }
}

// ---- Crafty polling --------------------------------------------------------

function craftyGet(pathName) {
  return new Promise((resolve, reject) => {
    const url = new URL(CFG.craftyURL + pathName);
    const mod = url.protocol === 'http:' ? http : https;
    const req = mod.request(url, {
      method: 'GET',
      headers: { Authorization: `Bearer ${CFG.craftyToken}`, Accept: 'application/json' },
      rejectUnauthorized: !CFG.allowSelfSigned,
      timeout: 12000,
    }, (res) => {
      let data = '';
      res.on('data', (d) => { data += d; });
      res.on('end', () => {
        try { resolve(JSON.parse(data).data); }
        catch (e) { reject(new Error('Bad JSON from Crafty')); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('Crafty timeout')));
    req.on('error', reject);
    req.end();
  });
}

function statusOf(stat) {
  if (!stat) return 'stopped';
  if (stat.crashed) return 'crashed';
  if (stat.updating) return 'updating';
  if (stat.waiting_start) return 'starting';
  if (stat.running) return 'running';
  return 'stopped';
}

function humanMem(mem) {
  if (mem == null) return '—';
  if (typeof mem === 'string') {
    if (/[a-zA-Z]/.test(mem)) return mem;            // already has a unit
    mem = Number(mem);
  }
  if (!isFinite(mem)) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0; let v = mem;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

async function buildSnapshot() {
  const servers = await craftyGet('/api/v2/servers');
  const rows = [];
  for (const s of servers) {
    let stat = null;
    try { stat = await craftyGet(`/api/v2/servers/${s.server_id}/stats`); } catch {}
    rows.push({
      id: String(s.server_id),
      name: s.server_name || 'Server',
      status: statusOf(stat),
      online: Number(stat && stat.online) || 0,
      max: Number(stat && stat.max) || 0,
      cpu: Number(stat && stat.cpu) || 0,
      memory: humanMem(stat && stat.mem),
    });
  }
  return { generatedAt: new Date().toISOString(), servers: rows };
}

// ---- Diff + push loop ------------------------------------------------------

let prev = null;          // last snapshot
let lastSilentPush = 0;   // epoch seconds

async function tick() {
  let snap;
  try { snap = await buildSnapshot(); }
  catch (e) { console.error('Poll failed:', e.message); return; }

  if (tokens.size === 0) { prev = snap; return; }

  const prevById = {};
  if (prev) for (const r of prev.servers) prevById[r.id] = r;

  // Status transitions → immediate alert pushes (one per affected server).
  let statusChanged = false;
  for (const r of snap.servers) {
    const old = prevById[r.id];
    if (!old || old.status === r.status) continue;
    statusChanged = true;
    if (r.status === 'crashed') {
      await broadcast(alertPayload(`⚠️ ${r.name} crashed`, 'The server stopped unexpectedly.', snap), { alert: true });
    } else if (r.status === 'running' && (old.status === 'crashed' || old.status === 'stopped')) {
      await broadcast(alertPayload(`✅ ${r.name} is back online`, 'The server is running again.', snap), { alert: true });
    }
  }

  // Otherwise, if anything changed, send a (rate-limited) silent refresh.
  const nowSec = Math.floor(Date.now() / 1000);
  const dataChanged = JSON.stringify(stripTime(prev)) !== JSON.stringify(stripTime(snap));
  if (!statusChanged && dataChanged && nowSec - lastSilentPush >= CFG.silentMinSeconds) {
    lastSilentPush = nowSec;
    await broadcast(silentPayload(snap), { alert: false });
  }

  prev = snap;
}

function stripTime(snap) { return snap ? snap.servers : null; }

function alertPayload(title, body, snap) {
  return { aps: { alert: { title, body }, sound: 'default', 'content-available': 1 }, snapshot: snap };
}
function silentPayload(snap) {
  return { aps: { 'content-available': 1 }, snapshot: snap };
}

// ---- HTTP server (token registration) --------------------------------------

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/register') {
    let body = '';
    req.on('data', (d) => { body += d; if (body.length > 1e5) req.destroy(); });
    req.on('end', () => {
      try {
        const { token } = JSON.parse(body);
        if (token && /^[0-9a-f]+$/i.test(token)) {
          tokens.add(token.toLowerCase());
          saveTokens(tokens);
          console.log(`Registered device …${token.slice(-8)} (${tokens.size} total)`);
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok' }));
      } catch {
        res.writeHead(400); res.end('bad request');
      }
    });
    return;
  }
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', devices: tokens.size, apns: CFG.apnsEnv }));
    return;
  }
  res.writeHead(404); res.end('not found');
});

server.listen(CFG.port, () => {
  console.log(`crafty-push listening on :${CFG.port}  (APNs ${CFG.apnsEnv}, poll ${CFG.pollSeconds}s)`);
  console.log(`Watching ${CFG.craftyURL}`);
  tick();
  setInterval(tick, CFG.pollSeconds * 1000);
});
