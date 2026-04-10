# MacClipper

A lightweight macOS menu-bar replay-buffer app inspired by Medal.tv.

## Super Simple GitHub Help

If you want the easiest possible GitHub update steps, read:

`GITHUB-UPDATE-README.md`

## What it does
- Lives in the **top menu bar** as an icon
- Keeps a rolling replay buffer of your desktop display
- Lets you choose which monitor the replay buffer targets when multiple displays are connected
- Saves the **last 30 seconds** (or a custom duration) with a global shortcut
- Lets you say **"Mac clip that"** to trigger a clip hands-free while the app is open
- Captures **system audio** and **microphone audio** into the exported clip
- Keeps the replay buffer armed on launch and re-arms it after interruptions
- Lets you tweak settings for clip length, shortcut, cursor visibility, and save folder

## Run it
```bash
cd /Users/meteorite/macclipper
swift run
```

## Run the local API
```bash
cd /Users/meteorite/macclipper
npm install
npm run web:start
```

That server exposes the local JSON API and bot-facing API on:

```text
http://127.0.0.1:4173
```

## Bot API
Point the Discord bot at this repo's backend with:

```text
MACCLIPPER_API_BASE_URL=http://127.0.0.1:4173
```

The backend keeps its config locked in `backend/config.env`. To print the generated bot API secret for `MACCLIPPER_BOT_SHARED_SECRET`, run:

```bash
cd /Users/meteorite/macclipper
npm run web:bot-secret
```

The bot contract now includes:

- `GET /api/bot/users/lookup`
- `POST /api/bot/users/link-discord`
- `POST /api/bot/users/admin`
- `POST /api/bot/users/status`
- `POST /api/bot/users/subscription`
- `POST /api/bot/users/features/grant`
- `GET /api/entitlements/by-user-id`

`/api/bot/users/features/grant` returns a `macclipper://purchase-complete?...` activation URL, and linked apps can also pick the same feature up live from `/api/entitlements/by-user-id`.

This repo no longer ships a bundled website frontend. The separate website running elsewhere on your machine is the one meant for the account and purchase UI.

## Package it as a `.app`
```bash
cd /Users/meteorite/macclipper
./scripts/package_app.sh
open dist/MacClipper.app
```

## Build a drag-and-drop `.dmg`
```bash
cd /Users/meteorite/macclipper
./scripts/build_dmg.sh
open dist/MacClipper.dmg
```

## Built-in updater feeds
Sparkle-enabled builds now use this hosted appcast:

```text
https://raw.githubusercontent.com/Userbro20/macclip-auto-update/main/appcast.xml
```

Older pre-Sparkle builds still use this legacy migration feed once:

```text
https://raw.githubusercontent.com/Userbro20/macclip-auto-update/main/update-feed.json
```

Both feeds should reference the same packaged HTTPS release archive:

```text
MacClipper.zip
```

Generate that archive plus both feed files with:

```bash
cd /Users/meteorite/macclipper
./scripts/release_with_update.sh
```

Set `MACCLIPPER_RELEASE_NOTES` first if you want custom release notes in the generated appcast.

## Permissions
On first launch, macOS will ask for:
- **Screen Recording / System Audio Recording**
- **Microphone access**
- **Speech Recognition** for the voice clip phrase

If clips fail, re-enable permissions in:
`System Settings → Privacy & Security`

## Discord Rich Presence
MacClipper can publish Discord Rich Presence while the app is open.

To show the MacClipper name and icon in Discord, set a real Discord application ID in `AppResources/Info.plist` under `DiscordRichPresenceClientID`, then upload the MacClipper icon to that Discord application with the asset key `macclipper`.

The activity text and button URLs are also defined in `AppResources/Info.plist`. The visual card layout itself is controlled by Discord.
