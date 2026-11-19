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

---

## Part 2 — Athlete-population evidence (2026-11-19)

Owner's follow-up: "rely on good research — not studies on ordinary people but on athletes." Part 1 leans on
general-population and trained-lifter data (frequency, splits, variation, deload surveys). Part 2 re-checks the
gym algorithm against studies **in athletes**: youth athletes, adolescent team-sport players, college and elite
athletes.

**Method.** PubMed (NCBI E-utilities) searches by author/topic; every source below was matched to its PubMed
record (PMID and DOI listed at the end) and its abstract was read. Full texts were not available for most, so
numbers come from abstracts; where a protocol detail is only in the full text it is not quoted. Population and
design are given for each. Grades:

- **strong** — meta-analysis (or several RCTs) in athletes with consistent results;
- **moderate** — one good RCT or a meta-analysis with caveats (mixed populations, heterogeneity, few studies);
- **limited** — small trials, cohorts/case series, or athlete data extrapolated to teens;
- **engineering** — a number we chose inside the evidence so the code has something to compute.

**Where youth data is thin.** Injury-prevention RCTs are mostly adult male soccer (Nordic, Copenhagen) or adult
elite handball (shoulder); only the neuromuscular warm-ups (11+, 11+ Kids, ACL programmes) have strong youth
trials. In-season maintenance is adult professional data (n = 14). Concurrent-training, velocity-loss and
reps-in-reserve accuracy studies are young adults. No athlete study tests how many days before a game a heavy
session is safe. Teen athletes get the conservative end of every range.

### Rules (A1 …)

#### Maturation and growth

**A1. Train by maturity and training age, keep strength training through the growth spurt.**
Strength gains in adolescent boy athletes were larger **during (ES 1.11) and after (ES 1.01) peak height
velocity than before it (ES 0.50)** (Moran2017; meta-analysis, 19 studies, boy athletes 10–18 y, 4–16-week
programmes). Jump training works before and after PHV (RamirezCampillo2023; 11 studies, n = 744, < 18 y, 1–3
sessions/wk); post-PHV boys gained more from combined lifting + plyometrics than pre-PHV boys (Kumar2025; 40 boys
9–17 y from several sports, 2×/wk for 12 weeks). The NSCA (Lloyd2016) and IOC (Bergeron2015) statements put
movement competence and strength at the centre at every stage and ask for maturity-aware programming
(Lloyd2014b).
→ Engine: `TrainingStage` stays the main switch. No change to the age cut-offs. Post-PHV / 16+ experienced
athletes are where heavier anchors and more power pay off most (supports the *performance* stage).
*Grade: moderate (meta-analyses, short trials, boys only).*

**A2. Growth spurt = more caution on impact, not a stop.**
Talented youth soccer players had more traumatic injuries in the year of PHV (1.41 vs 0.81 per player-year) and
more days lost (15.7 vs 7.3) than the year before; overuse injuries rose after PHV (vanderSluis2014; 26 players,
3-year cohort). In an English academy, injury incidence rose linearly with growth rate and peaked at ~92–95 % of
predicted adult height; week-to-week jumps in exposure also raised incidence (Johnson2022; 49 elite youth
players, one season).
→ Engine (new, optional input): if the athlete reports fast growth ("grew a lot in the last months" or a height
entry ≥ 7 cm/year — *engineering*), treat them as circa-PHV for 3 months: landing caps ×0.75, no new
sprint/jump volume increases, anchors held at the current load (technique and control, not new loads), keep 2
strength sessions a week. *Grade: limited (cohorts, small, male soccer).*

**A3. Apophysitis (Osgood-Schlatter, Sever) — load management, not blanket rest.**
In 51 adolescents (10–14 y) with Osgood-Schlatter, an activity ladder guided by pain plus progressive knee/hip
strengthening gave 80 % "improved" at 12 weeks and 90 % at 12 months (Rathleff2020; case series, no control).
Sever's disease in a German youth academy: 0.36 cases/100 players/year, mean age 11.8, mean 61 days to return
(Belikan2022; 10-year retrospective).
→ Engine: the safety rule stays ("pain = stop and get checked", never a diagnosis). After the athlete says it
has been checked, sore knee-below-kneecap or heel in 10–15-year-olds → no jumps or sprints that day, legs only
with pain-free strength work, upper/core preferred. *Grade: limited.*

#### In season

**A4. In-season floor: one lower-body strength session every 7 days; two when the schedule allows.**
One session/week kept the pre-season gains in strength and 40-m sprint for 12 weeks; one every second week lost
both (Rønnestad2011; professional soccer, n = 14, randomised). Intensity (relative load) is the variable that
must be kept; frequency and volume can drop a lot (Spiering2021; narrative review — says data in athletes are
insufficient for precise numbers). Youth players still *improve* in season: 3×/wk integrative neuromuscular
training added to soccer improved 10/20-m sprint, jump, change of direction and strength in 11-year-olds while
controls declined in some measures (Panagoulis2020; n = 28, RCT); high-level youth soccer players respond to
strength, plyometric and combined training despite heavy practice loads (Oliver2024; 34 studies, n = 1,396).
→ Engine: in season, flag "legs due" when ≥ 7 days since the last lower anchor (≥ 8 days = priority); target
2 strength exposures/week for foundation/development athletes (they are still developing), 1–2 for performance.
*Grade: moderate (one small adult RCT + youth meta-analysis).*

**A5. In-season dose: fewer sets, same heaviness.**
Youth-athlete dose–response: the most effective strength dose was 6–8 reps at 80–89 % 1RM with 3–4 min rest
(and > 23-week programmes, 5 sets/exercise) (Lesinski2016; meta-analysis, 43 studies, athletes 6–18 y —
dose–response computed per variable, so treat as direction, not a prescription).
→ Engine: in season, anchors 2–3 sets of 6–8 (youth floor 6, as now) at 2–3 reps in reserve; never "light
and many". The existing `dose` rule (sets −1, reps −2, ≥ 6 under 18) matches. Rest for anchors ≥ 2 min
(Part 1 rule 24). The 5-sets-per-exercise finding is **not** adopted (youth cap of 3 sets stays): it comes from
mostly supervised programmes and conflicts with time and practice load. *Grade: moderate.*

**A6. Game timing: high-volume heavy legs ≥ 72 h before a game; a short heavy "primer" is allowed the day
before or the morning of.**
After 10 × 5 squats at 80 % 1RM or 15 × 30-m sprints, fatigue took up to 72 h to resolve; after jumps 48 h
(Thomas2018; 10 male athletes). Match fatigue lasts up to 72 h (Silva2018, Part 1). Yet a *small* heavy morning
session (3RM squat and bench) improved same-afternoon sprint, jump and strength in semi-professional rugby
players (Cook2014; n = 18, randomised crossover).
→ Engine (refines Part 1 rule 6): MD-3 or earlier for the main heavy lower session; MD-2 = upper body, or lower
at reduced volume (≤ 2 sets per anchor, ≥ 3 reps in reserve); MD-1 / match morning = optional primer for
development/performance stage only: ≤ 3 sets × ≤ 3 reps of a lift or loaded jump at ≥ 3 reps in reserve, plus
2–3 short sprints, total ≤ 20 min. Upper-body heavy work is fine until MD-2. Two games ≤ 3 days apart → legs get
primers only. *Grade: limited (small studies, no youth data; the windows are engineering inside them).*

#### Periodisation

**A7. Keep the simple block model; no daily undulation.**
Linear and undulating periodisation produced the same strength gains (Harries2015; meta-analysis, 17 studies,
n = 510 — authors note few adolescent or athlete studies). In NCAA Division I track and field athletes, block vs
daily undulating: no significant difference, but block reached the gains with less volume (more efficient) and
looked better for fatigue (Painter2012, n = 31; Painter2018, n = 19).
→ Engine: keep 4-week anchor blocks with a fixed rep range per block (Part 1 rules 8, 11). Don't add DUP.
*Grade: moderate (no difference) / limited (block efficiency).*

**A8. Season phase sets the emphasis.**
Off-season = develop (most volume: anchors 3–4 sets, 2–3, max 4 sessions); pre-season = convert (strength kept,
power and sprint volume up, gym 2–3); in season = maintain/develop at low volume (A4–A5); post-season = 1–3
weeks of reduced, varied training (Part 1 rule 25: short breaks cost little). Long programmes beat short ones in
youth athletes (Lesinski2016: > 23 weeks most effective), so consistency across phases matters more than any
phase's details. *Grade: consensus (sequencing) / moderate (duration).*

**A9. Taper before a key competition.**
Across competitive athletes, the best taper lasted ~2 weeks, cut volume by 41–60 % and kept intensity and
frequency (Bosquet2007; meta-analysis, 27 studies, mostly endurance athletes). In team sports, tapers improved
maximal power (SMD 0.44), change of direction (0.38), repeated-sprint ability (0.41) and VO2max (0.76)
(Vachon2021; meta-analysis, 14 studies).
→ Engine: when the athlete marks a competition as **key** (tournament, championship, trials) in the
Competitions hub: days −10 to −1 halve gym sets (≥ 1–2 per anchor), keep the load and reps in reserve, keep the
number of sessions, last heavy lower ≥ 72 h out (A6). Not for weekly league games. *Grade: moderate.*

#### Power

**A10. Plyometric dose for youth athletes.**
Youth soccer review: 2 sessions/week, ~72 h apart, starting at 50–60 foot contacts/session and progressing to no
more than 80–120 (Bedoya2015; systematic review, 7 studies, ≤ 17 y — the dose is the authors' synthesis, not a
tested optimum). Jump training is effective pre- and post-PHV with 1–3 sessions/week (RamirezCampillo2023).
→ Engine: current per-session caps (40/60/80 by stage, ¾ in season) stay — they sit at or below the review's
start dose, which is right for athletes who also land in practice. Add: ≥ 48 h between sessions with a full
jump block (jump fatigue resolved by 48 h, Thomas2018); first 2 weeks of a block (or after a break) at ~60 % of
the cap. *Grade: limited–moderate.*

**A11. Strength + plyometrics together; don't trade strength away for jumps.**
In high-level youth soccer players, strength, plyometric and combined training all improved jumps, horizontal
power, acceleration and change of direction (g 0.73–1.08) and speed (g 0.40–0.59); only for strength did mode
matter — strength training g 1.07, combined 0.75, plyometrics 0.27 (Oliver2024).
→ Engine: anchors are never dropped to fit a power block; on 30-min sessions, power is the first thing cut
(already the case). *Grade: strong (large youth-athlete meta-analysis).*

**A12. Weightlifting derivatives — performance stage only, and optional.**
Weightlifting training beat traditional resistance training for jump height (g 0.95) and matched plyometrics for
sprint, change of direction, jump and strength (Morris2022; meta-analysis, 16 studies, n = 427, mostly athletes
incl. adolescents; high heterogeneity).
→ Engine: keep Olympic pulls/derivatives in the *performance* fast block (current rule); plyometrics are an equal
alternative, so no athlete is pushed into technical lifts. Prefer pulls/jump shrugs over full catches for teens
without coaching. *Grade: moderate.*

**A13. Contrast/complex pairs only for strong, experienced athletes.**
A heavy or plyometric "conditioning activity" before a jump or sprint gives a small boost (jump ES 0.29, sprint
0.51); larger in **stronger and more experienced** lifters; weaker athletes need longer rest and sub-maximal loads
to benefit; plyometric primers work sooner than heavy ones (Seitz2016; meta-analysis, 47 studies, n = 1,954).
→ Engine: no contrast pairs for foundation/development. Performance stage may pair an anchor set (≥ 2 reps in
reserve) with 3–5 jumps after ≥ 4 min (*engineering*). Order stays: fast work → anchors (Part 1 rule 10).
*Grade: moderate.*

**A14. Relative strength guides emphasis internally, never as a target.**
Stronger (1RM squat 1.97× body mass) and weaker (1.32×) men both improved jump and sprint after 10 weeks of
ballistic training; the stronger group tended to gain more (Cormie2010; n = 24, trained men, not athletes).
Suchomel2016/2018: weaker athletes build strength first. No validated thresholds for teens.
→ Engine: Part 1 rule 29 stands (no body-weight targets shown). Emphasis shifts with stage and the athlete's own
anchor trend (stalled strength → strength emphasis; rising → more power). *Grade: limited.*

#### Speed

**A15. Regular max-velocity exposure protects; sudden spikes don't.**
In elite soccer, players with moderate weekly sprint distance (201–350 m > 19.8 km/h) had lower injury odds
(OR 0.54) than those with little (≤ 165 m); large week-to-week changes in sprint distance raised odds a lot
(OR 6.12) (Malone2018; 37 players, one season, observational). In Australian football, hamstring strains
followed weeks with high-speed running well above the player's own average (week −1 OR 6.44) (Duhig2016; one
team, 2 seasons). Six weeks of sprint training lengthened biceps femoris fascicles more than Nordics and
improved sprint mechanics in soccer players (Mendiguchia2020; n = 32, matched groups).
→ Engine: field/court sports in off- and pre-season get ≥ 1 max-velocity exposure/week (e.g. 3–5 × 20–30 m
flying or build-up runs, full rest) when practice doesn't give it; after ≥ 10 days without sprinting (holiday,
injury), rebuild over 2 weeks rather than full volume at once. In season, practice and games usually cover it.
*Grade: limited (observational) — the app can't measure speed, so this relies on the athlete's answers.*

**A16. Sleds are optional.**
Resisted sled training improved acceleration (ES 0.61) and full sprint (0.36) but not max velocity, and was not
shown better than unresisted sprinting (Alcaraz2018; 13 studies, athletes and active people).
→ Engine: plain sprints default; sled only as variety for acceleration goals. *Grade: moderate.*

**A17. High days and low days.**
Heavy squats, sprints and jumps each leave fatigue for 48–72 h (Thomas2018). → Stack the neural work: on a
day with sprints, put heavy lower anchors after them in the same session (or the same day) rather than on the
next day; easy days stay easy. *Grade: limited / engineering.*

#### Injury prevention (dose and sports)

**A18. Nordic hamstring.**
Men's soccer (pro + amateur, 942 players): 10-week progressive programme then a weekly in-season session; acute
hamstring injuries RR 0.29, new injuries RR 0.41, recurrent RR 0.14; 13 players treated per injury prevented
(Petersen2011; cluster RCT). Amateur soccer (579 men, 24.5 y): 25 sessions in 13 weeks, OR 0.28, compliance 91 %
(vanderHorst2015; RCT). All programmes including Nordics: hamstring injuries halved (RR 0.49) (vanDyk2019;
meta-analysis, 8,459 athletes). **Low-volume programmes gave the same eccentric-strength and fascicle gains as
high-volume ones** (Cuthbert2020; meta-analysis, 13 studies).
→ Engine: sprinting sports (soccer, American football, rugby, field hockey, lacrosse, track sprints/jumps,
basketball, handball, Australian football): off-/pre-season 2×/week, in season 1×/week (≥ 1 every 7 days);
2–3 sets × 3–6 slow reps (the low-volume end). Matches the current `hamstring-eccentric` dose. Make it a
weekly **requirement** for these sports rather than a rotation slot. *Grade: strong for adult male soccer;
limited for teens (no Nordic-only youth RCT — youth evidence comes through A20 programmes that include it).*

**A19. Copenhagen adductor.**
Semi-professional men's soccer (652 players): one exercise with three progression levels, **3×/week in pre-season
(6–8 weeks), 1×/week in season (28 weeks)**; groin problems 13.5 % vs 21.3 % (OR 0.59) (Haroy2019; cluster RCT).
→ Engine: soccer and other kicking/skating/cutting sports (ice hockey, Australian football, futsal — extrapolated):
pre-season 3×/week can be met by gym + after-practice sessions, in season ≥ 1×/week. Start at the short-lever
(knee) level. *Grade: moderate (one RCT, adult men; other sports extrapolated).*

**A20. Neuromuscular warm-up and ACL programmes (strongest youth evidence).**
FIFA 11+ cut football injuries by 39 % (IRR 0.61) (Thorborg2017; meta-analysis, 4 cluster RCTs); it prevented
injuries in young female footballers (Soligard2008; cluster RCT). 11+ Kids (3,895 players, mean 10.8 y): injuries
−48 % (HR 0.52), severe −74 %; **at least 1×/week, 2× better** (Rossler2018). Youth athletes: neuromuscular
training cut lower-extremity injuries by 42 % (IRR 0.58); **2–3×/week, 10–15-min bouts, 30–60 min/week** worked
best (Steib2017; meta-analysis, 16 trials, ≤ 21 y); lower-extremity IRR 0.64 (Emery2015; youth sport). ACL in
young female athletes: OR 0.51, **middle/high school OR 0.38** vs college/pro 0.65; average 24 min × 2.5/week;
best with lower-body strength (Nordics, lunges, calf raises) and landing stabilisation (jump-and-hold) **every
session** (Petushek2019; 18 studies, 27,231 athletes). Meta-analysis of meta-analyses: all ACL injuries −50 %,
non-contact ACL in females −67 % (Webster2018). Younger age, higher dose, more exercise variety and feedback
predicted bigger ACL reductions (Sugimoto2016).
→ Engine: every lower or full-body session's prep includes a landing-stabilisation drill (jump-and-hold) for
knee-risk sports (soccer, basketball, handball, volleyball, netball, lacrosse, field hockey) and for all
foundation/development athletes — extend today's "foundation or knee-risk sport below performance" rule to
**female athletes at every stage**. Weekly target: ≥ 2 neuromuscular exposures (gym prep + after-practice
counts). *Grade: strong.*

**A21. Shoulder programme for overhead athletes.**
Elite handball (660 players, men and women): OSTRC shoulder programme (internal-rotation mobility,
external-rotation strength, scapular strength, kinetic chain, thoracic mobility) **3×/week in the warm-up**:
shoulder problems OR 0.72 (17 % vs 23 % prevalence) (Andersson2017; cluster RCT).
→ Engine: overhead/throwing sports (handball, volleyball, baseball, softball, water polo, tennis, cricket
bowlers, javelin, swimming — extrapolated) get the `shoulder-health` slot as a **fixed** item in every upper and
full session (not a rotating accessory), aiming at ≥ 3 short exposures/week including after-practice sessions.
*Grade: moderate (one large RCT, handball).*

#### Autoregulation

**A22. Reps in reserve works best on sets of ≤ 12.**
People underpredict reps to failure by ~1 rep on average, with large spread; accuracy is better closer to
failure and on sets of ≤ 12 reps, much worse above 12; training status didn't change accuracy (Halperin2022;
12 studies, 414 participants, mostly adults — no adolescent data).
→ Engine (refines Part 1 rule 12): RIR-driven load changes only on sets with a top of range ≤ 12; above that
(bodyweight work), progress by variant (Part 1 rule 26). Foundation keeps the easy/right/hard tap. *Grade:
moderate (adults), limited for teens.*

**A23. Stop sets well short of failure.**
Squatting with 20 % vs 40 % velocity loss per set gave the same strength gains and more jump improvement (CMJ
+9.5 % vs +3.5 %) with 40 % fewer reps (ParejaBlanco2017a; 22 young men, not athletes). In professional soccer
players, 15 % loss beat 30 % for jump height (ParejaBlanco2017b; n = 16).
→ Supports the current RIR cues (2–3 left; "stop if the bar slows") — especially for in-season and power-goal
athletes. No velocity device is assumed. *Grade: moderate.*

**A24. Progress from the last set's reps (APRE logic).**
Division I football players progressing with autoregulatory progressive resistance exercise (load set from the
reps achieved on the last set) gained more bench and squat strength in 6 pre-season weeks than with fixed linear
progression (Mann2010; n = 23).
→ Engine: Part 1 rules 11–12 already do this; add that the next session's anchor load is chosen from the **last
set's** reps at the target RIR (+1 step if ≥ 2 reps over, −1 step if under). *Grade: limited–moderate.*

**A25. Deloads follow the sport calendar.**
No athlete trial tests deloads. Coaches of strength sports deload for 5–7 days every 4–6 weeks, mostly by cutting
sets/reps and effort (Bell2022; 18 national-level coaches, interviews; plus Bell2023, Rogerson2024 in Part 1).
→ Engine (refines Part 1 rule 13.3): for team-sport athletes, put the planned easy week where the calendar
already gives one — exam week, tournament week (A9), post-season, holidays — instead of a fixed every-5-weeks
deload. *Grade: consensus.*

#### Concurrent training

**A26. In trained athletes, conditioning straight after legs costs explosive and lower-body strength gains.**
Concurrent training didn't reduce maximal strength or size overall, but reduced **explosive strength (SMD −0.28),
more when done in the same session** than ≥ 3 h apart; cycling vs running made no difference (Schumann2022;
43 studies). In **trained** people, lower-body 1RM gains were reduced (ES −0.35), only when both were in the
same session (−0.66 vs −0.10 separate) (Petre2021; 27 studies). Amateur rugby players: 0 h between strength
and aerobic work blunted strength gains; 6 h less so; 24 h best (Robineau2016; n = 58, RCT).
→ Engine (contradicts Part 1 rule 22 for experienced athletes): on **lower/full** sessions of *performance*-stage
(and experienced development) athletes in off-/pre-season, no hard interval finisher — either an easy 10–15-min
aerobic cool-down or move the intervals to an upper day or a session ≥ 6 h apart. Hard practice counts as the
aerobic session: gym legs before it or ≥ 6 h apart. Foundation athletes are unaffected (no interference in
untrained/moderately trained). Bike vs run stays an impact choice. *Grade: moderate.*

#### Sleep, readiness and load

**A27. Chronic short sleep matters more than one bad night for injury.**
Adolescent athletes who chronically slept poorly had higher injury odds (OR 1.58); the effect of one bad night
was undetermined (Gao2019; meta-analysis, 7 studies, ≤ 19 y). Adolescent elite athletes sleeping > 8 h on
weekdays had 61 % lower odds of a new injury (OR 0.39) (vonRosen2017; n = 340). Milewski2014 (Part 1): < 8 h,
1.7×.
→ Engine (refines Part 1 rule 18): add a **7-night average < 8 h** check: no load increases and no new sprint/jump
volume increases that week, and a calm note ("a week of short sleep — today holds your loads"). The single-night
thresholds (< 7 / < 6 / < 5 h) stay for the day's choice. *Grade: moderate (observational).*

**A28. Don't use the acute:chronic workload ratio.**
The ACWR is a rescaling of acute load that creates statistical artefacts; random "chronic" loads produced the same
associations, and neither ACWR nor acute load predicted injury better than chance in the original data
(c-statistic 0.574 vs 0.5) (Impellizzeri2021; Impellizzeri2020 on conceptual pitfalls).
→ Engine: never compute or show an ACWR or "injury risk". Use plain guard rails on *changes* — weekly landing
and sprint volume, gym sets — labelled as engineering (e.g. ≤ ~20 % more than the athlete's own last 3 weeks)
and phrased as "a big jump compared with your usual", never as a risk number. Week-to-week change was associated
with injury in youth academy and elite players (Johnson2022, Malone2018), but no threshold is validated.
*Grade: strong against ACWR as a predictor; weak for any threshold.*

### What the app does with Part 2 (2026-11-19)
- **Done:** A4 (in-season legs come back after 8 days), A6 (two days out: legs allowed, 2 sets per lift), A18, A19 and A21
  (the sport's Nordic/Copenhagen on every leg or full session, shoulder work on upper or full; the first one even
  in 30 min), A24 (APRE step-up after two reps past the target on sets of 12 or fewer), A26 (performance-stage and
  experienced development athletes ride easy after heavy legs), A27 (watch-measured short sleep holds the weight).
- **Deviation, on purpose:** A27's evidence uses under 8 h. Most teens sleep under 8 h on school nights, so holding
  every progression at 8 h would freeze the plan for most users. The app uses a 3-night average under 7 h or a
  last night under 6 h, and says why in the set's note.
- **Not yet:** A2–A3 (growth-spurt input), A9 (taper: needs a "key competition" flag), A10 (48 h between jump
  blocks), A15–A17 (weekly max-velocity exposure), A12–A13 (contrast pairs, Olympic derivatives).

### Part 1 rules — what the athlete evidence changes

| Part 1 rule | Status | Why |
|---|---|---|
| 1 (gym days; in season ≥ 1) | **refined** | A4: ≥ 1 lower strength exposure every 7 days; 2 for foundation/development in season |
| 5–6 (practice/games, MD rules) | **refined** | A6: MD-2 reduced-volume lower allowed; MD-1/match-morning primer for development/performance |
| 8, 11 (blocks, double progression) | **confirmed** | A7: block ≈ undulating; block more efficient in D-I athletes |
| 12 (RIR autoregulation) | **refined** | A22: RIR only for sets ≤ 12 reps; A24: base next load on the last set |
| 13.3 (deload every 4–6 weeks) | **refined** | A25: place easy weeks on the sport calendar |
| 15 / injury staples | **refined** | A18–A21: Nordic and Copenhagen as weekly requirements for listed sports; shoulder fixed for overhead sports; landing drill for all female athletes |
| 18 (sleep thresholds) | **refined** | A27: add 7-night average < 8 h |
| 22 (finisher after lifting, bike on leg days) | **contradicted for trained athletes** | A26: same-session conditioning blunts explosive and lower-body strength gains in trained people; separate by ≥ 6 h or put it on upper days |
| 28–29 (strength before power; no targets) | **confirmed** | A11, A14 |
| TRAINING-RESEARCH §6 in season (reps −2, ≥ 6 under 18) | **confirmed** | A5 (Lesinski 6–8 reps at 80–89 %) |
| TRAINING-RESEARCH §8 Gabbett 2016 load spikes | **qualified** | A28: keep "avoid sudden jumps" as advice; no ACWR |

### Sources (Part 2; PubMed record and abstract read, 2026-11-19)

- **Alcaraz2018** — Alcaraz PE, Carlos-Vivas J, Oponjuru BO, Martínez-Rodríguez A. The effectiveness of resisted sled
  training (RST) for sprint performance: a systematic review and meta-analysis. Sports Med 2018;48:2143–2165.
  doi:10.1007/s40279-018-0947-8 · PMID 29926369
- **Andersson2017** — Andersson SH, Bahr R, Clarsen B, Myklebust G. Preventing overuse shoulder injuries among throwing
  athletes: a cluster-randomised controlled trial in 660 elite handball players. Br J Sports Med 2017;51:1073–1080.
  doi:10.1136/bjsports-2016-096226 · PMID 27313171
- **Bedoya2015** — Bedoya AA, Miltenberger MR, Lopez RM. Plyometric training effects on athletic performance in youth
  soccer athletes: a systematic review. J Strength Cond Res 2015;29(8):2351–2360. doi:10.1519/JSC.0000000000000877 ·
  PMID 25756326
- **Belikan2022** — Belikan P, Färber LC, Abel F, Nowak TE, et al. Incidence of calcaneal apophysitis (Sever's disease)
  and return-to-play in adolescent athletes of a German youth soccer academy: a retrospective study of 10 years.
  J Orthop Surg Res 2022;17:83. doi:10.1186/s13018-022-02979-9 · PMID 35139872
- **Bell2022** — Bell L, Nolan D, Immonen V, Helms E, et al. "You can't shoot another bullet until you've reloaded the
  gun": coaches' perceptions, practices and experiences of deloading in strength and physique sports. Front Sports
  Act Living 2022;4:1073223. doi:10.3389/fspor.2022.1073223 · PMID 36619355
- **Bergeron2015** — Bergeron MF, Mountjoy M, Armstrong N, et al. International Olympic Committee consensus statement
  on youth athletic development. Br J Sports Med 2015;49:843–851. doi:10.1136/bjsports-2015-094962 · PMID 26084524
- **Bosquet2007** — Bosquet L, Montpetit J, Arvisais D, Mujika I. Effects of tapering on performance: a meta-analysis.
  Med Sci Sports Exerc 2007;39(8):1358–1365. doi:10.1249/mss.0b013e31806010e0 · PMID 17762369
- **Cook2014** — Cook CJ, Kilduff LP, Crewther BT, Beaven M, West DJ. Morning based strength training improves afternoon
  physical performance in rugby union players. J Sci Med Sport 2014;17(3):317–321. doi:10.1016/j.jsams.2013.04.016 ·
  PMID 23707139
- **Cormie2010** — Cormie P, McGuigan MR, Newton RU. Influence of strength on magnitude and mechanisms of adaptation to
  power training. Med Sci Sports Exerc 2010;42(8):1566–1581. doi:10.1249/MSS.0b013e3181cf818d · PMID 20639724
- **Cuthbert2020** — Cuthbert M, Ripley N, McMahon JJ, Evans M, Haff GG, Comfort P. The effect of Nordic hamstring
  exercise intervention volume on eccentric strength and muscle architecture adaptations: a systematic review and
  meta-analyses. Sports Med 2020;50:83–99. doi:10.1007/s40279-019-01178-7 · PMID 31502142
- **Duhig2016** — Duhig S, Shield AJ, Opar D, Gabbett TJ, et al. Effect of high-speed running on hamstring strain injury
  risk. Br J Sports Med 2016;50:1536–1540. doi:10.1136/bjsports-2015-095679 · PMID 27288515
- **Emery2015** — Emery CA, Roy TO, Whittaker JL, Nettel-Aguirre A, van Mechelen W. Neuromuscular training injury
  prevention strategies in youth sport: a systematic review and meta-analysis. Br J Sports Med 2015;49:865–870.
  doi:10.1136/bjsports-2015-094639 · PMID 26084526
- **Gao2019** — Gao B, Dwivedi S, Milewski MD, Cruz AI Jr. Lack of sleep and sports injuries in adolescents: a systematic
  review and meta-analysis. J Pediatr Orthop 2019;39(5):e324–e333. doi:10.1097/BPO.0000000000001306 · PMID 30888337
- **Haroy2019** — Harøy J, Clarsen B, Wiger EG, et al. The Adductor Strengthening Programme prevents groin problems among
  male football players: a cluster-randomised controlled trial. Br J Sports Med 2019;53:150–157.
  doi:10.1136/bjsports-2017-098937 · PMID 29891614
- **Halperin2022** — Halperin I, Malleron T, Har-Nir I, Androulakis-Korakakis P, et al. Accuracy in predicting
  repetitions to task failure in resistance exercise: a scoping review and exploratory meta-analysis. Sports Med
  2022;52:377–390. doi:10.1007/s40279-021-01559-x · PMID 34542869
- **Harries2015** — Harries SK, Lubans DR, Callister R. Systematic review and meta-analysis of linear and undulating
  periodized resistance training programs on muscular strength. J Strength Cond Res 2015;29(4):1113–1125.
  doi:10.1519/JSC.0000000000000712 · PMID 25268290
- **Impellizzeri2020** — Impellizzeri FM, Tenan MS, Kempton T, Novak A, Coutts AJ. Acute:chronic workload ratio:
  conceptual issues and fundamental pitfalls. Int J Sports Physiol Perform 2020;15(6):907–913.
  doi:10.1123/ijspp.2019-0864 · PMID 32502973
- **Impellizzeri2021** — Impellizzeri FM, Woodcock S, Coutts AJ, Fanchini M, et al. What role do chronic workloads play in
  the acute to chronic workload ratio? Time to dismiss ACWR and its underlying theory. Sports Med 2021;51:581–592.
  doi:10.1007/s40279-020-01378-6 · PMID 33332011
- **Johnson2022** — Johnson DM, Cumming SP, Bradley B, Williams S. The influence of exposure, growth and maturation on
  injury risk in male academy football players. J Sports Sci 2022;40(10):1127–1136. doi:10.1080/02640414.2022.2051380 ·
  PMID 35285754
- **Kumar2025** — Kumar NTA, Oliver JL, Pedley JS, Dobbs IJ, et al. Maturity-related adaptations to combined traditional
  resistance and plyometric training in pre- and post-peak height velocity boys. J Strength Cond Res
  2025;39(10):1034–1045. doi:10.1519/JSC.0000000000005177 · PMID 40644677
- **Lesinski2016** — Lesinski M, Prieske O, Granacher U. Effects and dose-response relationships of resistance training on
  physical performance in youth athletes: a systematic review and meta-analysis. Br J Sports Med 2016;50:781–795.
  doi:10.1136/bjsports-2015-095497 · PMID 26851290
- **Lloyd2014b** — Lloyd RS, Oliver JL, Faigenbaum AD, Myer GD, De Ste Croix MB. Chronological age vs. biological
  maturation: implications for exercise programming in youth. J Strength Cond Res 2014;28(5):1454–1464.
  doi:10.1519/JSC.0000000000000391 · PMID 24476778
- **Lloyd2016** — Lloyd RS, Cronin JB, Faigenbaum AD, et al. National Strength and Conditioning Association position
  statement on long-term athletic development. J Strength Cond Res 2016;30(6):1491–1509.
  doi:10.1519/JSC.0000000000001387 · PMID 26933920
- **Malone2018** — Malone S, Owen A, Mendes B, Hughes B, Collins K, Gabbett TJ. High-speed running and sprinting as an
  injury risk factor in soccer: can well-developed physical qualities reduce the risk? J Sci Med Sport
  2018;21(3):257–262 (online 2017). doi:10.1016/j.jsams.2017.05.016 · PMID 28595870
- **Mann2010** — Mann JB, Thyfault JP, Ivey PA, Sayers SP. The effect of autoregulatory progressive resistance exercise
  vs. linear periodization on strength improvement in college athletes. J Strength Cond Res 2010;24(7):1718–1723.
  doi:10.1519/JSC.0b013e3181def4a6 · PMID 20543732
- **Mendiguchia2020** — Mendiguchia J, Conceição F, Edouard P, Fonseca M, et al. Sprint versus isolated eccentric
  training: comparative effects on hamstring architecture and performance in soccer players. PLoS One
  2020;15(2):e0228283. doi:10.1371/journal.pone.0228283 · PMID 32045411
- **Moran2017** — Moran J, Sandercock GR, Ramírez-Campillo R, Meylan C, Collison J, Parry DA. A meta-analysis of
  maturation-related variation in adolescent boy athletes' adaptations to short-term resistance training. J Sports
  Sci 2017;35(11):1041–1051. doi:10.1080/02640414.2016.1209306 · PMID 27454545
- **Morris2022** — Morris SJ, Oliver JL, Pedley JS, Haff GG, Lloyd RS. Comparison of weightlifting, traditional resistance
  training and plyometrics on strength, power and speed: a systematic review with meta-analysis. Sports Med
  2022;52:1533–1554. doi:10.1007/s40279-021-01627-2 · PMID 35025093
- **Oliver2024** — Oliver JL, Ramachandran AK, Singh U, Ramirez-Campillo R, Lloyd RS. The effects of strength,
  plyometric and combined training on strength, power and speed characteristics in high-level, highly trained male
  youth soccer players: a systematic review and meta-analysis. Sports Med 2024;54:623–643.
  doi:10.1007/s40279-023-01944-8 · PMID 37897637
- **Painter2012** — Painter KB, Haff GG, Ramsey MW, et al. Strength gains: block versus daily undulating periodization
  weight training among track and field athletes. Int J Sports Physiol Perform 2012;7(2):161–169.
  doi:10.1123/ijspp.7.2.161 · PMID 22173008
- **Painter2018** — Painter KB, Haff GG, Triplett NT, et al. Resting hormone alterations and injuries: block vs. DUP
  weight-training among D-1 track and field athletes. Sports (Basel) 2018;6(1):3. doi:10.3390/sports6010003 ·
  PMID 29910307
- **Panagoulis2020** — Panagoulis C, Chatzinikolaou A, Avloniti A, et al. In-season integrative neuromuscular strength
  training improves performance of early-adolescent soccer athletes. J Strength Cond Res 2020;34(2):516–526.
  doi:10.1519/JSC.0000000000002938 · PMID 30431535
- **ParejaBlanco2017a** — Pareja-Blanco F, Rodríguez-Rosell D, Sánchez-Medina L, et al. Effects of velocity loss during
  resistance training on athletic performance, strength gains and muscle adaptations. Scand J Med Sci Sports
  2017;27(7):724–735. doi:10.1111/sms.12678 · PMID 27038416
- **ParejaBlanco2017b** — Pareja-Blanco F, Sánchez-Medina L, Suárez-Arrones L, González-Badillo JJ. Effects of velocity
  loss during resistance training on performance in professional soccer players. Int J Sports Physiol Perform
  2017;12(4):512–519. doi:10.1123/ijspp.2016-0170 · PMID 27618386
- **Petersen2011** — Petersen J, Thorborg K, Nielsen MB, Budtz-Jørgensen E, Hölmich P. Preventive effect of eccentric
  training on acute hamstring injuries in men's soccer: a cluster-randomized controlled trial. Am J Sports Med
  2011;39(11):2296–2303. doi:10.1177/0363546511419277 · PMID 21825112
- **Petre2021** — Petré H, Hemmingsson E, Rosdahl H, Psilander N. Development of maximal dynamic strength during
  concurrent resistance and endurance training in untrained, moderately trained, and trained individuals: a
  systematic review and meta-analysis. Sports Med 2021;51:991–1010. doi:10.1007/s40279-021-01426-9 · PMID 33751469
- **Petushek2019** — Petushek EJ, Sugimoto D, Stoolmiller M, Smith G, Myer GD. Evidence-based best-practice guidelines for
  preventing anterior cruciate ligament injuries in young female athletes: a systematic review and meta-analysis.
  Am J Sports Med 2019;47(7):1744–1753. doi:10.1177/0363546518782460 · PMID 30001501
- **RamirezCampillo2023** — Ramirez-Campillo R, Sortwell A, Moran J, Afonso J, et al. Plyometric-jump training effects on
  physical fitness and sport-specific performance according to maturity: a systematic review with meta-analysis.
  Sports Med Open 2023;9:23. doi:10.1186/s40798-023-00568-6 · PMID 37036542
- **Rathleff2020** — Rathleff MS, Winiarski L, Krommes K, Graven-Nielsen T, et al. Activity modification and knee
  strengthening for Osgood-Schlatter disease: a prospective cohort study. Orthop J Sports Med 2020;8(4):2325967120911106.
  doi:10.1177/2325967120911106 · PMID 32284945
- **Robineau2016** — Robineau J, Babault N, Piscione J, Lacome M, Bigard AX. Specific training effects of concurrent
  aerobic and strength exercises depend on recovery duration. J Strength Cond Res 2016;30(3):672–683.
  doi:10.1519/JSC.0000000000000798 · PMID 25546450
- **Rossler2018** — Rössler R, Junge A, Bizzini M, Verhagen E, et al. A multinational cluster randomised controlled trial
  to assess the efficacy of '11+ Kids': a warm-up programme to prevent injuries in children's football. Sports Med
  2018;48:1493–1504. doi:10.1007/s40279-017-0834-8 · PMID 29273936
- **Ronnestad2011** — Rønnestad BR, Nymark BS, Raastad T. Effects of in-season strength maintenance training frequency in
  professional soccer players. J Strength Cond Res 2011;25(10):2653–2660. doi:10.1519/JSC.0b013e31822dcd96 ·
  PMID 21873897
- **Schumann2022** — Schumann M, Feuerbacher JF, Sünkeler M, et al. Compatibility of concurrent aerobic and strength
  training for skeletal muscle size and function: an updated systematic review and meta-analysis. Sports Med
  2022;52:601–612. doi:10.1007/s40279-021-01587-7 · PMID 34757594
- **Seitz2016** — Seitz LB, Haff GG. Factors modulating post-activation potentiation of jump, sprint, throw, and
  upper-body ballistic performances: a systematic review with meta-analysis. Sports Med 2016;46:231–240.
  doi:10.1007/s40279-015-0415-7 · PMID 26508319
- **Soligard2008** — Soligard T, Myklebust G, Steffen K, et al. Comprehensive warm-up programme to prevent injuries in
  young female footballers: cluster randomised controlled trial. BMJ 2008;337:a2469. doi:10.1136/bmj.a2469 ·
  PMID 19066253
- **Spiering2021** — Spiering BA, Mujika I, Sharp MA, Foulis SA. Maintaining physical performance: the minimal dose of
  exercise needed to preserve endurance and strength over time. J Strength Cond Res 2021;35(5):1449–1458.
  doi:10.1519/JSC.0000000000003964 · PMID 33629972
- **Steib2017** — Steib S, Rahlf AL, Pfeifer K, Zech A. Dose-response relationship of neuromuscular training for injury
  prevention in youth athletes: a meta-analysis. Front Physiol 2017;8:920. doi:10.3389/fphys.2017.00920 ·
  PMID 29184511
- **Suchomel2016** — Suchomel TJ, Nimphius S, Stone MH. The importance of muscular strength in athletic performance.
  Sports Med 2016;46:1419–1449. doi:10.1007/s40279-016-0486-0 · PMID 26838985
- **Sugimoto2016** — Sugimoto D, Myer GD, Barber Foss KD, et al. Critical components of neuromuscular training to reduce
  ACL injury risk in female athletes: meta-regression analysis. Br J Sports Med 2016;50:1259–1266.
  doi:10.1136/bjsports-2015-095596 · PMID 27251898
- **Thomas2018** — Thomas K, Brownstein CG, Dent J, et al. Neuromuscular fatigue and recovery after heavy resistance,
  jump, and sprint training. Med Sci Sports Exerc 2018;50(12):2526–2535. doi:10.1249/MSS.0000000000001733 ·
  PMID 30067591
- **Thorborg2017** — Thorborg K, Krommes KK, Esteve E, et al. Effect of specific exercise-based football injury prevention
  programmes on the overall injury rate in football: a systematic review and meta-analysis of the FIFA 11 and 11+
  programmes. Br J Sports Med 2017;51:562–571. doi:10.1136/bjsports-2016-097066 · PMID 28087568
- **Vachon2021** — Vachon A, Berryman N, Mujika I, et al. Effects of tapering on neuromuscular and metabolic fitness in
  team sports: a systematic review and meta-analysis. Eur J Sport Sci 2021;21(3):300–311.
  doi:10.1080/17461391.2020.1736183 · PMID 32172680
- **vanderHorst2015** — van der Horst N, Smits DW, Petersen J, Goedhart EA, Backx FJG. The preventive effect of the Nordic
  hamstring exercise on hamstring injuries in amateur soccer players: a randomized controlled trial. Am J Sports Med
  2015;43(6):1316–1323. doi:10.1177/0363546515574057 · PMID 25794868
- **vanderSluis2014** — van der Sluis A, Elferink-Gemser MT, Coelho-e-Silva MJ, et al. Sport injuries aligned to peak
  height velocity in talented pubertal soccer players. Int J Sports Med 2014;35(4):351–355.
  doi:10.1055/s-0033-1349874 · PMID 24022568
- **vanDyk2019** — van Dyk N, Behan FP, Whiteley R. Including the Nordic hamstring exercise in injury prevention
  programmes halves the rate of hamstring injuries: a systematic review and meta-analysis of 8459 athletes. Br J
  Sports Med 2019;53:1362–1370. doi:10.1136/bjsports-2018-100045 · PMID 30808663
- **vonRosen2017** — von Rosen P, Frohm A, Kottorp A, Fridén C, Heijne A. Too little sleep and an unhealthy diet could
  increase the risk of sustaining a new injury in adolescent elite athletes. Scand J Med Sci Sports
  2017;27(11):1364–1371. doi:10.1111/sms.12735 · PMID 27539373
- **Webster2018** — Webster KE, Hewett TE. Meta-analysis of meta-analyses of anterior cruciate ligament injury reduction
  training programs. J Orthop Res 2018;36(10):2696–2708. doi:10.1002/jor.24043 · PMID 29737024

Reused from Part 1 / TRAINING-RESEARCH without re-listing: Silva2018, Milewski2014, Suchomel2018, Rogerson2024,
Bell2023. Looked for but not used: an adolescent validation of reps-in-reserve ratings (none found), a trial of
how many days before a game a heavy session is safe (none found), and Edouard's "sprinting as a vaccine" piece
(not a trial).
