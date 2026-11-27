# Check-ins that teach the twin: what to ask, when, and what it changes

Research for AthleteOS, 2026-11-27. This was a read-only pass over the repo plus a literature check. No code was changed. Rules C1–C20 are below, followed by the proposed morning and evening check-ins for each type of day.

## Bottom line

1. **The core morning items are the right ones. Keep them. Fix how two of them are stored.** Sleep, energy (fatigue), soreness and stress are the four items the athlete-monitoring literature uses most. Fatigue (our "energy") is the most consistently load-sensitive item. Two things break the signal today:
   - **Sleep quality is pre-filled from sleep hours.** On watch days it is just a copy of hours, so the readiness z-score counts sleep twice.
   - **The one-tap "Feeling normal" saves the athlete's two-week median as if it were a real answer.** On a quiet stretch the baseline fills with copies of itself, its spread shrinks, and the twin "learns" from answers nobody gave.
2. **The biggest gain for the twin is in the evening, not the morning.** A practice-day evening should ask the two things the Foster session-RPE method needs: how hard practice was (the same 1–10 scale the app already uses after a workout) and roughly how long it was (pre-filled from the schedule). It should also ask how practice went, and save all of it as a `PracticeLog`. Three problems exist today:
   - The evening's "How did practice go?" goes into `Reflection.practice`. `TwinKnowledgeEngine.sleepAndPractice` reads `PracticeLog.went`, so its "Still learning: practices with sleep logged" line barely moves.
   - Because the evening writes no PracticeLog, the next morning's Home card asks about the same practice again. That breaks "never make the athlete tell it twice".
   - The twin's load numbers guess every practice as 90 min × hard·2 and every game as 60 min × 8.
3. **A game-day evening should do the game rating.** The twin's slowest learner is "What your best games share", which needs 10 rated games. Today the rating lives only in the competitions hub, while the evening asks a generic "How hard did today feel?" and its own went-well and to-work-on chips. Asking "How did you play? 1–5" plus minutes played and effort that evening, and saving it into `CompetitionResult`, is the cheapest way to get to 10 games. It also removes a double ask.
4. **Ask rarely what changes rarely.** "What's on next week?" (normal, heavy school, exams, travel) and "How much did you enjoy your sport this week?" belong once a week, not every day. They are planned-missingness items: the twin needs their trend, not a daily point. They explain a lot of a student athlete's variation: exam periods were the high-stress, high-illness window in university athletes (Hamlin 2019), and loss of enjoyment comes with burnout.
5. **Fewer screens overall.** The proposal below shortens most check-ins:
   - The evening asks pain twice ("Something hurt" → "Any pain or new symptoms?"). Make it one step that goes straight to "Where?".
   - The went-well and to-work-on chips are asked even on rest days. Ask them only after practice or a game.
   - On gym days the in-workout RPE already answers "How hard did today feel?".
6. **Evidence honesty.** Single-item wellness questions are custom and only weakly validated. Their link to load is "predominantly trivial to moderate" (Duignan 2020). Their job is a status check and a conversation, not a measurement. That fits the product rules (words, not scores; the athlete's own usual; counts, not statistics). It also means nothing below should be oversold as "predicting" anything.

---

## Step 1: What exists (confirmed in code)

| Where | What it asks | Stored as | Who reads it |
|---|---|---|---|
| `CheckInCard.swift` `CheckInSheet` | ≤2 context follow-ups, what's on today, sleep hours, sleep quality, energy, soreness (skipped when a legs follow-up ran), pain → where/how much, ill/told to hold back, "How do you feel today?" (mood/stress) | `CheckIn` (1–5 ints), `PainStore`, `IllnessStore`, `DayChoiceStore` | `ReadinessEngine` (z vs 28 days, ≥7), `DailyLoop.readiness`, twin mornings |
| `CheckInCard.swift:633` `QuickCheckIn.save` | One tap: "Feeling normal, no pain" | Writes **the 14-day median** of each item as that day's `CheckIn`. No flag says it was a one-tap | Same readers. They cannot tell it from a real answer |
| `CheckInCard.swift:362` `loadHealth` | Sleep quality pre-filled from hours (`WearablePrefill.sleepQuality`) | `CheckIn.sleepQuality` | Readiness z (sleep counted twice on watch days) |
| `MindsetViews.swift` `ReflectionSheet` | How hard did today feel (4), how did your body feel (Good/Tired/Very tired/Something hurt) → "Any pain or new symptoms?" (again), how did practice go (4, practice days only), what went well, what to improve (chips + note) | `Reflection` (`hardness`, `body`, `practice`, `feeling = practice+1`, chips) | `yesterdaySignal` → tomorrow's readiness; twin `Reflect.feeling`, chip counts (focus, confidence) |
| same, `save()` | "Something hurt" + Yes | `PainReport(areas: [.other], level: .some)`. **No area asked**, "Not sure" not saved | T9 recurring-pain line can only say "the spot you marked somewhere else" |
| `PracticeCards.swift` `PracticeAskCard` | Next morning: "Went · normal / Went · hard / Didn't go" | `PracticeLog(hard 3/4, went 0 = not said)` | Calendar; twin practice load (minutes nil → 90) |
| `TwinKnowledge.swift:486` `sleepAndPractice` | — | Needs `PracticeLog.went > 0` on ≥20 practices with sleep | **Starved**: the evening rating never reaches it |
| `TwinAnalysis.swift:556` weekly load | — | practice = (minutes ?? 90) × hard·2; game = 60 × 8 | Load-spike insight |
| `CompetitionViews.swift` `CompetitionResultForm` | Outcome, score, "how you played" 1–5, went well / to improve | `CompetitionResult` | Twin best-games (≥10 rated) |
| `LiveSessionView.swift` `RPEPromptView` | CR-10 with word anchors after an app workout | `Session.sessionRPE` | Progression, legs efforts |
| `WorkoutCheckSheet.swift` | Health workout: CR-10, what it trained, hurt? | Session + inbox answer | Region recovery, twin |
| `ReminderScheduler.swift:143` | Evening reminder ≈ 1 h after practice ends (17:00–21:30) | — | Good timing for session RPE (see §2) |
| `AcademyHomeView.swift:818` | "Need to talk to someone?" | — | Only reachable from the Academy and search, never from a check-in answer |

What the twin cannot learn today for lack of input:
- **Best games** need ≥10 rated games, and ratings happen only if the athlete opens the hub.
- **Short nights vs practice** need ≥20 practices with `went` > 0, which is almost never written.
- **Real practice and game load** have no minutes and no effort for practices or games.
- **Recurring pain from the evening** has no area.
- **Exam weeks** are excluded only when the athlete happened to Tell AthleteOS about them.
- **Enjoyment and motivation** are not captured at all. `PracticeLog.enjoyment` exists but is never asked on a fast path.

---

## Step 2: Evidence

### A. Which daily items carry signal

- **Subjective beats objective for the training response.** In 56 studies, subjective well-being measures reflected acute and chronic load "with superior sensitivity and consistency" than objective markers (blood markers, HR and so on), and the two generally did not correlate (Saw, Main & Gastin 2016). This is the basis for T12: the athlete's words come first. [abstract and listing; full text not reopened]
- **Single-item custom check-ins are what everybody uses, and they are weak instruments.** Duignan et al. 2020 reviewed 21 team-sport studies (500 athletes):
  - Items asked: soreness (20 studies), fatigue (20), sleep quality (19), stress (14), mood (6).
  - Measures had 3–8 questions on 5-, 7- or 10-point scales.
  - Links with load were "predominantly trivial to moderate", mostly negative, and fatigue was the most consistent.
  - The authors say the link with load "may not be expected or useful"; the value lies in the status check and the conversation.
  [full text opened]
- **Fatigue is the most sensitive item.** In 17 days of in-season elite soccer, the daily change in perceived fatigue tracked high-intensity running (r = −0.51). Soreness, sleep quality and HR recovery did not (Thorpe et al. 2015). In a follow-up, morning fatigue, sleep quality and soreness tracked RPE load across weeks and were 35–40% worse the day after a match than the day before one (Thorpe 2016/17). [abstract and repository]
- **Pre-training wellness goes with what the athlete then does.** A wellness z of −1 had a likely negative effect on low-speed running load in that session (Gallo et al. 2016, Australian football, n = 36). [abstract] This supports making the day lighter when the athlete's own items are low. It does not support predicting performance.
- **After games, perceptual fatigue and soreness drop for about 48 h and recover within about 4 days** (McLean et al. 2010, rugby league, n = 12). [abstract] Wellness ratings are a practical way to follow responses to training and competition (Gastin, Meyer & Robinson 2013, AFL, 9 items, 1–5). [listing only]
- **Youth athletes.**
  - Daily well-being went with sleep duration (r = .28). A one-item perceived-recovery scale went with the previous day's training (r = −.23). Countermovement jump went with neither (Sawczuk et al. 2018, n = 52).
  - A 13-week follow-up found more training → more soreness and lower recovery, and more sleep → better sleep quality, well-being and fatigue (Sawczuk 2018, second paper). [abstracts]
  - In youth, **sleep hours** and **one "how recovered" item** both carry signal, and they carry different signal.
- **A perceived-recovery item works.** The Perceived Recovery Status scale went with sprint change (r = −0.63; Laurent 2011, n = 16) and with jump and bar speed after heavy squats (repeated-measures r ≈ .8; Tolusso 2022, n = 11). Equal ratings in two people do not mean equal recovery, which is one more reason to compare the athlete only with their own usual. [abstracts]
- **Validated short scales exist but are long for daily use.** The Short Recovery and Stress Scale has 8 items (4 recovery, 4 stress) and showed acceptable reliability in English-speaking samples. A measurement-invariance check found adolescents comparable to adults, "though younger groups showed more difficulties" (Kölling et al. 2019/2020). [abstracts] Eight items daily would break the 30-second budget, so we borrow its idea (recovery side vs stress side), not the instrument.
- **School stress matters for student athletes.** In 182 university athletes, lower mood and sleep, higher academic stress and a preseason load jump went with injury. Exam periods were the high-stress, high-illness window (Hamlin et al. 2019). **Caveat:** the abstract's odds ratio for academic stress is reported as 0.91, which is at odds with the stated direction. Not verified in the full text.
- **Mental fatigue is a separate construct.** It has been tracked daily over two netball seasons (Russell et al. 2022, 5-point Likert alongside fatigue, sleep, stress, mood and motivation), and the authors argue it belongs in athlete self-report. [listing] The evidence is elite and adult, and it is unclear what the plan should do with it. Weak evidence for a daily item.

**Redundancy we can act on:**
- **Sleep quality vs hours.** They are distinct in youth: hours go with well-being, and quality follows hours plus other things. Keep both, but never derive quality from hours.
- **Energy vs heart.** The heart pre-fill already defers to the athlete (T12), so no change is needed.
- **Soreness vs a legs follow-up.** Already merged in code.
- **Mood and stress.** These are one item today. The literature splits them, but one item is the right trade-off for the 30-second budget.

### B. Session RPE for practice and games

- **Method:** session load = RPE (CR-10) × minutes. It is valid across steady, interval and basketball practice (Foster et al. 2001, ~950 citing studies by 2017). [abstract]
- **Adolescents:** a meta-analysis of 16 studies found pooled r = 0.74 with HR load. CR-10 r = 0.69, CR-100 r = 0.80 (only 3 studies, all soccer). Correlations were weakest under age 12, and ~90% of participants were male (Liu et al. 2023). [full text] Our 13+ athletes are inside the validated range. CR-10 is enough, and it is the scale the app already uses.
- **Timing:** 10 min after training gives the same value as 30 min (Uchida 2014, adult boxers). In adolescent runners, ratings at 30 min were ~26% lower than at 0 min but valid at both (Mann 2019). Most studies collect at about 30 min. [abstracts] So the evening reminder at about 1 h after practice is fine.
- **Recall:** in 38 adolescent athletes, a rating recalled 24 h later matched the 30-minute rating (r = 0.98, typical error 8.3%, trivial bias). At 72 h the typical error was 35% (Scantlebury et al. 2018). [full text, already in `WORKOUT-CHECK-RESEARCH.md`] So the evening is best, the next morning is still valid, and later than that is not. This matches P17's "next morning only".
- **Duration matters:** load is RPE × minutes. A 45-minute walkthrough and a 2-hour scrimmage at "6" are not the same day. We know the scheduled time, so pre-fill it and let the athlete correct it. Never make them type minutes.
- **Games:** I found **no validation of match session RPE scaled by minutes played in adolescents**. Match sRPE is used routinely in youth soccer load studies, and the minutes are factual. Use minutes played as told (rough bands), not 60.
- **Teens' wording:** use word anchors on every point (see G). The app's existing CR-10 anchors ("Easy — breathing a little harder", "Hard — only a few words at a time") are good and should be reused verbatim, so one scale means the same thing everywhere.

What the twin can learn from practice sRPE × minutes (without a ratio):
- **"Your usual practice week":** minutes and how many were hard (≥7), against their own last 4 weeks, as counts. Example: "This week: 3 practices, 2 of them hard. Usually 1."
- **Recovery after hard practices:** next-morning soreness and energy after practices rated ≥7 vs ≤4. Same machinery and thresholds as the legs line (≥4 episodes, replicate).
- **Feeding the existing best-games factor** "hardest practice in the 2 days before" with real ratings instead of the 3/4 from the morning card.
- **Never:** acute:chronic ratios or injury-risk numbers (A28). The load-spike insight already compares this week with three earlier weeks internally. Keep that wording as counts and minutes and never show a multiplier.

### C. Burden, compliance and asking only when it matters

- **Elite athletes on self-report (Saw, Main & Gastin 2015, 30 interviews):**
  - "The more clicks the less compliant."
  - "Day after day after day" leads to copied answers.
  - Half admitted shading the truth.
  - People give dummy answers when nobody seems to look; visible feedback and autonomy help.
  - Some felt morning answers didn't reflect how they felt until after the session.
  - Staff suggested 2–3×/week for slow-changing items.
  [full text]
  Our design already shows "what this taught your twin" (`TwinPulse`). That is the feedback this paper asks for.
- **Youth EMA compliance:** a meta-analysis of 42 studies in children and adolescents found 78% of prompts answered. Non-clinical youth did best with 2–3 prompts a day (91.7%) and worse with 4–5 (77.4%). Study length didn't change compliance (Wen et al. 2017). [abstract] Two touchpoints a day (morning, evening) is the sweet spot; a third daily prompt is not.
- **Planned missingness:** asking each item on only some occasions gives unbiased estimates with slightly wider error and lowers burden (Silvia et al. 2014). [abstract] This is the evidence for weekly rotating items. Each item still gets enough points for a trend: ≥8 weekly answers over a season. Never rotate the safety items (pain, illness).
- **Implication:** every daily item must either change today's plan or feed a twin line with a declared minimum. Anything else becomes weekly, or goes.

### D. Per day type: what explains the athlete's own variation

- **Practice day evening:** effort (sRPE), minutes, and how it went (the athlete's own quality rating, already the twin's outcome in T-§6). One optional chip page (went well / work on) feeds focus and confidence.
- **Game day evening:** the athlete's own performance rating (the twin's best-games outcome, T-§1), minutes played, effort. Win/loss stays optional and in the hub. The twin never uses it.
- **Gym day:** the workout's own RPE already exists. The evening only needs the body.
- **Rest day:** body only (tired? hurt?). Nothing about performance.
- **Exam or heavy school day:** the morning stress item is the signal. The twin already excludes exam days from sleep comparisons, but only if told. A weekly forward-looking question catches exam weeks before they happen and lets the plan shorten without the athlete having to Tell.
- **Travel:** already a day status. No new question.
- **Before games:** the morning stress item already feeds the best-games "nerves" factor, which is declared in one direction only. On game mornings the hint can say "Nerves count too", so nerves land on the same scale without a new item. The "Your chance" self-rating in the hub stays where it is.

### E. Questions that unlock "Still learning"

| Still-learning line | Missing input | Proposed fix |
|---|---|---|
| What your best games share (≥10 rated games) | Ratings happen only in the hub | Game-evening "How did you play?" → `CompetitionResult.rating` |
| Short nights vs practice (≥20 practices with sleep, ≥5 short) | `PracticeLog.went` never written by the fast paths | Evening practice answers → `PracticeLog(hard, went, minutes)` |
| How long your legs take (≥4 hard leg sessions + mornings) | Fine for gym; practice/game legs unknown | Practice ≥8 or a game → counts as a hard leg exposure for sports where practice is mostly running (fixed sport list, declared up front) |
| Recurring pain (2 occasions, 8 weeks) | Evening pain has no area | Evening "Something hurt" → same "Where?" grid as the morning |
| *New:* What your best practices share | — | Same machinery as best games, outcome = practice `went`, factors = the 4 morning items + yesterday's effort. Needs ≥20 rated practices (reachable in ~6–8 weeks). Declared directions only |
| *New:* Enjoyment over the season | — | Weekly item (below). The twin shows the trend in words ("lower than your usual for three weeks") with the support row. Never a plan change |

### F. Sensitive items for minors

- **Menstrual cycle.** The Australian Institute of Sport says cycle tracking should never be mandatory, must be opt-in for every athlete, and needs medical oversight when collected by a system. Bioethics work warns of harm from systematic tracking in sport. A US analysis warns school-level collection risks discrimination and outing trans students. [AIS PDF listed; others abstracts] Menstrual dysfunction can be a sign of low energy availability (RED-S), and screening for that is a clinician's job (age-appropriate RED-S screening tools exist, female versions add cycle questions).
  - **Recommendation: no cycle tracking now.** Allow "period symptoms" only as a pain or symptom the athlete chooses to say, which lightens the day like any other symptom, with nothing logged as a cycle.
  - Open question for the owner below. It would need under-16 consent work (GDPR Art. 8) before it could exist.
- **Mood and mental health.** The IOC's SMHAT-1 (Gouttebarge et al. 2021) is for licensed professionals, for elite athletes **16 and over**. Its triage questionnaire is the APSQ.
  - **Recommendation:** an app for 13+ athletes must not run a screening questionnaire or show a mental-health result.
  - The daily stress item stays a training input.
  - What a stress answer should do is **route, not score**. When the athlete answers "Very stressed" on 2 of the last 3 mornings, or the weekly enjoyment item is low 3 weeks running, the result page shows the quiet "Need to talk to someone?" row (`SupportResources`, per country).
  - No push, nothing shared with coach or parent, no plan punishment beyond today's existing "lighter" rule.
  - Any free text containing crisis words should be handled by a separate safety path, not by the twin. That needs its own spec; flag only.
- **Weight and body size.** Never asked in check-ins (T14; body-image risk, Lupton 2021). Unchanged.

### G. Wording, options and recall

- **Every scale point carries a word.** Children's concordance with objective judgments was higher for word-based than number-based formats, and fewer points (3 vs 5) did not help (Mellor & Moore 2014, ages 6–13). [abstract and full-text summary] Our users are older, but the lesson holds: keep words on every option. The 1–10 effort tiles need the word for the selected value shown, as `RPEPromptView` does.
- **4 options for wellness items, 10 for effort.** This matches what the field uses and what the app stores. Don't switch to emoji-only faces: emoji are read differently across ages and cultures (not researched further here; design call). Emoji may decorate, never replace, the word.
- **Recall periods:**
  - Morning: "last night" (sleep) and "right now" (energy, soreness, stress).
  - Evening: "today" (body) and "practice" or "the game" (that session).
  - Effort: same evening, or next morning at the latest (Scantlebury).
  - Weekly: "this week" or "next week".
  - Never "lately".
- **Don't change a stored scale's meaning.** The 1–5 storage must stay, so baselines (28 days) and z-scores stay valid. New questions get new fields.

---

## Rules

- **C1 Four core morning items, every day:** sleep (hours + quality), energy, soreness, stress, plus the safety gates pain and illness. Nothing else is asked daily in the morning. [Duignan 2020; Thorpe 2015; Sawczuk 2018]
- **C2 Sleep quality is never pre-filled from hours.** On watch days hours come from Health. Quality starts at the athlete's own usual (median of 14 days) and is marked "your usual — tap to change". [Sawczuk 2018: distinct signals; design]
- **C3 A one-tap "Feeling normal" is stored as what it is.** Save it with a flag (`CheckIn.quick = true`). The readiness engine and twin baselines read quick days as "at usual" for that day, but leave them out of the spread (SD) and out of pattern detection (best games, best practices, recovery episodes). Without this, a quiet month narrows the spread and makes the next real dip look bigger than it is. [design; Epstein 2015: mark missing, don't fill]
- **C4 Every daily question has a job.** It changes today's or tomorrow's plan, or it feeds a twin line with a declared minimum. Otherwise it becomes weekly, or goes. [Saw 2015; Wen 2017]
- **C5 Two touchpoints a day, max.** Morning check-in and evening check-in. Practice and game questions live inside the evening, not on extra cards. [Wen 2017]
- **C6 Practice effort uses the app's one effort scale.** CR-10 tiles with the same word anchors as `RPEPromptView` and `WorkoutCheckSheet`. [Foster 2001; Liu 2023]
- **C7 Practice minutes are pre-filled, never typed.** From the schedule ("90 min, from your schedule"). Corrections: Shorter (−30) / As planned / Longer (+30), or tap for exact. [Foster 2001; design]
- **C8 The evening writes the PracticeLog.** `hard` (CR-10 mapped to 1–5), `went` (1–5), `minutes`, `intent` from the schedule title. The morning card then sees a log and stays quiet (it already checks `logged`). One question, one place. [owner rule "never tell twice"; P17]
- **C9 Recall window: same evening, else the next morning only.** After that a practice stays "not said". Never guess. [Scantlebury 2018]
- **C10 The game evening asks the game rating.** "How did you play?" 1–5 → `CompetitionResult.rating` (creating the result with outcome "not said" if needed), minutes played (bands), effort (CR-10). The hub's form opens pre-filled and asks only what's left (score, outcome). Win/loss is never asked in the evening. [T-§1]
- **C11 Game load = told minutes × told effort.** Fixed 60 × 8 only when not said. Practice load = told minutes × told effort; 90 × default only when not said. [Foster 2001]
- **C12 Ask a thing once.**
  - Don't ask "How hard did today feel?" on a day whose sessions already have an effort: an app workout's RPE, a checked Health workout, or a practice or game answered that evening.
  - Day hardness is derived from the hardest session.
  - Ask it only when nothing was rated (a told activity with no effort).
- **C13 The evening asks about pain once.**
  - "Something hurt" goes straight to "Where?" (the morning's `PainArea` grid) and "How much?" (A little / Quite a bit / A lot), then saves a real `PainReport`.
  - "Not sure" is kept as a symptom note for tomorrow's check-in, not as pain.
  - The stop-and-get-checked text is unchanged.
- **C14 The went-well and work-on chips follow a session.** Ask them only after practice or a game, as one page with two rows. Never on rest days.
- **C15 Weekly items rotate in, one per week, on Sunday evening.** Fixed order:
  - Week A: "Next week looks…" (Normal / Busy with school / Exams / Travel)
  - Week B: "How much did you enjoy your sport this week?" (Not much / Okay / A lot)
  - The schedule question comes back sooner whenever the calendar shows something new.
  - Never more than one extra tap per week.
  [Silvia 2014; Hamlin 2019; burnout literature]
- **C16 Exam and school answers act on the plan and the twin.** "Exams" or "Busy with school":
  - sets the existing exam-week context (`DayStatus` or `BusyDays`; no new store), so gym sessions that week shorten (time recomposed, C-adaptive), and
  - adds those days to `excludedDays` for the twin's sleep comparisons.
- **C17 Enjoyment is a twin line, never a plan input.** It appears only as a "Your mind" line after ≥8 weekly answers, in words, against the athlete's own usual. If low 3 weeks running, the line adds "Want to talk to someone?". [burnout: stress precedes it; DiFiori 2014]
- **C18 Stress routes, it doesn't diagnose.** "Very stressed" on 2 of 3 mornings → the result page shows "Need to talk to someone?" (per country). No screening questionnaire, no mental-health result, nothing shared, no push. [SMHAT-1 is for clinicians, 16+]
- **C19 No cycle tracking, weight or food questions.** Period symptoms may be told as a symptom (lightens the day, logged as a symptom only). [AIS; Lupton 2021; owner nutrition rule]
- **C20 Words on every option. Recall periods named in the question.** No emoji-only scales. Stored scales never change meaning. [Mellor & Moore 2014]

---

## Proposal

Taps count the usual path: answer, auto-advance. Optional pages are marked.

### Morning check-in (every day; ~6 taps, unchanged length)

| # | Question (hint) | Options | When asked | Plan / twin effect | Change vs today |
|---|---|---|---|---|---|
| 0 | Context follow-ups (≤2) | as today | Open fatigue / exposure events | as today | — |
| 1 | What's on today? | as today | Always (pre-filled from schedule and games) | Day choice | — |
| 2 | How long did you sleep? ("Apple Health: 7 h 40 min") | Under 6 · 6–7 · 7–8 · 8–9 · 9+ · Not sure | Always. On watch days it sits on the summary as "from your watch" | Readiness, twin sleep | — |
| 3 | How well did you sleep? | Poor · Okay · Good · Great | Always | Readiness | **C2: pre-fill = own usual, not hours** |
| 4 | How is your energy? (heart note when two signs) | Low · Okay · Good · Great | Always | Readiness (most sensitive item) | — |
| 5 | How sore are you? | None · Mild · Moderate · High | Unless a legs follow-up ran | Readiness, legs recovery line | — |
| 6 | Any pain or discomfort? → Where / How much | Yes · No | Always | Safety path | — |
| 7 | Ill, or told to hold back? | No · Yes · Not sure | Always (pre-filled from yesterday) | Plan | — |
| 8 | How do you feel today? ("School, home, anything." **Game day: "Nerves count too."**) | Calm · Okay · Stressed · Very stressed | Always | Readiness; twin best-games nerves factor; **C18 support row** | Hint varies on game mornings; support row |

**One-tap "Feeling normal, no pain":** keep it, flagged as quick (C3).

**Removed from Home:** the separate "Yesterday's practice?" card shows only when the evening wasn't done (C8/C9). Its options gain effort meaning:
- "Went · normal" → effort 5
- "Went · hard" → effort 7

`went` stays "not said".

### Evening check-in by day type

The first screen is chosen by what the day held, worked out from `TrainingCalendar` items: practice, game, gym, rest. A day with both practice and a game takes the game branch.

#### Practice day (~5 taps + optional page)

| # | Question | Options | Saves to | Plan / twin effect |
|---|---|---|---|---|
| 1 | **How hard was practice?** ("The whole practice, not just the end.") | CR-10 tiles, word shown for the tapped value | `PracticeLog.hard` (CR-10 kept in a new `effort` field; 1–5 mapped for old readers) | Tomorrow: ≥9 → same rule as "very hard" today (`EveningSignal.hardness 4`). Twin: practice load, recovery after hard practices, best-games "hardest practice" factor |
| 2 | **About 90 min?** (from your schedule) | Shorter · As planned · Longer (tap for exact) | `PracticeLog.minutes` | Load = effort × minutes; "Your usual practice week" line |
| 3 | **How did practice go?** | Poor · Okay · Good · Great (stored 2/3/4/5 on `went`) | `PracticeLog.went` (+ `Reflection.practice` for old readers) | Twin: short nights vs practice; new best-practices line |
| 4 | How does your body feel? | Good · Tired · Very tired · Something hurt | `Reflection.body` | Very tired → morning follow-up (exists). Hurt → C13 |
| 4a | (hurt only) Where? How much? | `PainArea` grid · A little / Quite a bit / A lot | `PainReport` | Safety path, T9 recurring pain with a real area |
| 5 | *Optional, one page:* Went well / Work on | chips (existing 9) + note | `Reflection.wentWell/needsWork` | Twin focus and confidence insights |

**Dropped on practice days:** "How hard did today feel?" (C12) and the second pain question (C13).

#### Game day (~5 taps + optional page)

| # | Question | Options | Saves to | Effect |
|---|---|---|---|---|
| 1 | **How did you play?** ("Your own read, not the score.") | 1 · 2 · 3 · 4 · 5 (words: Poorly … Your best) | `CompetitionResult.rating` (outcome "not said" until the hub) | Twin best-games outcome (≥10) |
| 2 | **How much did you play?** | Didn't play · Under half · About half · Most · All of it | new `CompetitionResult.minutesShare` | Game load (C11). "Didn't play" → effort skipped; tomorrow isn't a post-game recovery day for the legs rule (MD+1 rule only applies when they played) |
| 3 | **How hard was it?** | CR-10 tiles | new `CompetitionResult.effort` | Load; MD+1/MD+2 recovery evidence |
| 4 | How does your body feel? (+4a) | as practice | as practice | as practice |
| 5 | *Optional:* Went well / Work on | chips | `CompetitionResult.wentWell/toImprove` (one place; the hub shows them) | Twin; "Until the next one" focus |

The hub's result form opens with these filled. It asks only outcome and score, both optional.

**Open product point:** "Didn't play" on the bench is common in high school. It must read calmly and never as a failure. The twin should leave those days out of best-games (they have no rating to give) without saying so.

#### Gym day, no practice (~1–2 taps + optional)

| # | Question | Note |
|---|---|---|
| 1 | How does your body feel? (+4a) | The workout's RPE was asked at the end of the session. Nothing about effort is asked again (C12) |
| — | Went well / Work on | Not asked (C14). The workout already had its moment |

If today's workout was started but not finished, or was told without effort, ask "How hard was today's training?" (CR-10) instead. One question.

#### Rest day (1 tap)

How does your body feel? (+4a when hurt). That's all. The "Skip today" option stays.

#### Exam or heavy school day (day status or a weekly answer)

This is not a separate check-in. The branch for the day (usually rest or practice) stays the same. The morning stress hint reads "Exams count too". The twin leaves the day out of sleep comparisons (C16). The plan shortens via the existing time and exam rules, so nothing new is asked.

#### Weekly item (Sunday evening only, one extra page, after the day's questions)

| Week | Question | Options | Effect |
|---|---|---|---|
| A | Next week looks… | Normal · Busy with school · Exams · Travel | Busy/Exams → exam-week context for those days (plan shorter, twin excludes). Travel → offers Edit week. Normal → nothing. Comes back the next Sunday if the calendar changed |
| B | How much did you enjoy your sport this week? | Not much · Okay · A lot | Twin "Your mind" line after 8 answers (C17). Never a plan input |

**Campus review question:** stays as today (it's learning, not monitoring), but it never appears on a weekly-item evening, so the extra pages stay at one.

### Twin lines this enables (all within T1–T15)

- **Your best practices** (≥20 rated practices; same top-third, all-best-on-one-side and replication rules as best games).
  - Factors, fixed, one direction each: sleep two nights ≥ usual, energy ≥ usual, soreness ≤ usual, stress ≤ usual, yesterday's effort ≤ usual.
  - "less sleep" and "harder day before" are never tested as the good direction (same principle as `gameFactors`).
- **Your usual practice week:** minutes and hard practices this week vs the last 4 weeks, as counts. No multiplier.
- **After hard practices:** next-morning energy or soreness vs after easy ones (≥4 hard, ≥4 easy, replicate). This only ever lengthens the gym planner's leg rest (T10), as the legs line already does.
- **Short nights vs practice:** finally fed (exists; C8).
- **Enjoyment this season:** trend words, after 8 weeks.

---

## What not to build

- A daily mood or mental-health questionnaire, PHQ/GAD items, or any "mental health result" (SMHAT-1 is clinicians-only, 16+).
- Cycle tracking, cycle-phase training advice or cycle predictions (C19). Weight, body measures, food, water.
- The full SRSS, RESTQ or Hooper index daily. Eight or more items breaks the 30-second rule. Borrow the constructs, not the instruments.
- A third daily prompt (after practice and again in the evening). Fold it into the evening (C5).
- A readiness or wellness number, a load number, an acute:chronic ratio or "risk" anything, a "training load 540 AU" display.
- Free-text required anywhere. Coach-reported practice (owner rule).
- Predicting tomorrow's game or practice from this morning's answers.
- Asking win/loss in the evening.
- A daily mental-fatigue item. The evidence is elite and adult, and there is no plan action for it. Revisit only if exam-week data show the stress item misses it.

## Open questions for the owner

1. **Practice effort scale:** full 1–10 tiles (consistent with workouts, best resolution) or a 5-word version stored as CR-10 2/4/6/8/10 (faster, coarser)? I recommend 1–10, since it is one scale everywhere.
2. **Game evening rating:** OK to create a `CompetitionResult` with outcome "not said" from the evening, so the hub only asks the score later?
3. **"How much did you play?":** fine to ask a 13-year-old who sat on the bench? The alternative is asking it only in sports where it varies (team sports) and wording it "Your minutes today".
4. **Weekly items:** Sunday evening OK? Is enjoyment welcome as a twin line, given "gamification last" and "never guilt"?
5. **Period symptoms:** allow "Period symptoms" as a told symptom (lightens the day, no cycle log), or leave it out entirely?
6. **Quick check-in flag (C3):** this needs a model field and a small change to the readiness engine and the twin. It is invisible to the athlete, but it changes past behaviour (old quick days can't be identified). Accept that only new ones are flagged?
7. **Stress → support row (C18):** "2 of 3 mornings Very stressed" is a design threshold, not a validated cut-off. OK as a calm, non-alarming row?

## Code findings to fix whatever is decided

1. `CheckInCard.swift:362–364`: sleep quality pre-filled from hours (C2).
2. `CheckInCard.swift:660` `QuickCheckIn.save`: medians saved as real answers (C3).
3. `MindsetViews.swift:86, 116–132, 300–305`: the evening asks pain twice and saves `areas: [.other]` without asking where; "Not sure" is lost (C13).
4. `Mindset.swift:76` `saveEvening` + `PracticeCards.swift:15`: the evening practice rating isn't a `PracticeLog`, so the morning asks again and the twin's sleep-vs-practice line is starved (C8).
5. `MindsetViews.swift:86`: went-well and work-on asked on rest days (C14).
6. `TwinAnalysis.swift:556–557`: game load fixed 60 × 8, practice minutes default 90 (C11).
7. `ReflectionSheet` doesn't know about games: a game day gets the generic flow and the hub asks again (C10).

---

## Sources

Opened in this pass (abstract unless noted):
- Duignan C, Doherty C, Caulfield B, Blake C. 2020. Single-item self-report measures of team-sport athlete wellbeing and their relationship with training load: a systematic review. *J Athl Train* 55(9):944–953. https://pmc.ncbi.nlm.nih.gov/articles/PMC7534939 [full text]
- Foster C et al. 2001. A new approach to monitoring exercise training. *J Strength Cond Res* 15(1):109–115. https://pubmed.ncbi.nlm.nih.gov/11708692/
- Gallo TF, Cormack SJ, Gabbett TJ, Lorenzen CH. 2016. Pre-training perceived wellness impacts training output in Australian football players. *J Sports Sci* 34(15):1445–1451. https://doi.org/10.1080/02640414.2015.1119295
- Gastin PB, Meyer D, Robinson D. 2013. Perceptions of wellness to monitor adaptive responses to training and competition in elite Australian football. *J Strength Cond Res* 27(9):2518–2526. https://doi.org/10.1519/JSC.0b013e31827fd600 [listing only]
- Gouttebarge V et al. 2021. International Olympic Committee (IOC) Sport Mental Health Assessment Tool 1 (SMHAT-1) and Sport Mental Health Recognition Tool 1 (SMHRT-1). *BJSM* 55:30–37. https://pmc.ncbi.nlm.nih.gov/articles/PMC7788187 [listing]
- Hamlin MJ et al. 2019. Monitoring training loads and perceived stress in young elite university athletes. *Front Physiol* 10:34. https://pmc.ncbi.nlm.nih.gov/articles/PMC6361803 (odds-ratio direction not verified)
- Kölling S et al. 2019/2020. Validation of the Acute Recovery and Stress Scale (ARSS) and Short Recovery and Stress Scale (SRSS) in three English-speaking regions. *J Sports Sci*. https://radar.brookes.ac.uk/radar/items/bee8cdd9-08c6-4e29-906c-bf7122514305/1 ; adolescent invariance: *Front Physiol* 2019, https://www.frontiersin.org/articles/10.3389/fphys.2019.01414/full
- Laurent CM et al. 2011. A practical approach to monitoring recovery: development of a perceived recovery status scale. *J Strength Cond Res* 25(3):620–628. https://pubmed.ncbi.nlm.nih.gov/20581704/
- Liu H et al. 2023. A meta-analysis of the criterion-related validity of Session-RPE scales in adolescent athletes. *BMC Sports Sci Med Rehabil* 15:101. https://pmc.ncbi.nlm.nih.gov/articles/PMC10422765 [full text]
- Mann RH et al. 2019. Validation of session RPE for quantifying internal training load in adolescent distance runners. *IJSPP*. https://researchportal.bath.ac.uk/en/publications/the-validation-of-session-rating-of-perceived-exertion-for-quanti/ [search summary only]
- McLean BD, Coutts AJ, Kelly V, McGuigan MR, Cormack SJ. 2010. Neuromuscular, endocrine, and perceptual fatigue responses during different length between-match microcycles in professional rugby league players. *IJSPP* 5(3):367–383. https://pubmed.ncbi.nlm.nih.gov/20861526/
- Mellor D, Moore KA. 2014. The use of Likert scales with children. *J Pediatr Psychol* 39(3):369–379. https://pubmed.ncbi.nlm.nih.gov/24163438
- Australian Institute of Sport. Menstrual cycle tracking guidelines. https://www.ais.gov.au/__data/assets/pdf_file/0005/1024889/Menstrual-Cycle-Tracking-Guidelines.pdf [search summary; PDF not opened]
- Raedeke TD, Smith AL. 2001. Athlete Burnout Questionnaire, and youth validation. https://research.birmingham.ac.uk/en/publications/validation-of-the-athlete-burnout-questionnaire-with-youth-athlet/ [search summary only; used only for "stress precedes burnout, enjoyment and motivation link"]
- Russell S et al. 2022. Mental fatigue over 2 elite netball seasons: a case for mental fatigue to be included in athlete self-report measures. *IJSPP*. https://acuresearchbank.acu.edu.au/item/8zvx5/ [listing]
- Saw AE, Main LC, Gastin PB. 2015. Monitoring athletes through self-report: factors influencing implementation. *J Sports Sci Med* 14(1):137–146. https://pmc.ncbi.nlm.nih.gov/articles/PMC4306765 [full text]
- Saw AE, Main LC, Gastin PB. 2016. Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures: a systematic review. *BJSM* 50(5):281–291. https://pmc.ncbi.nlm.nih.gov/articles/PMC4789708
- Sawczuk T, Jones B, Scantlebury S, Till K. 2018. Relationships between training load, sleep duration, and daily well-being and recovery measures in youth athletes. *Pediatr Exerc Sci* 30(3):345–352. https://pubmed.ncbi.nlm.nih.gov/29478381/
- Scantlebury S, Till K, Sawczuk T, Phibbs P, Jones B. 2018. The validity of retrospective session-rating of perceived exertion to quantify training load in youth athletes. *J Strength Cond Res* 32(7):1975–1980. https://eprints.leedsbeckett.ac.uk/id/eprint/3865/ [full text]
- Silvia PJ, Kwapil TR, Walsh MA, Myin-Germeys I. 2014. Planned missing-data designs in experience-sampling research: Monte Carlo simulations of efficient designs for assessing within-person constructs. *Behav Res Methods* 46:41–54. https://pmc.ncbi.nlm.nih.gov/articles/PMC3781177
- Thorpe RT et al. 2015. Monitoring fatigue during the in-season competitive phase in elite soccer players. *IJSPP* 10(8):958–964. https://researchonline.ljmu.ac.uk/id/eprint/3335/
- Tolusso DV et al. 2022. The validity of perceived recovery status as a marker of daily recovery following a high-volume back-squat protocol. *IJSPP*. [search summary only]
- Uchida MC et al. 2014. Effect of different post-exercise time intervals on session RPE in boxers. *J Sports Sci Med* 13:59. https://www.jssm.org/jssm-13-59.xml-abst [search summary]
- Wen CKF, Schneider S, Stone AA, Spruijt-Metz D. 2017. Compliance with mobile ecological momentary assessment protocols in children and adolescents: a systematic review and meta-analysis. *JMIR* 19(4):e132. https://pmc.ncbi.nlm.nih.gov/articles/PMC5425774

Already in the repo (not re-opened): DiFiori 2014, Epstein 2015, Lupton 2021, Thorpe 2016/17 follow-up (search summary), plus the twin rules T1–T15 (`docs/TWIN-RESEARCH.md`).

Not verified: Hooper & Mackinnon 1995 (not opened, not relied on); match sRPE × minutes played in adolescents (no validation found); emoji vs word scales in teens (design call, not researched).


## Second opinion (independent review, 2026-11-27) — this section wins where it disagrees

Where this review disagrees with the draft, this review wins. I checked the code in `app/Shared/Sources` and opened the main sources myself.

### Verdict in five lines

1. The direction is right: the evening should write a real `PracticeLog`, the game evening should rate the game, and pain should be asked once with an area. Most of the code findings hold.
2. The draft misses three real problems that matter more than some it lists:
   - `ReadinessEngine` can turn a day red from **one** item's one-point dip.
   - `WearableLoad` **invents** `went: 3, mood: 3` for watch-logged practices.
   - The existing load-spike insight already shows "+X%" with an injury line. That breaks A28, and feeding real sRPE would make it fire more.
3. C2 contradicts C3. It criticises saving medians nobody gave, then proposes pre-filling sleep quality with the athlete's median. The watch summary also carries yesterday's soreness and stress forward as today's answer. "Answers nobody gave" is wider than `QuickCheckIn`.
4. Some citations are overstated. Duignan did **not** find fatigue most consistent. Silvia 2014 does not support weekly single items. Saw 2015's "2–3×/week" is one staff member's suggestion.
5. Cut or defer: the separate minutes page, weekly enjoyment, "best practices", practice-as-leg-exposure and period symptoms. Ship the bug fixes first.

---

### 1. Code claims

| Draft claim | Verdict | Evidence |
|---|---|---|
| Evening practice answer isn't a `PracticeLog`, so the morning asks again | **Confirmed** | `MindsetStore.saveEvening` (Mindset.swift:75) writes only `Reflection.practice`/`feeling`. `HomeView.practiceToAsk` (1815) checks `PracticeLogStore.log` + `PracticeAnswers.answered`, never the reflection. |
| `sleepAndPractice` is starved: "went almost never written" | **Partly wrong** | For watch users, `WearableLoad.practiceLog` (WearableLoad.swift:57) writes `went: 3, mood: 3` for every practice-time workout. The twin is fed made-up 3s, which is worse than starved. Non-watch users: confirmed (`PracticeAnswers.save` writes `went: 0`). |
| One-tap `QuickCheckIn` saves medians as real answers, no flag | **Confirmed** | CheckInCard.swift:661–671. `CheckIn` has no flag (AthleteModels.swift:143), and neither does the backend `CheckIn` model. |
| …"spread shrinks, the next real dip looks bigger" | **Confirmed and worse than stated** | `zScore` only applies the prior/cap when SD == 0 exactly (ReadinessEngine.swift:~75). With 27 equal answers + 1 one-point-different answer in 28 days, SD ≈ 0.19. A one-point dip in one item gives z ≈ −5, which divided by 4 is ≈ −1.3, which is **red**. That breaks CLAUDE.md's "one item alone never makes red". It happens to steady real answerers too, not only quick days. |
| Sleep quality pre-filled from hours | **Confirmed** | CheckInCard.swift:368–370 (`WearablePrefill.sleepQuality`, CheckInPrefill.swift:25, maps <some hours to 1). It is only a pre-fill; the athlete can change it. |
| …"so the readiness z counts sleep twice" | **Wrong as worded** | The z uses only `sleepQuality` (ReadinessEngine:58). Hours act separately in `DailyLoop.readiness` (<5 h measured, <6 h named), and those candidates are a max, not a sum. The real harm: on watch days the quality item becomes a copy of hours, so its own signal is lost. |
| Evening asks pain twice, saves `[.other]`, "Not sure" lost | **Confirmed** | MindsetViews.swift:86 (`bodyFeel == 4 → .symptoms`), 116–132, 302–304. Two more problems: (a) "Something hurt" → "None" is accepted, a contradictory answer; (b) the report is keyed `DayKey.of(.now)` while the reflection uses `reflectionDay()`, so after midnight they land on different days. |
| Chips asked on rest days | **Confirmed** | `steps` always ends `[.wentWell, .needsWork]` (line 86). Side note: the `.learned` step is unreachable dead code (not in `steps`). |
| Game load 60 × 8, practice minutes default 90 × hard·2 | **Confirmed** | TwinAnalysis.swift:555–557. |
| Reflection sheet doesn't know about games | **Confirmed** | HomeView.swift:435. Only `practiceToday` + `restDay` are passed. A game day gets hardness/body/chips. `practiceToday` is read at `.now`, so after midnight it is tomorrow's schedule (minor). |
| Evening reminder ≈ 1 h after practice, 17:00–21:30 | **Confirmed** | ReminderScheduler.swift:142. |
| `PracticeLog.enjoyment` never asked on a fast path | **Confirmed** | Only the detailed log (ProgressTabView.swift:849). |

Missed by the draft and relevant to the proposal:
- **`PracticeLogStore.save` replaces the day's log** ("one log per day and sport"). C8 as written would overwrite the watch log's measured minutes. The evening must merge into it: keep watch minutes and set `went` and effort.
- **The watch summary pre-fills soreness and stress from yesterday** (CheckInCard.swift:379–381), and energy from the heart, then saves them on one "Confirm". That is the same "answer nobody gave" class as `QuickCheckIn`, and it can carry "Very stressed" forward. This matters for C18's trigger.
- **Load-spike insight** (TwinAnalysis.swift:580–587): "Your training load jumped N% this week. Big jumps are when injuries happen most." It computes this week against the 3-week mean, which is an acute:chronic ratio in all but name, and it shows the percentage and an injury claim. That is against A28. Fix this before C11 makes loads real.
- **Hub defaults bias the twin:** `CompetitionResultForm` starts at `outcome = .win`, `rating = 3` (CompetitionViews.swift:671–674), and Tell does the same (TellView.swift:603). A result saved without touching the rating counts as a rated game. `Outcome` has no "not said" case, so C10's "outcome not said" needs a model change (make `outcome` optional).
- **Privacy note:** `CompetitionResult` lives under `mindset.` (sealed). `PracticeLog` lives under `progress.` (backed up **unsealed**). The watch-derived practice log (minutes, HR-derived effort, "From your Apple Watch") already reaches the server that way, and so do Health sleep hours in `CheckIn.sleepHours`. That sits uneasily with "Health data never backed up". It is out of scope here, but don't add more Health-derived fields to `PracticeLog` without deciding this. Moving "how practice went" from sealed `Reflection` to unsealed `PracticeLog` is acceptable, since `PracticeLog.went` already exists from the detailed log, but it is a choice.
- **Exam weeks already have a store:** `manualExamWeeks` in CalendarImport.swift:551. C16 should write there, not to `DayStatus`/`BusyDays`.

### 2. Sources

| Source | Verdict |
|---|---|
| Duignan 2020 | Counts (21 studies, 500 athletes; soreness 20, fatigue 20, sleep 19, stress 14, mood 6), "predominantly trivial to moderate" and "may not be expected or useful" are **accurate**. **Overreach:** "fatigue was the most consistent" is not in the paper. The review ranks no item above another. Remove it from Bottom line 1, §A and C1. |
| Thorpe 2015 | r = −0.51 fatigue vs high-intensity running is **accurate**. Ln rMSSD was also called sensitive (r = −0.24), and the draft leaves that out. Fine to leave out, but "HR recovery did not" should not imply the heart is useless. |
| Saw 2015 | **Accurate quotes**, but n = 30 was **8 athletes**, 7 coaches and 15 staff. "Half admitted" = 4 of 8. "2–3×/week" was one staff member's suggestion, not a finding. Say so. |
| Saw 2016 | Not re-checked; well known, claim fits. |
| Wen 2017 | **Accurate**, with small slips: 4–5 prompts = 74.4% (draft says 77.4%); 36 studies pooled out of 42. Conclusion unchanged. |
| Liu 2023 | **Accurate** (16 studies, r = 0.74, CR-10 0.69, CR-100 0.80 from 3 soccer studies, ~90% male, weakest under 12). Age was descriptive, not a tested moderator. |
| Scantlebury 2018 | **Accurate** (n = 38, 24 h r = 0.98 TEE 8.3%, 72 h TEE 35%). |
| Hamlin 2019 | **Resolved:** OR 0.91 is per point on a scale where 5 = *no* pressure, so more academic pressure → higher injury odds (~9% per point). The draft's direction is correct; drop the caveat. University athletes aged 18–22: say "older than ours". |
| Silvia 2014 | **Misapplied.** It is about omitting items of a *multi-item latent construct* within a beep, in multilevel models across many people. It says nothing about asking a single item weekly to follow one person's trend. Weekly items are a fine design call; cite it as design, not as Silvia. |
| Sawczuk 2018 | **Accurate** (n = 52, well-being–sleep r = .28, recovery–load r = −.23, CMJ neither). Well-being did *not* track load (r = −.05), which is worth saying. |
| Laurent 2011 | n = 16, r = −0.63: matches secondary listings. Not used by the proposal, so it doesn't matter. |
| Mellor & Moore 2014 | Exists. Ages are primary-school children. The word-vs-number claim could only be confirmed from summaries. Fine as a "design call, supported by", not as evidence for teens. |
| AIS cycle guidelines | Opt-in, not compulsory, and medical oversight for system-based tracking: **confirmed** from excerpts. |
| SMHAT-1 | For clinicians, athletes 16+: consistent with the published tool. |
| Foster 2001 "~950 citing studies by 2017" | Unsourced number; drop it. |

### 3. Proposal against the product rules

- **No scores / A28:** the draft is right not to show load, but it says "keep that wording" about an insight that today shows "+N%" with an injury claim. **Rewrite the load-spike insight first** as counts and minutes ("3 practices and 2 games this week, usually 2 and 1"), with no percentage and no injury line.
- **Answers nobody gave:** C2 (pre-fill quality = median) repeats the C3 problem. Leave quality **unfilled** on watch days (one tap, the row already says "Tap to answer"), or store a "pre-filled, untouched" mark. Apply the same mark to the watch summary's carried-over soreness, stress and heart energy. Simplest common fix:
  - (a) an SD floor in `ReadinessEngine` (`max(sd, priorSpread × 0.5)` or similar, and the "one item never red" cap applied always). This fixes the red-from-one-item bug for everyone.
  - (b) one optional `CheckIn.unchanged` flag (quick or confirmed-without-edit) that twin pattern detection skips. If it's local only, it is lost on restore; either add the backend column or accept that.
- **Never tell twice:**
  - C8 must merge with the watch log and must not ask how hard practice was when the watch already logged it. Show "From your watch: 85 min" and ask only how it went, and effort only if the athlete wants to correct it.
  - The weekly "Next week looks…" must be skipped when exams or travel are already known (`manualExamWeeks`, Tell, a calendar).
- **Pain = stop and get checked (minors):**
  - The evening "Where?" grid must route a **head** answer straight to the existing head-injury path that evening (PainNote with pause / Safety centre, "tell an adult tonight"), not wait for the morning.
  - Don't allow "Something hurt" → "None".
  - Keep pain out of `TwinPulse` lines (already the rule).
- **Personal data only lengthens rest:** "practice ≥ 8 = hard leg exposure" only adds rest, so it is allowed. But a soccer player who rates every practice 8 would see legs held all season. **Defer** until there's data, and give it a ceiling (the existing ~8-day in-season leg return wins).
- **Stress → support row (C18):** fine and calm. Trigger it only on mornings the athlete actually tapped, never on carried-over or quick values. No push, nothing shared.
- **Enjoyment (C17):** a weekly mood-like item for 13-year-olds that produces a "lower than your usual" mind line edges toward a wellbeing result, and it changes no plan (C4 says such items go). **Cut it for now.** Revisit only if the owner wants it.
- **Period symptoms:** leave it out. "Something hurt" and illness already lighten the day; a named period option for under-16s needs consent work.
- **Question count:**
  - The practice evening is **not shorter** than today (5 pages vs 5).
  - Fold minutes into the effort page as a pre-filled line ("About 90 min · change"), using watch minutes when present. That gives effort → how it went → body → optional chips: 3 taps.
  - Game evening: rating → "Did you play?" (Yes / A little / No; skip for individual sports) → effort → body: 4 taps. Drop the 5-band minutes scale; three bands are enough for load.
  - Morning is unchanged. The draft's "~6 taps" understates it: up to 2 follow-ups + 8 items on a non-watch day. Nothing new should be added there.
- **"Best practices" twin line:** adds a new Still-learning row and a new busy surface, and needs 20 rated practices. Defer until C8 has run a season. `sleepAndPractice` already uses the same data.
- **C12 (skip "How hard did today feel?")**: good. Keep `EveningSignal.hardness` working by deriving it (CR-10 ≥ 9 → 4, ≥ 7 → 3), so tomorrow's "yesterday was very hard" rule doesn't silently stop.

### 4. Recommended build order

Smallest valuable steps first. Each step is shippable alone.

1. **Fix what's wrong today, no new questions:**
   - SD floor plus the cap applied always in `ReadinessEngine` (harness-testable).
   - Load-spike insight as counts, with no % and no injury claim.
   - `WearableLoad` writes `went: 0, mood: 0` (not said).
   - Hub and Tell results: no default rating, optional outcome.
2. **Evening pain once:**
   - "Something hurt" → Where / How much → real `PainReport` on `reflectionDay`.
   - Head → head path tonight.
   - "Not sure" → a note for the morning.
3. **Evening practice answer writes or merges the `PracticeLog`** (`went`; `hard` from the answer; keep watch minutes). The morning card then stays quiet. Chips only after practice or a game.
4. **Sleep quality not pre-filled from hours.** Add the `unchanged` flag for quick and carried-over check-ins, skipped by twin patterns.
5. **Practice-day evening effort:** CR-10 replaces "How hard did today feel?" on practice days. Minutes as a pre-filled line. Real minutes × effort in `weeklyLoads`. Skip day hardness when sessions already have effort (C12, derived signal).
6. **Game evening:** rating + did you play + effort → `CompetitionResult`. The hub then asks only the score.
7. **Weekly "Next week looks…"** (Sunday, skipped when known) → `manualExamWeeks` and the twin's excluded days.
8. **Later / owner:** stress support row copy; enjoyment; best practices; practice as a leg exposure; period symptoms.

### Owner questions: who really decides

| # | Needs owner? | Default |
|---|---|---|
| 1 Effort scale | No | 1–10, same as workouts |
| 2 Result with outcome "not said" | No | Yes; make outcome optional |
| 3 Minutes played | No | "Did you play? Yes / A little / No", team sports only, calm copy |
| 4 Weekly items | Partly | Schedule item: default yes (Sunday, skipped when known). **Enjoyment: owner**, recommend not now |
| 5 Period symptoms | **Yes** | Leave out |
| 6 Quick flag only for new days | No | Yes |
| 7 Stress → support row | **Yes, for the wording** (minors, mental-health adjacent) | Threshold 2 of 3 *tapped* mornings is fine |
