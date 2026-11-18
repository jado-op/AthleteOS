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
  advice, progress charts, food log, 1,000+ exercises) must exist too, but secondary.
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
  Progress, Me. The Academy is its own area, not part of Campus (never move Campus lessons in).
- Academy = the **Digital Twin as an analysis of the athlete** (owner, 2026-11-18 — not a
  quiz, not scores, no figure): `TwinAnalysis.swift` reads their own check-ins, games, logged
  sets, tests, reflections and an intake interview (about mindset, never right/wrong) and
  finds insights; rule-based on the phone, every number traceable. The coach assigns a
  **briefing** for each insight: long reads (~10 min, chapters, the athlete's own chart, an
  example, one protocol) for ambitious athletes — quality over quick. The twin also holds
  **performances** (PRs from logged sets and tests, plus anything the athlete adds). Content:
  `content/src/academy/` (briefings, intake, validator). Editorial look: reading serif, big type,
  real charts, restrained violet.
- Navigation (owner, 2026-11-17): tabs Home · Campus · **Academy** (middle) · Workout ·
  Progress; **Me is not a tab** — it opens as a sheet from the round `ProfileButton` at the
  top left of every tab (iPhone shows only five tabs before "More"). Anything routed to
  `AppTab.me` opens that sheet (`MainTabView`).
- Academy privacy: the twin and every answer belong to the athlete alone — never coaches,
  parents, scouts or other users; backed up only to their own account, encrypted on the
  phone; "Delete twin" deletes the server backup for real (not an overwrite). Events
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
- Pricing: Pro Monthly $2.99 with an intro offer $0.99/mo for 3 months, Pro Yearly
  $24.99. Change prices only with the owner's say-so (`asc-pricing.yml`). The paywall
  lists only features that really are gated. The daily habit stays free (check-in, plan,
  all workout modes, logging, Watch, safety, Campus 3 lessons/day, sport guides, teams).
  Academy: free in the beta behind a flag (`AcademyAccess`), never counts toward Campus's limit.
  Coach notes: free coaches one private note per athlete a week, Pro unlimited (owner, 2026-10-10;
  enforced server-side from `proUntil`).

## Design (V7, owner 2026-11-18: "space", done smart — supersedes V5 where they differ)
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
- Sport atmosphere = abstract geometry at 2–8% opacity (`SportAtmosphere`), never photos.
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
- Foundation-only files (engine, reflection insights, Campus content) can be compiled and
  tested locally: `tools/engine-harness.sh` (Docker `swift:6.0`). Everything else: CI.

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

- Server jobs (root cron, scripts in `backend/deploy/`): parent emails every 10 min
  (`parent-emails.py`, host sendmail), nightly encrypted DB backup (`backup.sh`; Blomp via an
  rclone remote once configured), uptime + backup check every 5 min (`uptime.sh`). Their
  secrets and the alert address live in `/root/.config`, never in the repo.

## Cloud sessions (claude.ai/code)
- No `gh` CLI: use the GitHub MCP tools (e.g. dispatch `testflight.yml` via actions_run_trigger).
- Node 22 is available: `npm test` in `content/` and `backend/` runs locally.
