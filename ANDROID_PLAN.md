# OnTrack → Google Play: Architecture & Migration Plan

_Planning pass, 2026-07-24. Nothing implemented yet._

---

## 0. Read this first — the three things that change the plan

1. **This project is not under version control.** There is a `.gitignore` but no `.git`. You cannot run a two-platform, long-term-parity project without it. This is the single largest risk in the document and it costs 10 minutes to fix.
2. **The shareable surface is ~700 of 4,810 lines (≈15%).** Everything else is SwiftUI. That number is what drives the recommendation below, and it is the number to re-check if you disagree with the conclusion.
3. **iOS is on a trajectory to free CloudKit sync; Android has no equivalent.** SwiftData + CloudKit gives you multi-device sync with zero backend once the paid Apple account is active. Any shared-persistence architecture (KMP/SQLDelight, Room-everywhere) throws that away and replaces it with "build a sync backend." This is a product decision, not a technical one, and it needs to be made before Phase 3.

---

## 1. Current codebase analysis

### 1.1 Scale

| | |
|---|---|
| Swift files | 30 |
| Total LOC | 4,810 |
| Views (presentation) | ~4,100 LOC / 19 files |
| Services + models (logic) | ~710 LOC / 10 files |
| Third-party dependencies | **zero** |
| Backend | one Cloudflare Worker (`proxy/worker.js`, 83 LOC JS) |
| Bundled data | `exercises.json`, 1.0 MB (free-exercise-db) |

### 1.2 Architecture

There is no formal architecture pattern — and for this size, that's correct. It is **SwiftUI + SwiftData with views as the view-model**:

- No `ViewModel` classes anywhere. Views hold `@State` for local UI and `@Query` for data.
- 19 `@Query` declarations live **directly inside view structs** across 10 files. Data access is not abstracted behind a repository.
- Exactly one `ObservableObject` in the whole app: `TabRouter` (`OnTrackApp.swift:51`), a global singleton with two `@Published` fields used for cross-tab navigation and the notification deep-link.
- Free functions in `enum` namespaces do the computing: `Calculations`, `Units`, `CoachContext`, `FoodSearchService`, `ExerciseDatabase`, `Pro`, `ImageStore`. No protocols, no DI, no injection seams.
- **No Combine.** Async work is `async/await` + `Task` throughout.
- Persistent settings are 11 `@AppStorage` keys, read directly by whichever view needs them (no settings object).

**Navigation:** a 5-tab `TabView` (`today, diet, workout, weight, faith`) with a `NavigationStack` per tab, plus 45 `.sheet` / `NavigationLink` / `navigationDestination` sites. Settings is a sheet from a Today toolbar gear (iOS's 5-tab cap forced it out of the tab bar — that constraint does not exist on Android, but 5 bottom-nav items is also Android's practical max, so keep the same shape).

**Assessment:** the app is a thin, idiomatic SwiftUI shell over SwiftData. That is very cheap to maintain on iOS and very *expensive* to share, because there's almost no layer between the view and the database to lift out.

### 1.3 Apple frameworks in use

| Framework | Where | Android equivalent | Difficulty |
|---|---|---|---|
| **SwiftUI** | 20 files | Jetpack Compose | Rewrite, 1:1 conceptually |
| **SwiftData** (`@Model`, `@Query`, `ModelContainer`) | 17 files | Room + Flow | Rewrite; schema maps cleanly |
| **CloudKit** (via `cloudKitDatabase: .automatic`) | `OnTrackApp.swift:18` | **none** | ⚠️ no equivalent — see §0.3 |
| **HealthKit** (bodyMass read/write only) | `HealthKitService.swift` | **Health Connect** | Real equivalent; needs Play declaration |
| **UserNotifications** (4 local notification types) | `NotificationService.swift` | WorkManager / AlarmManager + NotificationCompat | Straightforward; Android is *easier* here (see note) |
| **Swift Charts** | `TodayView`, `WeightView` | Vico, or hand-drawn Compose `Canvas` | Sparkline + line chart only — trivial |
| **VisionKit `DataScanner`** | `BarcodeScannerView.swift` | ML Kit Barcode Scanning + CameraX | Direct equivalent |
| **PhotosUI `PhotosPicker`** | `WeightView`, `MealPhotoView` | `PickVisualMedia` (Android Photo Picker) | Direct equivalent |
| **UIKit interop** | 2 `UIViewControllerRepresentable` (barcode, camera) + `UIImage` in `ImageStore` + `Color(.systemGray4)` in `Theme.swift` | CameraX / Coil | Small, isolated |
| **StoreKit** | **not integrated** — `Pro.swift` is a 13-line UserDefaults stub | Play Billing Library | Seam already exists on both sides |
| Push notifications (APNs) | **not used** (entitlement commented out) | — | N/A, local notifications only |
| MapKit / WidgetKit / Sign in with Apple | **not used** | — | N/A |

> **Notification note worth keeping:** `NotificationService.swift:22` documents that iOS can't compute notification content at fire time, so the daily check-in is re-scheduled with fresh text on every diary change. **Android can compute at fire time** (WorkManager reads the DB when it runs). The Android implementation should be simpler, not a port of the iOS workaround. Don't copy the hack.

### 1.4 Third-party dependencies

**None.** No SPM packages, no CocoaPods, no `Package.swift`, no `Podfile`. Every capability is either Apple-native or hand-rolled. This is unusually clean and it means there is no "does an Android equivalent exist?" dependency-audit problem at all — the entire question reduces to "does Android have this framework?", answered in the table above.

It also means the KMP question is not being forced by a dependency you can't replace.

### 1.5 Backend / API layer

Three network surfaces, all `URLSession` + `Codable`, no client library:

1. **AI proxy** — `AIClient.swift` → your Cloudflare Worker → Gemini (OpenAI-compatible shape, SSE streaming + base64 vision). Key is server-side. Already platform-neutral: **an Android client is ~120 lines of Ktor/OkHttp.**
2. **Open Food Facts** — `FoodSearchService.swift`, public REST, no key.
3. **USDA FoodData Central** — `FoodSearchService.swift`, needs `USDA_API_KEY`, currently shipped in the app binary via Info.plist.

**This is the key finding for the strategy.** You already operate a server. Surfaces 2 and 3 — API shapes, response quirks (`serving_quantity` is sometimes a string and sometimes a number, `OFFProduct` has a hand-written `init(from:)` just for that), per-100g→per-serving normalization, nutrient ID 1008/1003/1005/1004 mapping, "USDA first then OFF" ordering — are ~130 lines of *volatile, external-API-shaped* logic that would otherwise be written twice and drift twice. Moving them into the Worker gives you a shared layer with **no new toolchain**, and gets the USDA key out of both binaries as a bonus.

### 1.6 Business logic vs. presentation

**Genuinely shareable (~710 LOC):**

| File | LOC | Volatility | Verdict |
|---|---|---|---|
| `Calculations.swift` | 66 | **Very low** — Mifflin-St Jeor, activity multipliers, 3500 kcal/lb. These will not change. | Port once, freeze, test both sides against one fixture table |
| `FoodSearchService.swift` | 158 | **High** — external APIs change | **Move to Worker** |
| `AIClient.swift` | 148 | Medium — but protocol is already server-defined | Thin client per platform |
| `CoachContext.swift` | 91 | Medium — prompt + summary format | Prompt → Worker; summary query stays native |
| `Models.swift` | 186 | Low — schema is stable | Shared *schema doc*, not shared code |
| `ExerciseDatabase.swift` | 34 | None — reads a static JSON | Trivial re-implementation |
| `Pro.swift` | 13 | N/A | Platform-specific by nature (StoreKit vs Play Billing) |
| `ImageStore.swift` | 33 | None | Platform-specific file APIs |

**Platform-specific by nature (~4,100 LOC):** every file under `Views/`. Not because Compose can't express it, but because these are dense platform-idiom UI — `TabView` paging for the active workout, `Form` sections, `PhotosPicker` sheets, SF Symbols, `.card()` modifiers, iOS grouped-list backgrounds. All of it wants to be rewritten, none of it wants to be shared.

**The ratio is the whole argument:** the shareable code is 15% of the app, and the *stable* half of that 15% (`Calculations`, `Models`, `ExerciseDatabase` — 286 LOC) is exactly the part where sharing buys you least, because shared code pays for itself at *change* time. The volatile half (`FoodSearchService`, prompts — ~250 LOC) can be shared **on the server you already run.**

---

## 2. Strategy evaluation

### Option A — Kotlin Multiplatform (shared logic, native UI both sides)

**What it would actually mean here.** To share anything meaningful you must share the data layer, because 17 of 30 files touch SwiftData and 19 `@Query` declarations sit inside view bodies. So the real work is:

1. Replace SwiftData with SQLDelight in a `shared` KMP module.
2. Rewrite all 10 iOS view files that contain `@Query` to consume Kotlin `Flow`s bridged into SwiftUI via `@Observable` wrappers (Swift can't consume Kotlin `Flow` natively — you need SKIE or hand-written `AsyncSequence` bridges).
3. Rewrite `ImageStore`, `HealthKitService` glue, and the AI client behind `expect`/`actual`.
4. Set up Gradle + Kotlin/Native + XCFramework packaging and wire it into your **XcodeGen-generated** project, which currently has zero dependencies and regenerates from `project.yml`.
5. **Lose CloudKit.** SQLDelight has no sync story. You would need to build one, or drop multi-device sync from the iOS roadmap.

**Migration cost: high, and it's paid on the working, shipped, App-Store-reviewed iOS app.** Realistically 3–5 weeks of restructuring iOS *before* a single Android screen exists, plus permanent Gradle/Kotlin-Native build complexity on a project that today builds with `xcodegen generate && xcodebuild`.

**What you'd get:** 700 shared lines, of which the 286 most-shared-looking are frozen arithmetic.

**Verdict: not now.** The infrastructure exceeds the payload. See §2.5 for the exact conditions that flip this.

### Option B — Compose Multiplatform (share the UI too)

**No.** Three independent reasons, any one sufficient:

- The UI *is* the app (85% of LOC) and it is deliberately iOS-idiomatic. Sharing it means the iOS app stops feeling like an iOS app — for the platform where you already have a shipped, reviewed, polished build.
- You would be rewriting a working App Store app in Kotlin to enable an Android app that doesn't exist yet. Maximum risk, and you'd re-run App Store review on a fully rewritten binary.
- CMP on iOS still has rough edges around text input, scroll physics, accessibility, and system integration (`PhotosPicker`, `DataScanner`, share sheets) — all of which you use.

### Option C — Two separate native codebases ← **recommended, with a caveat**

Plain: keep SwiftUI/SwiftData on iOS untouched. Write a fresh Kotlin + Compose + Room app for Android.

The stated worry about this option is drift, and it's a fair worry — but drift is concentrated in specific, identifiable places, and each has a cheaper fix than KMP:

| Drift risk | Cheaper fix than KMP |
|---|---|
| Calorie/macro math diverges | One shared JSON fixture file of `(profile, weight) → expected kcal/P/C/F`. Both platforms unit-test against it. ~40 lines of test code per side. A drift here fails CI, not the user. |
| Food API parsing diverges | **Move it into the Worker.** One normalized `/food/search` endpoint, two dumb clients. Also removes the USDA key from both binaries. |
| AI prompt / behavior diverges | **Move `CoachContext.systemPrompt` into the Worker.** Change tone once, both apps get it, no app update. |
| DB schema diverges | One `SCHEMA.md` in the repo, updated in the same commit as either migration. |
| Feature list diverges | One issue tracker, per-feature issues with an iOS and an Android checkbox. |

**Verdict: recommended.** This is Option C plus a *server-side* shared layer rather than a *client-side* one — using infrastructure you already deploy, instead of adopting Gradle + Kotlin/Native for 700 lines.

### Option D — React Native / Flutter

Rewrites the entire iOS app in a third language to add a second platform. Throws away the SwiftUI investment, the App Store approval, HealthKit/CloudKit/SwiftData integration, and the zero-dependency posture — in exchange for a JS/Dart dependency tree, and *still* needs native modules for Health Connect + HealthKit, barcode scanning, and billing. Strictly worse than C here. **No.**

### 2.5 When to revisit KMP

Adopt KMP the moment **any two** of these become true — and design Phase 3 (§3.3) so the switch stays cheap:

- Shared non-UI logic exceeds ~2,000 LOC (e.g. you add training-program periodization, an offline food cache with fuzzy matching, or a real analytics/streak engine).
- A second developer joins, or you stop being able to hold both codebases in your head.
- You need a real backend with accounts (which would already have killed CloudKit — the main argument against KMP disappears).
- You add a third target (web, watch, desktop).

---

## 3. The plan

### Phase 0 — Foundations (0.5 day) 🔴 **blocking**

1. `git init`, first commit. Verify `Config/Secrets.xcconfig` is ignored **before** committing (`.gitignore` currently ignores `*.xcodeproj`, `build/`, `proxy/.wrangler/` — but **not** `Config/Secrets.xcconfig`, which contains `USDA_API_KEY` and `APP_TOKEN`). Add it.
2. Push to a private GitHub repo.
3. Restructure to a monorepo:
   ```
   ios/          ← current OnTrack/, project.yml, Config/
   android/      ← new
   server/       ← current proxy/
   shared/       ← SCHEMA.md, calc-fixtures.json, PRIVACY.md, docs
   ```
4. Delete cruft: stale `FitTrack.xcodeproj/`, `build/`, `.DS_Store` files.
5. **Decide the sync question (§0.3):** does Android get multi-device sync? Recommended answer for v1: **no** — ship Android local-only, exactly like iOS is today, and treat "cross-platform sync" as a future project with its own backend. Do not let it block launch.

### Phase 1 — Toolchain (1 day)

- Install **Android Studio** (latest stable) + JDK 17 (`brew install --cask android-studio temurin@17` — note: **no JDK is currently installed on this machine**, `java` is missing).
- SDK Manager: Android SDK Platform 36 (Android 16) + build tools, Platform 35 for testing back-compat.
- Create AVDs: Pixel 8 (API 36), Pixel 6a (API 33 — covers the notification-permission boundary), and a small-screen device (Pixel 4a-class) since your Today screen is dense.
- Bootstrap the project: `minSdk 26`, `targetSdk 36`, Compose BOM, Kotlin 2.x, KSP for Room, `versionCatalog` (`libs.versions.toml`) from day one.
- Verify a hello-world APK runs on emulator + your own Android device if you have one (buy/borrow one — emulator-only shipping is a mistake for a camera/health app).

**Effort: 1 day if things go well, 2 if the SDK/JDK setup fights you.**

### Phase 2 — Server-side shared layer (2–3 days)

Do this **before** Android, so iOS proves the new endpoints work while it's your only client.

1. Add `POST /food/search` to the Worker: takes `{query}`, runs the existing OFF + USDA logic (port `FoodSearchService.swift`'s parsing to JS — it's ~130 lines and it's the single most drift-prone code in the app), returns a normalized `FoodSearchResult[]`.
2. Add `GET /food/barcode/:code` likewise.
3. Move `USDA_API_KEY` to a Worker secret. Remove it from `Secrets.xcconfig` / `Info.plist`.
4. Move `CoachContext.systemPrompt` server-side (Worker injects the system message; app sends only the data summary + user turn).
5. Rate-limit the new routes with the existing `AI_RATE_LIMIT` binding (or a separate, looser one — food search is cheap).
6. Shrink `FoodSearchService.swift` from 158 lines to ~30 (one call, one `Codable`). Ship this as an iOS point release and confirm in production before Android depends on it.

⚠️ **Also finish the pending Worker hardening first** (from prior sessions): `wrangler secret put APP_TOKEN` has never been run, so the endpoint is currently rate-limit-only. Adding a second client doubles your exposure and your Gemini bill.

**Effort: 2–3 days. This is the highest-leverage work in the whole plan.**

### Phase 3 — Android data layer (3–4 days)

Room schema mirroring SwiftData 1:1. Keep the same table/column names as the SwiftData entities so `SCHEMA.md` describes both.

| SwiftData `@Model` | Room `@Entity` | Notes |
|---|---|---|
| `BodyWeightEntry` | same | `healthKitUUID` → `healthRecordId` (Health Connect record ID) |
| `CustomExercise` | same | |
| `WorkoutTemplate` / `TemplateExercise` | same, `@Relation` one-to-many | SwiftData's cascade delete → Room `onDelete = CASCADE` |
| `WorkoutSession` / `LoggedSet` | same | |
| `FoodItem` | same | |
| `DiaryEntry` | same, FK to `FoodItem` | iOS has `food: FoodItem?` optional (CloudKit rule); Android should keep it nullable for parity |
| `FaithLogEntry` | same | |
| `UserProfile` | same, single row | |

Also in this phase:
- **`@AppStorage` → DataStore Preferences.** All 11 keys, same names, in one `SettingsRepository`. (iOS reads these ad-hoc from views; Android should not copy that — a single repository here is cheaper, not more complex.)
- Port `Calculations.swift` → `Calculations.kt` verbatim. Write `shared/calc-fixtures.json` and a test on each side. **This is the parity guarantee.**
- `ExerciseDatabase` → load `exercises.json` from `assets/` (1 MB — parse lazily off the main thread, cache in memory; it's read-only).
- **Unlike iOS, put `@Query`-equivalents behind DAOs/repositories, not in composables.** Compose has no `@Query`, so you'd be writing this layer anyway — and it's the seam that makes a future KMP migration cheap (§2.5).

### Phase 4 — Screen port (3–5 weeks, the bulk)

Order chosen so each step is testable against real data.

| # | SwiftUI | LOC | Android | Flag |
|---|---|---|---|---|
| 1 | `OnboardingView` | 103 | Compose form, DataStore write | Straight port |
| 2 | `Theme.swift`, `RootTabView` | 157 | Material 3 theme (dark-only to match `preferredColorScheme(.dark)`), `NavigationBar` + Navigation Compose | **SF Symbols → Material Icons; every icon needs a substitute** |
| 3 | `WeightView` + `LogWeightSheet` | 231 | LazyColumn + bottom sheet | Chart → Vico or `Canvas` |
| 4 | `DietView` | 199 | LazyColumn, meal sections | Straight port |
| 5 | `FoodSearchView` + `ServingsPicker` + `ManualFoodEntry` | 263 | Search screen + dialogs | Now hits the Worker (Phase 2) — much thinner |
| 6 | `BarcodeScannerView` | 42 | CameraX + ML Kit Barcode | **Rewrite, not port.** Add `CAMERA` permission rationale UI (iOS's usage string has no UI equivalent) |
| 7 | `TodayView` (+ `ProgressRing`, `MacroRingCard`, `RecentlyEatenRow`) | 434 | Compose `Canvas` rings, cards | **Densest screen.** Verify on a small phone; iOS's grouped-background look needs a deliberate Material equivalent, not a copy |
| 8 | `WorkoutView` + `WeekStrip` + `WorkoutsListView` + `SessionDetailView` | 487 | LazyRow week strip + LazyColumn | Largest single file |
| 9 | `TemplateBuilderView` + `ExercisePickerView` | 184 | Form + searchable list | Straight port |
| 10 | `ActiveSessionView` + `ExercisePage` + `SetPillRow` | 386 | `HorizontalPager` | **Redesign needed:** rest timer must survive backgrounding → **foreground service** + ongoing notification. iOS gets this free from `UNTimeIntervalNotificationTrigger`; Android under Doze does not. |
| 11 | `MealPhotoView` + `CameraCaptureView` | 228 | CameraX capture + Photo Picker | AI disclaimer text must carry over verbatim |
| 12 | `CoachView` | 171 | Chat list + SSE streaming client | SSE via OkHttp — no `URLSession.bytes` equivalent, write a small line-reader |
| 13 | `ProgressGalleryView` + `GalleryImage` | 230 | `HorizontalPager` + Coil | Compare mode needs re-layout for wider aspect ratios |
| 14 | `FaithView` (+ picker, tracker) | 346 | LazyColumn, tap-cycle state | Straight port; catalog is static data |
| 15 | `SettingsView` + `SourcesView` | 213 | Preference-style screen | **Play requires its own attributions/policy links.** Keep OFF/USDA/exercise-db credits. |
| 16 | `AIConsentSheet`, `ProPaywallView` | 135 | Bottom sheets | Consent gate is a **compliance requirement**, port it faithfully |

**Redesign flags summarized:** #6 (camera permission UX), #7 (density on small screens), #10 (foreground service for rest timer), #13 (compare layout), and globally — **SF Symbols have no Android equivalent**, so budget time for icon substitution across every screen.

### Phase 5 — Platform services (5–8 days)

| Service | iOS today | Android | KMP library exists? |
|---|---|---|---|
| **Local notifications** | `UserNotifications`, 4 types | WorkManager (daily check-in, weekly recap), one-shot alarm (weigh-in), foreground service (rest timer) | N/A — platform-specific, and *should* be |
| **Notification permission** | implicit | **`POST_NOTIFICATIONS` runtime permission on API 33+** — needs a rationale screen | — |
| **Health data** | HealthKit, bodyMass only | **Health Connect** (`androidx.health.connect`) read+write `WeightRecord` | No mature KMP wrapper — write it natively |
| **Billing** | StoreKit (not integrated; `Pro.swift` stub) | Play Billing Library 7+ | RevenueCat covers both if you ever monetize; not needed while `isPro` defaults true |
| **Deep links** | notification `userInfo["deepLink"]` → `TabRouter` | `PendingIntent` + Navigation Compose deep link | — |
| **Analytics** | **none** | keep it that way for v1 | — |
| **Crash reporting** | **none** (Xcode Organizer only) | **Add Play Console vitals** (free, no SDK) — optionally Sentry/Crashlytics later | Sentry has KMP support |
| **Image storage** | `ImageStore` → Documents/ | `context.filesDir` + Coil | — |

⚠️ **Health Connect gotcha:** Google Play requires a **separate declaration form** for apps requesting Health Connect permissions, with a stated use case and a privacy policy that explicitly covers health data. Budget 1–2 weeks of *calendar* time for approval, not dev time. **Start this in Phase 1, not Phase 5.** If it's blocked, ship v1 with Health Connect disabled — it's one optional feature (`HealthKitService.swift` is 53 lines) and everything else works without it.

### Phase 6 — Testing (3–5 days + ongoing)

- **Shared-logic parity:** `calc-fixtures.json` driving XCTest on iOS and JUnit on Android. Non-negotiable — this is the mechanism that replaces KMP's compile-time guarantee.
- **Android unit tests:** Room DAOs (in-memory DB), `Calculations`, food-response parsing, streak logic in Faith, `CoachContext` summary builder.
- **Compose UI tests** for the 4 flows that touch money-or-data: log a food, log a weight, complete a workout set, give/revoke AI consent.
- **Manual matrix:** Pixel 8 (API 36), Pixel 6a (API 33 — notification permission path), one small-screen device, one physical device. Add a Samsung if you can borrow one (Samsung's aggressive battery management will break your rest-timer service if you get it wrong — this is the #1 real-world Android notification bug).
- **iOS side:** add the fixture test. Currently there are **no tests at all** on iOS; don't fix that broadly, just add the parity one.

### Phase 7 — Google Play release (3–5 days work + calendar wait)

**Verify every policy item below in Play Console at the time you do it — Google changes these frequently.**

| Item | Notes |
|---|---|
| Developer account | **$25 one-time** (vs Apple's $99/yr). ⚠️ **Register under your own name** — do not repeat the iOS situation where the app ships under a family member's team. |
| ⚠️ **Testing requirement** | Personal (non-organization) accounts must run a closed test with **12+ testers for 14+ days** before production access. **This is a hard calendar dependency — start recruiting testers during Phase 4.** Policy has changed repeatedly; confirm current rules early. |
| App signing | Use **Play App Signing**. Generate an upload key, back up the keystore + password somewhere you will not lose them. Losing the upload key is recoverable; understand the flow before you need it. |
| Format | **AAB** (`.aab`), not APK. |
| Target API | **API 36 (Android 16)** expected for new apps/updates in the current window. Confirm the deadline in Console. |
| Store listing | App icon 512×512, feature graphic 1024×500, 2–8 phone screenshots, short description ≤80 chars, full ≤4000. Reuse iOS screenshot concepts, re-shoot on Android. |
| Content rating | IARC questionnaire. Health/fitness + a religious-practice tracker → expect a low rating; answer the questionnaire honestly, don't guess. |
| Data safety form | Maps closely to the App Privacy nutrition label you already completed: Health & fitness, Photos. Declare the Gemini proxy upload. **Not** tracking, **not** shared for ads. |
| Privacy policy | ✅ Already hosted at `se9uencer.github.io/ontrack-privacy/`. **Must be updated** to cover the Android app and Health Connect explicitly. |
| Health Connect declaration | See Phase 5 warning. |
| GenAI policy | Play has its own generative-AI policies. Your existing consent gate + "not medical advice" disclaimers should satisfy them; review the current policy text. |
| Ads / IAP declarations | No ads. IAP: declare only if you flip `Pro` to paid. |

**Rollout:**
1. **Internal testing** (up to 100 testers, instant, no review) — you + a few people, iterate fast.
2. **Closed testing** — the 12-tester/14-day requirement. Run it concurrently with your own polish work.
3. **Open testing** (optional) — useful for device-diversity crash data.
4. **Production, staged rollout: 5% → 20% → 50% → 100%**, watching Play Console vitals (crash rate, ANR rate) at each step. Halt-and-fix on a crash-rate spike. Android's staged rollout is genuinely better than App Store's phased release — use it.

### Phase 8 — Ongoing dual-platform workflow

The workflow that makes parity cheap, in order of leverage:

1. **New logic goes server-side by default.** If a feature can live in the Worker, it ships to both platforms at once with no app update and no store review. Ask this question first, every time.
2. **One issue per feature, two checkboxes** (iOS / Android). A feature isn't done until both are ticked. This is the entire parity discipline — resist anything heavier.
3. **Implement on iOS first** (you're fastest there, and it's where the design gets settled), then port within the same week. Deliberately avoid letting Android lag more than one release behind; a 3-month lag becomes permanent.
4. **Any change to `Calculations` requires a fixture update in the same commit.** Both test suites break if you forget. This is your only automated parity gate — keep it sharp.
5. **`SCHEMA.md` is updated in the same commit as any migration**, on either platform.
6. **Version in lockstep** — same `MARKETING_VERSION` / `versionName` for the same feature set, independent build numbers.
7. **Release cadence:** ship iOS and Android within a few days of each other. Play's review is hours; Apple's is a day or two — submit Apple first.

---

## 4. Phases, effort, milestones

Assumes **solo, learning Kotlin/Compose as you go**. Halve the Phase 4 number if you already know Compose. Days are focused working days.

| Phase | Work | Days | Milestone |
|---|---|---|---|
| 0 | Git, monorepo, sync decision | 0.5 | 🔴 Version control exists |
| 1 | Toolchain, emulators, skeleton | 1–2 | Hello-world runs on device |
| 2 | Worker: food search, prompts, key removal | 2–3 | **iOS ships on the new endpoints** |
| 3 | Room schema, DataStore, `Calculations.kt` + fixtures | 3–4 | Parity test green on both platforms |
| 4 | 16 screens (see table) | **15–25** | Feature-complete Android debug build |
| 5 | Notifications, Health Connect, camera, billing seam | 5–8 | All platform services working |
| 6 | Tests + device matrix | 3–5 | Green suite, tested on real hardware |
| 7 | Play Console, assets, internal track | 3–5 | Internal build installable |
| — | **Closed-test waiting period** | *14+ calendar days* | Production access unlocked |
| 7b | Staged production rollout | 1–2 | **Live on Google Play** |

**Total: ~33–55 working days** (≈7–11 weeks full-time; 4–6 months at evenings-and-weekends pace), **plus** the 14-day closed-test window and the Health Connect approval window — both of which run in parallel with other work if you start them early.

**Recommended first slice if you want something real fast:** Phases 0 → 1 → 3 → screens 1–5 → internal track. That's a working weight+diet tracker on Play in ~2–3 weeks, with workouts/faith/AI following. It also starts the 14-day test clock immediately, which is the longest pole.

---

## 5. Risks & unknowns, ranked

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | **No version control.** Two codebases with no history, no branches, no rollback. | Catastrophic | `git init` today. Phase 0 is blocking for a reason. |
| 2 | **Sync divergence.** iOS is one paid-account away from free CloudKit sync; Android can never have it. Users with both platforms will expect their data to follow them. | Product-level | Decide explicitly in Phase 0. Recommendation: local-only on both for v1; don't advertise sync until there's a real backend. |
| 3 | **Play's 12-tester/14-day rule** for personal accounts. | 2+ week schedule hit | Start recruiting during Phase 4. Verify current policy in Console on day one. |
| 4 | **Health Connect declaration approval.** Google reviews health-data use cases. | Feature blocked, not app blocked | Submit in Phase 1. Ship without it if delayed — it's 53 lines of optional functionality. |
| 5 | **AI cost doubles** with a second platform on your Gemini key, and **`APP_TOKEN` is still not set on the Worker** (the token is plumbed in the app but `wrangler secret put APP_TOKEN` was never run). | Financial | Set the token in Phase 2. Tighten the Google budget cap. Consider a lower per-IP rate limit. Revisit `Pro` monetization if Android brings real volume. |
| 6 | **Kotlin/Compose learning curve** dominates the Phase 4 estimate and is the least predictable number here. | Schedule | Front-load with the two simplest screens (Onboarding, Weight) before committing to a date. Re-estimate after screen 3. |
| 7 | **Rest timer under Doze / OEM battery management** (esp. Samsung, Xiaomi). The single most likely "it works on my emulator" production bug. | User-visible bug | Foreground service, not `AlarmManager`. Test on physical non-Pixel hardware. |
| 8 | **UI density on small Android screens.** `TodayView` is 434 lines of stacked cards tuned for iPhone. | Polish | Test at 360dp width early, in Phase 4 step 7. |
| 9 | **The USDA/OFF parsing port** (Swift `init(from:)` quirks → JS) has subtle edge cases — `serving_quantity` type-flipping, missing `energy-kcal_100g`, nutrient-ID gaps. | Silent wrong data | Port it once (Phase 2) into the Worker with a fixture test using saved real API responses, so it's never written twice. |
| 10 | **Gemini's `503 high demand`** behavior and model-alias churn (`gemini-flash-lite-latest` → fallback) affects both platforms simultaneously. | Both apps degrade together | Already handled server-side; no additional client work. Noted so it isn't misdiagnosed as an Android bug. |

**Explicitly not risks here** (because you have no dependencies and no exotic frameworks): no SPM/CocoaPods to find Android equivalents for, no StoreKit migration (never integrated), no push-notification infrastructure (local only), no Sign in with Apple / accounts, no MapKit, no WidgetKit, no Combine.

---

## 6. Summary recommendation

**Two native codebases, plus a server-side shared layer in the Cloudflare Worker you already run — not KMP.**

The reasoning in one line: KMP's payoff scales with the size and volatility of the shared layer, and here that layer is ~700 lines, half of which is arithmetic that will never change; the other half is API-parsing that the Worker can own for free, without adopting Gradle and Kotlin/Native and without rewriting the shipped iOS app's entire data layer.

Revisit KMP when two of the four conditions in §2.5 are true. Phase 3 deliberately puts Android's data access behind DAOs/repositories so that switch stays cheap when it comes.
