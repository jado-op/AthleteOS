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

### 3 · Workout: what do I train?
- Hero: today's session with one "Start training" button (same session as Home).
- Then **This week** (the plan, day by day).
- Everything else — muscle picker, own routines, exercise library, sport drills, tests,
  conditioning, travel workout — in one grouped **More workouts** list instead of a wall
  of tiles.

### 4 · Progress: how am I doing?
- Hero: Athlete Score and this week.
- Then results only: training history, strength, tests, practice log, body.
- Schedule and practice-time setup move to Me → Training setup; Progress links there only
  when the schedule is missing.

### 5 · Me: grouped
- Header (name, sport, score ring) stays.
- Four groups instead of one list: **My sport** (sport, position, goals, season, team),
  **Training setup** (schedule, equipment, practice times), **App** (notifications,
  widgets, Watch, appearance of Home), **Account** (Pro, privacy, parents, data, help).

### 6 · Campus: what do I learn next?
- Hero: continue the next lesson.
- Then the nine categories.
- Leagues, badges and the library grouped under one row each, below.

### 7 · One home per feature
Sweep for duplicate entry points (check-in, schedule, practice log, tests, history,
fuel) and keep each only in its home plus the place where it is the next step.

## What stays as it is
Colours and the dark, glass design; the five tabs; every sport and every feature; the free
daily habit and what Pro gates; under-18 safety rules; the calm coach wording.
