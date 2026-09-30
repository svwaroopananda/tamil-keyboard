# Tamil Keyboard

A custom iOS keyboard extension that transliterates English text into casual,
conversational Tamil written in the English (Latin) alphabet — the way Tamil
speakers actually type Tamil in WhatsApp chats ("Tanglish") — powered by the
Claude API.

## Architecture

```
┌─────────────────────┐        ┌──────────────────┐        ┌──────────────┐
│  iOS Keyboard        │  HTTP  │  Node/Express     │  HTTPS │  Claude API  │
│  Extension            │ ─────> │  backend           │ ─────> │              │
│  (runs inside the app  │        │  POST /translate   │        │              │
│   the user is typing   │ <───── │  holds the         │ <───── │              │
│   in, e.g. Messages)   │        │  Anthropic API key  │        │              │
└─────────────────────┘        └──────────────────┘        └──────────────┘
        ▲
        │ embeds / ships with
┌─────────────────────┐
│  iOS Host App          │
│  (onboarding only:      │
│   enable keyboard +     │
│   Full Access)          │
└─────────────────────┘
```

**Why the Claude API key lives on a backend, not in the app:** an iOS app
binary (and an app extension binary) can be unpacked and inspected by anyone
who downloads it — there is no way to embed a secret in client code and keep
it secret. If the Anthropic API key shipped inside the keyboard extension,
anyone could extract it and use it on our account. Routing translation
requests through a small server we control means the real API key only ever
exists there; the app only ever talks to our own `/translate` endpoint.

**Why there are two iOS targets (host app + extension), not one:** Apple
requires every custom keyboard to ship inside a containing app — a keyboard
extension can't be distributed standalone. The two are separate binaries,
loaded into separate processes at runtime (the extension runs inside
whatever app the user is actively typing in), embedded together into one
downloadable `.app` bundle at build time. See `ios/project.yml` for exactly
how they're wired together, and inline comments in
`ios/KeyboardExtension/KeyboardViewController.swift` for how the extension
talks to the host app's text field via `UITextDocumentProxy`, and why the
extension needs the user to grant "Full Access" before it's allowed to make
any network request at all (keyboard extensions are network-sandboxed by
default, since a keyboard sees everything a user types).

## Project structure

```
backend/    Node/Express server — the only thing holding the Claude API key
ios/        Xcode project: host app target + keyboard extension target
  project.yml   xcodegen spec — source of truth for both targets
```

## Setup

### 1. Clone and install backend dependencies

```bash
git clone <this-repo-url>
cd tamil-keyboard/backend
npm install
```

### 2. Configure your Claude API key

```bash
cp .env.example .env
```

Then edit `backend/.env` and set your own key (get one at
[console.anthropic.com](https://console.anthropic.com)):

```
ANTHROPIC_API_KEY=sk-ant-your-real-key
PORT=3000
```

`backend/.env` is gitignored — it will never be committed, and this repo's
history has never contained a real key (confirmed before this repo's first
commit).

### 3. Run the backend locally

```bash
npm start
```

You should see:

```
Tamil transliteration backend listening on http://localhost:3000
```

Verify it works with curl before touching Xcode:

```bash
curl -X POST http://localhost:3000/translate \
  -H "Content-Type: application/json" \
  -d '{"text": "What are you doing right now?"}'
```

### 4. Generate and open the Xcode project

The `.xcodeproj` is generated from `ios/project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not committed to
this repo.

```bash
brew install xcodegen   # if you don't already have it
cd ios
xcodegen generate
open TamilKeyboard.xcodeproj
```

### 5. Select your development team for signing

In Xcode:

1. Select the **TamilKeyboardApp** target → **Signing & Capabilities** →
   choose your own **Team** under "Signing" (a free personal Apple ID team
   works for Simulator and local device testing).
2. Repeat for the **KeyboardExtension** target.

Note: running purely in the iOS **Simulator** generally works out of the box
without picking a team at all (Xcode signs it "to run locally"). A team is
only strictly required once you build for a physical device. If Xcode
complains about the bundle identifier already being taken by another team,
change `PRODUCT_BUNDLE_IDENTIFIER` (and `bundleIdPrefix`) in
`ios/project.yml` to your own reverse-DNS string, then re-run
`xcodegen generate`.

### 6. Run in Simulator

With the backend still running locally (step 3), select the
**TamilKeyboardApp** scheme in Xcode and run it (`Cmd+R`) on any simulator.
This installs both the host app and the keyboard extension.

### 7. Enable the keyboard (manual, one-time, per simulator/device)

1. In the Simulator, open **Settings → General → Keyboard → Keyboards →
   Add New Keyboard...** and select **Tamil Keyboard**.
2. Tap **Tamil Keyboard** in the list again and enable **Allow Full
   Access**. This is required because the keyboard sends typed text to the
   local backend over the network — without it, translation requests will
   fail at the sandbox level.
3. Open any text field (e.g. Notes), switch to the keyboard via the globe
   key, type some English, and tap **Translate**.

### Testing on a physical device

`http://localhost:3000` only resolves to your Mac when run in the
**Simulator**, which shares your Mac's network stack. On a physical device,
`localhost` refers to the device itself — update `backendURL` in
`KeyboardViewController.swift` to your Mac's LAN IP (or a deployed backend
URL) instead.
