# AthleteOS — notes for Claude

Carried over from the long-running build session's memory (2026-09-22 → 09-26).
The repo is public: no secrets, key IDs or server internals go in this file.

## Working together — READ FIRST, every session (owner, 2026-11-17)
Two people work on this repo with Claude at the same time (one Claude Team
account), all on `master`. Only one Claude session may change master at a time.
The lock is `WORK-LOCK.md` on the remote master; `tools/work-lock.sh` reads and
writes it (never edit it by hand).
1. **Before changing any file**: `tools/work-lock.sh take "short task"`.
   - exit 0: you hold the lock — go ahead.
   - exit 1 (busy: someone else is working): **pause, don't edit**. Tell the user
     who holds it and since when, then run `tools/work-lock.sh wait "short task"`
     in the background (Bash `run_in_background`); it polls every minute and takes
     the lock the moment it is free. Carry on only after it exits 0.
2. Before every push: `git pull --rebase origin master`, then push. Never force-push
   master. If a rebase conflicts, keep both sides' work — never drop the other
   person's changes; ask the user if unsure.
3. **When done** (pushed, or abandoning the task): `tools/work-lock.sh release`.
   Also release before ending a turn that waits on the user or a long CI run, so
   the other person isn't blocked; take it again before the next edit.
4. Working longer than ~2 hours: `take` again to refresh the time. A lock older
   than 3 hours counts as abandoned (a crashed session) and can be taken over.
Reading files, CI logs or the GitHub API needs no lock.

## What this is
- iOS + watchOS training companion for high-school and college athletes (13+),
  built end to end from the owner's own spec, `docs/BUILD-PLAN.md` (§22 milestones,
  §23 decisions already made — check there before asking). The owner wrote that doc;
  treat it as their instructions. Roadmap: `docs/ROADMAP.md`.
- Sport first, gym second. Original gym-companion ideas (muscle picker, balance
  advice, progress charts, 1,000+ exercises) must exist too, but secondary.
- No nutrition tracking (owner, 2026-11-18: "not our product right now"): no food log,
  water counter, meal cards or hydration reminders. Nutrition stays as learning only
  (Campus lessons, sport-guide fuel paragraphs, the game-day fuel briefing) and safety text.
- Focus cut (owner, 2026-11-18): no habit badges, partner "Train together", Wind down
  screen, offline Downloads row, Mindset season goals, separate Off-season program or
  "Build a new gym plan". One place per job: games live in the Competitions hub, one
  Trends block, PRs/tests in the twin's Performances, one Season review.
- Layout: `app/` (Swift, XcodeGen `project.yml`), `content/` (Node: catalogue, sport
  guides, 3D rig → generated Swift + packs), `backend/` (Express + Prisma + Postgres),
  `tools/asc.mjs` (App Store Connect API client).

## Name, version, identity
- Name **AthleteOS** (one word; short form AOS). App Store name "AthleteOS: Train & Learn"
  ("AthleteOS" alone is taken). Bundle IDs stay `com.studentathlete.app*`; internal
  PRODUCT_NAME stays Sportvisor (CI paths depend on it).
- **Stays version 1.0 in App Store Connect** — owner's decision; V3 ships as new builds
  of 1.0. Build number = the workflow's `github.run_number`. Don't bump without asking.

## Product rules (owner's decisions — don't re-litigate)
- Never remove a sport: variants merge into the main sport as a *format*. 29 featured
  sports get researched guides and real workouts.
- Plans only ever contain general exercises + drills of the athlete's **own** sport.
  Position drills (goalkeeper etc.) only for that position, at least one per session.
  Filter with `CatalogueItem.fits(sport:position:)`.
- **Version 6 (owner's brief, `docs/VERSION-6.md`) leads everything**: three pillars —
  Workout (build the athlete), Campus (teach), Reflection (understand and adapt) — in the
  loop prepare → perform → reflect → adapt. Priority: workout quality, schedule
  adaptation, reflection, Campus, progress, gamification last. Copy sounds like a calm
  performance coach (no "unlock your potential"); never guilt about streaks or rest.
- Six areas (owner, 2026-11-17 — was five; a deliberate exception): Home, Campus
  (9 categories × 5 levels, ~100 lessons; `CampusLibrary.swift`), **Academy**, Workout,
  Progress, Me. Since 2026-11-19 (owner) Campus is a page inside the Academy (see Navigation).
- Academy = the **Digital Twin as an analysis of the athlete** (owner, 2026-11-18 — not a
  quiz, not scores, no figure): `TwinAnalysis.swift` reads their own check-ins, games, logged
  sets, tests, reflections and an intake interview (about mindset, never right/wrong) and
  finds insights; rule-based on the phone, every number traceable. The coach assigns a
  **briefing** for each insight: long reads (~10 min, chapters, the athlete's own chart, an
  example, one protocol) for ambitious athletes — quality over quick. The twin also holds
  **performances** (PRs from logged sets and tests, plus anything the athlete adds). Content:
  `content/src/academy/` (briefings, intake, validator). Look: V8 widgets (owner, 2026-11-19 —
  "the twin isn't really a twin"): the Twin page answers three questions with the athlete's own
  data — how are you performing (lift strength trend, performances, tests), how are you changing
  (body map trained/fresh, training minutes per week, sleep and readiness words), how is your
  mind evolving (calm and how training felt, week by week) — each with its insights and the
  coach's briefing (`TwinWidgets.swift`). Never a score. With Apple Health data (owner, 2026-11-19) the twin
  opens with "More insights into your health" (see Apple Health below). It replaces the sleep/readiness widget
  when Health has sleep.
- Layout pass (owner, 2026-11-26: "before you fix it, delete it"): one door for input — Home's "+" sheet is gone,
  everything the athlete adds goes through Tell AthleteOS (with one-tap starters); the training calendar (Progress)
  left the Academy for the Workout tab ("Training calendar" row, `WorkoutNavigation`); "Exercises by muscle" was
  deleted (the library's body-map filter does it). Don't bring these back as separate entry points.
- Architecture pass (owner, 2026-11-26: "yes do all of it", from NN/g, Apple HIG, Oura/WHOOP/Strava and adaptive-UI
  research): **one brain** — today's workout is decided once, `TodayEngine.todaysPick`, and Home, Workout, the Watch and
  the widgets only display it (never add a second decision path). **One home per thing** — Trends lives in the twin's
  "How are you changing?" (`TrendsSheet`), the calendar in Workout, mental skills in Campus; search jumps to that home
  (`AcademyNavigation.pendingTwinSheet`) instead of opening a copy. **Home is a fixed skeleton**: the now slot (a
  workout left open, else the day's next step), three glance tiles (body today → twin or check-in, next competition →
  hub, this week → training calendar; `GlanceTile`), today's plan + tomorrow + why, then notices (pain, low energy, coach
  note, schedule) — slots never move, only their content changes. Told practice saves a `PracticeLog` (went 0 = not
  said). Deleted: "Muscle workouts" (MuscleBuilderView, its Pro allowance), the exercise-minutes % ring, Home's week bar.
- Navigation (owner, 2026-11-18, replaces the five-tab layout): tabs **Home · Academy · Workout**.
  The Academy has a **Twin · Campus** switch at the top (Progress moved to Workout 2026-11-26) (owner, 2026-11-19;
  `AcademyTabView`, `AcademyNavigation`). Campus (`CampusPage.swift`) asks the interview
  questions one at a time ("Campus asks", answers in `AcademyStore`), shows what it knows about
  the athlete, and holds the ~100 short lessons, the long reads (briefings), mental skills and the
  sport guide. The training calendar is in the Workout tab. Routes to `AppTab.campus` / `.progress` / `.me`
  are redirected in `MainTabView` (Me = profile-button sheet).
- Academy privacy: the twin and every answer belong to the athlete alone — never coaches,
  parents, scouts or other users; backed up only to their own account, encrypted on the
  phone; "Delete twin" deletes the server backup for real (not an overwrite). Done (2026-11-18):
  `CloudSeal` seals the `mindset.`, `safety.` and `academyTwin.` groups (AES-GCM, key in the
  athlete's iCloud Keychain, never on our server); `CloudSync.deleteTwin` + `DELETE /sync/state/:key`.
  The parent page/email never shows anything the athlete wrote (game notes included). Events
  (`AcademyEvent`: twin_viewed, body_zone_tapped, lesson_completed, reflection_submitted,
  twin_born) are on-phone counts only — never answers or reflection text. "Need to talk to
  someone?" is configured per country in `SupportResources.swift` (Germany: Nummer gegen
  Kummer 116 111). Parental consent: TODO for the beta; EU under-16 (GDPR Art. 8, Germany)
  must be checked before a public launch.
- Competitions (owner, 2026-11-18): Home's trophy button opens the hub (`CompetitionViews.swift`):
  next competition with countdown and the athlete's own chance (self-rated, never a prediction),
  "until the next one" focus points (`CompetitionCoach`: last result's "to improve" + twin insights),
  last result form, record. "Tell AthleteOS" (`TellParser`, EN + DE, on the phone): free text →
  proposed changes (competition, pain, exam week, day status, goals), applied only when confirmed.
- Under-18 safety: no calorie counting as primary UI, readiness never a score, pain =
  "stop and get checked", never a diagnosis.
- App audit (owner, 2026-11-18, "do all of that") — don't bring these back: no Athlete Score
  or any 0–100 figure from wellness data; no leagues, XP, levels, Campus streak or Campus
  badges (Campus = a calm library sheet with the learned count and spaced review); no Home
  "level" widgets; one streak only (`AthleteStats.streak`, Me profile only) and rest never
  breaks it (up to two days off in a row, frozen days any length). The twin is the one
  analyst and the one reading recommender (Home's "Next step · read" = the coach's unread
  briefing; short lessons are follow-ups). Joining a team shows exactly what the coach sees
  and needs an explicit OK. Coach workouts are Pro on the server too.
- Pricing: Pro Monthly $2.99 with an intro offer $0.99/mo for 3 months, Pro Yearly
  $24.99. Change prices only with the owner's say-so (`asc-pricing.yml`). The paywall
  lists only features that really are gated. The daily habit stays free (check-in, plan,
  all workout modes, logging, Watch, safety, Campus 3 lessons/day, sport guides, teams).
  Academy: free in the beta behind a flag (`AcademyAccess`), never counts toward Campus's limit.
  Coach notes: free coaches one private note per athlete a week, Pro unlimited (owner, 2026-10-10;
  enforced server-side from `proUntil`).

## Design (V8, owner 2026-11-18 — supersedes V7 and V5 where they differ)
- Reference: big, short sentences with impact that carry the whole message, tap to dig
  deeper (`Headline`: key words white, connecting words dimmed, inline SF Symbols);
  vivid coloured cards where colour has a job (`AuraTone`: training ember, body/readiness
  blue, mind/twin/reflection magenta, games green, calm dark) with the aura placed behind
  the one number the eye should land on (`AuraCard`, `AuraBackground`, `MetricTile`);
  big light numbers (`BigFigure`); black canvas; white primary button; floating pill tab
  bar (`PillTabBar`). No decoration without a function. Pieces in `DesignV8.swift`.
- Owner's inspiration: Dribbble "Veri Mobile – Smart Health Tracking" (aura cards,
  tiles) and "Time Tracking & Productivity" (big sentence greeting, orange cards,
  ring timer). Don't copy; make it more useful.
- **V8 only** (owner, 2026-11-19: "I only want the new one"): no violet, no monospaced
  telemetry face, no numbered sections or hairline section rules, no grey number boxes, no
  starfield. The old component names now render V8 (`SpaceSection`/`SectionHeader` = big
  plain labels, `Font.telemetry` = regular face with monospaced digits, `GlassMetric` = big
  light number without a box); old colour tokens carry V8 colours (`brand`/`brightRed`/`red`
  = training ember #FB7A35, `purple` = mind magenta, `orange` = practice in body blue).
  Activity colours: gym ember, practice blue, after-practice yellow, mobility cyan, game green.
  The V7 and V5 sections below are history: where they name violet, telemetry or starfield,
  V8 wins.

## Design (V7, owner 2026-11-18: "space", done smart — superseded by V8)
- Deep space, not decoration: `AppBackground` is a quiet seeded starfield (`Starfield`) with two
  faint nebulae, coloured by the time of day (`SkyPalette`: dawn plum/rose, day deep blue with dimmer stars,
  dusk violet with a warm edge, night near-black; always dark); no light-field glows, no sport geometry behind content (`SportAtmosphere` unused).
  Surfaces are hairline plates (`glassSurface`), not frosted cards. Sections start on a hairline
  (`SectionHeader`, numbered `SpaceSection(1, "Today")`). Numbers in the monospaced telemetry face
  (`Font.telemetry`, `TelemetryStat`); words stay in the regular face. Primary button = "starlight"
  (bright #EEEAFE plate, dark type); violet stays light, never a fill. Less text at first sight:
  explanations open on a tap ("Why this workout?", "The numbers"). No planets, no glow everywhere.

## Design (V5: "cinematic premium sports performance")
- Always dark (`.preferredColorScheme(.dark)`): near-black #050608 space with soft violet
  light fields (`AppBackground`, `.appScreen(.hero, sportSlug:)` on the main tabs).
  **Signature colour is violet** (owner, 2026-10-07; was red): #8B5CF6 / #A78BFA / deep
  #6D28D9 (tokens still named `brand`, `brightRed`, `crimson`, `red`) is **light** — glows,
  edges, the selected tab — never a flat fill. Real red `AppTheme.danger` only for warnings
  (pain, head injury, emergency, stop). Mind/sleep/reflection accent `AppTheme.purple` is
  indigo #818CF8 so it never reads as the brand. App icon: `tools/generate-app-icon.py`.
  Website and coach dashboard are violet too (dashboard keeps `--danger` red for go easy,
  paused, pain). Website images are real screenshots only (`website/screens.py` from the
  `screenshots` workflow artifact, `website/dashboard-shot.mjs` for the dashboard); publish
  with `sh website/deploy.sh`. Three layers: atmosphere, frosted glass (`glassSurface`, `glassCapsule`), type.
- Sport atmosphere = abstract geometry at 2–8% opacity (retired; no sport geometry), never photos.
- V6 component levels: one **hero** per screen (big type, open), **information panels**
  (glass) for important data, flat **utility rows** for the rest — not every block in a
  card. Sentence case, not all-caps (eyebrows, buttons, labels). Big numbers, few icons,
  section spacing 48–72. Primary button = glass lit violet (`.primary`, `HeroCTALabel("…")` →);
  secondary = outlined. Data on glass: `GlassMetric` (asymmetric heights).
- Activity colours: gym violet (`AppTheme.red`), practice orange, after-practice yellow, mobility cyan, game
  green; a day with several splits the dot (`PieDot`). Campus categories have their own
  accent (`CampusView.color(for:)`). Readiness is a word + `ReadinessScale`, never a %.
- Strongest treatment only on Home, Workout hero, Campus hero, Academy twin, Progress overview, Me header;
  settings, logging, lists and safety stay calm and readable. Motion smooth, never bouncy.
- Tokens: `app/Shared/Sources/DesignSystem.swift`; Home pieces in `HomeDay.swift`.
- ~30–40% less text; each block answers one question. No lock icons: Pro features explain
  the benefit with one Upgrade button (`.proFeature(...)`). Insights neutral.
- Wording: Development Goals, Today's Focus, Recommended Training, Practice Log,
  Training History, Quick Log / Detailed Log.

## Workout engine (V6)
- `WorkoutEngine.swift` (TrainingDay → `SessionPlanner.decide` → `SessionDecision`: type,
  duration, targets, what to avoid, reason codes), `SportDemands.swift` (what practice
  already gives, per sport/position), `ConditioningEngine.swift`, `SessionBuilder.swift`
  (blocks by movement pattern and role from `ExerciseProfile`), `PlanExplanation.swift`
  ("Why this plan?"). App side: `TodayEngine.swift` builds the TrainingDay from real data
  and caches sessions; Home, Workout, week plan, Watch and widgets all use it.
- Exercise profiles are authored in `content/src/profiles.js` (hand table for every base
  exercise) and shipped in the packs.
- Evidence base (2026-11-18): `docs/TRAINING-RESEARCH.md` — every engine rule maps to a verified
  source ("Rules the engine now follows"). Profiles carry `quality`, `energy`, `muscles` (coach muscle
  words over the anatomical list); `TrainingStage` (foundation / development / performance), effort
  by reps in reserve (never to failure), landing caps, `InjuryPrevention` per sport, pull ≥ push,
  strength before running. Workout tab shows what each exercise trains; the library filters by muscle on a body map.
- Gym by focus (owner, 2026-11-19): tap Gym → upper / legs / core / full body / "you pick", 30 / 60 / 90 min
  (`GymFocus.swift`, `GymStore.swift`, `GymSetupView.swift`). Anchors (one push + one pull, squat + hinge,
  anti-extension + anti-rotation) hold for a four-week block; accessories rotate every session; a stalled anchor
  swaps to its sibling. "You pick" (`GymAdvisor`) reads region recency (legs 72 h, upper 48 h), games, practice,
  soreness, goals and watch-measured sleep. Evidence: `docs/GYM-ALGORITHM-RESEARCH.md` (rules first).
  Part 2 (athlete-population studies only, rules A1–A28) adds: legs allowed but short two days before a game;
  in season legs come back after ~8 days without a heavy exposure; the sport's Nordic/Copenhagen ride on leg days
  and shoulder work on upper days (fixed, even in a 30-min session); easy finisher after heavy legs for trained
  athletes; one-step-up after two reps past target (APRE); watch-measured short sleep holds the weight; a tournament or meet within 10 days
  halves the gym sets (taper; weekly games don't).
  Never compute or show an acute:chronic ratio or injury-risk number (A28). 48 h between jump blocks (A10):
  the day after 20+ landings the fast work is throws.
- Gym sessions stay in the gym (owner, 2026-11-19: a skier got on-snow drills mid-workout). Item surfaces
  include `snow`, `water`, `outdoors`; `CatalogueItem.venue` reads the compiled `itemSurfaceBySlug`
  (generated into `Equipment.swift`, so it works with older downloaded packs). Every session except a
  conditioning one is indoor: no snow/ice/water/trail items, sport drills on a gym floor only (a field drill
  only when the sport/position has no gym-floor drill, e.g. goalkeepers), at most one item outside on a
  field or track; warm-up skips don't count.
- Adaptive context (owner, 2026-11-23: "never make the athlete tell it twice; never ignore what it was told"):
  one shared context layer, `AthleteContext.swift` (Foundation, harness) + `AthleteContextStore` (sealed `safety.`
  group). Events: fatigue by region (open until answered "back to normal", superseded, or 4 days without word),
  exposures (practice character, sprints, conditioning, jumps; the athlete's own workouts by pattern), temporary
  equipment and time (end by themselves). Reported facts are kept apart from derived tags; never invented numbers.
  Inputs: Tell AthleteOS (`TellParser` reads fatigue, practice reports, own workouts, equipment, time; still
  confirm-to-apply, then "Plan adjusted: before / now / why"), the evening reflection (body very tired), the Health
  workout check (a very hard part), the check-in answers. The morning check-in opens with at most 2 follow-ups
  (`AthleteContext.questions`) that can change the plan; a legs follow-up replaces the soreness question; pain is
  always asked separately and keeps its safety path. TodayEngine → `TrainingDay.context` (`ContextSignals`) →
  SessionPlanner rules + reason codes (`HIGH_LOWER_BODY_FATIGUE`, `RECENT_HIGH_SPRINT_EXPOSURE`,
  `PRACTICE_COVERED_CONDITIONING`, `LIMITED_EQUIPMENT`, `AVAILABLE_TIME_TODAY`…) → `PlanExplanation.contextLines`.
  Told time picks the gym length that fits (recomposed, not cut); told equipment replaces the kit for those days;
  reported workouts count in RecentLoad and the advisor's region recency. No chatbot, no score, no cloud.
- Told = saved (owner, 2026-11-24: "I put in a workout, but it didn't save anywhere"): a told workout is also a
  Session (`HealthWorkoutInbox.logTold`, already answered, merged per day, joins a same-day Health workout); "we won 3-1"
  saves a `CompetitionResult`; Tell after the check-in updates that day's `DayChoiceStore` answer; Tell lists what it
  remembers (removable). Siri "Tell AthleteOS" (`TellIntent`). Calendars: a phone calendar can be picked
  (`PhoneCalendars`, EventKit, read only, feed url `phone:<id>`); practice titles like Scrimmage/Walkthrough set
  practice intensity (`ScheduleClassifier.practiceCharacter`). No coach-reported practice (owner: "I hate the idea").
- Foundation-only files (engine, reflection insights, Campus content) can be compiled and
  tested locally: `tools/engine-harness.sh` (Docker `swift:6.0`). Everything else: CI.

## Apple Watch (owner, 2026-11-19)
- Watch app on hold: it stays in the project and must keep compiling (Shared/Sources builds into
  it — wrap iPhone-only SwiftUI like `Menu` in `#if os(iOS)`), but no Watch features, design work
  or Watch-specific fixes unless the owner asks. Never let the Watch shape or slow iPhone work.

## Working rules
- Every milestone ships with real, reachable UI — no headless engine code, no
  placeholder or debug text.
- **Code goes to master** (owner, 2026-09-27; again 2026-11-17: "always put everything on
  main"): commit and push everything straight to `master`, even when the session was handed
  another branch — no feature branches, no PRs. `testflight.yml` also builds master by itself every day at
  06:00 UTC, and TestFlight installs the highest build number — so anything not on master
  gets replaced on the owner's phone by an older app the next morning.
- **Always build TestFlight** (owner, 2026-09-27): after every push that goes green in
  `check.yml`, dispatch `testflight.yml` on master and watch it to a real upload; then
  carry on without waiting.
- **One TestFlight build at a time, from one session** (owner, 2026-11-18; two sessions
  once dispatched the same build in the same second). Only the session whose commit is the
  **newest code commit** on master dispatches (`work-lock:` commits don't count). If the
  other session pushed code after yours, don't dispatch: its green run covers your commit
  too, and it builds. Right before dispatching, list `testflight.yml` runs and look at each
  run's commit (`head_sha`), not just its status: a run builds master as it was when it was
  created, never later pushes. Don't dispatch only if a run (queued, in progress or
  succeeded) already has the newest code commit. A run on an older commit doesn't count —
  dispatch anyway: `concurrency: testflight` queues yours behind it (a newer queued run
  replaces an older queued one), and the higher build number wins on the phone. A duplicate
  you started by mistake: cancel your own run, never the other session's.
- "UPLOAD SUCCEEDED" ≠ in TestFlight. Apple can process for an hour; check with
  `asc-inspect.yml` ("Recent uploads": PROCESSING / COMPLETE / FAILED) before diagnosing.
- CI is the only compiler for the app (~8 min per round), except the Foundation-only
  files `tools/engine-harness.sh` covers. So:
  - grep the real `Generated/*.swift` for exact names before using them;
  - pick the conservative pattern when unsure of Swift/SwiftData/concurrency behaviour;
  - any XCTestCase touching a `@MainActor` type must itself be `@MainActor` — grep every
    test file when adding one; a file absent from one failed build's errors isn't clean;
  - never compare `Optional<Enum>` to `.none` when the enum has a `none` case;
  - bound loops with `for _ in 0..<n`; a test step that hangs twice on the same commit is
    a bug in the diff, not flakiness;
  - "Unable to find a device" = runner image drift; pick a destination from the log.
- Read the real CI result (job/step status, failed-step log), never a summary.
- Don't re-add the "Simulator screenshots" step to `check.yml` (slow, flaky, gated nothing).
- Signing: TestFlight archives use MANUAL signing with profiles recreated each run by
  `tools/asc.mjs app-store-profiles`. If manual ever fails, switching back to automatic is OK.
- ASC credentials live in GitHub Actions secrets. Privacy labels have no API — the owner
  enters them in the ASC web UI.

## Content and animations
- Catalogue (2026-09-26): 869 base items expanding to 1,020 (`BASE_ITEMS` / `CATALOGUE`
  in `content/src/catalogue.js`), each with its own 3D rig pattern. Maths `content/src/rig3d.js`,
  drawing `rigDraw.js`, patterns `content/src/poses/*`, assignments `poseAssignments/*`.
  Swift ports `RigEngine.swift` / `RigShapes.swift` must stay line-for-line
  (`RigEngineTests` compare against golden samples from `build.mjs`).
- Review an animation (from `content/`): `KEYFRAMES=1 node --max-old-space-size=6000 tools/renderRig.mjs out.png slug`
  and look at the PNG; floor penetration: `node tools/whereLow.mjs slug`.
- Animation fixes ship without an app build: `content/dist/animations.json` is served by the
  backend and downloaded by the app at launch. New joints, a new poseModelVersion or new
  drawing kinds still need an app build.
- Sport guides: `content/src/guides/*.js`; cite only from `sources.js` (each verified).

## Backend
- Live at `https://api.lejacob.dev/fitness` (`AppConfig.backendBaseURL`), Docker Compose
  on the owner's server, own Postgres. Redeploy = `docker compose up -d --build` in
  `backend/` **on that server** — cloud sessions can't do it; say so instead.
- Apache on that server: `systemctl restart apache2`, never reload/graceful. DB passwords
  in connection URLs: hex only. `ProxyPass` target must not end in `/` when the
  `<Location>` has none (see `backend/deploy/apache/`).

- Apple Health is the only wearable integration (owner, 2026-11-19: "remove the Suunto API… HealthKit becomes the
  single source of truth"; then "the same with the Google Fitbit side"). No brand APIs and no brand-specific code: the
  Suunto Cloud connection, `SuuntoLink`, Me → Suunto, Me → Fitbit Air and the "Google Health = Fitbit" rule were
  removed (migration `remove_suunto_link`). Apple Watch, Garmin, Suunto, Fitbit, Polar, Oura, WHOOP… all arrive through
  Health and are read the same way; `WearableBrand` only names a source in a sentence from its own name.
  Layers: `HealthKitManager` (+ `HealthKitInsights.swift`: daily statistics per `HealthMetric` — sums merged across
  sources by Health so steps aren't double-counted — newest sample, nights, workouts with routes, observer queries
  + background delivery, an anchored workout query) → `HealthDataRepository` (actor; in-memory snapshot, re-reads
  only parts HealthKit reported changed, shares overlapping refreshes) → `HealthInsightsViewModel` → views.
  Model + rules are Foundation-only and in the harness: `HealthMetric.swift` (17 metrics, summaries against the
  athlete's own usual, workout de-duplication across sources, nights, sleep rhythm) and `HealthWidgetRegistry.swift`
  (every widget kind; a widget exists only when its data is recent; derived ones — recovery word, sleep rhythm,
  wrist temperature difference — only when their inputs exist). Twin: `HealthInsightsSection` (first cards + "All
  your health insights") → `MoreHealthInsightsView` (sections, tiles, detail sheets, route maps). Me → Apple Health:
  `HealthConnectionView`. Never invent a value; demo data only under `-demoData` (`HealthDemo`). Screenshots:
  `-tab academy -sheet health|health2|healthAll`. Energy (kcal) and body weight stay low-key tiles, never goals.
- Health workouts are training (owner, 2026-11-20): a counting workout from Health (strength/cardio/sport ≥ 15 min,
  light ≥ 45, not during practice) is logged as a Session at once (`HealthWorkoutInbox`, never pushed to the server), so
  Home and the Workout tab show "Training done". Next app open (within 24 h) `WorkoutCheckSheet` asks: CR-10 effort, what
  it trained (regions or exact exercises), per-region effort when several, anything hurt. Effort sets each region's
  recovery for the gym planner (`WorkoutTagging`, `GymHistory.recoveryOverride`). Evidence: `docs/WORKOUT-CHECK-RESEARCH.md`.
  Answers feed the twin too: body map (`HealthWorkoutInbox.bodyMapSets`), "Ready for hard work again", weekly minutes × effort.
- "Your last 7 days" (owner, 2026-11-20): the twin page's card under the name opens `TwinWeekView` — the body figure
  lit by this week's training, the week's numbers floating around it (sleep → head, heart → chest, steps → legs,
  training → core), dashed lines to the body, tap a number for its 7-day chart, tap the body to turn it around. Rules in
  `TwinWeek.swift` (harness). Screenshot: `-tab academy -sheet week`. Muscles are coloured by how hard they worked
  (owner: "by colour"): `MuscleTraining.week` (sets × effort, light/solid/very hard) on `HeatScale` (one warm hue,
  rising lightness, never a rainbow). Tap a muscle for its week. Look rules: `docs/TWIN-WEEK-DESIGN.md`.
- Server jobs (root cron, scripts in `backend/deploy/`): parent emails every 10 min
  (`parent-emails.py`, host sendmail), nightly encrypted DB backup (`backup.sh`; Blomp via an
  rclone remote once configured), uptime + backup check every 5 min (`uptime.sh`). Their
  secrets and the alert address live in `/root/.config`, never in the repo.

## Cloud sessions (claude.ai/code)
- No `gh` CLI: use the GitHub MCP tools (e.g. dispatch `testflight.yml` via actions_run_trigger).
- Node 22 is available: `npm test` in `content/` and `backend/` runs locally.
