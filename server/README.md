# crafty-push

A tiny companion server that gives the CraftyMobile app **live updates**: it
polls your Crafty Controller and sends Apple push notifications so the app's
widget stays current and crash/recovery **alerts arrive instantly**.

Pure Node.js — **no npm dependencies** (uses built-in `http2`, `crypto`, `https`).

## How it works

```
Crafty API  ──poll──▶  crafty-push  ──APNs──▶  your iPhone  ──▶  widget + alerts
                          ▲
              app POSTs its device token to /register
```

- **Status change** (up / down / crash) → an **alert** push, delivered
  immediately (shows the notification).
- **Routine change** (player count, CPU…) → a **silent** push, rate-limited
  (Apple throttles background pushes; default min 5 min apart).
- Every push embeds the latest snapshot, so the app updates the widget without
  calling back to Crafty.

## One-time Apple setup

You need a **paid Apple Developer account** (you already use one to sideload).

1. Go to <https://developer.apple.com/account/resources/authkeys/list>.
2. **Keys → (+)** → enable **Apple Push Notifications service (APNs)** → Register.
3. Download the **`AuthKey_XXXXXXXXXX.p8`** (you can only download it once) and
   note the **Key ID**. Your **Team ID** is `3BGHPQ6C3H`.
4. In Xcode, select the **CraftyMobile** target → **Signing & Capabilities** →
   **+ Capability → Push Notifications** (this provisions the `aps-environment`
   entitlement that's already in the project).

## Run

```sh
cd server
cp .env.example .env
# edit .env — set CRAFTY_URL, CRAFTY_TOKEN, APNS_KEY_PATH, APNS_KEY_ID
node crafty-push.js
```

You should see:

```
crafty-push listening on :8099  (APNs sandbox, poll 30s)
Watching https://crafty.example.com:8443
```

Check it's alive: `curl http://localhost:8099/health`

Keep it running (e.g. `pm2 start crafty-push.js`, a `systemd` unit, or
`screen`/`tmux`). It's lightweight and can live on the same box as Crafty.

## Run with Docker (recommended)

A prebuilt, multi-arch image is published to GitHub Container Registry
(replace `OWNER` with the GitHub account that owns this repo):

```sh
docker pull ghcr.io/OWNER/crafty-push:latest
```

Run it as a **sidecar next to Crafty** with the included compose file:

```sh
cd server
cp .env.example .env          # fill in CRAFTY_* and APNS_KEY_ID / APNS_TEAM_ID
cp /path/to/AuthKey_XXXX.p8 ./AuthKey.p8   # your APNs key
docker compose up -d
docker compose logs -f crafty-push
```

The compose file mounts `AuthKey.p8` read-only, persists device tokens in a
named volume, and exposes port `8099`. In `.env` you don't need `APNS_KEY_PATH`
or `TOKENS_FILE` — the compose file sets those to the in-container paths.

- **Same compose as Crafty?** Put both services on one network and set
  `CRAFTY_URL=https://crafty:8443` (the service name). Otherwise use your
  external Crafty URL.
- **Config is per-user.** The image is generic; your `.env` + your `AuthKey.p8`
  make it yours. Nothing secret is baked into the image.

Build it yourself instead of pulling:

```sh
cd server && docker build -t crafty-push .
```

## Point the app at it

In the app: **Settings → Live updates (push)** → turn on, and set **Push server
URL** to where this server is reachable from your phone, e.g.
`http://your-host:8099` (or front it with your reverse proxy for TLS, e.g.
`https://crafty.example.com/push`). The app registers its device token
automatically; **Device registered** should flip to **Yes**, and the server log
prints `Registered device …`.

## Notes & limits

- **`APNS_ENV=sandbox`** for sideloaded/Xcode builds — they use the APNs sandbox.
  A mismatch returns `BadDeviceToken` from APNs.
- Silent (widget-refresh) pushes are **throttled by Apple** to a few per hour;
  that's why routine refreshes are rate-limited. Status-change alerts are not
  throttled and arrive immediately.
- If a device token becomes invalid, APNs returns `410` and the server prunes it
  automatically.
- The `/register` endpoint is plain HTTP. If you expose it beyond your LAN, put
  it behind your reverse proxy with TLS.
