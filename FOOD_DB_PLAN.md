# OnTrack — Comprehensive Food Database

**Status:** approved plan, not yet implemented
**Written:** 2026-08-21
**Target:** OnTrack 1.2.0

Goal: match the depth of the Samsung Health / FatSecret logging screen — real portion
units with gram weights, a full nutrition panel, and a database that actually finds
what people eat — without a backend, a paid data licence, or breaking local-first.

---

## 1. Decisions (locked — do not relitigate)

| # | Decision | Rationale |
|---|---|---|
| D1 | Market is **US + South Asian** | Drives dataset choice and the alias table |
| D2 | **No FatSecret / Nutritionix / Edamam** | FatSecret's storable-data rule permits only 11 id fields to be kept; names and macros must be re-fetched on every use. That means no offline diary, or accounts + a backend. Nutritionix is $1,850/mo. Both are incompatible with local-first. |
| D3 | **Bundled core + live long tail** | ~13.5k generic foods ship inside the app as JSON; branded/barcode stays online |
| D4 | Bundle is **USDA-only** | USDA FoodData Central is US-government public domain — no attribution obligation, **no ODbL share-alike**. Open Food Facts data is ODbL and must **never** be baked into the shipped file, only queried live. This is a licensing firewall, not a preference. |
| D5 | **JSON in memory, not SQLite** | Measured at 389 bytes/record trimmed → **5.3 MB** for 13.5k foods. SQLite/FTS5 would add a dependency to a zero-dependency app to solve a problem that doesn't exist. Mirrors the existing `ExerciseDatabase` pattern. |
| D6 | Desi gap = **alias table + AI fallback** | FNDDS has `Biryani with chicken`, `Bread, chappatti or roti`, `Samosa`. It has nothing for karahi, nihari, haleem. Aliases fix naming; AI fixes true blanks. No new data licence. |
| D7 | Schema = **reference + frozen grams** | `fdcId` on FoodItem, `grams` + `portionLabel` on DiaryEntry. Micros read from the bundle at render, never stored → minimal CloudKit payload, and historical entries stay numerically correct. |
| D8 | Search = **local instant, online on explicit tap** | Protects USDA's 1,000 req/hour key ceiling; zero-latency default; works offline |
| D9 | AI fallback is **free, device-rate-limited to 10/day** | An empty search result is broken core functionality, not an upsell. Cap protects the Gemini proxy budget. Still behind `aiConsentGiven`. |
| D10 | **Fix the FoodItem duplication bug** in this work, including existing rows | `FoodSearchView.swift:56` inserts a new FoodItem on every single log. Live users are accumulating duplicates now; CloudKit will multiply them across devices once enabled. Fix the cause and clean up the damage before that happens. |

### Non-goals
Restaurant chain menus (needs Nutritionix money). Recipe builder. Meal templates.
Non-US branded coverage beyond whatever Open Food Facts happens to have. User-contributed
shared foods (needs a backend).

---

## 2. Facts established by measurement

Do not re-derive these; they were verified against the live APIs on 2026-08-21.

- FNDDS total size: **5,432 foods**. Foundation + SR Legacy add ~8,100. Total ~13,500.
- FNDDS record `2707713` = `Bread, chappatti or roti` carries **65 nutrients** and **5 named
  portions with gram weights**: `1 large chappatti or roti (8")` = 52 g, `1 medium ... (7")`
  = 40 g, `1 small ... (6")` = 27 g. This is the screenshot's unit dropdown, already free.
- Trimmed to 15 nutrients + portions, one record = **389 bytes** → 13.5k foods = **5.3 MB**.
- USDA's own search relevance is poor: FNDDS query `chicken tikka masala` returns
  `Chicken, chicken roll, roasted` and `Orange chicken` in the top 3. A local ranked index
  beats their API — this is why we bundle rather than proxy.
- USDA API limit: **1,000 requests/hour**, key blocked for an hour on breach.
  **OPEN ITEM:** confirm whether this is counted per-key (a hard ceiling shared by the whole
  user base) or per-IP. Ask FoodData Central for a raise if per-key.
- OFF `cgi/search.pl` (what the app calls today) is **deprecated**, 10 req/min.
  Replacement `https://search.openfoodfacts.org/search?q=…&page_size=20` works, but its
  index reported `last_indexed_datetime: 2024-02-29` — **verify freshness before relying on it**.
- USDA Branded search returns `servingSize`, `servingSizeUnit`, `householdServingFullText`
  and `gtinUpc` — enough to drive the unit picker for branded foods too.
- Working dataset base URL is `https://fdc.nal.usda.gov/fdc-datasets/` (the download page
  advertises `www.usda.gov/fdc-datasets/`, which returns 403).

---

## 3. Architecture

```
OnTrack/Sources/Resources/foods.json      5.3 MB, USDA-only, read-only, NOT in SwiftData
OnTrack/Sources/Resources/aliases.json    ~200 desi/colloquial → FNDDS term mappings
OnTrack/Sources/Models/FoodDatabase.swift load + rank + alias-expand (mirrors ExerciseDatabase)
tools/build_food_db.py                    regenerates foods.json from USDA dumps
```

Search flow:

```
type "roti"
  → FoodDatabase.search()          in-memory, ranked, offline, instant
  → [Search branded foods online]  explicit row; fires OFF + USDA Branded
  → no results at all              → [Estimate with AI] (≤10/day) or [Create food]
```

Only foods the user actually **logs** become SwiftData `FoodItem` rows — and now at most
one row per distinct food.

---

## 4. Phases

Each phase ships independently and has its own verification. Do them in order; phase 0
must land before phase 3 touches the schema.

### Phase 0 — Kill the duplicate-FoodItem bug

1. Add `var fdcId: String? = nil` to `FoodItem` (defaulted → CloudKit-safe, lightweight-migratable).
2. Add `FoodItem.dedupeKey: String` (computed, not stored):
   `fdcId ?? barcode ?? "\(source)|\(name)|\(brand ?? "")"`.
3. Add `FoodStore.findOrCreate(_ result:, in: context)` — fetch by key, reuse if found,
   insert only if absent. Route **every** insertion site through it:
   `FoodSearchView.swift:56` (search result), the barcode path, `MealPhotoView`, `ManualFoodEntryView`.
4. One-time cleanup guarded by `@AppStorage("foodDedupeMigrationV1")`: group all `FoodItem`s
   by `dedupeKey`, keep the oldest by `createdAt`, OR-together `isSaved`, repoint every
   `DiaryEntry.food` to the survivor, delete the rest.

**Verify:** on a store seeded with 200 duplicate rows, the pass leaves 1 row, every
DiaryEntry still resolves to a food, and daily totals are byte-identical before and after.
Existing users are live on the App Store — run this against a real populated store, not an empty one.

### Phase 1 — Build the bundle

`tools/build_food_db.py`, stdlib only:

```
DATASETS = [
  ("fndds",      "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip",      "SurveyFoods"),
  ("foundation", "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-04-30.zip",  "FoundationFoods"),
  ("srlegacy",   "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip",      "SRLegacyFoods"),
]
NUTRIENTS = {1008:"kcal", 1003:"protein", 1005:"carb", 1004:"fat", 1258:"satFat",
             1257:"transFat", 1253:"chol", 1093:"sodium", 1079:"fiber", 2000:"sugar",
             1106:"vitA", 1162:"vitC", 1087:"calcium", 1089:"iron", 1092:"potassium"}
```

Per record emit: `id`, `n` (description), `s` (source tag), `p` (portions as
`[[label, grams], …]`), and the 15 nutrient values **per 100 g**. Drop any food with no
energy value. Energy fallback: if nutrient 1008 is absent, try 2047/2048 (Atwater).
Portion label = `portionDescription`, falling back to
`"\(amount) \(measureUnit.name) \(modifier)"`. Always append a synthetic `["100 g", 100]`
portion so every food has at least one unit. Minify (`separators=(',',':')`).

Script ends with asserts — this is the phase's test:
```
assert 12_000 < len(records) < 16_000
assert out_path.stat().st_size < 8_000_000
for probe in ["Bread, chappatti or roti", "Biryani with chicken", "Samosa"]:
    assert any(r["n"] == probe for r in records), probe
```

Note: SR Legacy was frozen in 2018 and FNDDS updates roughly every two years, so this
script is run rarely — on demand, shipped inside an app update. It is not a service.

### Phase 2 — FoodDatabase.swift

Model on `ExerciseDatabase.swift`: `static let all` lazy-decoded once, plus a
`[String: BundledFood]` index by id. Precompute a lowercased name and its word list at
load time so ranking never re-lowercases in the loop.

`search(_ query:) -> [BundledFood]`, scored:

| Condition | Score |
|---|---|
| name == query | 1000 |
| name starts with query | 800 |
| every query token matches a word-prefix in name | 500 |
| name contains query | 300 |
| otherwise | 0 (drop) |

Tie-break: shorter name first, then source rank `fndds > foundation > srlegacy`.
FNDDS descriptions are comma-inverted (`Bread, chappatti or roti`) — word-prefix matching
is what makes `roti` find it, so do not skip that rule.

Alias expansion runs first: each query token is expanded through `aliases.json`
(`"karahi": ["chicken curry"]`, `"roti": ["chappatti"]`, `"daal": ["lentils", "dal"]`, …),
and the best score across the original and expanded queries wins. Author ~200 entries
covering Urdu/Hindi/Punjabi staples and common misspellings.

Load off the main thread; debounce keystrokes 150 ms.

**Verify:** a `#if DEBUG` `FoodDatabase.selfCheck()` asserting that `roti`, `biryani`,
`samosa`, `chicken breast`, `karahi` and `daal` each return a sensible top-3 hit. Wire it
to a debug-only Settings row. If a query in that list returns nothing, the alias table is
missing an entry — that's the check earning its keep.

### Phase 3 — Schema + portion maths

```swift
// FoodItem: fdcId added in phase 0. Add "fndds" and "ai" to the source vocabulary.
// DiaryEntry — both additive and defaulted:
var grams: Double = 0          // frozen at log time; 0 means a pre-1.2.0 row
var portionLabel: String = ""  // e.g. "1 medium chappatti or roti (7\")"
```

**Do not change the existing computed properties.** `calories` stays
`food.calories * numberOfServings`. At log time set
`numberOfServings = grams / gramsPerServing` and record `grams`/`portionLabel` alongside
for display and provenance. Legacy rows have `grams == 0` and keep rendering exactly as
they do today. This keeps the migration lightweight and makes it impossible for the
change to alter anyone's historical totals.

**Verify:** upgrade a populated store from 1.1.0 → 1.2.0 and confirm every past day's
totals are unchanged to the calorie.

### Phase 4 — UI

Rebuild `ServingsPickerView` into the portion sheet:
- Unit dropdown from the food's portion list (`1 medium roti (40 g)`, `100 g`, …); for
  branded foods, build it from `householdServingFullText` + `servingSize`.
- 0.1-step slider (0.25–4.0) with the value bubble, plus a tappable number field.
- Macro % split bar (carb/fat/protein).
- Collapsible FDA panel: sat/trans fat, cholesterol, sodium, fiber, sugar, vitamin A/C,
  calcium, iron, potassium, each with %DV against the standard 2,000 kcal reference, and
  the reference footnote. Hide any row whose value is absent rather than printing 0.
- Favourite star writing `isSaved`.

`FoodSearchView`: add a **Recents** section (distinct foods from the last 14 days of
`DiaryEntry`, most recent first) above Saved, and one-tap re-log that reuses the previous
`grams`/`portionLabel`. For a daily tracker this is the highest-value item in the whole plan.

### Phase 5 — Rework online search

- **Delete** `searchUSDA`'s `Foundation,SR Legacy` path — it's bundled now and hitting the
  network for it is pure waste against a 1k/hr ceiling.
- Online search becomes: USDA `dataType=Branded` + OFF, behind the explicit
  "Search branded foods online" row.
- Migrate OFF off `cgi/search.pl` to `https://search.openfoodfacts.org/search`, keeping the
  legacy endpoint as a fallback until the new index's freshness is confirmed.
- Barcode: keep OFF as primary, add USDA Branded `gtinUpc` as a second try on miss.

### Phase 6 — AI fallback

Empty result set offers **Estimate with AI** and **Create food** side by side.

- Gate: existing `aiConsentGiven`. **Not** `Pro.isActive`.
- Rate limit: `@AppStorage("aiFoodEstimateDay")` (a `yyyy-MM-dd` string) +
  `aiFoodEstimateCount`; reset when the day string changes; cap 10/day. Over the cap, show
  "Daily AI estimate limit reached — you can still create this food manually" and surface
  the manual path.
- Prompt the existing Gemini proxy for name + serving grams + the 4 macros as JSON.
- Result opens the manual-entry form **pre-filled and editable**, saved with
  `source: "ai"` and rendered everywhere with an **Estimated** badge. It must never look
  like USDA data.

### Phase 7 — Ship

- `SourcesView`: add "Nutrition data from USDA FoodData Central (FNDDS, Foundation, SR
  Legacy) — public domain." Keep the existing Open Food Facts ODbL attribution.
- `PRIVACY.md` + the hosted policy: note that generic food search is now fully on-device
  and hits no network.
- Bump `MARKETING_VERSION` to 1.2.0 and `CURRENT_PROJECT_VERSION`. Regenerate with
  `xcodegen generate` — and re-select the signing team in Xcode afterwards, it gets reset.
- Register `foods.json` and `aliases.json` in `project.yml`. **XcodeGen 2.45.4's target
  `resources:` key silently no-ops** — use a `sources` entry with `buildPhase: resources`,
  the same way `PrivacyInfo.xcprivacy` is declared.
- Confirm the +5.3 MB is acceptable against the App Store cellular-download threshold.

---

## 5. Risks

| Risk | Response |
|---|---|
| USDA 1k/hr limit is per-key, not per-IP | Bundling already removes most traffic. Request a raise; if refused, move branded search behind the existing Cloudflare Worker with a cache. |
| search-a-licious index is stale (2024) | Verify before cutting over; keep `cgi/search.pl` as fallback. |
| Alias table is a bottomless pit | Cap v1 at ~200 entries. The AI fallback is what covers the tail — that's its job. |
| Dedupe migration corrupts live diaries | Test against a real populated store before release. Migration is idempotent and flag-guarded. |
| 5.3 MB in memory on old devices | Load off the main thread, lazily, on first search. Reconsider SQLite only if this measurably hurts — not before. |

---

## 6. Order of execution

`0 → 1 → 2 → 3 → 4 → 5 → 6 → 7`

Phase 0 can ship on its own as a 1.1.1 patch if you want the duplicate bleeding stopped
immediately. Phases 1–2 are usable behind a debug flag before any UI exists.
