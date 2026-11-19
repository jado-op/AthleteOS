# Gym algorithm — research

Owner's brief (2026-11-19): the athlete taps **Gym** and picks a focus — Upper body, Lower body, Core, Full
body, or **You pick**. Each focus keeps a stable base of **anchor lifts** for weeks (so progress is real and
measurable) and **rotating accessories** that change every session. "You pick" chooses the region from recent
training, recovery per region, stalled lifts, sport demands, practice and game load, readiness and sleep (sleep
from a watch via Apple Health counts more when it is there). The athlete also picks a **length** (~30 / ~60 /
~90 min), and a **no-gym (bodyweight) mode** covers holidays and travel.

This file adds to `docs/TRAINING-RESEARCH.md` and does not repeat it (training stage, reps in reserve, landing
caps, injury prevention per sport, pull ≥ push, strength before cardio, in-season maintenance, Milewski/Mah
sleep findings are there). Every source below was opened or its abstract read in Europe PMC / the publisher /
an author repository (list at the end). Evidence labels:

- **[strong]** meta-analysis or position stand with consistent findings;
- **[moderate]** a few RCTs or a systematic review with caveats;
- **[weak]** single small studies, mostly adults or trained men;
- **[consensus]** coaching consensus / expert opinion, no trial behind the exact number;
- **[engineering]** a number we chose inside the evidence so the code has something to compute.

Most trials are on young adult men. Youth evidence is thinner; where a rule is applied to 13–19-year-olds on
adult data, the more conservative end of the range is used.

---

## Rules for the gym algorithm

### A. Week shape and frequency

1. **Gym days per week:** 2–3 on non-consecutive days is the default for youth; in season at least 1 (keeps
   strength, see TRAINING-RESEARCH §6). 4 days only for *performance* stage (16+, experienced) in off-season.
   *(Lloyd2014 [consensus]; ACSM2009 2–3 d novice, 3–4 d intermediate [consensus]; Rønnestad2011)*
2. **Each region (upper / lower / core) should be hit at least 2× per week when there are ≥2 gym days.**
   Frequency itself barely matters when weekly volume is equal; it matters because it is the easiest way to
   get enough weekly sets without long, exhausting sessions. Target ≥ 4 hard sets per muscle group per week as
   the floor, ~6–10 as the development target (youth: size is not the goal, so no chase beyond ~10).
   *(Schoenfeld2019, Grgic2018 [strong]; Iversen2021 ≥4 sets floor [moderate]; Sousa2024 5+ sets/movement/week for strength [consensus])*
3. **Split by number of gym days** (suggested template; the athlete's focus choice overrides it):
   - 1 day → Full body.
   - 2 days → Full body + Full body (A/B anchors).
   - 3 days → Full body ×3 with rotating emphasis (lower-led, upper-led, full), or Lower / Upper / Full.
   - 4 days → Upper / Lower / Upper / Lower.
   Split vs full body makes no meaningful difference for strength or size when volume is equal, so the choice
   is made by recovery and schedule (practice days, games), not by "which split is best".
   *(RamosCampo2024 [strong]; Bartolomei2021 [weak, slight strength edge for full body]; templates [consensus])*

### B. Recovery windows (hard filters before anything is scored)

4. **Heavy lower** (squat/hinge anchor at ≤ 3 reps in reserve, or ≥ 6 hard lower sets): next heavy lower
   **≥ 72 h** later; light/technique lower or jumps allowed after **48 h**.
   **Heavy upper:** next heavy upper **≥ 48 h**; a light upper session after 24 h is fine.
   **Core:** may be trained every gym day (low fatigue), but heavy loaded carries/anti-rotation count as lower
   for the 48 h rule only if ≥ 4 hard sets.
   Sets to failure lengthen recovery by ~24–48 h, which is one more reason the app never goes to failure.
   *(Sousa2024: lower 48–72 h, upper ≤ 24 h; failure adds 24–48 h [moderate]; 72 h for legs = conservative [engineering])*
5. **Practice counts as lower-body load** for running, jumping and cutting sports: a *hard* practice (sRPE ≥ 7
   or "hard" in the check-in) marks lower as trained for 24 h (heavy lower is not offered the same day *after*
   it); a game marks lower as heavily trained for **72 h** (contact sports) / **48 h** (others).
   *(Silva2018: match fatigue lasts up to 72 h [strong for soccer, extrapolated]; SportDemands mapping [engineering])*
6. **Before games:** no heavy lower at MD-2 or MD-1 (no anchors at ≤ 3 RIR within 48 h of a game); MD-1 may
   only have short upper/core work or a light "primer" (≤ 3 sets of fast, low-rep moves, ≥ 4 RIR). After a game
   (MD+1), upper or core only. *(Silva2018; Sousa2024 — light upper the day after a damaging lower session
   helped recovery [weak]; primer details [consensus])*

### C. Anchors and accessories

7. **Anchors per focus** (fixed for the block):
   - Upper: 1 horizontal or vertical **push** + 1 **pull** (pull ≥ push still applies).
   - Lower: 1 **knee-dominant** (squat family) + 1 **hip-dominant** (hinge family).
   - Full: 1 lower anchor + 1 upper anchor, alternating squat/hinge and push/pull between A and B days.
   - Core: 1 anti-extension + 1 anti-rotation anchor (see rule 15).
   Foundation athletes get *simpler* anchors (goblet squat, trap-bar or KB deadlift, push-up, inverted row).
8. **Keep anchors for one block of 4 weeks** (allowed range 3–6), then either keep them (still progressing) or
   swap to a close variant (back → front squat, RDL → trap-bar deadlift, bench → incline). Never swap an anchor
   mid-block except for pain, equipment, or rule 13. Skill-heavy lifts (squat, hinge, Olympic derivatives) need
   repetition to improve, so they rotate least.
   *(Kassiano2022: systematic variation helps, excessive/random variation hinders [moderate]; Fonseca2014:
   varied *exercises* at constant intensity gave the best strength gains [weak]; 4-week block = Issurin2010
   block length + Gavanda2020 / Plotkin2022 8–12-week trials [consensus])*
9. **Accessories rotate every session** from a pool of **≥ 3 exercises per slot**; a slot is defined by movement
   pattern + main muscle (e.g. "single-leg knee-dominant", "horizontal pull", "hamstring knee-flexion").
   Constraints: not the same accessory as the last session of that focus; not a redundant copy of the anchor
   (same pattern and same muscle length); variety should *add* a muscle, angle or plane. Rotation is good for
   motivation and gives similar gains in trained lifters.
   *(Kassiano2022 [moderate]; BazValle2019: random variation = same gains, more motivation [weak]; Fonseca2014)*
10. **Session order:** fast/power work → anchors → accessories → core → conditioning (existing order, still
    supported). *(Simão2012 in TRAINING-RESEARCH; Murlasits2018)*

### D. Progression and stalls

11. **Double progression on every anchor and accessory.** Each lift has a rep range by stage — foundation
    8–12, development 6–10, performance 4–8 for anchors (accessories 8–12 for all). When **all work sets reach
    the top of the range at the target reps in reserve in 2 consecutive sessions**, add load: **+2–5 %**
    (smallest plate step: 2.5 kg lower, 1–2.5 kg upper, next dumbbell) and restart at the bottom of the range.
    Youth cap +5 % per step.
    *(ACSM2009: +2–10 % when 1–2 reps over target on two consecutive sessions [consensus]; Plotkin2022: adding
    reps works as well as adding load [moderate]; Lloyd2014: 2–4 × 6–12 at ≤ 80 % 1RM once technique is
    competent [consensus]; youth 5 % cap [engineering])*
12. **In-session autoregulation from reps in reserve.** After each anchor set the athlete taps how many reps
    were left. ≥ 2 more left than the target → next set +1 step (~4 %); ≥ 1 fewer than the target (or a missed
    rep) → next set −1 step. Within ±1 → keep. Foundation athletes use a simpler "easy / right / hard" tap
    [engineering]. *(Zourdos2016 RIR-based RPE scale, "a practical method to regulate daily training load"; Helms2018: ±2 % per 0.5 RPE outside the target range,
    missed rep = 1 RPE point [moderate]; Larsen2021: autoregulation ≥ fixed loading for strength [moderate])*
13. **Stall = no increase in either reps or load on an anchor across 3 consecutive exposures** (exposures on a
    "below normal" readiness or short-sleep day don't count — they are context, not a stall). Response, in order:
    1. 1st stall: reset — load −10 %, build back with double progression (usually passes the old best in 2–3 weeks).
    2. 2nd stall in the same block, or 2 anchors stalled at once: **deload week** (sets −40–50 %, load kept or
       −10 %, reps in reserve ≥ 4), then change the rep range (e.g. 6–8 → 8–10) or swap to the close variant at the
       next block.
    3. Planned deload every 4–6 weeks of hard training for development/performance stage; foundation athletes
       rarely need one (light loads), they progress technique instead.
    *(Rogerson2024 survey: deloads ~every 5.6 ± 2.3 weeks, ~6 days long, volume and load cut, more reps in
    reserve, same exercises, also used "when performance stalled" [consensus]; Bell2023 Delphi definition
    [consensus]; "3 exposures" and "−10 %" [engineering])*
14. **Lagging lift detection** for "You pick": compute an estimated-strength trend per anchor (best load × reps
    in the last 6 exposures, using the same formula every time, never a 1RM test). A region whose anchors are
    stalled or trending flat for ≥ 3 weeks while others rise gets a priority bonus (rule 19). This is a
    **trend for the athlete's own Performances**, never compared with other athletes. *[engineering]*

### E. Core

15. **Every gym session ends with 5–8 min of core** (1–2 exercises); a Core focus session is 20–30 min.
    Cover the three "anti" categories each week — **anti-extension** (dead bug, plank, ab-wheel rollout),
    **anti-rotation** (Pallof press, bird dog, renegade row), **anti-lateral flexion** (side plank, suitcase carry,
    Copenhagen side plank for groin sports) — plus for development/performance stage **rotational power**
    (med-ball throws, ≤ 6 reps, fast). Holds of ≤ 10 s repeated for reps (e.g. 5 × 8 s), not 60-s planks;
    progress with leverage/load, not duration. Stable ground first; unstable surfaces are a variation, not the
    base. *(McGill2010 [consensus + mechanistic]; Saeterbakken2022: trunk training improves fitness and sport
    performance, > 18 sessions and ≤ 30-min sessions work best [moderate]; Behm2010 instability [moderate])*

### F. "You pick" — choosing the region

16. **Hard filters first** (rules 4–6, pain flags from the check-in, and the weekly landing cap). If nothing
    passes → offer Core + mobility or rest.
17. **Readiness (subjective check-in) is the main signal**, wearables are secondary. Below-normal check-in →
    choose the lowest-fatigue eligible region (core > upper > full > lower), +1 rep in reserve on everything,
    −1 set per anchor, no load increase that day. *(Saw2016: subjective measures track training load better than
    objective ones [strong]; Foster2001 sRPE valid [strong])*
18. **Sleep.** Teens need **8–10 h** (AASM). Use **total sleep time** from Apple Health when available — use
    *duration and timing only*, never sleep stages (wearables agree with polysomnography on sleep vs wake
    ~86–89 %, on stages only ~50–65 %). Compare with the athlete's own 14-day median.
    - Last night < 7 h **or** 3-night average < 7.5 h → treat as below normal (rule 17).
    - Last night < 6 h → also no heavy lower, no power/sprint work (skill and power drop most), no new loads;
      prefer upper or core; suggest training earlier in the day if possible.
    - < 5 h → technique/mobility only.
    - Watch data present → it **overrides** self-reported duration; self-reported "slept badly" still counts.
      No watch → the check-in's sleep answer is used with the same thresholds.
    *(Paruthi2016 [consensus]; Craven2022: one night of sleep loss −7.6 % performance overall, strength −2.9 %,
    anaerobic power −6.3 %, skill −20.9 %, early waking worst, morning tasks least affected [strong];
    Milewski2014 injury odds 1.7× < 8 h [moderate]; Miller2022, Chinoy2021 device accuracy [moderate];
    Walsh2021 individual sleep need [consensus]; thresholds [engineering])*
19. **Score the eligible regions** (higher = pick), then show the reason in "Why this workout?":
    - +3 per day since that region's last hard session beyond its recovery window (cap +9);
    - +4 if the region is below its weekly set floor (rule 2), +2 if below target;
    - +3 lagging anchor (rule 14);
    - +2 sport priority (the sport's `SportDemands` / `InjuryPrevention` region — e.g. lower + hamstrings for
      soccer, upper pull + cuff for throwers/swimmers);
    - −4 lower if hard practice yesterday or today, −2 lower if practice later today;
    - readiness/sleep modifiers from rules 17–18.
    Full body wins ties when ≥ 2 regions are eligible and the session is ≥ 60 min. *[engineering, inputs from
    rules above]*

### G. Session length tiers

20. **~30 min "Quick":** 4–5 min specific warm-up (ramp-up sets of the first anchor, no long general warm-up),
    **2 anchors × 3 sets**, each paired as a superset with a non-competing accessory or core exercise
    (push + pull, squat + core, hinge + upper pull); rest ~90–120 s between rounds; no conditioning.
21. **~60 min "Standard":** 8–10 min warm-up (+ fast block when the plan has one), **2 anchors × 3–4 sets** with
    2–3 min rest, **2–3 accessories × 2–3 sets** (60–90 s, paired), 5–8 min core.
22. **~90 min "Full":** the Standard session + 1 more accessory + **conditioning finisher 12–20 min after the
    lifting**. Default finisher = bike or rower intervals (e.g. 6–10 × 30 s hard / 60–90 s easy) or 15–20 min easy
    aerobic ("you can talk"). Running intervals only on upper days or for running sports in pre-season.
    Guard rails: development/performance stage only (foundation gets max 60 min), not on below-normal readiness
    or short sleep, not within 48 h of a game, not on a hard-practice day, and weekly organised-sport hours
    (practice + games + gym) stay ≤ the athlete's age in years.
    *(Murlasits2018: strength before endurance keeps lower-body strength gains [strong]; Sabag2018: HIIT
    reduces lower-body strength gains slightly (ES −0.25), upper body and size unaffected [moderate]; Wilson2012:
    running interferes more than cycling [moderate] — Sabag found the opposite trend, so the mode choice is made
    for impact load and landing caps, not interference [consensus]; Jayanthi2015 hours rule)*
23. **When time is short, cut in this order:** conditioning finisher → 3rd accessory → accessory sets (to 2) →
    core (to 1 exercise) → pair remaining exercises as supersets → anchor sets (never below 2 hard sets each).
    Anchors are the last thing cut. *(Iversen2021: prioritise multi-joint lifts; supersets roughly halve session
    time at the same volume [moderate]; cut order [consensus])*
24. **Rest periods:** anchors 2–3 min (power/Olympic and heavy sets 2–3 min, Lloyd2014; trained lifters ≥ 2 min,
    Iversen2021); accessories 60–90 s; supersets only of non-competing muscle groups.

### H. No-gym / bodyweight days (holiday, travel)

25. **Short breaks cost little.** Up to ~3 weeks without lifting barely moves strength in trained athletes, and
    3 weeks of no training did not reduce strength, muscle thickness or sport performance in 15–18-year-olds.
    Losses grow with the length of the break. So the message is calm: "a week away doesn't undo your work".
    *(McMaster2013 up to 3 weeks maintained [moderate]; Gavanda2020 adolescents [weak]; Mujika2000 strength
    declines limited < 4 weeks [consensus review]; Bosquet2013 dose–response with break length [strong])*
26. **Bodyweight mode:** 15–25 min sessions, every day or every other day, alternating Lower+Core and
    Upper+Core. Keep sets hard (1–3 reps in reserve) and keep a little speed: 20–30 low-impact jump contacts per
    lower session (inside the landing caps).
    - Lower: split squat → rear-foot-elevated split squat → slow-eccentric (3–4 s) or pause versions → single-leg
      squat to box; single-leg RDL; hip thrust / single-leg bridge; Nordic (with a partner) or slider curls.
    - Upper: push-up → feet-elevated / deficit / tempo push-up → archer; inverted row under a table or towel row;
      pike push-up.
    - Progression: when a set passes **~15 reps at the target reps in reserve**, move to the next harder variant
      (or slow the tempo) rather than adding reps without end.
    *(Calatayud2015: push-ups loaded to a comparable effort gave the same strength gains as bench press [weak];
    Kotarsky2018: progressive push-up variations raised bench 1RM like bench training over 4 weeks [weak];
    15-rep cut-off [engineering])*
27. **Back from a break of ≥ 2 weeks:** first gym session at the last working loads −10 % and +1 rep in reserve,
    then normal progression. *[consensus]*

### I. Long-term development

28. **Weaker athletes build strength before emphasising power;** stronger athletes add power while keeping
    strength. In the app: foundation and early development stage spend most of the gym time on anchors and
    technique; power blocks grow with stage (existing `TrainingStage`). *(Suchomel2018 [consensus review];
    Lloyd & Oliver 2012 in TRAINING-RESEARCH)*
29. **No relative-strength targets for teens.** "Squat 1.5–2× body weight" style benchmarks come from adult
    athlete studies (associations, not trials) and are not validated for 13–19-year-olds; they also invite
    max-testing and comparison. The app shows each athlete's own trend only. *[consensus]*

---

## Detailed evidence

### 1. Frequency and recovery

**Frequency.** Schoenfeld, Grgic & Krieger (2019) meta-analysed frequency trials for muscle growth: "no
significant difference between higher and lower frequency on a volume-equated basis", also for trained people
and for upper vs lower body. In non-volume-equated studies higher frequency helped modestly, because it adds
volume. Conclusion: "for a given training volume, individuals can choose a weekly frequency per muscle group based
on personal preference". Grgic et al. (2018) found the same for strength: effect sizes rose 1 → 4+ sessions/week,
but with volume equated there was no frequency effect; higher frequencies seemed more useful for multi-joint
upper-body lifts and in young people. So the app uses frequency as the tool to reach weekly volume without long
sessions (rule 2), not as a goal itself. Youth consensus: 2–3 sessions a week on non-consecutive days
(Lloyd2014, adapted from the UKSCA statement); ACSM 2009 gives 2–3 d novice, 3–4 d intermediate.

**Recovery.** Sousa, Zourdos, Storey & Helms (2024) reviewed how recovery should shape the training week.
Findings they collate: lower body generally needs 48–72 h, upper body ≤ 24 h; after sets to failure jump
performance stayed down for up to 48 h while non-failure groups recovered in ~6 h (González-Badillo 2016); with
equal volume, 3 × 10 to failure needed 24–48 h longer than 6 × 5 (Morán-Navarro 2017); jump recovered by 48 h but
strength and sprint took 72 h (Thomas 2018); multi-joint lifts need more recovery than single-joint; an upper-body
session the day after a damaging lower session improved recovery (Abaidia 2017). Practical points: start low,
increase volume only if recovery allows; put lower-fatigue sessions before high-priority ones. Limits: small,
mostly male, lab samples; sleep and nutrition rarely controlled. **The 72-h heavy-lower window is the
conservative end of this range, chosen because our athletes also run and jump in practice.**

**Practice and games.** Silva et al. (2018, soccer meta-analysis): neuromuscular, perceptual and biochemical
fatigue after a match can last up to 72 h, and "coaches must adjust the structure and content of the training
sessions during the 72-h post-match" window. No equivalent meta-analysis was found for other team sports;
extending it to basketball, handball, rugby, football etc. is a reasonable assumption, labelled [consensus].

### 2. Splits

Ramos-Campo et al. (2024, meta-analysis, healthy adults, volume-equated): "solid evidence that the use of split or
full-body routines … does not significantly impact either strength gains or muscle hypertrophy … individuals
are free to confidently select a resistance training routine based on their personal preferences."
Bartolomei et al. (2021, 21 trained men): both improved; full body had a slightly larger gain in one strength
measure, split in one thickness measure. For youth athletes, the consensus statements describe sessions that
include lower, upper and trunk work (Lloyd2014), i.e. full body, and S&C practice for team sports uses full body
at 2–3 days. Upper/lower at 4 days is coaching practice that keeps each session short. **Takeaway:** the split is
a scheduling tool; choose it so recovery windows (rule 4) and practice/games fit.

### 3. Anchors vs variation

- Kassiano et al. (2022, systematic review, 8 studies, 241 young men): "Some degree of systematic variation seems
  to enhance regional hypertrophic adaptations and maximize dynamic strength, whereas excessive, random variation
  may compromise muscular gains … employing different exercises that provide a redundant stimulus, as well as
  excessive rotation of different exercises (i.e., high frequency of change), may actually hinder muscular
  adaptations."
- Fonseca et al. (2014): constant intensity + varied *exercises* (squat variants, leg press, deadlift, lunge)
  gave the largest strength gains and hypertrophy in all quadriceps heads; varied intensity on the same
  exercise did worst. Small study; strength was tested on a Smith-machine squat.
- Baz-Valle et al. (2019, trained men): exercises randomised every session gave the same muscle and strength
  gains as a fixed programme and **more motivation to train**.
- Practical reading: the main lift that is tested/tracked must stay constant long enough to measure progress and
  to learn the skill (anchors); variety belongs in accessories, chosen to add a different angle or muscle, not
  a near-duplicate. The **4-week anchor block** is not a trial number: mesocycles of 3–6 weeks are the usual
  block length in periodisation literature (Issurin 2010, cited in TRAINING-RESEARCH) and most variation trials
  ran 8–12 weeks with the same main lifts. [consensus]

### 4. Progression and stalls

- **Load rule.** ACSM 2009 position stand: "When training at a specific RM load, it is recommended that a 2–10 %
  increase in load be applied when the individual can perform the current workload for 1–2 repetitions over the
  desired number on two consecutive training sessions." This is the textbook "2-for-2" logic; rule 11 uses it
  with the youth-conservative 2–5 % step.
- **Reps or load.** Plotkin et al. (2022, 8 weeks): progressing repetitions vs progressing load gave similar
  strength and size gains — so double progression (reps first, then load) is valid.
- **Autoregulation.** Helms et al. (2018, Frontiers in Physiology, trained men, 8 weeks): RPE-based loading was
  at least as good as %1RM (small, non-significant edge for RPE). Their rule: "for every 0.5 RPE above or below the
  … threshold, load was decreased or increased by 2 %"; a missed repetition counted as a full RPE point. Larsen,
  Kristiansen & van den Tillaar (2021, systematic review): subjective (RPE/RIR) and objective (velocity)
  autoregulation tended to equal or beat fixed loading for maximal strength.
- **Youth dose.** Lloyd2014: once technique is competent, 2–4 sets of 6–12 reps at ≤ 80 % 1RM; experienced
  adolescents may use heavier, lower-rep work (e.g. 3 × 3–5 squat) "on the proviso that technical competency
  remains".
- **Stalls and deloads.** There is no trial defining a "stall". Deload research is mostly surveys and Delphi
  consensus in strength/physique athletes. Rogerson et al. (2024, survey of 246 competitive lifters): a deload
  lasted 6.4 ± 1.7 days every 5.6 ± 2.3 weeks, was pre-planned and/or triggered "when performance stalled",
  cut sets and reps, lowered load and effort, and kept frequency and exercise selection. Bell et al. (2023,
  Delphi of expert coaches) defines a deload as "a period of reduced training stress designed to mitigate
  physiological and psychological fatigue, promote recovery, and enhance preparedness". Neither is youth data. The 3-exposure stall rule and −10 % reset are [engineering],
  chosen to be conservative and simple to explain.

### 5. Core

McGill (2010) describes the trunk's main sport job as *stopping* motion — stiffening so hip power transfers
("energy leaks" when the spine bends) — which is the basis of the anti-extension / anti-rotation / anti-lateral
flexion categories. Programme organisation: push, pull, lift, carry and "torsional buttressing" tasks; the "Big 3"
(curl-up, side bridge, bird dog) for endurance and control; "keep the duration of isometric exercises under 10
seconds and build endurance with repetitions, not by increasing the duration of the holds"; asymmetric carries
(suitcase) train the lateral wall in a way squats do not. Saeterbakken et al. (2022, meta-analysis, young and adult
athletes): trunk muscle training improves physical fitness and sport-specific performance; more than 18 sessions
and sessions ≤ 30 min were most effective for power, sprint and change of direction. Behm et al. (2010):
unstable-surface training is a useful variation and for rehab, but ground-based free-weight lifts remain the base;
trunk muscles may respond to higher reps. Frequency: no trial sets a weekly number; 2–4 short exposures a week
via end-of-session blocks is [consensus].

### 6. Sleep

- **Need.** AASM consensus (Paruthi2016): "Teenagers 13 to 18 years of age should sleep 8 to 10 hours per 24
  hours on a regular basis." Walsh et al. (2021 expert consensus, BJSM): athletes often sleep < 7 h; a
  one-size-fits-all target is "unlikely ideal" — individualise to the athlete's perceived need (→ compare against
  the athlete's own baseline, rule 18).
- **Performance.** Craven et al. (2022, meta-analysis, 227 outcomes): acute sleep loss lowered next-day
  performance by 7.56 % on average; strength −2.85 %, anaerobic power −6.26 %, endurance −5.55 %, strength-endurance
  −9.85 %, skill −20.9 %. Total deprivation and **late restriction (waking earlier than normal)** were consistently
  harmful; early restriction (going to bed later) less so; afternoon/evening tasks were hit harder than morning
  ones. Authors: "prioritise morning exercise" when sleep loss is unavoidable. → short sleep cuts power, sprint
  and skill work first; heavy strength is less affected but injury risk is the bigger concern for teens.
- **Injury.** Milewski2014: adolescents sleeping < 8 h had 1.7× the odds of injury (in TRAINING-RESEARCH).
  Mah2011: sleep extension improved sprint and shooting.
- **Wearables.** Chinoy et al. (2021, 7 consumer devices vs polysomnography): "high performance in detecting
  sleep", most equal or better than research actigraphy in detecting wake, but "sleep stage assessments were
  inconsistent". Miller et al. (2022, six devices incl. Apple Watch S6, Oura, WHOOP, one lab night, 53 adults):
  sleep/wake agreement 86–89 % (Apple Watch 88 %, but the lowest kappa, 0.30 — it finds sleep well and wake
  less well), stage agreement 50–65 % (Apple Watch 53 %); all "valid for the field-based assessment of the
  timing and duration of sleep" but "require improvement for the assessment of specific sleep stages".
  Walsh2021's measurement table: actigraphy-type devices "typically overestimate total sleep time and sleep
  efficiency", and commercial wearables do "not measure sleep stages accurately, unless validation supports this".
  **Trust level:** total sleep time and bed/wake times — yes, as a trend against the athlete's own baseline
  (expect a small overestimate, since wake is under-detected); single-night stage data — no. Studies were in adults; no adolescent
  validation of Apple Watch staging was found.

### 7. Readiness and autoregulation

Saw, Main & Gastin (2016, systematic review): subjective self-reported measures (mood, perceived stress,
recovery, fatigue, sleep quality, soreness) responded to acute and chronic load changes more consistently than
objective markers (blood markers, heart rate) — "subjective measures may stand alone". Foster et al. (2001):
session RPE × minutes is a valid load measure across exercise types (used here for practice load in rule 5).
This supports the app's check-in being the primary readiness input and the watch a secondary one; readiness is
still never shown as a score (product rule).

### 8. Long-term development and strength benchmarks

Lloyd & Oliver's Youth Physical Development model and the NSCA LTAD statement (both in TRAINING-RESEARCH) put
muscular strength and movement competence at the centre throughout adolescence. Suchomel et al. (2018): "Weaker
athletes should focus on developing strength before emphasizing power-type training. Stronger athletes may
begin to emphasize power-type training while maintaining/improving their strength"; training to failure is not
needed for maximal strength; rest 2–5 min for strength/power. Suchomel et al. (2016) link greater relative strength
with better jumping, sprinting and change of direction in (mostly adult) athletes. We found **no validated
relative-strength benchmarks for 13–19-year-olds**; numbers like "2× body-weight squat" are adult associations
and are not used as targets (rule 29). McMaster et al. (2013): in elite rugby/American football, strength gains
follow diminishing returns after 12–24 months of training — consistent, long-term training matters more than any
single programme.

### 9. Session length

- Iversen et al. (2021, narrative review, time-efficient training): prioritise bilateral multi-joint exercises
  (a leg press/squat, an upper pull, an upper push); "a minimum of 4 weekly sets per muscle group using a 6–15 RM
  loading range"; "supersets, drop sets and rest-pause training roughly halves training time compared to
  traditional training, while maintaining training volume"; "restrict the warm-up to exercise-specific warm-ups";
  rest 1–2 min for untrained, ≥ 2 min for trained; strength can be maintained with 1–2 sessions a week. Its
  advice targets the general population, not athletes chasing maximum gains — fine for the 30-min tier, where
  the goal is maintenance and progress on anchors.
- **Concurrent training.** Murlasits et al. (2018): lifting before endurance in the same session gave larger
  lower-body 1RM gains (+3.96 kg, 95 % CI 0.81–7.10) with no effect on aerobic capacity. Sabag et al. (2018):
  adding HIIT to lifting did not reduce size or upper-body strength but slightly reduced lower-body strength gains
  (ES −0.25); a non-significant trend was larger for cycling than running HIIT. Wilson et al. (2012) found
  running interferes more than cycling. The two disagree on mode, so the app chooses bike/rower for its low impact
  (teens already have running and landing load from practice), not because of interference. [consensus]
- **Is 90 min sensible for teens?** No trial tests session length in youth. The guard rails in rule 22 come from
  consensus: technique degrades with fatigue (Lloyd2014 warns against programmes with insufficient recovery
  between sets "may result in the performance of potentially injurious exercise movements"), weekly sport hours ≤
  age (Jayanthi2015), and strength-first ordering (Murlasits2018). The 90-min tier is ~60 min of lifting plus
  conditioning, not 90 min of heavy lifting.

### 10. Bodyweight and breaks

- **Detraining.** Mujika & Padilla (2000, Part I): in < 4 weeks of insufficient training "strength performance
  declines are limited", while aerobic fitness drops quickly. Part II: to maintain, keep intensity, reduce
  frequency moderately and volume a lot. Bosquet et al. (2013, meta-analysis, 103 studies): training cessation
  reduces all strength qualities, with a dose–response by break length; larger losses in older and inactive
  people. McMaster et al. (2013): strength "can be maintained for up to 3 weeks of detraining, but decay rates
  will increase thereafter (i.e. 5–16 weeks)". Gavanda et al. (2020): after 12 weeks of full-body training, 3
  weeks off did not reduce muscle thickness, strength or sport performance in 15–18-year-old male athletes.
  → aerobic fitness (practice/conditioning) is the first thing to keep on a holiday, strength second.
- **Bodyweight as a stimulus.** Calatayud et al. (2015): push-ups made as hard as a 6RM (with bands) gave the same
  1RM and 6RM gains as bench press over 5 weeks. Kotarsky et al. (2018): progressive push-up variations raised
  bench 1RM similarly to bench training over 4 weeks. Principle: effort and progression matter more than the tool;
  bodyweight works if variants get harder. Lower-body bodyweight trials of similar quality were not found;
  single-leg variants and slow eccentrics are the coaching standard [consensus].

---

## Sources (opened or abstract read, 2026-11-19)

- **ACSM2009** — American College of Sports Medicine. Position stand: Progression models in resistance training for
  healthy adults. Med Sci Sports Exerc 2009;41(3):687–708. doi:10.1249/MSS.0b013e3181915670 (full text read via
  https://sfu.ca/~ryand/kin343/ACSMresistance.pdf)
- **Bartolomei2021** — Bartolomei S, Nigro F, Malagoli Lanzoni I, et al. A comparison between total body and split
  routine resistance training programs in trained men. J Strength Cond Res 2021;35(6):1520–1526.
  doi:10.1519/JSC.0000000000003573
- **BazValle2019** — Baz-Valle E, Schoenfeld BJ, Torres-Unda J, et al. The effects of exercise variation in muscle
  thickness, maximal strength and motivation in resistance trained men. PLoS One 2019;14(12):e0226989.
  doi:10.1371/journal.pone.0226989
- **Behm2010** — Behm DG, Drinkwater EJ, Willardson JM, Cowley PM. The use of instability to train the core
  musculature. Appl Physiol Nutr Metab 2010;35(1):91–108. doi:10.1139/H09-127
- **Bell2023** — Bell L, Strafford BW, Coleman M, Androulakis Korakakis P, Nolan D. Integrating deloading into
  strength and physique sports training programmes: an international Delphi consensus approach. Sports Med Open
  2023;9:87. doi:10.1186/s40798-023-00633-0
- **Bosquet2013** — Bosquet L, Berryman N, Dupuy O, et al. Effect of training cessation on muscular performance: a
  meta-analysis. Scand J Med Sci Sports 2013;23(3):e140–e149. doi:10.1111/sms.12047
- **Calatayud2015** — Calatayud J, Borreani S, Colado JC, et al. Bench press and push-up at comparable levels of
  muscle activity results in similar strength gains. J Strength Cond Res 2015;29(1):246–253.
  doi:10.1519/JSC.0000000000000589
- **Chinoy2021** — Chinoy ED, Cuellar JA, Huwa KE, et al. Performance of seven consumer sleep-tracking devices
  compared with polysomnography. Sleep 2021;44(5):zsaa291. doi:10.1093/sleep/zsaa291
- **Craven2022** — Craven J, McCartney D, Desbrow B, et al. Effects of acute sleep loss on physical performance: a
  systematic and meta-analytical review. Sports Med 2022;52(11):2669–2690. doi:10.1007/s40279-022-01706-y
  (full text: https://pmc.ncbi.nlm.nih.gov/articles/PMC9584849/)
- **Fonseca2014** — Fonseca RM, Roschel H, Tricoli V, et al. Changes in exercises are more effective than in loading
  schemes to improve muscle strength. J Strength Cond Res 2014;28(11):3085–3092. doi:10.1519/JSC.0000000000000539
- **Foster2001** — Foster C, Florhaug JA, Franklin J, et al. A new approach to monitoring exercise training. J Strength
  Cond Res 2001;15(1):109–115. PMID 11708692
- **Gavanda2020** — Gavanda S, Geisler S, Quitmann OJ, et al. Three weeks of detraining does not decrease muscle
  thickness, strength or sport performance in adolescent athletes. Int J Exerc Sci 2020;13(6):633–644.
  PMID 32509134
- **Grgic2018** — Grgic J, Schoenfeld BJ, Davies TB, et al. Effect of resistance training frequency on gains in
  muscular strength: a systematic review and meta-analysis. Sports Med 2018;48(5):1207–1220.
  doi:10.1007/s40279-018-0872-x
- **Helms2018** — Helms ER, Byrnes RK, Cooke DM, et al. RPE vs. percentage 1RM loading in periodized programs matched
  for sets and repetitions. Front Physiol 2018;9:247. doi:10.3389/fphys.2018.00247
- **Iversen2021** — Iversen VM, Norum M, Schoenfeld BJ, Fimland MS. No time to lift? Designing time-efficient training
  programs for strength and hypertrophy: a narrative review. Sports Med 2021;51(10):2079–2095.
  doi:10.1007/s40279-021-01490-1 (full text: https://pmc.ncbi.nlm.nih.gov/articles/PMC8449772/)
- **Kassiano2022** — Kassiano W, Nunes JP, Costa B, et al. Does varying resistance exercises promote superior muscle
  hypertrophy and strength gains? A systematic review. J Strength Cond Res 2022;36(6):1753–1762.
  doi:10.1519/JSC.0000000000004258
- **Kotarsky2018** — Kotarsky CJ, Christensen BK, Miller JS, Hackney KJ. Effect of progressive calisthenic push-up
  training on muscle strength and thickness. J Strength Cond Res 2018;32(3):651–659.
  doi:10.1519/JSC.0000000000002345
- **Larsen2021** — Larsen S, Kristiansen E, van den Tillaar R. Effects of subjective and objective autoregulation
  methods for intensity and volume on enhancing maximal strength during resistance-training interventions: a
  systematic review. PeerJ 2021;9:e10663. doi:10.7717/peerj.10663
- **Lloyd2014** — Lloyd RS, Faigenbaum AD, Stone MH, et al. Position statement on youth resistance training: the 2014
  International Consensus. Br J Sports Med 2014;48(7):498–505. doi:10.1136/bjsports-2013-092952 (full text read
  from the authors' ResearchGate copy)
- **McGill2010** — McGill S. Core training: evidence translating to better performance and injury prevention.
  Strength Cond J 2010;32(3):33–46. doi:10.1519/SSC.0b013e3181df4521 (full text read:
  https://www.backfitpro.com/medical-scientific-articles/2010/)
- **McMaster2013** — McMaster DT, Gill N, Cronin J, McGuigan M. The development, retention and decay rates of strength
  and power in elite rugby union, rugby league and American football: a systematic review. Sports Med
  2013;43(5):367–384. doi:10.1007/s40279-013-0031-3
- **Miller2022** — Miller DJ, Sargent C, Roach GD. A validation of six wearable devices for estimating sleep, heart rate
  and heart rate variability in healthy adults. Sensors 2022;22(16):6317. doi:10.3390/s22166317
- **Mujika2000** — Mujika I, Padilla S. Detraining: loss of training-induced physiological and performance
  adaptations. Part I: short term insufficient training stimulus. Sports Med 2000;30(2):79–87.
  doi:10.2165/00007256-200030020-00002 · Part II: long term insufficient training stimulus. Sports Med
  2000;30(3):145–154. doi:10.2165/00007256-200030030-00001
- **Murlasits2018** — Murlasits Z, Kneffel Z, Thalib L. The physiological effects of concurrent strength and endurance
  training sequence: a systematic review and meta-analysis. J Sports Sci 2018;36(11):1212–1219.
  doi:10.1080/02640414.2017.1364405
- **Paruthi2016** — Paruthi S, Brooks LJ, D'Ambrosio C, et al. Recommended amount of sleep for pediatric populations: a
  consensus statement of the American Academy of Sleep Medicine. J Clin Sleep Med 2016;12(6):785–786.
  doi:10.5664/jcsm.5866
- **Plotkin2022** — Plotkin D, Coleman M, Van Every D, et al. Progressive overload without progressing load? The
  effects of load or repetition progression on muscular adaptations. PeerJ 2022;10:e14142. doi:10.7717/peerj.14142
- **RamosCampo2024** — Ramos-Campo DJ, Benito-Peinado PJ, Andreu-Caravaca L, et al. Efficacy of split versus
  full-body resistance training on strength and muscle growth: a systematic review with meta-analysis. J Strength
  Cond Res 2024;38(7):1330–1340. doi:10.1519/JSC.0000000000004774
- **Rogerson2024** — Rogerson D, Nolan D, Androulakis Korakakis P, et al. Deloading practices in strength and physique
  sports: a cross-sectional survey. Sports Med Open 2024;10:26. doi:10.1186/s40798-024-00691-y
- **Sabag2018** — Sabag A, Najafi A, Michael S, et al. The compatibility of concurrent high intensity interval training
  and resistance training for muscular strength and hypertrophy: a systematic review and meta-analysis. J Sports Sci
  2018;36(21):2472–2483. doi:10.1080/02640414.2018.1464636
- **Saeterbakken2022** — Saeterbakken AH, Stien N, Andersen V, et al. The effects of trunk muscle training on physical
  fitness and sport-specific performance in young and adult athletes: a systematic review and meta-analysis. Sports
  Med 2022;52(7):1599–1622. doi:10.1007/s40279-021-01637-0
- **Saw2016** — Saw AE, Main LC, Gastin PB. Monitoring the athlete training response: subjective self-reported measures
  trump commonly used objective measures: a systematic review. Br J Sports Med 2016;50(5):281–291.
  doi:10.1136/bjsports-2015-094758
- **Schoenfeld2019** — Schoenfeld BJ, Grgic J, Krieger J. How many times per week should a muscle be trained to
  maximize muscle hypertrophy? A systematic review and meta-analysis of studies examining the effects of resistance
  training frequency. J Sports Sci 2019;37(11):1286–1295. doi:10.1080/02640414.2018.1555906
- **Silva2018** — Silva JR, Rumpf MC, Hertzog M, et al. Acute and residual soccer match-related fatigue: a systematic
  review and meta-analysis. Sports Med 2018;48(3):539–583. doi:10.1007/s40279-017-0798-8
- **Sousa2024** — Sousa CA, Zourdos MC, Storey AG, Helms ER. The importance of recovery in resistance training
  microcycle construction. J Hum Kinet 2024;91(Spec Issue):205–223. doi:10.5114/jhk/186659
  (https://pmc.ncbi.nlm.nih.gov/articles/PMC11057610/)
- **Suchomel2018** — Suchomel TJ, Nimphius S, Bellon CR, Stone MH. The importance of muscular strength: training
  considerations. Sports Med 2018;48(4):765–785. doi:10.1007/s40279-018-0862-z
- **Zourdos2016** — Zourdos MC, Klemp A, Dolan C, et al. Novel resistance training-specific rating of perceived
  exertion scale measuring repetitions in reserve. J Strength Cond Res 2016;30(1):267–275.
  doi:10.1519/JSC.0000000000001049
- **Walsh2021** — Walsh NP, Halson SL, Sargent C, et al. Sleep and the athlete: narrative review and 2021 expert
  consensus recommendations. Br J Sports Med 2021;55(7):356–368. doi:10.1136/bjsports-2020-102025 (full text read:
  https://researchonline.ljmu.ac.uk/id/eprint/16297/)

Already cited in `docs/TRAINING-RESEARCH.md` and reused here: Rønnestad 2011, Issurin 2010, Simão 2012, Wilson
2012, Jayanthi 2015, Milewski 2014, Mah 2011, Lloyd & Oliver 2012, Suchomel 2016, Gabbett 2016.
