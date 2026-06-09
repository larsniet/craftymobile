# crafty-relay (Cloudflare Worker)

A **zero-knowledge** APNs relay for CraftyMobile. It turns a plain Crafty webhook
into an Apple push — so you get instant alerts (and a widget refresh) **without
running or paying for a server**, and **without the relay ever seeing a user's
Crafty URL or API token**.

- Runs on Cloudflare Workers' **free tier** (100k req/day; you'll use a sliver).
- **Scales to zero** — no VPS, no OS, no patching, no uptime babysitting.
- Holds only your APNs key + opaque device tokens + random pairing codes.

```
App ──/register {token}──▶ relay ──▶ returns a pairing code
User pastes  https://<relay>/hook/<code>  into Crafty → Webhooks
Crafty ──(event)──▶ /hook/<code> ──APNs──▶ phone   (token never leaves device)
```

## Prerequisites

- A (free) **Cloudflare account** and Node.js installed locally.
- An **APNs Auth Key** (`.p8`) + its **Key ID**, and your **Team ID** (`3BGHPQ6C3H`).
  Create the key at developer.apple.com → Keys → Apple Push Notifications service.
- In Xcode: **CraftyMobile** target → Signing & Capabilities → **+ Push Notifications**.

## Deploy A — connect GitHub (recommended: push-to-deploy)

In the Cloudflare dashboard → **Workers & Pages → Create → Connect to Git**, pick
this repo and:

- **Root directory:** `/relay`
- **Build command:** `npx wrangler deploy`
- **(non-production branches):** `npx wrangler versions upload`

Every push to your default branch then redeploys automatically — no local tools.
**But the Git build only deploys code + `[vars]`; you must do these two things once:**

1. **Create the KV namespace and commit its id.** Dashboard → **Storage &
   Databases → KV → Create** (any name) → copy the **Namespace ID** → paste it
   into `relay/wrangler.toml` (`id = "…"`) → commit & push. (The id isn't secret.)
   Until this is set, the build fails with an invalid-KV error.
2. **Add the secrets to the Worker** (after the first deploy creates it):
   Worker → **Settings → Variables and Secrets** → add **encrypted secrets**
   `APNS_KEY` (paste the whole `.p8`), `APNS_KEY_ID`, `APNS_TEAM_ID`. These are
   **runtime** secrets — *not* Workers *Build* variables — and they persist
   across deploys. Then re-run the build (push a commit or "Retry").

`APNS_BUNDLE_ID` and `APNS_ENV` come from `wrangler.toml`, so you don't set those
by hand.

## Deploy B — one command from your machine

```sh
cd relay
./setup.sh /path/to/AuthKey_XXXXXXXXXX.p8 <KEY_ID> <TEAM_ID>
```

This installs wrangler, logs you in, creates the KV namespace, stores your
secrets, and deploys. At the end it prints your relay URL
(`https://craftymobile-relay.<subdomain>.workers.dev`).

### …or step by step

```sh
cd relay
npm install
npx wrangler login
npx wrangler kv namespace create DEVICES   # paste the printed id into wrangler.toml
printf '%s' "$(cat AuthKey_XXXXXXXXXX.p8)" | npx wrangler secret put APNS_KEY
echo "<KEY_ID>"  | npx wrangler secret put APNS_KEY_ID
echo "3BGHPQ6C3H" | npx wrangler secret put APNS_TEAM_ID
npx wrangler deploy
```

> If your wrangler is v3, the KV command is `npx wrangler kv:namespace create DEVICES`.

Verify: `curl https://craftymobile-relay.<subdomain>.workers.dev/health` → `{"status":"ok",...}`

## Connect the app

In CraftyMobile: **Settings → Live updates (push)** → enter your relay URL. The
app registers and shows a **Crafty webhook URL** (`.../hook/<code>`). Copy it.

## Connect Crafty

In Crafty: **Webhooks** → add a webhook for the server start/stop (and any other)
events → set the URL to the copied `.../hook/<code>` → set the body to JSON:

```json
{"title": "{{ server_name }}", "message": "{{ server_name }} — {{ event }}"}
```

(Adjust the variable names to whatever your Crafty version exposes — the relay is
tolerant and falls back to a generic message.) Save, then use Crafty's **Test**
button — you should get a push within a second or two.

## Notes

- `APNS_ENV` in `wrangler.toml` must be **`sandbox`** for sideloaded/TestFlight
  dev builds, **`production`** for App Store builds. A mismatch → `BadDeviceToken`.
- Dead device tokens (APNs `410`) are pruned automatically.
- The relay never receives Crafty credentials. The widget's live data is fetched
  by the app directly from Crafty using the on-device token; the push only
  triggers the refresh.
