# OnTrack

[<img src="https://img.shields.io/badge/Download_on_the-App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store" />](https://apps.apple.com/us/app/ontrack-fitness-faith/id6791721388)

All-in-one personal fitness app for iPhone: body weight, gym workouts/splits, diet tracking, and an AI coach powered by Google Gemini. Local-first (SwiftData) — no accounts, no user-data backend.

## Setup

1. **Install Xcode** from the Mac App Store (required — Command Line Tools alone can't build iOS apps). Then: `sudo xcode-select -s /Applications/Xcode.app`
2. **AI proxy** — the app's AI features call a small Cloudflare Worker that holds the Gemini key (never shipped in the app). Deploy it and set `AIClient.endpoint`: see [`proxy/README.md`](proxy/README.md).
3. **USDA key** (optional) — edit `Config/Secrets.xcconfig`, set `USDA_API_KEY` from [api.data.gov](https://api.data.gov/signup/) for whole-food search. Open Food Facts works without any key.
4. **Open** `OnTrack.xcodeproj`, select the OnTrack target → Signing & Capabilities → pick your Apple Developer team.
5. **Run** on your iPhone (HealthKit, camera, and notifications need real hardware).

If you change `project.yml`, regenerate with `xcodegen generate`.

## TestFlight

Archive (Product → Archive) → Distribute → App Store Connect → TestFlight. External tester groups need Beta App Review on the first build (~1–2 days); after that, invite friends by email or public link.

## Structure

- `OnTrack/Sources/Models/` — SwiftData models (CloudKit-compatible: defaults on everything, optional relationships) + bundled exercise database (616 exercises, read-only JSON kept out of SwiftData so CloudKit sync doesn't duplicate it)
- `OnTrack/Sources/Services/` — HealthKit, food search (Open Food Facts + USDA), AI client (Gemini via proxy), notifications, TDEE/macro math
- `proxy/` — Cloudflare Worker that fronts the Gemini API
- `OnTrack/Sources/Views/` — one folder per tab: Today, Diet, Workout, Weight, Coach, Settings, plus Onboarding
