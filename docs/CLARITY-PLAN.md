# Clarity plan

Owner's brief (2026-11): the app feels cluttered and without a plan — "you don't know what
to do or where to start", too many functions that are simply there. Make it clear and easy
to use. Colours stay (dark, violet light). Exercise pictures are stills that cross-fade,
not played animations.

Nothing is deleted: features are regrouped so each has one home. Version 6
(`docs/VERSION-6.md`) still leads; this plan is about where things live and what leads a screen.

## What was wrong

- **No single next step.** Home showed a hero, a schedule list, a readiness block, a
  progress track and a supporting list, all at similar weight. Nothing said "do this now".
- **The same thing in many places.** Check-in, schedule, practice log, tests and history
  were each reachable from three or four screens, so no screen felt like the place for them.
- **Tabs without one question.** Workout had 14 entry points, Progress mixed results with
  schedule setup (48 buttons), Me was one list of 34 rows.
- **Animations** drew attention to their own mistakes.

## Rules

1. **Each tab answers one question.**
   - Home — *What do I do now?*
   - Workout — *What do I train?*
   - Campus — *What do I learn next?*
   - Progress — *How am I doing?*
   - Me — *Who am I, and how is the app set up?*
2. **One next step per screen**: one hero, one primary button. Everything else is quieter.
3. **Three levels only**: hero → glass panel for what matters → flat rows for the rest.
4. **One home per feature.** Other screens may link to it, but only where it is the next
   step — never as a standing shortcut. Search (Home, top right) finds everything.
5. **Setup lives in Me**, results in Progress, doing in Home and Workout.
6. **Seldom-used things go behind one "More" row**, grouped and named, not spread out.
7. Less text: a row is a name and a few words. Reasons stay one tap away ("Why this plan?").

## Phases

Each phase ships through CI and TestFlight on its own.

### 1 · Exercise stills — shipped
Two or three key positions per movement (lying / up for a sit-up) that cross-fade; the
movement between them is never played. `content/src/stills.js`, `RigPoseView.swift`.

### 2 · Home: what do I do now? — shipped
- The top (day, greeting, quote) is unchanged.
- **One next step** as the hero, marked with a lit dot: "Start here · check-in", then
  "Next step · training / learn / reflect". When nothing needs doing it says so plainly
  ("Team practice · 4:30", "Rest day", "Done for now") instead of inventing a task.
- **Today's plan** under it: the day as a short numbered list — check-in, game or practice,
  workout, lesson, reflection — with a check on what is done, the next one lit, and
  "2 of 5 done". A tap on a step does it.
- The order is fixed and tested (`TodayPlan.swift`, `TodayPlanTests`): check-in first, a
  game leads its day, the workout comes after practice, the evening is for the reflection,
  a rest day has nothing to tick off for training.
- Readiness moved into "Why this plan?" (a word and its scale, never a number).
- Removed from Home: the intro card, the separate schedule list, the check-in reminder,
  the readiness hero, the progress track, the supporting list. Their content is in the plan.
- Below the plan, quiet: the week, then the athlete's own widgets.

### 3 · Workout: what do I train? — shipped
- Hero: today's session with one Start button (the same session as Home).
- Then **This week** (the gym days).
- **More workouts**: one list instead of separate cards — the other modes, skill plans and
  muscle workouts, train together, the off-season program.
- **My workouts** (own and shared), then **Your plan**: gym days and length, a new plan,
  the workouts the athlete changed — one card.

### 4 · Progress: how am I doing? — shipped
- Results only, in one order: this week, calendar, practice log, 30 days, stats, training
  history.
- **Training history** holds every look back in one list: all workouts, exercise progress,
  tests, trends, past check-ins (they used to be split between Progress and Me).
- "Schedule & events" became **Games & events**: add a game or a training, what is coming
  up. Practice days and calendars are set up in Me → Training Setup; Progress links there
  only while the schedule is missing.

### 5 · Me: who am I, how is it set up? — shipped
- Profile, goals, then setup and settings only: Training Setup, Food/mind/health, Safety,
  Team & Family, Settings, Subscription, Your data, About, Account.
- The "Training History" group moved to Progress.

### 6 · Campus: what do I learn next?
Already follows the rules (one recommended lesson, continue, the nine areas, your sport,
progress last). Next: Leagues, badges and the library under one row each.

### 7 · One home per feature
Sweep for duplicate entry points (check-in, schedule, practice log, tests, history,
fuel) and keep each only in its home plus the place where it is the next step. Home's
search keeps finding everything.

## What stays as it is
Colours and the dark, glass design; the five tabs; every sport and every feature; the free
daily habit and what Pro gates; under-18 safety rules; the calm coach wording.
