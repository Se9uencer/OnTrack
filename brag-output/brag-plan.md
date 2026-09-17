# Brag Plan: OnTrack

## What is this app?
OnTrack is a local-first iPhone app that tracks body weight, gym workouts, diet, and — unusually — daily prayers, with an AI coach (Gemini) layered on top; no accounts, no user-data backend, everything lives on-device in SwiftData.

## The angle
The joke/claim is the pairing nobody else ships: a fitness app that also tracks your five daily prayers, and does it all without an account or a server holding your data. "One app. Every track you're on." — literal (OnTrack) and about the different tracks (weight trend, workout log, food log, prayer streak) converging into one dashboard, at sunrise, on your phone, offline.

## Hook (first 2-3 seconds)
App-store hook style: product name, then the tagline that earns the reaction.
"OnTrack." → "Fitness. Faith. Fully offline." Dawn-gradient background with sunburst rays lifted straight from the app icon art.

## Key moments (the middle)
- The food search sheet populating with three real result rows (grilled chicken breast, greek yogurt, banana) landing one by one — "12,000+ foods, searchable with the phone in airplane mode."
- A workout set-log row ticking "3 × 10" as reps count up next to a rest-timer ring — "616 exercises, logged one set at a time."
- A split-screen: the Coach chat bubble typing a real insight next to the Faith tab's five-prayer row lighting up green one by one with a "14 day streak" counter — the app knowing your logs and your streak in the same beat.

## Outro / punchline
"No accounts. No cloud. Just on track." — app icon + wordmark lockup, then "OnTrack — on the App Store."

## User flow worth showing
1. Entry — open Diet tab, tap search.
2. Key action — search a food, or scan a barcode, log it; separately, log a workout set with the rest timer running.
3. Result — the AI coach reads those real logs back as an insight, right next to today's prayer streak.

## Tone
- Preset: `app-store`
- Creative direction: quiet dawn routine — calm, clean, feature-card, not corporate-cheesy
- Interpretation: 4-6 scenes, each a clean feature-card reveal (product/feature name, then 1-2 supporting details), title-case medium-weight type, no aggressive cuts — slide/wipe transitions, generous but not slow holds.

## Format: landscape — 1920x1080
## Duration: 20s

## Visual identity (from the project)
- Background: `#E7F1F4` (pale dawn sky, sampled from app icon)
- Accent: `#E8AE86` (sunrise peach/tan, sampled from app icon dunes)
- Text: `#1B2A3A` (navy silhouette ink, sampled from app icon)
- Display font: Inter (system fallback for SF Pro; project has no bundled web font)
- Body font: Inter
- Strongest visual element: the App Store icon artwork — a navy silhouette walking a forked path toward a radiating sunrise. Use its sunburst motif as a recurring background element and its exact palette throughout.

## Share copy (draft)
Body weight, gym splits, diet, an AI coach, and your daily prayers — one local-first iPhone app, no accounts, no cloud. OnTrack, on the App Store.

## Audio direction
- Role: warm bed / sparse professional accents
- Music: `happy-beats-business-moves-vol-1-by-ende-dot-app.mp3` (bundled with the skill; 120.19 BPM)
- Music treatment: fade in 0→0.6s to ~0.55 gain; dip to ~0.35 under the Coach/Faith split scene where two things read at once; back to 0.55 for the outro; fade to 0 over the last ~1s.
- Music cue guidance: bundled preset read from `assets/music/cues/track.music-cues.md` (window 0–25s covers this whole video). Strong cue at 17.02s lines up almost exactly with the planned outro-card landing — lock that transition to it. Beat grid used for the three sequential food-result rows and the five sequential prayer-row ticks (see storyboard).
- Audio-reactive treatment: subtle — the background sunburst glow may breathe with music RMS; restrained, no waveform/equalizer look.
- SFX posture: sparse, motion-matched, professional restraint (app-store tone, not chaotic)
- Audio-coupled moments: food rows arriving (soft card tap ×3), prayer row ticks (soft check tick ×5), Coach bubble typing (subtle key ticks), outro card landing (single soft chime on the beat-locked cue)
- Restraint rule: no waveform bars, no note/music glyphs, no strobing; at most one strong-cue lock in this video (the outro landing)

## Storyboard

### Scene 1 — Hook — 3s
Dawn-gradient background (`#E7F1F4` → warm peach near the horizon) with thin sunburst rays fanning up from the bottom third, matching the app icon. "OnTrack." slams in center, holds, then "Fitness. Faith. Fully offline." settles beneath it.
Sequential/interaction: none
Audio intent: calm, confident open — the bed fades in under the title
Audio-coupled idea: none
Music: fade in, mood = warm/optimistic
Transition mood: clean crossfade → Scene 2

### Scene 2 — Identity card — 2.5s (starts 3.0s, beat-grid: 3.02s)
The app icon artwork scales in and settles center-left; "OnTrack" wordmark and the subtitle "Fitness + Faith" card slide in beside it; one supporting line: "Body weight. Workouts. Diet. Prayer. One app."
Sequential/interaction: none
Audio intent: settle, let the identity land
Audio-coupled idea: none
Transition mood: slide → Scene 3

### Scene 3 — Diet highlight — 4s (starts 5.5s, beat-grid: 5.53s)
A search-sheet card recreates the real Diet search: search bar reading "chicken breast", then three result rows land one by one — "Chicken Breast, Grilled — 165 cal", "Greek Yogurt, Plain — 100 cal", "Banana, Medium — 105 cal" — followed by a small barcode-scanner icon flash. Supporting line: "12,000+ foods. Fully offline."
Sequential/interaction: yes — 3 result rows arrive one by one, snapped to beats 6.03s / 7.02s / 8.02s (every-other-beat spacing so each row holds long enough to read; // beat-grid: row 1 6.03s, row 2 7.02s, row 3 8.02s)
Audio intent: light, tactile — each row lands with a soft card tap
Audio-coupled idea: card-tap SFX on each row arrival
Music: steady bed, no dip
Transition mood: slide → Scene 4

### Scene 4 — Workout highlight — 3.5s (starts 9.5s, beat-grid: 9.52s)
A workout-session card: exercise name "Barbell Bench Press", a set row counting up "1×10 → 2×10 → 3×10" as a rest-timer ring drains beside it. Supporting line: "616 exercises. Log it, don't guess it."
Sequential/interaction: yes — the set counter ticks up through 3 states; natural timing (count-up reads as one continuous motion, not discrete beat-snapped reveals)
Audio intent: purposeful, a little propulsive
Audio-coupled idea: soft tick on each count-up step
Transition mood: slide → Scene 5

### Scene 5 — Coach + Faith split — 4s (starts 13.0s, beat-grid: 13.01s)
Split card. Left: a chat bubble types out "How'd this week go?" then the Coach's reply types in below it — a real-sounding line referencing logged workouts and weigh-ins. Right: the five-prayer row (Fajr, Dhuhr, Asr, Maghrib, Isha) lights up green one by one beside a "14 day streak" counter. Supporting line: "An AI coach that knows your logs. And your streak."
Sequential/interaction: yes — 5 prayer ticks, non-text accent icons, snapped to every beat 14.02/14.52/15.02/15.52/16.02s (// beat-grid: prayer ticks 14.02–16.02s); chat text types with key-tick SFX
Audio intent: warm but a touch more intimate — this is the "it knows you" beat
Audio-coupled idea: key-tick on chat typing; soft check-tick on each prayer row
Music: dip to ~0.35 so both text elements read clearly
Transition mood: soft crossfade → Scene 6

### Scene 6 — Outro / punchline — 3s (starts 17.0s, beat-locked: 17.02s strong cue)
Return to the Scene 1 dawn/sunburst background. App icon + "OnTrack" wordmark lock up center. "No accounts. No cloud. Just on track." lands, then "OnTrack — on the App Store."
Sequential/interaction: none — single deliberate landing, beat-locked
Audio intent: the payoff swell
Audio-coupled idea: one soft chime exactly on the beat-locked landing, music fades to 0 over the last ~1s
Transition mood: hard hold → end

**Music mood for this video:** upbeat but restrained (app-store)
**Audio summary:** A warm, professional bed fades in under the hook, stays steady through the feature cards with light card-tap/tick SFX on every sequential reveal, dips slightly for the Coach/Faith split so both text elements read, then swells into one beat-locked chime on the outro card before fading out.
