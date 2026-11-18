# Training research — what the workout engine is built on

Owner's brief (2026-11-18): "Put lots of work into research about exercises. What exercises attack which
muscle and in which way. Evolve the algorithm … how do ordinary athletes turn into the best."

This file is organised by **the decision the engine makes**. Each claim cites a source that was looked up
(author, year, journal, DOI or a stable URL). Where the evidence is weak or a number is an engineering choice
rather than a research finding, it says so. The last two sections are "What separates athletes who get to the
top" and "Rules the engine now follows" (rule → code → source).

Code: `app/Shared/Sources/WorkoutEngine.swift` (decision), `SessionBuilder.swift` (exercises, order, dose),
`ConditioningEngine.swift`, `SportDemands.swift` (`InjuryPrevention`), `ExerciseProfile.swift` (what an exercise
trains), `PlanExplanation.swift` ("Why this plan?"). Exercise knowledge: `content/src/profiles.js`.

---

## 1. Who is this athlete? — training stage

**Decision:** how specific, how fast and how hard the session may be.

- Youth resistance training is safe and effective when supervised and progressed by technique first; loads are
  set by competence, not age alone. *Faigenbaum et al. 2009, J Strength Cond Res 23(5 Suppl):S60–79,
  doi:10.1519/JSC.0b013e31819df407* and *Lloyd et al. 2014, Br J Sports Med 48(7):498–505,
  doi:10.1136/bjsports-2013-092952* (international consensus).
- The Youth Physical Development model organises training by maturation and training age: movement skill,
  strength, power, speed and agility are trainable throughout youth; hypertrophy is a smaller emphasis before
  and around the growth spurt. *Lloyd & Oliver 2012, Strength Cond J 34(3):61–72,
  doi:10.1519/SSC.0b013e31825760ea.*
- Long-term athletic development should be individualised, put the athlete's health first, build muscular
  strength and movement competence early, and be overseen by qualified coaches. *Lloyd et al. 2016 (NSCA
  position statement), J Strength Cond Res 30(6):1491–1509, doi:10.1519/JSC.0000000000001387.*
- The IOC asks for healthy, resilient, capable youth athletes and warns against early single-sport
  specialisation and overload. *Bergeron et al. 2015, Br J Sports Med 49:843–851,
  doi:10.1136/bjsports-2015-094962.*

**What the app does:** `TrainingStage` — *foundation* (new to lifting or under 14), *development*, *performance*
(experienced and 16+). Stage changes priorities (landing and movement skill first vs. specific power and speed),
variety, jump volume and effort (§3). The app never tests a 1-rep max; effort is felt (reps left), not a
percentage of a max.

## 2. What does an exercise train? — the exercise knowledge base

**Decision:** which exercise fills which slot, and what the athlete is told it builds.

- Strength underpins jumping, sprinting and change of direction; stronger athletes perform better in sport
  tasks and may get injured less. *Suchomel, Nimphius & Stone 2016, Sports Med 46(10):1419–1449,
  doi:10.1007/s40279-016-0486-0.* → strength is the base of every development day.
- Power has a force end and a velocity end (the force–velocity profile); training aimed at the individual's
  weaker end improved jump height more than a generic programme. *Jiménez-Reyes et al. 2017, Front Physiol
  7:677, doi:10.3389/fphys.2016.00677.* → the knowledge base separates **strength-speed** (heavy and fast:
  cleans, loaded jumps, push press) from **speed-strength** (light and fast: jumps, throws) and **reactive**
  work (short ground contacts: pogos, hurdle hops, depth jumps). The app has no force plate or velocity data,
  so it does not profile athletes; the twin's `strengthNotSpeed` insight is the nearest signal.
- Conditioning is described by what it costs physiologically (cardiopulmonary, glycolytic, neuromuscular),
  not just "cardio". *Buchheit & Laursen 2013, Sports Med 43(5):313–338, doi:10.1007/s40279-013-0029-x.* →
  every fast or conditioning item carries an energy system: alactic, glycolytic, aerobic or mixed.

**Exercise profile fields (content/src/profiles.js, hand-tagged for all 201 base exercises):**

| field | values |
|---|---|
| `quality` | max-strength · strength-speed · speed-strength · reactive · acceleration · max-velocity · change-of-direction · deceleration · hypertrophy · strength-endurance · aerobic · anaerobic · repeated-sprint · mobility · stability · injury-prevention · recovery |
| `energy` | alactic · glycolytic · aerobic · mixed (fast and conditioning items) |
| `muscles` | primary / secondary in the focus vocabulary: neck, traps, front-/side-/rear-delts, rotator-cuff, chest, serratus, lats, upper-back, biceps, triceps, forearms, abs, obliques, lower-back, glutes, glute-med, hip-flexors, adductors, quads, hamstrings, calves, shins, feet |

Each focus muscle is a set of the anatomical muscles in `content/src/muscles.js`, so the body map, the
Library's muscle filter and the planner agree. A test checks every hand row against the item's own weighted
muscle map. Variants inherit their base; an explosive tempo variant becomes speed-strength; sport drills get
theirs from their qualities and muscle map.

## 3. How much, how hard, in which order? — dose and sequence

**Strength effort.** The reps-in-reserve (RIR) RPE scale lets load follow how the athlete is that day.
*Helms et al. 2016, Strength Cond J 38(4):42–49, doi:10.1519/SSC.0000000000000218.* → every strength set has an
effort cue: foundation 3–4 reps left, development 2–3, performance 2 (1–2 only for 18+ main lifts); a
below-normal check-in or return from illness → 3–4 left. Never to failure. Velocity-based training is the more
objective version (*Weakley et al. 2021, Strength Cond J 43(2):31–49, doi:10.1519/SSC.0000000000000560*) — not
used, because athletes have no velocity device; the cue "stop if the bar slows" borrows its idea.

**Hypertrophy volume.** More weekly sets give more muscle growth, analysed up to ~10 sets per muscle per week.
*Schoenfeld, Ogborn & Krieger 2017, J Sports Sci, doi:10.1080/02640414.2016.1210197.* → size is
not a youth priority (§1), so the engine does not chase volume; `SessionTrains.sets` counts weighted sets per
muscle group so the session can be described and balanced.

**Jumps.** Plyometric training works in youth before and after the growth spurt; the review reports a minimal
effective dose of about 4 weeks / 8 sessions and ~92 jumps a week, with low-to-very-low certainty.
*Ramirez-Campillo et al. 2023, Sports Med Open 9:23, doi:10.1186/s40798-023-00568-6.* → the weekly landing caps
already in the app (80–140 by age, ×¾ beginner, ×1.2 experienced) stay; new per-session caps of 40 / 60 / 80
(foundation / development / performance, ¾ in season) are a conservative engineering choice inside that range,
not a research number. Contacts per set: foundation ≤ 5, development ≤ 6, performance ≤ 8. (The often-quoted
80–100 / 100–120 / 120–140 contacts per session come from textbook tables we could not verify in the primary
source, so they are not used.)

**Sprints.** Specific sprint training is the most effective way to get faster over 0–30 m and beyond. *Rumpf et
al. 2016, J Strength Cond Res 30(6):1767–1785 (https://ro.ecu.edu.au/ecuworkspost2013/1872).* Resisted sleds may
help acceleration but have not been shown better than plain sprinting. *Petrakos, Morin & Egan 2016, Sports Med
46(3):381–400, doi:10.1007/s40279-015-0422-8.* Elite sprint practice: power, technique and sprint-specific
endurance are trainable; sprinting is done fresh with full recovery. *Haugen et al. 2019, Sports Med Open 5:44,
doi:10.1186/s40798-019-0221-0.* → acceleration reps ≤ 20 m with 2 min rest, max-velocity ≤ 30 m with 2½ min,
"stop when you slow down".

**Order.** Exercises done early in a session respond best; priority work goes first. *Simão et al. 2012, Sports
Med 42(3):251–265 (https://pubmed.ncbi.nlm.nih.gov/22292516/).* → blocks run prep → fast work → sport drill →
main strength → secondary → trunk/resilience → conditioning → cool-down. Inside the fast block: landing skill,
then sprints, then reactive work, then heavy power, then jumps, then throws (most neurally demanding first; the
within-block order is coaching practice, not a trial result).

## 4. Is the week balanced? — muscles and patterns

- Squat and hinge alternate as the main lower pattern; push and pull alternate as the main upper pattern, and
  the other is the secondary (existing rule).
- **Pull ≥ push.** A shoulder programme of rotator-cuff and scapular strength cut shoulder problems in elite
  handball. *Andersson et al. 2017, Br J Sports Med 51(14):1073–1080, doi:10.1136/bjsports-2016-096226.* That
  supports strengthening the back of the shoulder; "at least as much pulling as pressing" is a widely used
  coaching heuristic rather than a trial-tested ratio. → after building, the session counts upper-body exercises
  whose main movers press (chest, front delts, triceps) vs pull (lats, upper back, rear delts, cuff) and adds one
  pulling or shoulder-health exercise when pressing wins.
- Single-leg strength every development day with leg budget (existing), and a hamstring-dominant exercise on
  squat days (existing).

## 5. What protects this sport? — injury prevention

- Strength training reduced sports injuries to about a third and balance (proprioception) training to about a
  half in a meta-analysis of 25 trials; stretching did not. *Lauersen, Bertelsen & Andersen 2014, Br J Sports
  Med 48:871–877 (https://nih.brage.unit.no/nih-xmlui/handle/11250/279729).*
- Programmes including the Nordic hamstring exercise halve hamstring injuries (RR 0.49). *van Dyk, Behan &
  Whiteley 2019, Br J Sports Med 53:1362–1370 (https://bjsm.bmj.com/content/53/21/1362).* In amateur soccer
  (OR 0.28). *van der Horst et al. 2015, Am J Sports Med 43(6):1316–1323, doi:10.1177/0363546515574057.*
- Copenhagen adductor programme: groin problems 13.5% vs 21.3% season prevalence (OR 0.59). *Harøy et al. 2019,
  Br J Sports Med 53(3):150–157, doi:10.1136/bjsports-2017-098937.*
- FIFA 11+ warm-up prevented injuries in young female footballers. *Soligard et al. 2008, BMJ 337:a2469,
  doi:10.1136/bmj.a2469.*
- Neuromuscular training (landing, strength, balance) roughly halves ACL injuries in young female athletes
  (OR 0.51), with a bigger effect in middle- and high-school athletes (OR 0.38). *Petushek et al. 2019, Am J
  Sports Med 47(7):1744–1753, doi:10.1177/0363546518782460.*
- Shoulder programme for throwing athletes: *Andersson et al. 2017* (§4).

→ `InjuryPrevention` maps each sport to its preventable risks (hamstring, groin, knee/ACL, shoulder, ankle), most
important first. Gym days get the top one; after-practice sessions rotate through them. The dose is small and
regular (Nordics: 2–3 × ≤ 6 slow reps). Foundation athletes, and athletes in knee-risk sports below performance
stage, start the fast block with a landing drill.

## 6. Which part of the season? — periodisation

- One strength session a week kept strength and 40-m sprint in professional soccer over 12 in-season weeks;
  one every two weeks lost both. *Rønnestad, Nymark & Raastad 2011, J Strength Cond Res 25(10):2653–2660,
  doi:10.1519/JSC.0b013e31822dcd96.* Similar in cyclists: *Rønnestad, Hansen & Raastad 2010, Eur J Appl Physiol
  (https://pubmed.ncbi.nlm.nih.gov/20799042/).*
- Before competition the best taper cuts volume by 41–60% over ~2 weeks and keeps intensity and frequency.
  *Bosquet et al. 2007, Med Sci Sports Exerc 39(8):1358–1365 (https://pubmed.ncbi.nlm.nih.gov/17762369/).*
- Block periodisation concentrates training on few targets per block, then sequences them. *Issurin 2010,
  Sports Med 40(3):189–206, doi:10.2165/11319770-000000000-00000.*

→ In season the main lifts lose sets but keep intensity (reps −2, never below 6 under 18); pre-season
favours speed and power; off-season has the most volume (existing durations).

## 7. Strength and conditioning on the same day — interference

- Concurrent training blunts power, and with running (not cycling) also strength and size; longer and more
  frequent endurance work interferes more. *Wilson et al. 2012, J Strength Cond Res 26(8):2293–2307
  (https://pubmed.ncbi.nlm.nih.gov/22002517/).*
- Endurance athletes train ~80% easy, ~20% hard. *Seiler 2010, Int J Sports Physiol Perform 5(3):276–291,
  doi:10.1123/ijspp.5.3.276.* → aerobic base work is easy ("you can talk"), intervals are few.

→ Conditioning always follows the lifting; on a leg day the engine picks a bike or rower before running
(`afterLifting`), and the 30-15 running test protocol is not used straight after lifting.

## 8. Load, recovery and sleep

- Spikes in load, not high load itself, drive soft-tissue injury; high chronic load built gradually protects.
  *Gabbett 2016, Br J Sports Med 50(5):273–280, doi:10.1136/bjsports-2015-095788.* (The twin's `loadSpike`
  steer.)
- Adolescent athletes sleeping < 8 h had 1.7× the odds of injury. *Milewski et al. 2014, J Pediatr Orthop
  34(2):129–133, doi:10.1097/BPO.0000000000000151.* Sleep extension improved sprint times and shooting in
  college basketball players. *Mah et al. 2011, Sleep 34(7):943–950, doi:10.5665/SLEEP.1132.*
- More weekly hours of organised sport than years of age doubled the odds of serious overuse injury.
  *Jayanthi et al. 2015, Am J Sports Med 43(4):794–801, doi:10.1177/0363546514567298.*

→ Readiness changes the day (never shown as a score); a below-normal check-in lowers sets and effort.

---

## What separates athletes who get to the top

What the evidence actually says:

1. **Broad early, specific later.** World-class adults did *more* other sports in childhood, started their main
   sport *later* and did *less* main-sport practice than national-class peers — while among juniors the
   early specialisers were ahead. Early success and later excellence are different things. *Güllich, Macnamara &
   Hambrick 2022, Perspect Psychol Sci 17(1):6–29 (https://pubmed.ncbi.nlm.nih.gov/34260336/).* The DMSP
   describes sampling (≈6–12), specialising (≈13–15) and investment (16+) years. *Côté & Vierimaa 2014, Science
   & Sports 29:S63–S69, doi:10.1016/j.scispo.2014.08.133.*
2. **Practice matters, but it isn't everything.** Deliberate practice explained ~18% of sport performance
   overall and ~1% among elite performers. *Macnamara, Moreau & Hambrick 2016, Perspect Psychol Sci
   11(3):333–350, doi:10.1177/1745691616635591.* Hours alone don't make the difference at the top.
3. **Psychological skills carry athletes through the pathway** — commitment, goal setting, quality practice,
   handling pressure and setbacks, using support. *MacNamara, Button & Collins 2010, The Sport Psychologist
   24(1):52–73, doi:10.1123/tsp.24.1.52.*
4. **The whole picture** (performer, environment, practice) with graded evidence: *Rees et al. 2016, Sports Med
   46(8):1041–1058, doi:10.1007/s40279-016-0476-2.*
5. **Being born early in the selection year is an advantage at youth level** (relative age effect), strongest
   in 15–18-year-old boys at representative level — early selection often reflects maturity, not talent.
   *Cobley et al. 2009, Sports Med 39(3):235–256, doi:10.2165/00007256-200939030-00005.*
6. **Strength is a long-term asset** (*Suchomel 2016*), built through **consistent** training with gradual
   load increases (*Gabbett 2016*), and protected by sleep (*Milewski 2014; Mah 2011*) and staying healthy
   (§5 — you can't develop while injured).

What it means for the app:

- **Training age over birthday.** Foundation athletes get variety on purpose (the builder chooses among the
  top five candidates, not three), landing and movement skill first, and are told why ("athletes who reach the
  top usually learned to move in lots of ways first").
- **Progressive overload, never max-out:** effort by reps left; "when every set feels smooth, add a little".
- **Consistency over heroics:** small injury-prevention doses every week; one strength session a week keeps
  in-season gains; rest never breaks the streak (existing rule).
- **Recovery is training:** readiness and sleep shape the day; spikes are flagged by the twin.
- **Mindset:** the Academy's twin and Reflection pillar already cover the psychological characteristics;
  copy stays calm and never guilts. Relative age: worth a Campus/briefing note ("late developers often catch
  up"), not an engine rule.

---

## Rules the engine now follows

| Rule | Where | Source |
|---|---|---|
| Training stage from age + training age (foundation / development / performance); reason codes `STAGE_FOUNDATION`, `STAGE_PERFORMANCE` | `TrainingStage`, `SessionPlanner.decide` | Lloyd & Oliver 2012; Lloyd 2016; Faigenbaum 2009 |
| Foundation: balance, landing and change of direction rank higher; performance: power, acceleration, speed rank higher | `SessionPlanner.priority` | Lloyd & Oliver 2012 |
| Foundation: more variety (top 5 candidates) | `BuildState.pick` | Güllich 2022; Côté & Vierimaa 2014 |
| Landing drill first in the fast block for foundation athletes and knee-risk sports | `BuildState.powerBlock` | Petushek 2019; Lloyd & Oliver 2012 |
| Performance stage: heavy-power option (Olympic pulls) in the fast block | `BuildState.powerBlock` | Jiménez-Reyes 2017; Suchomel 2016 |
| Fast block order: landing → sprint → reactive → heavy power → jumps → throws; fast work before strength | `BuildState.fastRank`, `planned()` | Simão 2012; Haugen 2019 |
| Fast work dosed by quality: ≤ 5 reps (≤ 3 heavy power), sprints ≤ 20/30 m, 90–150 s rest, intent cues | `BuildState.dose` (.power) | Haugen 2019; Rumpf 2016 |
| Landings per session 40/60/80 by stage, ¾ in season, inside the weekly cap; `LANDINGS_CAPPED` when it bites | `BuildState.init`, `pick` | Ramirez-Campillo 2023 (dose range; caps are an engineering choice) |
| Strength effort by reps in reserve, never to failure, no max testing; one notch easier on a below-normal day | `strengthEffort` | Helms 2016; Faigenbaum 2009 |
| In season: fewer sets, reps −2 (≥ 6 under 18) on main lifts; `IN_SEASON_KEEP_INTENSITY` | `decide`, `dose` | Rønnestad 2011; Bosquet 2007 |
| Sport's preventable injury gets its exercise (Nordic, Copenhagen, landing, shoulder, balance); `SPORT_INJURY_RISK` | `InjuryPrevention`, `injuryStaple` | van Dyk 2019; van der Horst 2015; Harøy 2019; Petushek 2019; Andersson 2017; Lauersen 2014 |
| Eccentric hamstring/quad work: 2–3 × ≤ 6 slow reps | `dose` (.accessory) | van der Horst 2015 |
| Pull ≥ push in the upper body; `PULL_BALANCES_PUSH` | `balancePulling` | Andersson 2017 (+ coaching heuristic) |
| Conditioning after lifting, bike/rower before running on leg days; `STRENGTH_BEFORE_CARDIO` | `decide`, `ConditioningEngine.prescribe(afterLifting:)` | Wilson 2012 |
| "What does it build?" and "How hard should it feel?" in Why this plan | `PlanExplanation` | — (explains the above) |

Not in the engine (and why): force–velocity profiling and velocity-based loading need equipment and testing the
app doesn't have; hypertrophy volume targets aren't a youth priority; relative age and deliberate-practice
findings belong in the Academy's teaching, not in the session builder.
