# Academy + Digital Twin (Beta v0.1)

The Academy is AthleteOS's sixth area: lessons that teach athletes *about* their sport in
six pillars (Body, Fuel, Recovery, Mind, Legends, Sport IQ), and a **Digital Twin** — the
athlete's own figure — that those lessons and their honest answers build. The full plan is
`docs/ACADEMY-PLAN.md`.

## Where things are

| What | Where |
| --- | --- |
| Lessons (data) | `content/src/academy/lessons.js` |
| The twin's birth: eight baseline questions | `content/src/academy/baseline.js` |
| Pillars, body areas per sport, area → muscles, legend traits | `content/src/academy/model.js` |
| Seed validator (structure + safety) | `content/src/academy/validate.js`, tests in `content/test/academy.test.js` |
| Generated for the app | `app/Shared/Sources/Generated/AcademyContent.swift` (by `npm run build` in `content/`) |
| Models, decoding | `app/Shared/Sources/AcademyModels.swift` |
| Twin scoring (0–100, knowledge vs habits) | `TwinScoring.swift`, tests `TwinScoringTests.swift` |
| Recommendations (top 3 + reason) | `AcademyRecommender.swift`, tests `AcademyRecommenderTests.swift` |
| Storage, events, access flag | `AcademyStore.swift` |
| The twin: anatomical hologram (the muscle map's front/back body), pillar gauges wired to the body | `DigitalTwinView.swift` (`TwinVisualState` in, nothing else) |
| Twin birth (goals, look, baseline, reveal), before vs now | `AcademyBirthView.swift` |
| Screens | `AcademyHomeView.swift`, `AcademyLessonView.swift` |
| "Need to talk to someone?" per country | `SupportResources.swift` |

The Foundation-only parts are tested locally with `tools/engine-harness.sh`.

## Adding a lesson

1. Add it to `content/src/academy/lessons.js` (two per pillar in the seed; tag `sports: ['all']`
   when it holds for every sport).
2. `cd content && npm test && npm run build` — the build refuses invalid lessons.
3. Mark draft text with `// CONTENT: needs expert review` until a coach, dietitian or
   sports psychologist has checked it, and fact-check every Legend insight.

The validator rejects: calorie talk, dieting, weight cutting or weight loss, fasting,
supplements, sets × reps, % of max and kg/lb loads; ages under 13; more or fewer than 2–4
questions; a knowledge check without exactly one right answer; Mind lessons without the
support row.

## Privacy and safety

- The twin and every answer are **private to the athlete**: no coaches, parents, scouts or
  other users see them. Stored on the phone (`academyTwin.state.v1`); the encrypted backup
  to the athlete's own account and "Delete twin" (which deletes the server copy for real)
  are step 3 of the plan.
- Events (`twin_viewed`, `body_zone_tapped`, `lesson_completed`, `reflection_submitted`,
  `twin_born`) are counts on the phone only — never uploaded, no identifiers, no answers.
- Mind lessons are mental-skills education, not therapy. "Need to talk to someone?" is always
  on the Academy home and in Mind lessons; Germany: Nummer gegen Kummer 116 111.
- The Academy is free in the beta. `AcademyAccess.freeLessonsPerDay` switches on a daily
  limit later; it never counts toward Campus's limit.

## TODO before a public launch

- **Parental consent.** AthleteOS is 13+ (under 13 is a hard stop at the age gate) and has
  no parental-consent flow. That is accepted for the beta. **For EU users under 16 this must
  be checked before the public launch: GDPR Art. 8 lets member states set the age of digital
  consent between 13 and 16, and Germany uses 16** — processing an under-16's data on the
  basis of consent then needs a parent's consent. Decide the legal basis for the Academy's
  reflection answers (and whether a consent flow is needed) with legal advice.
- Expert review of every lesson marked `CONTENT: needs expert review`.
