# Academy — the Digital Twin (Beta v0.2)

The Academy is AthleteOS's sixth area. Its centre is the **Digital Twin**: an analysis of
the athlete built from their own data — morning check-ins, games, logged sessions and sets,
tests, evening reflections — and an intake interview about how they think. The twin finds
insights; for each, the **coach** assigns a **briefing**: a long read written for athletes who
want the real thing. The twin also holds the athlete's **performances**. Plan:
`docs/ACADEMY-PLAN.md`.

## Where things are

| What | Where |
| --- | --- |
| Briefings (one file each) | `content/src/academy/briefings/*.js` |
| Intake interview | `content/src/academy/intake.js` |
| Insights, topics, chart keys, "why" placeholders | `content/src/academy/model.js` |
| Validator (structure + safety) | `content/src/academy/validate.js`, tests `content/test/academy.test.js` |
| Generated for the app | `app/Shared/Sources/Generated/AcademyContent.swift` (`npm run build` in `content/`) |
| Models, decoding, the athlete's state | `AcademyModels.swift` |
| The analysis (rules, evidence, coach's read) | `TwinAnalysis.swift`, tests `TwinAnalysisTests.swift` |
| Performances (PRs from sets and tests, custom ones) | `Performances.swift`, `PerformanceViews.swift` |
| Reading the athlete's data | `TwinInputBuilder.swift` |
| Storage, events, access flag | `AcademyStore.swift` |
| Screens | `AcademyHomeView.swift`, `BriefingReaderView.swift`, `IntakeInterviewView.swift` |
| "Need to talk to someone?" per country | `SupportResources.swift` |

The Foundation-only parts are tested locally with `tools/engine-harness.sh`.

## The insights (rule-based, last 8 weeks)

| Insight | Rule | Briefing |
| --- | --- | --- |
| Sleep before games | ≥2 game mornings and ≥4 others with sleep hours; game eves ≥24 min shorter | Sleep before the big night |
| Recovery after games | soreness the morning after ≥3/5 and ≥1 above normal | The 48 hours after a game |
| Game-day fuel | energy on game mornings ≥0.8 lower, or the interview says little/no food | Fuel on game day |
| Strength not speed | a main lift up ≥5% (reps-adjusted) while the sprint test improved <1.5% | Turning strength into speed |
| Mistake replay | interview: replays / angry / goes quiet, or focus flagged in ≥2 reflections | Reset after mistakes |
| Pressure & confidence | interview: tenses up / hides, or confidence flagged in ≥2 reflections | Confidence under pressure |

"Strong pattern" needs three or more occurrences (or interview and data agreeing). What's
working (consistency, sleep base, strength carrying into speed) is shown without a briefing.

## Adding a briefing

1. A new file in `content/src/academy/briefings/`, added to `index.js`. Follow an existing one:
   3–5 chapters, 1,700–2,800 words, one protocol, at least one example, the athlete's chart once.
2. `cd content && npm test && npm run build` — the build refuses invalid briefings.
3. Keep `// CONTENT: needs expert review` until a coach, sports scientist, dietitian or
   psychologist has checked it.

The validator rejects: calorie talk, dieting, weight loss or cutting, fasting, supplements and
caffeine products, sets × reps, % of max and kg/lb loads; mind briefings must say who to
talk to.

## Privacy and safety

- Everything is **private to the athlete** and stays on the phone (`academyTwin.state.v3`, the
  athlete's own SwiftData and stores). The encrypted backup and a real server-side delete are
  a later step.
- Events (`twin_viewed`, `insight_opened`, `lesson_completed` = briefing read,
  `reflection_submitted` = interview edited, `twin_born` = interview done) are counts on the
  phone only — never uploaded, never answers.
- Insights point at patterns; they never diagnose. Soreness insights say to get sharp or
  one-spot pain checked. Mind briefings are mental-skills education, not therapy;
  "Need to talk to someone?" is always on the Academy (Germany: Nummer gegen Kummer 116 111).
- The Academy is free in the beta (`AcademyAccess.freeBriefingsPerWeek`, nil = unlimited).

## TODO before a public launch

- **Parental consent.** AthleteOS is 13+ and has no parental-consent flow — accepted for the
  beta. **For EU users under 16 this must be checked before launch: GDPR Art. 8 lets member
  states set the age of digital consent between 13 and 16, and Germany uses 16.** Decide the
  legal basis for the interview answers and the analysis with legal advice.
- Expert review of every briefing and the interview.
