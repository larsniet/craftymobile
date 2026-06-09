# CraftyMobile

A native, dark-first iPhone app (SwiftUI, iOS 17+) for monitoring and lightly
controlling Minecraft servers on a self-hosted **Crafty Controller 4.10.3**
instance via its v2 API. No third-party dependencies — just URLSession and
native APIs.

It's built for personal, sideloaded use (run from Xcode onto your own iPhone);
it is **not** intended for the App Store.

<img src="CraftyMobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="96" align="right" />

## What it does

- **Settings / connection** — editable base URL, obscured API token (stored in
  the Keychain), "Allow self-signed certificates" toggle (default ON), and a
  **Test connection** button hitting `/api/v2/crafty/check`.
- **Servers list (home)** — a card per server: name, status pill
  (Running 🟢 / Stopped ⚪️ / Starting 🟠 / Crashed 🔴 / Updating 🔵), players,
  CPU %, memory. Pull-to-refresh + auto-refresh every ~10s.
- **Server detail** — status header, **Start / Stop / Restart** (Stop/Restart/
  Kill are confirmed), live stats refreshing ~5s, a players section, and a
  Force-Kill / Back-up menu. Buttons to jump to Logs and Console.
- **Logs viewer** — full-width dark monospace terminal, newest at the bottom,
  auto-scroll, a **Live tail** toggle (~3s) and pull-to-refresh.
- **Console** — the same live stream with a command input pinned to the bottom.
  Commands POST to `/stdin` (no leading slash needed), the tail refreshes so you
  see the result, and recent commands are remembered.
- **Home Screen & Lock Screen widgets** — small / medium / large Home Screen
  widgets plus Lock Screen accessory widgets (circular ring, rectangular summary,
  inline). Fetch live on iOS's schedule (with the last app snapshot as fallback),
  so they stay useful without opening the app.
- **Face ID / passcode lock** *(optional)* — lock the app and your stored token
  behind biometric authentication; re-locks when the app is backgrounded.
- **Background status alerts** *(optional)* — a best-effort background check that
  sends a local notification when a server crashes or comes back online. Timing
  is controlled by iOS (not real-time); see the Alerts note below.
- **Live updates via push** *(optional)* — pair the app with the companion
  [push server](server/README.md) running next to Crafty for near-real-time
  widget refreshes and **instant** crash/recovery alerts.

Polling pauses automatically when a screen isn't visible or the app is
backgrounded, so it won't hammer your server.

## Requirements

- **Xcode 16 or newer** (the project uses Xcode's file-system-synchronized
  groups). It was last built with Xcode 26.5.
- An iPhone running **iOS 17.0+**.
- A free Apple ID is enough to sideload onto your own device.

## Open & run on your iPhone

1. **Open the project**

   ```sh
   open CraftyMobile/CraftyMobile.xcodeproj
   ```

2. **Set your signing team**
   - Select the **CraftyMobile** project → **CraftyMobile** target → **Signing &
     Capabilities**.
   - Check **Automatically manage signing** and pick your **Team** (your
     personal Apple ID works).
   - If Xcode complains the bundle identifier is taken, change
     **Bundle Identifier** (e.g. `com.yourname.CraftyMobile`).

3. **Plug in your iPhone** and select it as the run destination (top toolbar).
   - First time: on the iPhone, trust the developer profile under
     **Settings → General → VPN & Device Management**.

4. **Run** (⌘R). The app installs and launches on your device.

5. **Configure the connection** (in-app, on the **Settings** tab):
   - **Server URL** — starts empty; enter your Crafty address (an example is
     shown as placeholder). If Crafty isn't behind a reverse proxy, include the
     port, e.g. `https://crafty.example.com:8443`.
   - **API Token** — generate one in Crafty's panel
     (*Panel Config → API Keys* / your user's API credentials) and paste it.
     It's stored securely and shared with the widget via the App Group container.
   - **Allow self-signed certificates** — leave **ON** if Crafty uses a
     self-signed cert (most self-hosted setups do).
   - Tap **Test connection** to verify, then switch to the **Servers** tab.

## Widget & Face ID

**App Group (required for the widget).** The widget reads your URL + token from a
shared App Group container, `group.com.larsniet.CraftyMobile`. This needs a
**paid Apple Developer account** (free "Personal Team" Apple IDs can't provision
App Groups). It's already declared in both targets' `.entitlements` files; with
automatic signing Xcode registers it for you. If you change the bundle ID prefix,
update the group ID in all three places: `CraftyMobile.entitlements`,
`CraftyWidget.entitlements`, and the `appGroupID` constant in
`AppSettings.swift` / `WidgetData.swift`.

> Security note: to let the widget fetch live, the token is stored in the App
> Group's shared container (sandboxed to your team's apps) rather than the
> Keychain. The app migrates any previously Keychain-stored token automatically.

**Add the Home Screen widget:** long-press the Home Screen → **+** → search
"Crafty" → pick a size.

**Add a Lock Screen widget:** long-press the Lock Screen → **Customize** → **Lock
Screen** → tap a widget slot → search "Crafty" (circular, rectangular, or inline).

Widgets refresh on iOS's timeline (system-throttled, typically several minutes to
~an hour) and instantly whenever the app is open. Lock Screen widgets render
monochrome/tinted by design.

**Enable Face ID:** Settings tab → **Require Face ID / Passcode**. The app locks
immediately on next background and prompts on return. If no biometrics/passcode
is enrolled, it won't lock you out.

## Background alerts

Settings → **Server status alerts**. When enabled, the app asks for notification
permission and registers a `BGAppRefreshTask`. On iOS's schedule the task wakes,
checks each server, and posts a local notification when one **crashes** or comes
**back online** (it also refreshes the widget). Use **Send a test alert** to
confirm notifications are permitted.

> **This is not real-time.** iOS owns the schedule — background app refresh
> typically runs every 15–60 min (sometimes longer), adapts to your usage and
> battery, and does **not** run if you force-quit the app. There's no entitlement
> or backend required because these are *local* notifications. Genuinely instant
> alerts would need a push server (APNs).

**To test the background task immediately** (Debug build, device attached), pause
in the Xcode debugger and run in the LLDB console:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.larsniet.CraftyMobile.refresh"]
```

## Live updates (push)

For **instant** crash/recovery alerts and a fresh widget (instead of iOS's slow
background schedule), there are two ways to add push — pick one:

**A. Cloudflare Worker relay — recommended (zero-maintenance, ~free, private).**
A tiny serverless relay turns a plain Crafty webhook into an Apple push. It
**never sees your Crafty URL or token**, scales to zero, and costs nothing at
homelab volume. You deploy it once with one command. See
**[relay/README.md](relay/README.md)**.

```
App ─register▶ relay ─returns code▶  paste https://<relay>/hook/<code> into Crafty
Crafty ─event▶ relay ─APNs▶ phone    (widget then fetches Crafty directly on-device)
```

**B. Self-hosted Node poller (Docker).** A small service that polls Crafty and
pushes directly. Fully self-hosted, but it holds your Crafty token and you run a
container. See **[server/README.md](server/README.md)**.

One-time setup (both options):

1. Create an **APNs Auth Key (.p8)** at developer.apple.com (Keys → APNs).
2. In Xcode: **CraftyMobile** target → **Signing & Capabilities** →
   **+ Capability → Push Notifications** (the `aps-environment` entitlement is
   already in the project).
3. Deploy the relay (A) or run the server (B).
4. In the app: **Settings → Live updates (push)** → enter the relay/server URL.
   For the relay, copy the shown **Crafty webhook URL** into Crafty → Webhooks.

> Honest limits: *alert* pushes (up/down/crash) are instant. Apple throttles
> background/silent widget refreshes to a few per hour, so the widget is always
> current for status changes and as fresh as Apple allows otherwise. This is the
> only way to beat iOS's widget/background throttling without opening the app.

## Project structure

```
crafty/                             # repo root
├─ README.md                        # this file
├─ CraftyMobile/                    # iOS app (Xcode project)
│  ├─ CraftyMobile.xcodeproj/       # Xcode project (synchronized file groups)
│  ├─ CraftyMobile/                 # APP target
│  │  ├─ CraftyMobileApp.swift      # @main entry; owns AppSettings + AppLockManager
│  │  ├─ Info.plist                 # ATS exception + Face ID + background modes
│  │  ├─ CraftyMobile.entitlements  # App Group + push (aps-environment)
│  │  ├─ Assets.xcassets/           # App icon + accent color
│  │  ├─ Models/                    # tolerant Codable models + parsing
│  │  ├─ Networking/                # CraftyAPI, APIError, AppSettings, Keychain
│  │  ├─ Security/                  # AppLockManager (Face ID / passcode)
│  │  ├─ Background/                # BGAppRefresh, AppDelegate, PushManager
│  │  ├─ Shared/                    # WidgetSnapshot (written for the widget)
│  │  ├─ ViewModels/                # polling-aware view models
│  │  ├─ Theme/                     # colors, surfaces, haptics
│  │  └─ Views/                     # RootView, lists, detail, logs, console,
│  │                                #   Settings, Lock, Components/
│  └─ CraftyWidget/                 # WIDGET extension target (self-contained)
│     ├─ CraftyWidgetBundle.swift   # @main WidgetBundle
│     ├─ CraftyWidget.swift         # widget config + timeline provider + views
│     ├─ WidgetData.swift           # App Group config read + live fetch + fallback
│     ├─ Info.plist                 # WidgetKit extension point + ATS exception
│     ├─ CraftyWidget.entitlements  # App Group (same group as the app)
│     └─ Assets.xcassets/           # accent color
├─ relay/                           # push option A: Cloudflare Worker (recommended)
│  ├─ src/worker.js                 # zero-knowledge APNs relay (webhook → push)
│  ├─ wrangler.toml                 # Worker config (KV + vars)
│  ├─ setup.sh                      # one-command deploy
│  └─ README.md                     # deploy guide
└─ server/                          # push option B: self-hosted Node poller (Docker)
   ├─ crafty-push.js                # poll Crafty → APNs alert/silent pushes
   ├─ package.json
   ├─ Dockerfile                    # tiny Alpine image (no install step)
   ├─ docker-compose.yml            # run as a sidecar next to Crafty
   ├─ .env.example                  # configuration template
   └─ README.md                     # push + Docker setup guide

# (.github/workflows/docker-publish.yml builds + pushes the server image to GHCR)
```

## Notes on the tricky bits

- **Self-signed TLS** — `CraftyAPI`'s `URLSessionDelegate` accepts the server's
  certificate chain only when *Allow self-signed certificates* is ON; when OFF,
  it falls back to the system's default validation. The setting is read fresh
  before every request. `Info.plist` also carries an App Transport Security
  exception so plain-HTTP / weak-TLS LAN endpoints aren't blocked.
- **Tolerant decoding** — Crafty's JSON varies across versions; numbers
  sometimes arrive as strings, booleans as ints, and the player list is a
  *string* (`"[]"`, `"['Steve']"`, …). Models decode all of this defensively and
  never crash on surprising input — worst case a field shows `—`.
- **Auth** — every request sends `Authorization: Bearer <token>`. A `401`/`403`
  surfaces a clear "check your token" banner rather than failing silently.

## Troubleshooting

- **"iOS 26.x is not installed" / asset-catalog build error** — Xcode is missing
  the iOS platform/simulator runtime that matches its SDK. Install it via
  **Xcode → Settings → Components**, then rebuild. (Building straight to a
  physical device only needs the iOS device support, which Xcode offers to
  install the first time you connect your phone.)
- **"Could not verify the server's certificate"** — turn **Allow self-signed
  certificates** ON in Settings.
- **"Authentication failed"** — regenerate the API token in Crafty and re-paste.
- **Nothing loads** — confirm the URL/port is reachable from your phone's
  network and that Crafty's API is enabled.
