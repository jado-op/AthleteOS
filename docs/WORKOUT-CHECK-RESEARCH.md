# Workouts from Apple Health: the quick check (owner, 2026-11-20)

The owner trained, the watch wrote the workout to Apple Health, the app showed
it — and still told them to do another workout. Now a counting Health workout
is logged as the day's training straight away, and the next time the app opens
it asks a few taps about it. Code: `WorkoutTagging.swift` (rules, tested in the
harness), `HealthWorkoutInbox.swift` (import, answers, planner input),
`WorkoutCheckSheet.swift` (the questions).

## The flow
1. **How hard was it overall?** 0–10 with Foster's CR-10 words (0 Rest, 1 Very,
   very easy, 2 Easy, 3 Moderate, 4 Somewhat hard, 5 Hard, 7 Very hard,
   10 Maximal). "Think of the whole session, not just the end."
   Also "Not a training session" (removes it for good) and "Ask me later".
2. **What did it train?** Upper body · Legs · Core · Full body, "Mostly running
   or cardio", or the exact exercises (logged as sets, so the body map and the
   gym planner see them). Pre-ticked from the activity (run, soccer → legs;
   swim, row → upper + legs; strength → nothing).
3. **Which part worked hardest?** Only when more than one region is ticked;
   Light · Solid · Very hard, defaulting to the overall rating's band.
4. **Did anything hurt?** No / Yes. Yes → today's pain report and "stop that
   movement and get it checked"; tomorrow's plan stays lighter. Never a diagnosis.

Asked only within 24 h of the workout; after that it stays unrated. Skipping
never costs anything: the workout counts either way. No calories anywhere.

## What counts
- Strength, cardio and sport workouts of 15 min or more; walks, yoga, mobility
  and golf only from 45 min.
- Not during practice (that becomes the practice log, as before), not a
  workout the AthleteOS Watch app or a live session already logged.
- Imported sessions stay on the phone (`syncedAt` set; never pushed).

## Evidence
- Session RPE (CR-10 × minutes) is valid in children and adolescents
  (meta-analysis, Liu 2023, PMC10422765) and for resistance training
  (McGuigan, Egan & Foster 2004; Sweet 2004).
- Recall: in adolescent athletes a rating given 24 h later matched the
  30-min rating (r = 0.98, error 8 %); at 72 h it did not (error 35 %)
  (Scantlebury et al., JSCR 2018; Phibbs 2017). Hence "within a day".
- Rating regions separately (differential RPE: legs, upper body,
  breathlessness) adds information to the overall rating (McLaren 2015, 2017;
  upper-body rating r = 0.92 with upper-body weights). Evidence is from adult
  team sport and "core" isn't validated, so the split is optional, three words.
- Recovery: sets to failure impair performance 24–48 h, recovered by 72 h
  (Morán-Navarro 2017); children recover faster than adults (Falk & Dotan
  2006), so adult windows are a conservative ceiling.

## Recovery the gym planner uses (`WorkoutTagging.recoveryDays`)
| Band | Legs | Upper body | Core |
|---|---|---|---|
| Light (0–3) | 1 day | 1 day | 0 |
| Solid (4–6) | 2 days | 2 days | 1 day |
| Very hard (7–10) | 3 days | 2 days | 2 days |

Cardio counts as legs one band easier unless rated 7+. Over 90 minutes, or
anything hurt: one band harder. The newest session of a region decides
(`GymHistory.recoveryOverride`); logged gym sessions keep the usual 72 h / 48 h.
