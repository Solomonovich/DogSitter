# DogSitter — Session Handoff

_Last updated: 2026-06-21 · `main` @ `b4fb214`_

This document summarizes the work done in this session and the goals/known gaps going
forward. It's written so the next person (or next session) can pick up cleanly.

---

## TL;DR

This session delivered **walk tracking that survives the phone being locked**, a **Live
Activity (Dynamic Island + Lock Screen)** for the active walk — now with **interactive
Pause/Resume/End buttons and tap-to-open** — plus three smaller walk features, two bug
fixes, and the commit of a large backlog of previously-uncommitted work. Everything is
merged to `main` via two PRs (#9, #10). The **main outstanding item is real-device
verification** (the simulator can't exercise Live Activities / background location, and CI
doesn't build the iOS app).

---

## What shipped this session

### 1. Browse-posts drag handle hit target (`BrowsePostsView.swift`)
Enlarged the grab-handle touch target on the "פוסטים" sheet **without changing its
appearance** (grow with padding → capture as content shape → negate the added space; `zIndex`
so the lower part wins over the carousel). You can now grab the handle slightly off-center.

### 2. Background tracking + Live Activity + 3 extras — **PR #9**
The headline feature. Key parts:
- **Background location**: `UIBackgroundModes:[location]` + `allowsBackgroundLocationUpdates`
  enabled **only during an active walk**. Permission stays **When-In-Use** (not Always).
- **Live Activity** (Dynamic Island + Lock Screen): new `WalkActivityWidget` app-extension
  target. **Local-update only** — no APNs / App Group / server.
- **Authoritative driver moved into `LocationTracker`**: the 5-second Firestore sync + Live
  Activity updates used to live in `WalkFullView` and died when you left the screen. They now
  run from a tracker-owned timer, so tracking continues backgrounded and across screens.
- **Pause/Resume**: `isPaused` field on the **walk doc** (never a `status` change — Firestore
  rules require `status=='active'`); route stored as `routeSegments` so a pause shows a map gap.
- **Post-walk recap card** (`WalkRecapView` + `RouteSnapshotter`): route snapshot, distance,
  duration, average pace, photos, ShareLink.
- **Live owner map + alerts**: owner sees a live position marker + recenter; in-app
  stray/long-walk banners; sitter-side **local notifications** (`NotificationManager`).

### 3. Interactive Live Activity + tap-to-open — **PR #10**
- **Pause/Resume + End buttons** on the expanded Dynamic Island and Lock Screen (not allowed
  in compact/minimal).
- Buttons are `LiveActivityIntent`s whose `perform()` runs **in the app process**, bridged via
  an in-process `WalkActivityActionCenter` → **no App Group required**. Intents carry `walkId`
  so they work even if a tap relaunches a force-quit app.
- **Tap-to-open**: registered the `dogsitter://` URL scheme + `onOpenURL` →
  `AppState.openWalk(byId:)` → existing sitter `openChat` teleport (lands in the walk's chat).

### 4. Bug fixes
- **Address onboarding (`AddressAutocompleteView.swift`)**: the contact-details step only
  committed an address when you tapped a MapKit autocomplete suggestion. On a device where the
  completer returned nothing (network/region/iOS state — e.g. the 14 Pro Max), users were
  hard-blocked. Fix: typed text now also commits as the address.
- **Device install rejection (`project.yml`)**: the appex shipped with an empty
  `CFBundleVersion`, which a device install rejects. Added `MARKETING_VERSION`/
  `CURRENT_PROJECT_VERSION` at the project level so app + appex share a non-empty, matching
  version (currently 1.0 / 1).

### 5. Committed the prior backlog
PR #9 also committed a large amount of previously-uncommitted work that was sitting in the
tree: design-system additions (`ProfileAvatar`, `ThemePickerView`, `Radius`, `Typography`,
`Theme`, `AppearancePreferences`, `Date+ChatTime`), chat work (`ChatReadStore`,
`ChatComponents`), posts work (`PostComponents`), and `ProfileComponents`.

---

## Architecture & key decisions (so you don't re-derive them)

- **`LocationTracker.shared` is the source of truth** during a walk. It owns the GPS stream,
  the 1s elapsed clock, the 5s sync/Live-Activity driver, pause state, and segmented route.
  `AppState.beginWalkSession` wires its `onSync` / `onLiveActivityUpdate` callbacks;
  `endWalkSession` tears them down + ends the Activity.
- **Live Activity updates are local.** Background location keeps the app alive during a walk,
  which is what lets the app push Live Activity updates without APNs.
- **Interactive buttons need App Intents only, NOT an App Group**, because
  `LiveActivityIntent.perform()` runs in the app process. The shared file
  `Sources/Shared/WalkActivityIntents.swift` is compiled into **both** targets and must stay
  dependency-free (Foundation + AppIntents only).
- **Pause = a field on the walk doc**, never a `status` change (`firestore.rules` only allow
  walk updates while `status=='active'`, and chat messages are immutable).
- **Owner alerts are in-app only** (+ sitter local notifications). Real out-of-app owner
  alerts were **intentionally declined** (would need remote push).
- **XcodeGen owns the project.** Edit `project.yml`, run
  `./xcodegen_bin/xcodegen/bin/xcodegen generate --spec project.yml`, never hand-edit
  `project.pbxproj`. Build with `-scheme DogSitter` (not `-target`). Shared files must be
  listed explicitly in the widget target's `sources`.

See also the persisted memory note `walk-tracking-overhaul.md` for the condensed version.

---

## Key files

| Area | Files |
|---|---|
| Tracking engine | `Sources/Services/LocationTracker.swift` |
| Live Activity manager | `Sources/Services/WalkLiveActivityManager.swift` |
| Live Activity UI | `Sources/WalkActivityWidget/WalkActivityLiveActivity.swift`, `WalkActivityWidgetBundle.swift` |
| Shared (both targets) | `Sources/Shared/WalkActivityAttributes.swift`, `Sources/Shared/WalkActivityIntents.swift` |
| Walk flow / state | `Sources/App/AppState.swift`, `Sources/Views/WalkFullView.swift`, `Sources/Views/PreWalkView.swift` |
| Recap / snapshot | `Sources/Views/WalkRecapView.swift`, `Sources/Services/RouteSnapshotter.swift` |
| Notifications | `Sources/Services/NotificationManager.swift` |
| Deep link / launch | `Sources/App/DogSitterApp.swift`, `Sources/Info.plist` |
| Project config | `project.yml` |

---

## Outstanding / must-do

1. **Real-device verification** (cannot be done in simulator; CI doesn't build the app):
   - Background tracking continues with the phone locked / app backgrounded (route + distance).
   - Live Activity appears on Dynamic Island + Lock Screen; clock ticks; distance updates ~5s.
   - Interactive **Pause/Resume** and **End** buttons work from the Island/Lock Screen.
   - **Tap-to-open** opens the walk's chat.
   - Pause/Resume map gap; post-walk recap card; owner live marker + alerts.
2. **Rotate the GitHub token.** A personal access token is embedded in plaintext in the git
   remote URL. Rotate it and switch to SSH or a credential helper:
   `git remote set-url origin https://github.com/Solomonovich/DogSitter.git` then `gh auth login`.

---

## Future goals / backlog

- **CI should build the iOS app.** Today `.github/workflows/ci.yml` only runs Firestore-rules
  and SecurityKit tests — Swift/app regressions are not caught. Add an `xcodebuild -scheme
  DogSitter` job.
- **Repo hygiene**: `UserInterfaceState.xcuserstate`, `Sources/.DS_Store`, and `xcuserdata/`
  are tracked and noisy — consider `.gitignore`-ing them.
- **Remote push (APNs/FCM)**: would unlock real out-of-app **owner** alerts (walk
  start/stop/photo, stray/long-walk) — currently only `print` placeholders + in-app banners.
- **Live Activity ideas previously suggested but not built** (revisit if wanted): average pace
  + photo count in the expanded view, a red "alert state" Island for stray/long walks, push
  updates so the Activity refreshes while the app is fully suspended.
- **Deep link could route directly to `WalkFullView`** (currently lands in the chat).
- **"Always" location permission** if walks need to survive a force-quit (currently
  When-In-Use; after a force-quit, Pause/End still work via the intent but GPS won't auto-resume
  until the walk screen is reopened).
- **Recap polish**: share the whole card via `ImageRenderer`; persist a route snapshot.

---

## How to build / run

```bash
# regenerate after any Sources/ or project.yml change
./xcodegen_bin/xcodegen/bin/xcodegen generate --spec project.yml

# compile check (simulator)
xcodebuild -project DogSitter.xcodeproj -scheme DogSitter \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
Run the **DogSitter** scheme on a **real device** for Live Activity / background features.
(The separate `WalkActivityWidget` scheme is the extension — don't run it directly.)
