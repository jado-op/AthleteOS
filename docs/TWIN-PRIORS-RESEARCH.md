# Twin priors: what "good" starts from, and how the athlete's own data takes over

> **Read the second opinion at the end first.** An independent review corrected several points (the MD+2 gate, the short-night count, three citations, the leg blend and the Still-learning wording). Where they disagree, the review section and its build order win.

Research for AthleteOS, 2026-11-27. Read-only pass over the repo plus a literature check. No code changed.

## Bottom line

1. **Priors only make sense where the twin actually observes how this athlete responds.** That covers recovery after hard legs, recovery after games, the noise in heart and check-in data, and the usual week-to-week load. Prescriptions with no personal feedback signal stay as fixed evidence-based rules, with no shrinkage. Those are the landing caps, taper, in-season frequency, sessions per week and sleep need. The app cannot learn that a 14-year-old "needs" 7 h of sleep, or tolerates 100 landings, from check-ins.
2. **Use asymmetric shrinkage.** When personal data points to *more* rest, the prior should be weak, so the athlete takes over fast. When it points to *less* rest, the prior is infinitely strong: the floor never moves. A naive symmetric weighted mean gets this backwards. It slows down exactly the lengthening that the safety rule wants.
3. **Priors are about the shape of noise and the starting rest, never about the level.** The app never uses a population resting HR, HRV or sleep figure as the athlete's "usual". It uses population evidence for how wide a normal swing is and how many days a hard session or game costs.
4. Three code findings to fix whatever is decided (details in Step 1):
   - The `sleepBase` card ranks the athlete against peers: "Most teenage athletes don't get there".
   - There are two different definitions of a "short night": a fixed 7.5 h and the athlete's own usual − 1 h.
   - `docs/TWIN-RESEARCH.md` T10 contradicts the code and CLAUDE.md. T10 says personal data may shorten rest by ≤24 h; the code only ever lengthens.

---

## Step 1: Inventory of population assumptions

Paths are relative to `app/Shared/Sources/`. "Learnable" means the twin observes a personal outcome that could move the value.

| # | Where | Value | What it decides | Evidence today | Learnable? |
|---|---|---|---|---|---|
| 1 | `GymFocus.swift:93` `GymRegion.recoveryDays` | legs 3, upper 2, core 0 days | Gap before the next hard session per region (`GymAdvisor` filters, l.229–245) | Sousa 2024 (legs 48–72 h, upper ≤24 h); 72 h = conservative end [GYM rule 4] | **Yes** (soreness after) |
| 2 | `TwinKnowledge.swift:124` `defaultLegRecoveryDays` | 3 | Reference for the personal leg-recovery line; lengthens planner rest (l.396–414) | Same as 1; T10 | Already personal (median, ≥4 episodes) |
| 3 | `WorkoutTagging.swift:216` `recoveryDays(after band)` | legs 1/2/3, upper 1/2/2, core 0/1/2 (light/solid/very hard) | Recovery after a rated Health workout (`recoveryOverride`) | Sousa 2024 by analogy; band mapping is design | Yes (same signal as 1) |
| 4 | `WorkoutEngine.swift:458` `gameYesterday` | MD+1: no heavy legs, no impact, no max sprint | Post-game day | Silva 2018 (soccer, up to 72 h) | **Yes**, by sport |
| 5 | `WorkoutEngine.swift:460` + `TwinAnalysis.swift:364–380` `slowGameRecovery` | MD+2 caution only if day-1 soreness ≥3/5 and ≥1 above usual (≥2 games); day 2 ≥0.7 above | Whether MD+2 also protects legs | Design; no sport prior | **Yes**: today it starts "off" for every sport |
| 6 | `WorkoutEngine.swift:448–456` | MD-1 no heavy/volume legs; MD-2 no volume legs | Pre-game | Thomas 2018, A6 | No (prescription) |
| 7 | `HeartSignals.swift:51–52` | baseline 28 nights, ≥14 | Resting HR / HRV usual | T2 (Mishra 2020, Alavi 2022) | Level is personal; **noise width** learnable |
| 8 | `HeartSignals.swift:97` | raised = ≥ usual + max(3 bpm, 5%) on 2 days | Heart sign | Design from Altini & Plews 2021 (+6% when ill); T3 asks for a CV-based rule that isn't implemented | **Yes** (personal SD) |
| 9 | `HeartSignals.swift:113` | HRV low = 3-day mean ≤ 90% of usual | Second sign | Altini & Plews (−10% when ill) | **Yes** (personal SD) |
| 10 | `HeartSignals.swift:132` | 2-month change shown only if ≥3 bpm | Twin line | Design | Could use personal SD |
| 11 | `TwinKnowledge.swift:201` `usualSleep` | median of 28 days, ≥7 nights | "You usually sleep…" | T2; Apple Vitals uses 7 nights | Personal level; no prior needed |
| 12 | `GymFocus.swift:234` | measured sleep <6 h → no heavy legs | Safety | GYM rule 18: Craven 2022 and others; thresholds are engineering | **No**: fixed floor |
| 13 | `GymFocus.swift:294–297` | last night <7 h or 3-night avg <7 h → shorter session | Session length | GYM rule 18 says avg <7.5; code uses 7 (small drift) | No (floor) |
| 14 | `TwinAnalysis.swift:596` | "short" night = <7.5 h | Sleep vs practice insight | None (fixed) | Conflicts with #15 |
| 15 | `TwinKnowledge.swift:489` | short = ≤ usual − 1 h; ≥20 practices, ≥5 short | Sleep vs practice line | T-research §6 | Personal |
| 16 | `TwinAnalysis.swift:673–675` `sleepBase` | avg ≥8 h → "Most teenage athletes don't get there" | Positive card | AASM 8–10 h | **Violates "never compare with others"** |
| 17 | `TwinAnalysis.swift:619` `irregularSleep` | SD ≥0.9 h (strong ≥1.2) over ≥7 nights | Insight | Design | Could use a prior |
| 18 | `TwinAnalysis.swift:571` `loadSpike` | this week ≥1.5 × mean of 3 prior weeks | Insight + `TwinSteer.loadSpike` (no hard conditioning) | Design; A28 bans ACWR numbers | Noise learnable |
| 19 | `TwinAnalysis.swift:557` | game = 60 min × 8 RPE; practice minutes default 90 | Load units | Design | Partly (own sRPE) |
| 20 | `ReadinessEngine.swift:33–35` | z-score vs 28-day history, ≥7 check-ins; amber ≤ −0.3, red ≤ −1.0 | Readiness band | Design (file says nothing published) | **Yes** (prior SD stabilises early z) |
| 21 | `WorkoutEngine.swift:173` `sessionLandingCap` | 40 / 60 / 80 by stage, ¾ in season | Jump volume | Bedoya 2015 (50–60 start, ≤80–120) | No |
| 22 | `WorkoutEngine.swift:339` `tapering` | 1–10 days before a key event: half the sets | Taper | Bosquet 2007, Vachon 2021 | No |
| 23 | `PlanGenerator.swift:155` / `WorkoutEngine.swift:885` | 3 off / 3 pre / 2 in-season (6 for performance stage, owner); `WeekPlanner` 1–2 in season | Frequency | Lloyd 2014, Rønnestad 2011; 6 = owner decision | No |
| 24 | `GymFocus.swift:345` | in season, legs due after ≥8 days | Maintenance | Rønnestad 2011 (A4) | No |
| 25 | `WorkoutEngine.swift:168` `TrainingStage.of` | <14 or beginner = foundation; experienced ≥16 = performance | Stage | Lloyd 2014/2016 | No |
| 26 | `WorkoutEngine.swift:447, 488` | ≥6 days in a row flag, ≥7 → recovery | Rest days | DiFiori 2014 (in repo) | No |
| 27 | `TwinKnowledge.swift:326` | best-game patterns need ≥10 rated games | Minimum data | T1/T6 | Not a prior question |

---

## Step 2: Evidence per decision

### A. Leg / upper / core recovery after hard strength work (items 1–3)
- **Adults:** lower body 48–72 h, upper ≤24 h. Failure adds 24–48 h. Jump recovers by 48 h; strength and sprint take about 72 h after heavy squats or sprints. (Sousa 2024; Morán-Navarro 2017; Thomas 2018; all in `GYM-ALGORITHM-RESEARCH.md` §1. Not re-opened here.) *Moderate* confidence, small male lab samples.
- **Youth vs adults:** Fernandes et al. 2024 (*Pediatr Exerc Sci*, systematic review with meta-analysis, PMID 38065086) found muscle damage clearly smaller in under-18s than adults: strength ES −2.01, soreness −1.52, CK −1.98. The gap is larger in the upper limbs. Falk & Dotan 2006 (*Exerc Sport Sci Rev* 34:107–112) say children recover faster from high-intensity exercise, mainly because they produce less power. Marginson et al. 2005 (*J Appl Physiol* 99:1174, doi:10.1152/japplphysiol.01193.2004): boys 9–10 had much milder symptoms than men after 80 plyometric jumps. Men's soreness lasted 72 h. Both groups showed a repeated-bout effect. **Caveat:** most of this is pre-pubertal children. Our athletes are 13–22, mostly around or after peak height velocity, so they are drifting toward adult values. There are no adolescent recovery-curve data (TWIN-RESEARCH §2 says the same).
- **Training age:** the first exposure to a new movement causes much more soreness than repeats (Marginson 2005, repeated-bout effect). New lifters and the first sessions of a new block are not typical.
- **Prior:** legs 3 days (72 h) for every age band and stage. Upper 2. Core 0–1. Youth evidence would justify shorter, but it is **not** used to shorten. Our athletes also run and jump in practice, and the safety rule forbids it. *Confidence: moderate for adults, low for 13–18.*

### B. Recovery after games, by sport (items 4–5)
- **Soccer:** Silva 2018 meta-analysis (*Sports Med* 48:539) found neuromuscular, perceptual and biochemical fatigue up to 72 h.
- **Team ball sports:** Doeven et al. 2018 (*BMJ Open SEM* 4:e000264, doi:10.1136/bmjsem-2017-000264; 28 studies) summarise:
  - Soccer CMJ mostly back by 48 h, but some studies not by 72 h. Sprint 48 h to >72 h (2 of 4 studies >72 h). CK 48–120 h.
  - Rugby CMJ about 60 h (union). Basketball CMJ 48 h to about 96 h, sprint 48–72 h. Handball sprint and CK about 48 h.
  - The authors conclude that soccer and rugby need longer than other team ball sports for sprint and CK, and that performance returns before muscle-damage markers do.
  - CMJ and sprint data were men only. Youth was not analysed separately; two youth soccer studies were included, with CK back at about 48 h in one and not recovered in the other.
- **Volleyball, baseball, individual sports:** no usable time-course meta-analysis found.
- **Prior (probability that MD+2 legs are still not recovered):**
  - High, about 0.6: soccer, rugby, Australian/American football, basketball, lacrosse, field and ice hockey.
  - Middle, about 0.4: handball, futsal, volleyball.
  - Low, about 0.2: sports without repeated sprints or eccentric braking (swimming, golf, shooting, rowing).
  - These numbers are **engineering choices**, informed by the sport differences in Doeven and Silva, not measured probabilities. *Confidence: moderate for the soccer/rugby ranking, low for the exact values.*

### C. Sleep (items 11–17)
- **13–18:** the AASM recommends 8–10 h per 24 h "on a regular basis" (Paruthi et al. 2016, *J Clin Sleep Med* 12:785–786 and 12:1549–1561, PMC4877308 / PMC5078711).
- **14–17:** NSF (Hirshkowitz et al. 2015, *Sleep Health* 1:40–43, doi:10.1016/j.sleh.2014.12.010) gives 8–10 h recommended and 7 h "may be appropriate".
- **18–25:** NSF gives 7–9 h recommended and 6 h "may be appropriate".
- **Adults 18–60:** AASM/SRS recommends ≥7 h; more may be appropriate for young adults and when repaying sleep debt (Watson et al. 2015, *J Clin Sleep Med* 11:591–592, PMC4434546).
- **Athletes:** Walsh 2021 (BJSM consensus, in repo) says a single target is "unlikely ideal", individualise. Craven 2022 found acute loss cuts skill and power most. Milewski 2014 found <8 h in adolescents went with 1.7× injury odds (cross-sectional, n=112).
- **How many nights define a usual:** Aili et al. 2017 (*J Clin Sleep Med* 13:39–47, PMC5181612; adults, actigraphy, 7 nights recorded) found total sleep time needs **more than 7 nights** for reliability, and self-reported sleep at least 6. → The current 7-night minimum for "You usually sleep about…" is at the edge. 14 nights would be safer for anything that *decides* something; 7 is fine for a descriptive line.
- **Prior:** sleep *need* is a fixed floor by age band: 8 h for 13–17, 7 h for 18+. It is never learned from data, because a teen's habitual sleep is usually below need. The personal usual is used only to define "short for you". *Confidence: high (consensus) for the floors.*

### D. Resting HR and HRV noise (items 7–10)
- **Smallest worthwhile change** at about 2% for resting HR and 3% for HRV. Typical error is about 10% (RHR) and 12% (rMSSD). In 28,175 app users, sickness came with RHR +6% and rMSSD −10%. RHR did not correlate with age; rMSSD fell with age (r = −0.35) (Altini & Plews 2021, *Sensors* 21:7932, PMC8659706).
- **Readings needed:** at least 3 valid readings per week. Weekly averages plateau after 3–4 days (Plews et al. 2014, *IJSPP* 9(5), doi:10.1123/IJSPP.2013-0455; trained triathletes). Plews et al. 2012 (*Eur J Appl Physiol* 112:3729; two elite triathletes) is the basis for the 7-day rolling lnRMSSD vs an individual SWC. Its "0.5 × SD" figure is only second-hand here.
- **Apple caveat:** Apple stores SDNN from sparse readings, not morning rMSSD. It is noisier than the studies above (TWIN-RESEARCH §3).
- **Prior:** day-to-day SD of resting HR about 5% of usual (≈2.5–3 bpm at 50–60 bpm), which is the width the current max(3 bpm, 5%) already assumes. For HRV, about 10% on the raw scale for the 3-day mean. These are **design priors on width, not level**. There are no adolescent wearable data. *Confidence: low–moderate.*

### E. Readiness check-in spread (item 20)
- Subjective measures track load better than objective ones (Saw 2016). Nothing is published on the SD of a 1–5 teen check-in, so the prior SD is design: about 0.7–0.8 points per item.
- The early z-score with only a few days is unstable. A week of identical "3" answers gives SD 0, so any later "2" reads as extreme or is ignored (the code returns 0 when SD is 0). A prior SD fixes both cases.

### F. Load change (items 18–19)
- There is no trustworthy population threshold. GRONORUN (Buist et al. 2008, *Am J Sports Med*; n=532 novice runners) found the "10% rule" did not reduce injuries. ACWR is discredited (Impellizzeri 2020, A28).
- Kellmann et al. 2018 (*IJSPP* 13:240–245, doi:10.1123/ijspp.2017-0759) recommend systematic, individual recovery monitoring rather than fixed ratios.
- Jayanthi et al. 2015 (*Am J Sports Med* 43:794, doi:10.1177/0363546514567298) and a 2020 follow-up link weekly organised hours above the athlete's age with injury. That one is a usable *absolute* youth flag. It is not a target and is not currently in the app.
- **Prior:** keep 1.5× as a design floor and widen it for athletes whose weeks naturally swing (see Step 3).

### G. Jump spacing, taper, in-season maintenance (items 21–24): keep as fixed rules
- Bedoya 2015: 50–60 contacts per session at start, ≤80–120, about 72 h apart. Thomas 2018: jump fatigue gone by 48 h.
- Bosquet 2007: taper about 2 weeks, −41–60% volume, intensity kept. Vachon 2021: team-sport tapers help power and change of direction.
- Rønnestad 2011: one in-season strength session per week maintains strength; one every two weeks does not.
- None of these has a personal outcome the twin measures well, so **no shrinkage**. They stay population rules, cited in the existing docs.

### Precedent for the method
Hecksteden et al. 2017 (*IJSPP* 12:1137–1142, doi:10.1123/ijspp.2016-0120) built **Bayesian individual reference ranges** for CK and urea. They started from a group prior (883 squad athletes) and let each athlete's repeated measures take over, the approach of the Athlete Biological Passport. In elite junior swimmers and triathletes, individualised ranges misclassified recovery less often than group ranges (significant for CK). This is exactly the proposed "prior → personal" logic, done by a sports-medicine group, and partly in juniors.

---

## Step 3: How to blend (on the phone, explainable, no ML)

### Three building blocks

**(1) Means and durations: pseudo-observations.**
`blended = (k · prior + Σ personal) / (k + n)`. The prior counts as k imaginary observations. The athlete's weight is n/(n+k).

**(2) Yes/no patterns ("legs still sore on MD+2?"): a Beta-style count.**
`p = (k · p0 + hits) / (k + n)`. Act when p ≥ 0.5.

**(3) Noise widths: pooled variance.**
`σ² = (k · σ0² + (n−1) · s²) / (k + n − 1)`. A new athlete gets the prior width. A watch that is noisy for this person widens its own threshold within weeks.

### Asymmetry: the safety rule written as maths
- **Toward more rest (recovery longer, caution on):** small k. The personal data takes over quickly once the replication rule (3 of the last 4 agree) holds.
- **Toward less rest:** the floor is absolute, with k = ∞.
  - Recovery never goes below the prior: legs 72 h, upper 48 h.
  - Game rest is never below MD+1.
  - Sleep floors: 8 h (13–17) / 7 h (18+) as advice; <6 h always blocks heavy legs.
  - Landing caps, taper and the in-season minimum never move.
- **Resolve the T10 conflict in favour of the code and CLAUDE.md** ("only ever longer"), and correct the doc.

### k and minimums per decision

| Decision | Prior | k | Minimum before personal data moves anything | Floor / ceiling |
|---|---|---|---|---|
| Leg recovery (lengthen only) | 3 d | 2 episodes | 4 clean episodes (as now); first 2 sessions of a block or after a ≥2-week break excluded (repeated-bout effect) | Floor 3 d; ceiling 5 d (beyond that = "show it to a trainer", not more rest) |
| Upper recovery | 2 d | 2 | 4 episodes | Floor 2; ceiling 4 |
| MD+2 leg caution | p0 by sport (0.6 / 0.4 / 0.2) | 3 games | 2 games with day-1 and day-2 check-ins | Turning it **off** only returns to today's behaviour (MD+1 rule); never below that |
| Resting HR threshold width | σ0 = 5% of usual | 14 nights | Usual still needs 14 nights (T2) | Threshold ≥ usual + max(3 bpm, 5%); data can only widen it |
| HRV low width | σ0 = 10% | 14 days | 14 days | Low ≤ −10% at most; data can only widen |
| Readiness z | σ0 = 0.75 per item | 7 check-ins | Could start at 4 check-ins, but only to say "below normal", never to pre-fill "good" | Pain always on its own safety path |
| Load spike | weekly CV0 = 25% | 3 weeks | 3 active weeks (now 2) | Threshold ≥ 1.5×; ceiling 2.0× |
| "Short night" | none for need | – | 14 nights | Short = below usual − 1 h **or** below the age floor − 1 h (7 h teen, 6 h 18+), whichever comes first |

The k values are judgement, not fitted numbers. k = 2–3 for recovery means "two or three of your own clear cases outweigh the textbook". That matches T6's replication rule and keeps the logic explainable as counts.

### Worked examples

**Example 1: legs, 16-year-old, development stage.**
- Clean episodes so far: day 4, 4, 5, 3. Prior 3 d, k = 2.
- Blended = (2·3 + 16) / (2 + 4) = 22/6 = 3.67 → round up → **4 days**. Three of the last 4 are ≥4, so the replication rule holds. Final = max(3, 4) = 4.
- With only 2 episodes (4, 4): (6 + 8)/4 = 3.5 → 4, but below the 4-episode minimum → stays 3 and shows "Still learning: 2 of 4".
- Ten episodes later (median 3): blended about 3.0 → back to 3. Never 2, even if every episode says day 2.
- Today's code would give the same 4. The difference is that the lengthening stays smooth when one odd episode arrives, instead of jumping 3 ↔ 5.

**Example 2: soccer player, MD+2.**
- Prior p0 = 0.6, k = 3 → caution **on** from the first game, with no data. Today it is off until the twin has ≥2 games.
- After 4 games, legs back to usual by MD+2 in all four: p = (1.8 + 0)/(3 + 4) = 0.26 → caution off. That is today's behaviour, so no floor is crossed.
- A swimmer (p0 = 0.2) who reports sore legs on MD+2 after 3 of 3 meets: p = (0.6 + 3)/6 = 0.6 → caution on. Their own data turned it on.

**Example 3: resting HR, usual 52 bpm, 20 nights.**
- Personal SD 3.4 bpm. Prior σ0 = 2.6 bpm (5%), k = 14.
- σ² = (14·6.76 + 19·11.56)/33 = 9.52 → σ = 3.09.
- Threshold = 52 + max(3, 2.6, 1.5·3.09 = 4.6) = **56.6** instead of 55.0.
- A noisy watch therefore stops triggering on ordinary swings. A very steady athlete (s = 1.5) keeps 55.0, because the floor never narrows. This also implements T3's "larger than the athlete's own noise", which the docs ask for and the code lacks.

---

## Step 4: What the athlete sees

1. **Default: nothing.** Priors are silent starting values. "Why this plan?" uses the existing wording: "Legs rest 3 days after heavy work". It never says "athletes your age need…".
2. **Still learning** may carry one quiet line per item, only for recovery items, for example:
   > "Most people need about 3 days after a very hard leg day. I'm learning yours: 2 of 4."
   - Use "most people" and "sport science", never "athletes your age" or "your teammates", so nothing reads as a peer group.
   - No percentages, no curve, no "faster than".
3. **When personal data has taken over:** keep the current lines ("…on day 4, not day 3 (3 of 4 times)"). Never add "slower than most" or "faster than most".
4. **Guideline advice is allowed in Campus and briefings, not as a verdict.** "Teens need 8–10 h" belongs in the sleep lesson. It must not appear next to the athlete's own number as a grade.
   - Fix `TwinAnalysis.swift:675`: drop "Most teenage athletes don't get there". Say what their sleep does for them instead: "It's where your training turns into progress."
5. **Never shown:**
   - Population HRV and resting-HR values, or any priors for them. HRV is age-dependent and device-dependent, so a teen would read it as "my HRV is low".
   - Prior widths, and the k values or weights.
   - Game-recovery probabilities.
   - Load thresholds and ratios (A28).
   - Any CK or "muscle damage" language.

---

## Step 5: Second thought, what could go wrong

- **Adult priors applied to teens.** Almost all recovery data are adult men. Mitigation: priors only set the starting rest, which is conservative for youths (they get less damage, per Fernandes 2024). Youth evidence is never used to shorten.
- **Soreness ≠ readiness.** Performance often returns before markers do (Doeven 2018), and soreness lags. Mitigation: soreness only lengthens rest, and only after replication. Pain stays on its own safety path.
- **Repeated-bout and novelty bias.** The first sessions of a new block inflate recovery times, which would lock in a needlessly long rest. Mitigation: exclude the first 2 exposures after a block change or a ≥2-week break.
- **Under-reporting by keen teens** (answering "fine" to get more training). Mitigation: the asymmetry means wrong "fine" answers cannot shorten anything below the floor.
- **A teen reading a guideline as a target** (sleep 8 h, "3 days"). Mitigation: no numbers next to their data; floors live in Campus copy; T14 calm tone; no sleep score.
- **False precision.** "3.67 days" is not knowledge. Mitigation: round to whole days, speak in counts ("3 of 4 times"), hide the formula.
- **Sport labels are coarse.** A soccer goalkeeper or a volleyball libero differs from the sport's average. Mitigation: per-position override where `SportDemands` already distinguishes it. Treat the sport p0 as a starting point the athlete's own games overwrite within 3–4 games.
- **Device and population drift in heart data.** Mitigation: per-device baselines (already done), and widths that only ever widen.
- **A wider threshold misses a real early illness.** The cost is low. The note only asks "how do you feel?", and the athlete's words move the plan (T12), so missing a weak signal matters little.
- **k chosen by judgement.** This is honest but not fitted. Mitigation: keep the k values in one table, test with harness fixtures, and revisit them if the twin's own lines show the prior was routinely wrong. Never tune them on other users' data (project rule).
- **Mixed priors and evidence across files** ("one brain"). The two short-night definitions already disagree. Mitigation: a single `Priors.swift` (Foundation, harness-tested) holding every prior, its source and its k, read by `GymAdvisor`, `TwinAnalysis`, `TwinKnowledgeEngine`, `HeartSignals` and `SessionPlanner`.

### Priority: most real value in an athlete's first two weeks

1. **Sport-specific MD+2 game prior.** It works from game 1 with no data. Today every soccer, rugby or basketball player starts with no MD+2 protection until the twin has seen ≥2 games. This is the biggest safety and quality gain.
2. **Age-band sleep floors, and one "short night" definition.**
   - The floors are already partly there; unify the 7 h / 7.5 h / usual − 1 h variants.
   - Fix the peer-comparison copy.
   - Use 14 nights before "usual" decides anything (Aili 2017).
3. **Readiness prior SD.** It stabilises the first week's z-scores and removes the zero-spread blind spot. Use it only to recognise "below normal" early.
4. **Leg and upper recovery with asymmetric k and the novelty exclusion.** Small change to existing code; it mostly matters from week 3 on, but the exclusion avoids a bad lock-in from week 1.
5. **Heart-noise widths.** Real value only after 14+ nights, so it comes later. Worth doing because T3 already demands a personal-noise rule.
6. **Load-spike width.** Needs ≥3 weeks, so lowest priority for the first two weeks.

---

## Sources

Opened or abstract read in this pass:
- Hecksteden A et al. 2017. A new method to individualize monitoring of muscle recovery in athletes. *IJSPP* 12:1137–1142. doi:10.1123/ijspp.2016-0120 (abstract)
- Doeven SH, Brink MS, Kosse SJ, Lemmink KAPM. 2018. Postmatch recovery of physical performance and biochemical markers in team ball sports: a systematic review. *BMJ Open SEM* 4:e000264. https://pmc.ncbi.nlm.nih.gov/articles/PMC5841509 (full text)
- Fernandes et al. 2024. Youths are less susceptible to exercise-induced muscle damage than adults: a systematic review with meta-analysis. *Pediatr Exerc Sci*. https://pubmed.ncbi.nlm.nih.gov/38065086/ (abstract)
- Falk B, Dotan R. 2006. Child-adult differences in the recovery from high-intensity exercise. *Exerc Sport Sci Rev* 34:107–112 (abstract)
- Marginson V et al. 2005. Comparison of the symptoms of exercise-induced muscle damage after an initial and repeated bout of plyometric exercise in men and boys. *J Appl Physiol* 99:1174–1181. https://pubmed.ncbi.nlm.nih.gov/15817716/ (abstract)
- Paruthi S et al. 2016. AASM consensus on recommended sleep for pediatric populations. *J Clin Sleep Med* 12:785–786; methodology 12:1549–1561. https://pmc.ncbi.nlm.nih.gov/articles/PMC4877308 , https://pmc.ncbi.nlm.nih.gov/articles/PMC5078711
- Hirshkowitz M et al. 2015. National Sleep Foundation's sleep time duration recommendations. *Sleep Health* 1:40–43. doi:10.1016/j.sleh.2014.12.010 (ranges from the NSF release: https://www.eurekalert.org/news-releases/554948)
- Watson NF et al. 2015. Recommended amount of sleep for a healthy adult. *J Clin Sleep Med* 11:591–592. https://pmc.ncbi.nlm.nih.gov/articles/PMC4434546/
- Aili K et al. 2017. Reliability of actigraphy and subjective sleep measurements in adults: the design of sleep assessments. *J Clin Sleep Med* 13:39–47. https://pmc.ncbi.nlm.nih.gov/articles/PMC5181612 (abstract)
- Altini M, Plews D. 2021. *Sensors* 21:7932. https://pmc.ncbi.nlm.nih.gov/articles/PMC8659706 (full text)
- Plews DJ et al. 2014. Monitoring training with heart-rate variability: how much compliance is needed for valid assessment? *IJSPP* 9(5). doi:10.1123/IJSPP.2013-0455 (abstract)
- Plews DJ et al. 2012. Heart rate variability in elite triathletes… *Eur J Appl Physiol* 112:3729–3741. https://pubmed.ncbi.nlm.nih.gov/22367011/ (abstract)
- Kellmann M et al. 2018. Recovery and performance in sport: consensus statement. *IJSPP* 13:240–245. doi:10.1123/ijspp.2017-0759 (abstract)
- Buist I et al. 2008. No effect of a graded training program on the number of running-related injuries in novice runners (GRONORUN). *Am J Sports Med*. https://research.rug.nl/en/publications/no-effect-of-a-graded-training-program-on-the-number-of-running-r/ (abstract)
- Jayanthi NA et al. 2015. Sports-specialized intensive training and the risk of injury in young athletes. *Am J Sports Med* 43:794–801. doi:10.1177/0363546514567298 (abstract; the "hours > age" threshold is from the 2020 follow-up, not verified in the 2015 text)

Cited from the repo's own research docs (`docs/GYM-ALGORITHM-RESEARCH.md`, `docs/TWIN-RESEARCH.md`, `docs/TRAINING-RESEARCH.md`), not re-opened here: Sousa 2024, Morán-Navarro 2017, Thomas 2018, Silva 2018, Rønnestad 2011, Bosquet 2007, Vachon 2021, Bedoya 2015, Saw 2016, Buchheit 2014, Hopkins 2004, Walsh 2021, Craven 2022, Milewski 2014, Impellizzeri 2020, Lloyd 2014/2016, DiFiori 2014.

Not found or not verified: day-to-day resting-HR CV in adolescents with wrist wearables; any post-game recovery time course for volleyball or baseball; adolescent (13–18) muscle-damage recovery curves, as opposed to pre-pubertal children; the exact "0.5 × SD" SWC wording in Plews 2012.

---

## Second opinion (independent review, 2026-11-27) — this section wins where it disagrees

Code claims checked line by line; the load-bearing sources re-opened (Fernandes 2024, Altini & Plews 2021, Aili 2017, Doeven 2018, Hecksteden 2017, AASM/NSF).

### Corrections
1. **MD+2 is misdescribed above.** `TwinSteer.from` (WorkoutEngine.swift) turns on `slowGameRecovery` whenever the `recoveryAfterGames` insight exists, and that needs only ≥2 day-after-game mornings with soreness ≥3 and ≥1 above usual (TwinAnalysis.swift `recoveryAfterGames`). The day-2 check only picks the wording ("a day" / "two days"). So today the caution switches on **from day-1 soreness alone** — an over-protection bug, not missing protection.
2. **At least five short-night cut-offs**, not two: <6 h (GymFocus, DailyLoop), watch average <6.5 h (DailyLoop), <7 h (GymFocus, CampusSignals), <7.5 h (TwinAnalysis), ≤ usual − 1 h (TwinKnowledge). Check-in sleep answers are fixed steps (5.5/6.5/7.5/8.5/9.5), so every cut-off lands on a step.
3. **Aili 2017:** "self-report ≥6 nights" was about diary sleep *quality*, not duration.
4. **Altini & Plews 2021:** the 10%/12% figures are typical error cited from Buchheit 2014, not a measured day-to-day spread. σ0 = 5% / 10% are design values, not evidence.
5. **Doeven 2018** required a mean age ≥18; its studies are mostly adult, often professional. Treat its sport ranking as adult evidence only.
6. **Fernandes 2024:** the larger upper-limb gap is significant for soreness only.
7. **Example 3 does not implement T3** (≥0.5 × the athlete's own CV); the 1.5σ multiplier has no source.
8. Also: `sleepBase` calls 18–22-year-olds "teenage" and needs only 5 nights.

### Disagreements
- **Skip the leg-recovery blend.** The median + "3 of the last 4" rule already decides; a k=2 blend on top counts the prior twice, and rounding up is sticky (nine 3-day episodes and one 5-day → 3.17 → 4). Episodes are already capped at 5.
- **Novelty exclusion only after a ≥2-week break or for a brand-new lifter**, not the first 2 sessions of every block (clean episodes are rare in season; learning would stall).
- **No MD+2 caution from game 1 by sport prior.** With two games a week, MD+1, MD+2 and MD-1 already cover almost every day; the caution would remove the last heavy-leg slot and fight the in-season "legs due after ≥8 days" rule. Missing check-ins would keep it on forever. Instead: gate the caution on real day-2 answers, ask one MD+2 follow-up ("legs back to normal?") through `AthleteContext.questions` (the sport prior only decides whether to ask), never block when the next game is within 2 days and legs haven't been heavy for ≥7 days, and make `GymAdvisor` read the steer (today only `SessionBuilder` does — two decision paths).
- **Heart widths aren't free.** A wider threshold makes "raised" rarer, which turns on the "good" energy pre-fill and the one-tap normal check-in more often — the less cautious direction. Do it last, with T3 reconciled.
- **Readiness prior SD is fine** (σ0 0.75: a one-point drop on one item → z ≈ −0.33, amber). The band is also sent to the server; check what a coach sees.
- **Sleep: two jobs, two names.** A fixed safety floor for plan decisions (<6 h no heavy legs, <7 h shorter session; settle 7 vs 7.5 against GYM rule 18) and a personal "short for you" for twin lines. No age-floor arm in twin patterns (a teen who usually sleeps 6.5 h would have every night "short"). TwinAnalysis switches to the personal definition; 14 nights before "usual" decides anything.
- **Still-learning wording:** not "Most people need…" (reads as a norm, invites "slower than most"; the evidence is a 48–72 h range). Use the plan framing: "Your plan gives legs 3 days after a very hard session. Learning yours: 2 of 4."

### Missed
- A lighter first one or two sessions for a new lifter or after a long break (repeated-bout effect): a real week-one prior that only adds caution.
- Practice minutes default to 90 for load; the sport's typical practice length is a better prior.

### Build order (final)
1. Rule fixes: drop the sleepBase peer copy; correct T10 in TWIN-RESEARCH.md to "only lengthen".
2. Readiness prior SD (fixes the zero-spread blind spot from week one).
3. MD+2 gate on day-2 evidence + the one MD+2 follow-up + two-games-a-week guard + `GymAdvisor` reads the steer.
4. Sleep: safety floor vs personal "short for you", TwinAnalysis on the personal one, 7 vs 7.5 settled, 14 nights.
5. Novelty caution for new lifters / after a ≥2-week break.
6. Heart widths (after the pre-fill knock-on is settled, T3 reconciled).
7. Load-spike width. The leg-recovery blend is dropped.
