# Hyperframes Composition Brief: OnTrack

## Objective
Create a short launch-style brag video for OnTrack, a local-first iPhone fitness + faith tracking app.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 20s

## Source Material
- Project root: /home/user/OnTrack (native iOS app, no index.html/styles.css — copy pulled from README.md, OnTrack/Sources/Views/Onboarding/TourSlides.swift, and OnTrack/Sources/Views/Faith/FaithView.swift)
- Primary files read: README.md, project.yml, TourSlides.swift, FaithView.swift, Assets.xcassets/AppIcon.appiconset/icon-1024.png
- Product name: OnTrack
- Tagline / strongest claim: "All-in-one personal fitness app... Local-first (SwiftData) — no accounts, no user-data backend" + the unusual Fitness+Faith pairing (five daily prayers tracked alongside macros)
- Key UI or visual moment to recreate: the App Store icon art (navy silhouette walking a forked path into a sunrise) as the recurring visual motif; the Diet search sheet, a workout set-log row, the Coach chat, and the Faith five-prayer streak row as feature-card recreations
- Copy that must appear verbatim:
  - "OnTrack"
  - "12,000+ foods" / "The bundled food database works fully offline — search, tap, log. No signal required." (paraphrased as "12,000+ foods. Fully offline.")
  - "616 exercises" (from "Create workout templates from a 616-exercise library")
  - "No accounts, no user-data backend" (paraphrased as "No accounts. No cloud. Just on track.")

## Creative Direction
- Tone preset: app-store
- Creative direction: quiet dawn routine — calm, clean, feature-card, not corporate-cheesy
- Interpretation: 6 scenes, each a clean feature-card reveal; title-case medium-weight type; slide/wipe transitions; no aggressive cuts
- Angle: see `brag-plan.md` — "One app. Every track you're on."
- Hook: "OnTrack." → "Fitness. Faith. Fully offline."
- Outro / punchline: "No accounts. No cloud. Just on track." → "OnTrack — on the App Store."
- Avoid:
  - Generic SaaS language ("streamline your workflow")
  - Abstract filler visuals
  - Unrelated visual redesign — stay inside the app icon's dawn/sunrise palette

## Visual Identity
- Background: `#E7F1F4` (pale dawn sky)
- Text: `#1B2A3A` (navy)
- Accent: `#E8AE86` (sunrise peach)
- Display font: Inter (system fallback for SF Pro — no bundled web font in the project)
- Body font: Inter
- Visual references from the project: `OnTrack/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (sunburst + silhouette + palette), the five-tab structure (Today, Diet, Workout, Weight, Coach) plus Faith

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. Hook — 3s — "OnTrack." then "Fitness. Faith. Fully offline." on the dawn/sunburst background
2. Identity card — 2.5s — app icon art + wordmark + "Body weight. Workouts. Diet. Prayer. One app."
3. Diet highlight — 4s — search sheet, 3 food rows land one by one, "12,000+ foods. Fully offline."
4. Workout highlight — 3.5s — set-log row counting 1×10→3×10 with a rest-timer ring, "616 exercises."
5. Coach + Faith split — 4s — typing chat bubble + 5-prayer row ticking green + streak counter
6. Outro — 3s — dawn background returns, icon+wordmark lockup, "No accounts. No cloud. Just on track." → "OnTrack — on the App Store."

## Audio
- Audio role: warm bed / sparse professional accents
- Audio arc: fade in under the hook, steady through the feature cards, dip under the Coach/Faith split for legibility, swell into one beat-locked chime on the outro, fade out over the last second
- Music: `happy-beats-business-moves-vol-1-by-ende-dot-app.mp3` (copied into `composition/assets/music/`)
- Music treatment: fade 0→0.6s to gain 0.55; dip to 0.35 for scene 5 (13–17s); back to 0.55 for scene 6; fade to 0 over the final ~1s
- Music cue guidance: bundled preset at `assets/music/cues/track.music-cues.md` (120.19 BPM, window 0–25s covers the full video). Strong cue 17.02s — lock the outro-card landing to it. Beat grid used for scene 3's three food rows (every-other-beat: 6.03/7.02/8.02s) and scene 5's five prayer ticks (every beat: 14.02/14.52/15.02/15.52/16.02s).
- Audio-reactive treatment: subtle — background sunburst glow may breathe with music RMS; skip if extraction is unavailable in this environment rather than block the render
- Audio-coupled moments:
  - Scene 3 food rows — soft card-tap SFX on each of the 3 arrivals
  - Scene 4 set counter — soft tick on each count-up step
  - Scene 5 — key-tick SFX on chat typing; soft check-tick on each of the 5 prayer ticks
  - Scene 6 — single soft chime exactly on the beat-locked 17.02s landing
- SFX selection guidance: sparse, motion-matched, professional restraint (app-store tone) — prefer low high-frequency-risk sounds since several cues repeat (3 food rows, 5 prayer ticks)
- SFX analysis guidance: use `skills/brag/assets/sfx/sfx-analysis.md` if present when selecting exact files; otherwise choose tasteful built-in/registry SFX matching the above intents
- Exact SFX choice: Hyperframes should choose filenames, timestamps, density, and volume based on the implemented animation
- Audio files: music copied to `brag-output/composition/assets/music/`; any SFX Hyperframes selects should also land under `brag-output/composition/assets/`

## Hyperframes Instructions
Load `hyperframes-core`, `hyperframes-animation`, `hyperframes-creative`, `hyperframes-keyframes`, `hyperframes-cli`. This is `/brag`'s own workflow — do not enter the generic `hyperframes` intent interview or its promo/launch-video workflow.

Requirements:
- Show at least one real UI/copy element from the source project (the Diet search rows, the workout set counter, the Coach chat, and the Faith prayer row all qualify).
- Keep all text readable in the final render (respect the reading-time floors from `step-2-plan.md`).
- Keep the video within 15-25 seconds (target 20s).
- Include the planned music/SFX layer.
- Treat the `/brag` audio notes and cue guidance as hints, not a fixed cue sheet — Hyperframes decides exact timing.
- Run `npx hyperframes check` before render — the single gate.
