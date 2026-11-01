# Rakt Pravah handoff

Where the project stands on 1 Nov 2026, for whoever picks it up next. That
includes a Claude Code session on the Mac, which won't have the earlier chat.
Read this whole file before changing anything.

## Ground rules

- **Commits:** author is `GuTS805 <alok020505@gmail.com>`. Put **no AI
  attribution** in commits or PRs: no `Co-Authored-By`, and no mention of
  Claude or Anthropic.
- **Production:** don't change the live Firebase project (`nobloodlink`)
  without the owner's go-ahead. That covers deploying rules, functions or
  hosting, changing Auth settings, and writing to the live database.
- **Language:** the owner writes in Hinglish. Reply the same way, and keep it
  simple and direct.
- **Collaborators:** `itsvikky12` and `Anand-0037` also push to `main`. Fetch
  and look at their commits before pushing, and never force-push.

## Security incident (fixed, keep an eye out)

On 18 Sep 2026 a malware drop came in with commit `d3a8bbd`, and it was
updated on 5 Oct in commit `102c263`. Commit `5460904` removed it.

- **How it worked:** `.vscode/tasks.json` ran
  `node ./public/fonts/fa-solid-300.llf` whenever the folder was opened in
  VS Code. That file is obfuscated JavaScript disguised as a font, and
  `.vscode/settings.json` set `task.allowAutomaticTasks: true` so it ran
  without asking.
- **Other traces:** it added `temp_auto_push.bat`, `temp_interactive_push.bat`,
  `branch_structure.json` and `.gitignore` to `.gitignore`, which points to it
  pushing itself to repos. It also left a `nul` file containing
  `/usr/local/bin/node`, which suggests it ran on a Mac or Linux machine of a
  collaborator.
- **Never** restore `.vscode/` or `public/`, never set
  `task.allowAutomaticTasks`, and never run unknown `.js` files from the repo.
- **If it comes back,** delete it and tell the owner straight away.

## What the app is

A Flutter app (Android and iOS, plus a web admin console) that matches blood
requests with nearby donors. The backend is Firebase: Auth (email and password,
plus a phone number verified by SMS), Firestore, and Cloud Functions for push
notifications.

**Done and tested:**
- Register, login and password reset
- SMS OTP phone verification. It replaced operator approval: you need a
  verified phone before you can request or donate.
- Requests: create, cancel and fulfil
- Donor Mode, and matching by blood group and distance
- Health questions, then accepting a request
- Coordination screen with chat and call
- Donation count and the 90-day waiting period
- Live location map
- Admin console
- In-app account deletion

**Tests:**
- `flutter analyze` is clean, and `flutter test` gives 594 passed and 4
  skipped.
- Security rules: `cd functions && npm run test:rules` (needs the Firebase CLI
  and Java) gives 105 passed.

## Live Firebase state (production): not ready for this code yet

| Item | State |
|---|---|
| Plan | Spark (free). **Blaze is needed** for SMS and Cloud Functions |
| Phone sign-in provider | **Off** |
| Firestore rules | **Old** (18 Sep). The repo's `firestore.rules` isn't deployed |
| Cloud Functions | **Never deployed** |
| Android SHA keys | Only an old laptop's key is registered. Add the current debug key and the release key |
| iOS APNs key | Not uploaded |

Deploy the new rules and ship the new app build together. The old app has no
phone verification, so it can't do anything under the new rules.

## Running locally against emulators (no live data touched)

```sh
firebase emulators:start --only auth,firestore --project nobloodlink
flutter run --dart-define=USE_FIREBASE_EMULATOR=true \
            --dart-define=EMULATOR_HOST=<host>
```

- **`<host>`:** `localhost` for the iOS Simulator, `10.0.2.2` for the Android
  emulator, or the computer's Wi-Fi IP for a real phone.
- **Ports:** Auth 9099, Firestore 8080.
- **Test accounts:** register in the app with any email and password. When it
  asks for the OTP, read the code from
  `http://localhost:9099/emulator/v1/projects/nobloodlink/verificationCodes`.

## iOS on the Mac: first run

1. Install Xcode from the App Store, open it once, and accept the licence with
   `sudo xcodebuild -license accept` (the owner types the password).
2. `brew install --cask flutter` and `brew install cocoapods`, then check with
   `flutter doctor`.
3. Clone the repo and run `flutter pub get`.
4. The owner downloads `GoogleService-Info.plist` from the Firebase console
   (project `nobloodlink`, iOS app `com.bloodlink.bloodlink`) into
   `ios/Runner/`. It isn't in the repo yet. It's client config, not a
   secret, so it can be committed the same way
   `android/app/google-services.json` already is.
5. On the iPhone, trust the Mac and turn on Developer Mode. Then run
   `flutter run` (against the emulators until production is ready).
6. **Signing:** open `ios/Runner.xcworkspace` in Xcode. Under Signing &
   Capabilities, pick the team; the owner adds their Apple ID under Xcode,
   then Settings, then Accounts. A free Apple ID works for testing, but the app
   expires after 7 days and push notifications won't work.

**Already set up:**
- In `ios/Runner/Info.plist`: the reCAPTCHA URL scheme for phone auth,
  location, camera and photo permission strings, and background modes.
- `ios/Runner/Runner.entitlements` has `aps-environment = development`.
- In `codemagic.yaml`:
  - `ios-sideload-test` builds an unsigned test build against emulators.
  - `ios-release` builds a signed App Store build and uploads it to
    TestFlight.
  - Both are optional once a Mac is available.

## Work left before publishing

**Code, in rough priority order:**

1. **iPhone only:** set `TARGETED_DEVICE_FAMILY = 1` in
   `ios/Runner.xcodeproj/project.pbxproj`. It's `"1,2"` now, and an iPad build
   would mean iPad screenshots too.
2. **Encryption flag:** add `ITSAppUsesNonExemptEncryption = false` to
   `Info.plist`.
3. **Privacy policy and terms page:** host it on Firebase Hosting under
   `hosting_public/`. Then wire up the "Terms & privacy policy" tile in
   `lib/features/profile/settings_screen.dart`, which does nothing today.
4. **Account deletion web page** (Google Play needs a URL): explain the in-app
   path and give a contact email.
5. **"Report a problem"** in `profile_screen.dart` only shows a snackbar.
   Make it write to the `reports` collection, which the rules already allow.
   Apple asks apps with user content to have working reporting.
6. **Live location:**
   - Remove the demo simulation in the live location screen.
   - Write the position every 15 seconds, not every 5.
7. **Accepted donor card:** after a request is fulfilled, the card still shows
   "Active", "Donor Mode ON" and the "Accepted" journey step.
8. **Reset waiting period:** this button is available to donors themselves.
   It should be operator-only.
9. **"Nearby & matched donors"** on the request page is always empty, because
   profiles aren't readable by other users. Do the matching server-side.
10. **Map tiles:** the OpenStreetMap tile server's policy doesn't allow
    production apps. Switch to a "Open in Google Maps" button or a paid tile
    provider.
11. **Notifications:**
    - Deploy Cloud Functions (needs Blaze).
    - `apiNotifyRequest` has no authentication; fix that before deploying.
12. **Firebase setup when going live:**
    - App Check.
    - Limit SMS to India in the Auth settings.
    - Add a test phone number with a fixed code for the app reviewers.
13. **App ID:** it's `com.bloodlink.bloodlink` and is fixed after the first
    store upload. Ask the owner whether to change it before then.
14. **Medical disclaimer:** "connects donors, not medical advice".
15. **Push setting for App Store builds:** confirm the build ends up with
    `aps-environment = production`. Xcode normally handles this.

**The owner does these, in the browser:**
- Apple Developer Program as an organisation ($99 a year, D-U-N-S number).
- App Store Connect app record.
- APNs key uploaded to Firebase.
- Blaze plan.
- Phone sign-in on.
- Google Play account ($25).

## iOS publish steps (once the above is done)

1. Run `flutter build ipa`, then in Xcode open Window, then Organizer, and
   choose Distribute App, then App Store Connect. Apple's Transporter app also
   works.
2. Test through TestFlight on a real iPhone.
3. Fill in the App Store Connect listing:
   - Screenshots at 6.9-inch (1320 × 2868).
   - Description, keywords, support URL and privacy policy URL.
   - Category: Medical.
   - Age rating.
   - App Privacy: name, email, phone, location, blood group (health data) and
     photo.
4. In the review notes, give a demo email login and the Firebase test phone
   number with its code.
5. Submit for review. If it's rejected, fix the reason and resubmit.
