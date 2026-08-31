# BloodLink

**Emergency blood donor coordination.** One account, two loops: request blood when
you need it, and help as a donor when someone nearby does. BloodLink is a
peer-to-peer coordination app — not a hospital, blood-bank, or inventory system.
Hospitals are only destinations attached to a request.

```
REQUEST BLOOD → FIND DONORS → DONOR ACCEPTS → COORDINATE → FULFILL
ENABLE DONOR MODE → RECEIVE OPPORTUNITY → ACCEPT → COORDINATE → HELP
```

Built with Flutter for **Android, iOS, and web** from a single codebase.

---

## Status

This repository is the **Flutter frontend**, built against a **swappable
in-memory backend** (`lib/data/mock/`) that simulates the real system:
progressive donor-matching waves, the request state machine, live status
updates, and chat. When the production backend (FastAPI + PostgreSQL/PostGIS +
matching worker + FCM + WebSockets) is ready, only the repository/data layer is
replaced — screens and state consume the same models and streams unchanged.

> iOS builds require macOS + Xcode. Android and web build and run on any
> platform, including the Windows machine this was developed on.

## Architecture

```
lib/
  main.dart                     App entry (MaterialApp.router)
  core/
    theme/                      Design tokens: semantic colors (ThemeExtension),
                                IBM Plex type system, spacing/radius, enum→color
    router/                     go_router config + auth-aware redirect
    widgets/                    Design-system components (badges, buttons, cards,
                                states, timeline, pickers…)
    utils/                      Formatters
  data/
    models/                     Domain entities + enums (incl. request state machine)
    mock/                       In-memory backend (the swappable seam)
    providers.dart              Riverpod providers (auth, requests, donor, chat…)
  features/                     One folder per feature (screens + local widgets)
    splash, auth, home, requests, donate, invitations,
    coordination, notifications, profile, shell
  shared/                       Cross-feature widgets (brand mark, segmented control…)
```

- **State management:** Riverpod. UI state (form step, selected tab) is kept
  separate from server/domain state (request status, donor availability,
  messages) — the backend stream is always the source of truth.
- **Routing:** go_router with a `StatefulShellRoute` for the 4-tab shell (Home,
  Requests, Donate, You) and contextual full-screen routes for create/track/
  coordinate/chat/location. Notifications deep-link to the relevant screen.

## Design

Calm, neutral chrome so that **red carries meaning** — it's reserved for brand
identity and critical urgency, never used as wallpaper. The urgency ladder
doubles as the semantic color ladder (routine→blue, urgent→amber, critical→red).
Critical data — blood groups, units, distances, ETAs, timestamps — is set in
**IBM Plex Mono**, giving the app the precise feel of a dispatch console.
Full light and dark themes. Status is always conveyed by label + icon, not color
alone.

## Run it

```bash
flutter pub get
flutter run -d chrome        # web
flutter run -d <android-id>  # android device/emulator
flutter test                 # widget tests
flutter analyze              # static analysis (0 errors, 0 warnings)
```

## The demo backend

Because there's no live server yet, the mock backend scripts a realistic flow:
create a request and it advances on its own — *created → searching* (donors
contacted in widening waves) *→ a donor accepts → coordinating* — with the
tracking screen updating live. Turn on Donor Mode to see incoming opportunities;
accept one to open a coordination context with private chat.
