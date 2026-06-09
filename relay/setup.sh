#!/usr/bin/env bash
#
# One-shot deploy for the crafty-relay Cloudflare Worker.
#   Usage: ./setup.sh /path/to/AuthKey_XXXXXXXXXX.p8 <KEY_ID> <TEAM_ID>
#
set -euo pipefail

KEY_PATH="${1:?Usage: ./setup.sh <path-to-.p8> <APNS_KEY_ID> <APNS_TEAM_ID>}"
KEY_ID="${2:?missing APNS_KEY_ID}"
TEAM_ID="${3:?missing APNS_TEAM_ID}"

[ -f "$KEY_PATH" ] || { echo "Key file not found: $KEY_PATH"; exit 1; }
command -v npx >/dev/null 2>&1 || { echo "Node.js / npx is required."; exit 1; }

cd "$(dirname "$0")"

echo "==> Installing wrangler"
npm install --silent

echo "==> Logging in to Cloudflare (browser may open)"
npx wrangler login

# Create the KV namespace (handle both wrangler v4 and v3 command spellings).
if grep -q "REPLACE_WITH_KV_NAMESPACE_ID" wrangler.toml; then
  echo "==> Creating KV namespace 'DEVICES'"
  OUT=$(npx wrangler kv namespace create DEVICES 2>&1 \
        || npx wrangler kv:namespace create DEVICES 2>&1 || true)
  echo "$OUT"
  ID=$(echo "$OUT" | grep -oE '[0-9a-f]{32}' | head -1 || true)
  if [ -n "${ID:-}" ]; then
    sed -i.bak "s/REPLACE_WITH_KV_NAMESPACE_ID/$ID/" wrangler.toml && rm -f wrangler.toml.bak
    echo "    wrote KV id $ID into wrangler.toml"
  else
    echo "!!! Could not auto-detect the KV id. Paste it into wrangler.toml (id = \"...\") and re-run."
    exit 1
  fi
else
  echo "==> KV id already set in wrangler.toml, skipping creation"
fi

echo "==> Storing secrets"
printf '%s' "$(cat "$KEY_PATH")" | npx wrangler secret put APNS_KEY
printf '%s' "$KEY_ID"  | npx wrangler secret put APNS_KEY_ID
printf '%s' "$TEAM_ID" | npx wrangler secret put APNS_TEAM_ID

echo "==> Deploying"
npx wrangler deploy

echo
echo "Done. Test with:  curl https://crafty-relay.<your-subdomain>.workers.dev/health"
echo "Then put that URL in the app: Settings → Live updates (push)."
