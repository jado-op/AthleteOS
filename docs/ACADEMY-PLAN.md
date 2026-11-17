# Academy + Digital Twin — Beta v0.1 plan

Owner's brief 2026-11-17, decisions the same day:

- The Academy is a **new area of its own**, not part of Campus. Campus stays exactly as
  it is; no Campus lesson moves. This deliberately breaks the old five-section rule.
- The **Digital Twin** is the centre of the Academy.
- Backup: **private in the athlete's own account** like the evening reflection,
  **encrypted**, with "Delete twin". Nobody but the athlete ever sees the twin.
- Pro: **free in the beta**, behind a feature flag so a limit can be switched on later.
  Does not count toward Campus's 3 lessons a day.

Status: plan, waiting for the owner's OK on navigation (§1).

## 1. Navigation

On iPhone a `TabView` with six tabs shows four of them plus a system "More" tab — the
sixth tab would be hidden behind a list. So a plain sixth tab is not clean.

**Proposal (recommended): Academy becomes a tab, Me moves to a profile button.**

- Tabs: Home · Campus · **Academy** · Workout · Progress. Academy sits in the middle
  (icon: a figure in a ring).
- Me stays a whole screen, unchanged inside, but opens from a round profile button
  (the athlete's initial / twin head) at the top left of every main tab — the pattern
  Apple's own apps use. Deep links and Search that lead to Me keep working.

Alternative: keep the five tabs and give the Academy its own entry — a twin card on Home
and in Me that opens the Academy full screen as its own "space". Less change, but the
Academy is then two taps away and easy to miss.

## 2. Screens

1. **Academy home** — hero: the twin, full body, on deep space. Around it six pillar
   indicators. Below: "Next for you" (top 3 lessons, each with a one-line reason),
   the six pillars as flat rows, "Before vs now", and the always-visible
   "Need to talk to someone?" row.
2. **Area sheet** — tap a body area or pillar: score 0–100, split into *Knowledge*
   (quiz answers) and *Habits & mindset* (reflections), what it means in one line, and
   the next lesson that would raise it.
3. **Lesson player** — 3–5 minutes: content cards → optional *Legend insight* →
   2–4 questions (knowledge checks scored, self-reflection never right/wrong) →
   end screen where the twin shows the change ("+6 Recovery — your battery is charging").
4. **Twin birth** (first visit) — sport, position, level, season phase and goals come
   from the existing profile (asked only if missing); new: age range check, 1–3
   Academy goals, appearance (body type, skin tone, hair, kit colours), 8 baseline
   questions across the pillars, then the animated reveal.
5. **Post-game reflection** — 4–5 taps on the evening after a game (how it felt,
   reaction to mistakes, sleep and food before, energy). Offered from Academy home and
   from the existing evening reflection on game days; updates *Habits & mindset*.
6. **Before vs now** — the twin at birth beside today's twin.
7. **Twin privacy** (in Academy, top right) — what is stored, that it is encrypted and
   private, and **Delete twin**.

## 3. The twin — `DigitalTwinView`

- Isolated behind one value type, so a 3D model can replace it later:
  `DigitalTwinView(state: TwinVisualState, onTapArea: (TwinArea) -> Void)` with
  `TwinVisualState { appearance, sport, pillars: [TwinPillar: TwinScore],
  bodyAreas: [TwinBodyArea: Double], traits: [LegendTrait], egoBalance: Double,
  mode: .idle | .levelUp(TwinDelta) | .compare(TwinVisualState) }`.
- Beta drawing: the existing 3D rig (`RigEngine`) in a standing pose, drawn as a
  hologram in SwiftUI `Canvas` — violet wireframe edges, a slow scan line, skin tone and
  kit as faint fills under the lines, gentle idle breathing. No Lottie, no 3D engine,
  no new dependency.
- Pillars on the body:
  - **Body** — the sport's key muscles glow as Body grows (soccer: hamstrings, glutes,
    core, calves), reusing the rig's muscle-region glow.
  - **Fuel** — aura intensity.
  - **Recovery** — a battery beside the twin; a calmer, cleaner outline as it fills.
  - **Mind** — head glow (indigo, the Mind accent) and a small ego ↔ humility meter.
  - **Legends** — unlocked legend traits as holographic rings with a short label.
  - **Sport IQ** — a scanning arc around the head.
- Colours: violet stays light (glows, edges), never a flat fill; red only for warnings.
  Motion slow and smooth; the level-up is a single bright pass, never bouncy.
- The Recovery battery is Recovery *knowledge and habits* — never today's readiness, so
  "readiness is never a score" still holds.

## 4. Data model

No SwiftData models, so **no migration** of the existing store.

- `TwinProfile` — appearance, sport/position at birth, birth date, Academy goals.
- `TwinLedger` — append-only list of `TwinEffect { date, source (lesson / baseline /
  reflection id), pillar, side (knowledge | habits), delta, bodyArea?, trait?, ego? }`.
  Scores are always **derived** from the ledger, so they are deterministic, testable,
  and "before vs now" is the ledger cut at birth.
- `AcademyProgress` — completed lessons, answers given (needed to avoid re-scoring).
- Stored as one JSON document, `academy`, in UserDefaults on the phone.
- Content types (decoded from the bundled JSON): `AcademyLesson { id, title, pillar,
  sports ("all" or slugs), ageRange, seasonPhases, prerequisites, minutes, sections,
  legendInsight?, questions }`, `AcademyQuestion { id, kind: knowledge | reflection,
  prompt, options: [{ text, correct?, effects: [TwinEffectSpec] }] }`.

## 5. Backup, encryption, delete

- Same rule as the evening reflection: backed up only when the athlete is signed in
  (an account), never in the demo; nothing is sent otherwise.
- **Encrypted on the phone** before it leaves: AES-GCM (CryptoKit) with a key kept in
  the iCloud Keychain (synchronisable), so the athlete's new iPhone can read it and the
  server cannot. The server stores one opaque document, key `academy`, through the
  existing `/sync/state` — **no backend change, no redeploy**. It is deliberately not
  under a `settings.*` group (those are plain JSON).
- Parent summary, coach and team routes never read it (they read only `competitions`
  and `summary`; a test keeps Academy data out of `summary`).
- **Delete twin**: clears the phone, writes an empty, newer `academy` document to the
  server (replaces the backup), and deletes the key. "Delete all data" in Me does the
  same. Without iCloud Keychain the backup cannot be restored on a new phone — said
  plainly in Twin privacy.

## 6. Logic (Foundation-only, unit-tested, also in `tools/engine-harness.sh`)

- `TwinScoring` — ledger → 0–100 per pillar and side (diminishing returns so one
  lesson never maxes a pillar), body-area levels, traits, ego balance.
- `AcademyRecommender` — rule-based ranking: weakest twin dimension (highest weight),
  Academy goals, sport match, season phase, not completed, prerequisites met. Top 3,
  each with a one-line reason.
- `AcademyAccess` — the feature flag: `dailyLessonLimit: Int?` (nil = unlimited in the
  beta). Separate from Campus's counter.

## 7. Content (`content/`)

- `content/src/academy/lessons/*.js` — lessons as data. Seed: 12 soccer lessons, two
  per pillar; Body, Fuel, Recovery and Mind ones tagged "all sports". Basketball and
  Track & Field get their body-area tables and sport tags, lessons later. Athletes of
  other sports get the twin and every "all sports" lesson.
- Draft text marked `// CONTENT: needs expert review`; legend facts only from verified
  sources in `sources.js`.
- `content/src/academy/validate.js` (runs in `npm test`): schema, unique ids,
  prerequisites exist and have no cycles, 2–4 questions, 3–5 minutes by word count,
  ages ≥ 13, every effect names a real pillar/area, and safety bans — calorie
  restriction, weight cutting, supplements, load prescriptions (sets × reps, % 1RM,
  kg/lb loads). Mind lessons must carry the support row.
- The content build writes `academy-lessons.json` into the app bundle.

## 8. Safety and privacy

- Minors: the twin and every answer are the athlete's alone — no coaches, scouts,
  parents or other users in the beta.
- Events (twin viewed, body area tapped, lesson completed, reflection submitted) are
  counted with `UsageCounts`: counts on the phone only, never uploaded, never answers.
- Mind lessons are mental-skills education, not therapy. "Need to talk to someone?"
  is always on Academy home and in Mind lessons; the resource is configurable in
  `AppConfig` (default: the existing 988 / trusted-adult text from `Safety.swift`).
- Parental consent: the app has no parental-consent flow (13+ only, under 13 is a hard
  stop). TODO recorded in `ACADEMY_README.md`.

## 9. Files

New (app, `app/Shared/Sources/`): `AcademyModels.swift`, `AcademyContent.swift`,
`AcademyStore.swift` (storage, encryption, delete), `TwinScoring.swift`,
`AcademyRecommender.swift`, `AcademyAccess.swift`, `DigitalTwinView.swift`,
`AcademyHomeView.swift`, `AcademyLessonView.swift`, `AcademyOnboardingView.swift`,
`AcademyReflectionView.swift`, `TwinPrivacyView.swift`; resource
`academy-lessons.json`.
Tests: `TwinScoringTests`, `AcademyRecommenderTests`, `AcademyStoreTests`
(encrypt/decrypt round trip, delete, not in `summary`).
Content: `content/src/academy/*`, validator tests.
Changed: `MainTabView.swift` (Academy tab; Me via profile button), `CloudSync.swift`
(the encrypted `academy` document), `LocalWipe.swift`, `AppConfig.swift`,
`MindsetViews.swift` (game-day link), `ACADEMY_README.md`, `CLAUDE.md`.

## 10. Shipping (straight to master, CI + TestFlight each)

1. Academy tab with the twin, scoring, recommender, lesson player, 12 seed lessons,
   validator.
2. Twin birth, post-game reflection, before vs now.
3. Encrypted backup, Delete twin, Twin privacy, README.
