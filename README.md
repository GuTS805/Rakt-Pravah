# Rakt Pravah

**Emergency blood donor coordination.** One account, two loops: request blood when
you need it, and help as a donor when someone nearby does. Rakt Pravah is a
peer-to-peer coordination app — not a hospital, blood-bank, or inventory system.
Hospitals are only destinations attached to a request.

```
REQUEST BLOOD → FIND DONORS → DONOR ACCEPTS → COORDINATE → FULFILL
ENABLE DONOR MODE → RECEIVE OPPORTUNITY → ACCEPT → COORDINATE → HELP
```

Built with Flutter for **Android, iOS, and web** from a single codebase.

---

## Status

This repository is the **Flutter client**. Its default production data layer is
Firebase Authentication plus Cloud Firestore (`lib/data/firebase/`), isolated
behind the typed `Backend` interface. Tests override that interface with a fake
backend, so UI and domain flows can be exercised without a live Firebase
project. Firestore rules live in `firestore.rules`; deploy and validate them
separately from an app build.

Rakt Pravah coordinates registered people. It does not claim hospital
partnerships, blood-bank inventory, automated medical eligibility, or a medical
recommendation engine. Medical decisions remain with qualified professionals.

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
    firebase/                   Firebase Auth + Firestore backend
    backend.dart                Typed backend contract (the swappable seam)
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

## Operations console

The console is a second entrypoint into the same codebase, deployed on its own
site: **https://raktpravah-admin.web.app**. Operators sign in with an email and
password; the mobile app never asks for either.

```bash
flutter build web -t lib/main_admin.dart --pwa-strategy=none
rm -rf hosting_admin && cp -r build/web hosting_admin
firebase deploy --only hosting
```

Granting access to the first operator is a manual step, by design: no rule
lets an account promote itself. Create the account under Authentication in the
Firebase console, sign in once so the profile document appears, then set
`isAdmin: true` on that document in Firestore. Every operator after that can be
granted from the console's own Users page.

## Tests

```bash
flutter test                    # app: screens, models, the real FirebaseBackend on in-memory fakes
cd functions && npm test        # notification matching, push payloads, endpoint access
cd functions && npm run test:rules   # Firestore security rules (needs Java; starts the emulator)
```

- **Screens** run against `FakeBackend` (`test/fakes.dart`). **`FirebaseBackend`** itself runs
  against `fake_cloud_firestore` and `firebase_auth_mocks` (`test/firebase_backend*_test.dart`),
  so what gets written to Firestore is checked too.
- **Privacy and access** are covered in `functions/test/rules/`, which exercises the real
  `firestore.rules`, and in `test/privacy_test.dart`.
- Tests marked **KNOWN GAP** / `todo` describe behaviour that is still missing (for example the
  admin-email rule and the unauthenticated notify endpoint). They are skipped or reported as
  `todo` so the suite stays green; each turns into a normal failing test the moment it is
  un-skipped, and into a pass once the gap is fixed.
- Run the app against the Firebase emulators with
  `flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true`.

## Local development boundaries

The test suite uses `FakeBackend` from the test tree. Passing it is local test
evidence only; it does not verify Firebase Authentication, Firestore rules,
notifications, or a deployed release.

Maps use OpenStreetMap tiles during development and visibly attribute their
source. The tile endpoint is configurable for a policy-compliant production
provider or self-hosted tile service:

```bash
flutter run --dart-define=MAP_TILE_URL='https://tiles.example.com/{z}/{x}/{y}.png'
```

Do not treat the public OpenStreetMap tile service as a production CDN. Review
the provider's usage policy before launch.
