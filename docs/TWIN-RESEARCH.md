# Digital Twin: evidence for the new personal insights

Researched 2026-11-27. Every source below was found and its record opened, either as the full text or as the PubMed, publisher or repository abstract. "[abstract]" means only the abstract or catalogue record was checked. "[design]" marks a threshold that **I** derived from the evidence. It is not a published cut-off.

## Rules the twin should follow

- **T1 Say nothing without data.** Every insight has a minimum amount of data (listed below). Until it has that, the card reads "Still learning: 4 of 8 games so far" with no direction and no hint. [Garmin, Oura, Apple Vitals, Apple Trends all hold back like this]
- **T2 Compare the athlete with their own usual.** For resting HR and HRV, "usual" = the median of the last 28 nights, needing ≥14 valid nights. For check-in scales, it = the median of the last 28 days. Never compare with population norms. [Mishra 2020; Alavi 2022; Buchheit 2014; design]
- **T3 Judge on averages, not one day.** HR and HRV are judged on a 3–7-day average with ≥3 valid readings in the week. A change counts only when it is larger than the athlete's own day-to-day noise: ≥0.5 × their coefficient of variation (CV). As a fallback, use ≥3% for HRV and ≥2% for resting HR. [Buchheit 2014; Plews 2013; Altini & Plews 2021]
- **T4 Test only a short, fixed list of patterns.** Each insight has ≤5 pre-declared factors. Never search freely across every variable and lag. With 18 comparisons at p<0.05, there is a 60% chance of at least one false "pattern". [Gelman & Loken 2013; Choe 2014]
- **T5 Show counts, not statistics.** For example: "in 5 of your 6 best games", "so far", "last 8 weeks". No percentages of certainty, no p-values, no 0–100 scores. [Hopkins 2004; Bentley 2013]
- **T6 Promote patterns in two steps.** A pattern starts as a *hint*. It becomes an *insight* only when the next independent cases agree. Example: it still holds after the next 3 games. If a later case breaks it, it drops back quietly. [design, after Gelman & Loken; Karkar 2017]
- **T7 Say "goes with", never "causes".** Allowed: "goes with", "on days after…", "so far". Forbidden: "because", "causes", "makes you", "you respond better to". [Daza 2018; Hecksteden 2015]
- **T8 Body signals never diagnose.** An HR/HRV rise means "your body is working harder than usual". It never means "you are getting sick". Show it only when ≥2 signals agree, inside the morning check-in, never as a night push notification. In adults, only ~1 in 8 such alerts was a confirmed infection. [Apple Vitals; Esmaeilpour 2024; Alavi 2022]
- **T9 Pain is always "get it checked".** Recurring pain in the same area makes the twin say that the pain *came back*, and that the athlete should show it to an athletic trainer, physio or doctor. No risk number, no cause, no self-treatment plan. [Bahr 2016; Impellizzeri 2020; Clarsen 2013]
- **T10 Personal recovery times only lengthen rest.** A personal recovery time may lengthen the default rest; it never shortens it (owner rule; after a hard session the engine default stays legs 72 h, upper 48 h — see `docs/TWIN-PRIORS-RESEARCH.md`). [Cosio 2024; Morán-Navarro 2017; Silva 2018; design]
- **T11 Don't claim "you respond better to 3 vs 4 gym days".** Show the lift trend per block descriptively. Frequency is confounded with season and volume, and one person's season cannot separate them. [Grgic 2018; Hecksteden 2015; Swinton 2018; Grgic 2020]
- **T12 Treat the athlete's own words as the main signal.** Check-in and effort answers outweigh wearable numbers when they disagree. [Saw 2016]
- **T13 Let the athlete correct the twin.** Every insight has "That's not right" and "Something else explains it". The answer is stored as context. The insight is hidden or re-labelled, never argued. [design; Choe 2014: missing context is the top pitfall]
- **T14 Calm tone, no chasing numbers.** No "perfect sleep" goals, no daily HRV push, no streak pressure. Sleep stages from a watch are never an insight on their own. [Baron 2017; Lupton 2021]
- **T15 One monthly reflection.** It covers: what we learned, what changed, what we're unsure about, and "Correct me". It shows long-term data, which people rarely look at by themselves. [Tang & Kay 2017; Kocielnik 2018; Li 2010]

## 1. What the best games have in common

**Evidence.** At group level, links between pre-match wellness and match performance are small and mixed. Pre-game wellness tracked running output in a 6-match field-hockey tournament (Ihsan 2017, n=12) [abstract]. Other team-sport studies find no clear link (search summary only; not verified). No study validates n-of-1 "best game" profiling.

**Rules**

- **Outcome.** Use the athlete's **own game self-rating**, not win/loss. The team result is mostly not the athlete's doing.
- **Minimum data.** ≥10 rated games. "Best" = the top third of ratings, which gives ≥3 best games.
- **Factors.** Use a fixed list of 5:
  - mean sleep over the 2 nights before
  - the morning check-in on game day (energy and soreness)
  - the hardest practice in the 2 days before (on the 1–5 scale)
  - a heavy-legs gym session in the 48 h before
  - stress
- **Threshold.** A factor is shown only when **every best game** sits on the same side of the athlete's own median. The size of the difference must also matter: sleep ≥30 min, or ≥1 point on a 1–5 scale [design].
- **Why so strict.** By chance, all 4 best games land on the same side 6% of the time per factor (0.5⁴), and 4 of 5 land there 19% of the time. With 5 factors, "4 of 5" would produce a false pattern about 65% of the time. Require all, then require replication (T6).
- **Wording.** "Your 4 best-rated games so far all came after two nights of 8 h+ sleep. Your other games averaged 7 h 10 min." Never "sleep wins you games".
- **Don't claim** a cause, a prediction for the next game, or anything about the team result.

## 2. Personal recovery time per body region

**Evidence.**

- Recovery varies widely between people. After repeated sprints, 21 of 29 adults were "high responders": hamstring force still down at 72 h (Cosio 2024).
- Sets not taken to failure recover in 24–48 h. Failure sets take longer (Morán-Navarro 2017, trained men).
- After a soccer match, 72 h is not enough for full recovery (Silva 2018 meta-analysis).
- All three are adult studies. There are no adolescent data on individual recovery curves.

**Rules**

- **Minimum data.** Per region, ≥4 "hard" exposures (region effort ≥7 on CR-10), each with soreness or readiness answered on at least 2 of the next 3 days.
- **Personal recovery** = the median number of days until soreness is back at the athlete's own baseline.
- **When to show it.** Only when it differs from the default by ≥1 day in at least 3 of 4 episodes.
- **Wording.** "After your hardest leg days, your legs usually feel normal again on day 3, not day 2 (4 of 5 times)."
- **Don't claim** muscle damage, tissue state or injury risk. Apply T10.

## 3. Resting HR / HRV rising before feeling run down

**Evidence (all adults).**

- **Mishra 2020.** 63% of COVID cases were detectable before symptoms from elevated resting HR against a personal baseline. A later online method used a 28-day sliding baseline.
- **Alavi 2022.** A real-time system flagged 80% of infections, using a streaming median of overnight resting HR. Most alerts had other causes: travel, big meals, alcohol, stress, menstruation.
- **Esmaeilpour 2024.** In a prospective validation, 63 of 512 alerts were confirmed respiratory infections. The false-positive rate was ~2% per day.
- **Altini & Plews 2021** (28,175 users). During self-reported sickness, HR was +6% and rMSSD −10%. Typical error is ~10–12%. The smallest worthwhile change (SWC) is ~2% for HR and ~3% for HRV.
- **Buchheit 2014.** Use ≥3–4 readings per week, act on changes lasting 2–3 days, and treat HRV as sensitive but not specific.
- **Apple Vitals.** The baseline needs 7 nights, and it alerts only when ≥2 metrics are outside the usual range.
- **Hernando 2018.** Apple Watch HRV agreed well with a chest strap (r > 0.9) at rest (n=20 adults).
- **Caveat.** Apple stores HRV as SDNN from sparse spot readings, not the morning rMSSD these studies used. Treat it as the noisier signal.

**Rules**

- **Baseline.** Resting HR and HRV: 28-day median, ≥14 valid nights.
- **Trigger.** Mean overnight resting HR on 2 consecutive nights ≥ baseline + max(3 bpm, 5%) [design, from Altini's +6%]. Plus at least one of:
  - 3-day HRV ≥10% below baseline
  - check-in energy ≤2 or soreness up ≥2 points
  - the athlete told the app they feel ill
- **Wording.** "Your resting heart rate has been higher than your usual for two nights. That often comes with hard training, short sleep, stress or a cold starting. Today's plan is lighter. How do you feel?" Never "you may be sick", and never a count of alerts.
- **Don't claim** illness detection or a diagnosis. Don't show HRV ms changes as good or bad on their own.

## 4. Recurring pain in the same area

**Evidence.**

- Overuse problems are common. Weekly, 39% of athletes reported one and 13% a substantial one. Time-loss registration misses most of them (Clarsen 2013, OSTRC).
- Screening and risk models cannot predict an individual's injury (Bahr 2016).
- The acute:chronic workload ratio is statistically flawed (Impellizzeri 2020).
- Youth overuse and burnout are a recognised concern (DiFiori 2014) [abstract].
- At group level, lower mood and higher acute load went with injury in female youth soccer players (Watson 2017). That is not an individual prediction.

**Rules**

- **Same area twice.** Pain logged in the same area on ≥2 separate occasions within 8 weeks → "Your left knee hurt again: 12 Oct and 3 Nov. Pain that comes back is worth showing to an athletic trainer, physio or doctor."
- **Linking to week type.** Mention a week type only when every pain episode followed it **and** that week type covers <50% of weeks. Wording: "Both times came after weeks with lots of sprinting." Purpose: something to tell the clinician.
- **Never say:** a risk number, "overuse injury", a tissue name, "avoid sprinting", or that the pattern is the cause.
- Any single pain episode keeps the existing stop-and-get-checked path.

## 5. Response to training frequency / volume

**Evidence.**

- When volume is equated, training frequency does not change strength gains (Grgic 2018; adults).
- To show that one person responds differently, you need repeated measures, a known measurement error and a pre-set smallest worthwhile change (SWC) (Hecksteden 2015; Swinton 2018).
- Responses don't even agree across two training types in the same person (Bonafiglia 2016).
- 1RM test–retest error has a median CV of 4.2%, ranging 0.5–12% (Grgic 2020). Estimates from logged reps are noisier.
- A few weeks of one person's lifts cannot separate a frequency effect from season, volume, sleep or maturation. Growth in 13–17-year-olds alone raises strength.

**Rules**

- **Don't build** "you progress better on 4 days".
- **Do build** a descriptive line: "In your 4-day block, estimated squat went from 80 to 86 kg. In your 3-day in-season block it held at 85." Show a change only when it is >2 × the athlete's own week-to-week noise for that lift [design, after Bonafiglia's 2 × typical-error rule]. Otherwise say "about the same".

## 6. Sleep vs next-day practice quality

**Evidence.**

- In youth athletes, sleep went with next-day well-being, with a small correlation (Sawczuk 2018).
- Sleep extension improved sprint and shooting in 11 college basketball players (Mah 2011; small, uncontrolled order).
- Adolescents sleeping under 8 h reported more injuries (Milewski 2014; cross-sectional, n=112). That supports advice, not individual claims.

**Rules**

- **Minimum data.** ≥20 practice days with sleep from the night before, including ≥5 "short" nights. Short = ≥60 min below the athlete's own median [design].
- **Comparison.** "How practice went" (1–5) after short nights vs usual nights.
- **When to show it.** Mean difference ≥0.5 point, and the same direction in each of the last two 4-week halves (replication).
- **Wording.** "On days after short nights, you rated practice about one step lower (8 of 11 times)."
- **Note the confounders.** Late games, exams and travel shorten sleep and lower practice too. Exclude days the athlete told were exam, travel or sick.
- **Don't claim** "lack of sleep makes you play worse" or set sleep-stage targets.

## Method notes

- **N-of-1 logic.** Self-tracked data are observational. Daza 2018 frames causal claims within one person as needing counterfactual periods. Without designed alternation, as in Karkar 2017's 12-day self-experiments, the twin can only report associations.
- **Measurement error comes first.** A change matters only if it beats the noise. The smallest worthwhile change is ~0.3 × the athlete's typical variation for performance (Hopkins 2004, updated 2011). For HR/HRV it is 0.5–1 × the personal CV (Buchheit 2014).
- **Forking paths.** Even one implicit data-dependent choice inflates false findings (Gelman & Loken 2013). Hence fixed factor lists (T4), counts over all-or-nothing rules, and replication (T6).
- **Subjective measures.** They respond to load more consistently than objective markers (Saw 2016), so check-in answers are the primary signal.

## Presentation

- **Natural-language statements work.** Health Mashups found that statements like "You lose weight on weeks when it is warmer" were understood. They also showed that patterns are highly individual and led to focused behaviour changes (Bentley 2013, 60 people, 90 days).
- **Learning periods in consumer products:**

  | Product | Learning period | Comparison |
  | --- | --- | --- |
  | Garmin HRV Status | 3 weeks | 7-day average vs baseline range |
  | Oura | up to 2 weeks to learn averages | last 14 days vs a 2-month baseline |
  | Apple Trends | 180 days to start | last 90 days vs last 365 |
  | Apple Vitals | 7 nights | alerts on ≥2 outliers |
  | WHOOP | first 4 days greyed out | "30 days" appears only in community posts (unverified) |

  All of them show a "still learning" state. The twin should too (T1).
- **Personal informatics research.**
  - Li 2010: the reflection stage needs both short-term and long-term views.
  - Choe 2014: common pitfalls are tracking too much, missing context and weak rigour.
  - Choe 2017: people find insights through trends, comparisons and correlations, and need context to interpret them.
  - Epstein 2015: people lapse and resume. Design for gaps without guilt, and mark missing data rather than fill it.
- **Teens.** Self-tracking can feed body-image concern and fixation (Lupton 2021, narrative review). Girls valued the social side that solo apps remove (Depper & Howe 2017, n=8). "Orthosomnia" shows that sleep-tracker perfectionism worsens sleep (Baron 2017, case series). Hence T14: no weight or kcal insights, no perfect-number goals.
- **Monthly summary.** I found **no study testing a monthly cadence specifically**. Related evidence:
  - Long-term trackers rarely look at old data, but a long-term view gave them new insight (Tang & Kay 2017).
  - Prompted reflection dialogues engaged users: 16 of 33 kept using one unpaid (Kocielnik 2018).
  - Health Mashups surfaced weekly and monthly patterns.

  Recommendation: keep the monthly reflection short (3 learned, 1 changed, 1 unsure), with a correction step.
- **Letting users correct the model** is a design principle here. I did not verify a study that tests it directly.

## Sources (2010–2026 unless noted; all opened)

- Alavi A et al. 2022. Real-time alerting system for COVID-19 and other stress events using wearable data. *Nat Med* 28:175–184. https://doi.org/10.1038/s41591-021-01593-2 [abstract]
- Altini M, Plews D. 2021. What is behind changes in resting heart rate and heart rate variability? A large-scale analysis of longitudinal measurements acquired in free-living. *Sensors* 21:7932. https://pmc.ncbi.nlm.nih.gov/articles/PMC8659706
- Apple. Track your overnight vitals with Apple Watch. https://support.apple.com/en-gb/guide/watch/apd15aa7ed96 ; Fitness/Health Trends: https://support.apple.com/en-lamr/guide/iphone/iph4c34a8a95/16.0/ios
- Bahr R. 2016. Why screening tests to predict injury do not work—and probably never will…: a critical review. *BJSM* 50:776–780. https://pubmed.ncbi.nlm.nih.gov/27095747/
- Baron KG et al. 2017. Orthosomnia: are some patients taking the quantified self too far? *J Clin Sleep Med* 13:351–354. https://pmc.ncbi.nlm.nih.gov/articles/PMC5263088
- Bentley F et al. 2013. Health Mashups: presenting statistical patterns between wellbeing data and context in natural language to promote behavior change. *ACM TOCHI* 20(5):30. https://doi.org/10.1145/2503823 [abstract]
- Bonafiglia JT et al. 2016. Inter-individual variability in the adaptive responses to endurance and sprint interval training: a randomized crossover study. *PLoS One* 11:e0167790. https://pmc.ncbi.nlm.nih.gov/articles/PMC5147982
- Buchheit M. 2014. Monitoring training status with HR measures: do all roads lead to Rome? *Front Physiol* 5:73. https://pmc.ncbi.nlm.nih.gov/articles/PMC3936188
- Choe EK et al. 2014. Understanding quantified-selfers' practices in collecting and exploring personal data. *CHI '14*. https://doi.org/10.1145/2556288.2557372 [abstract]
- Choe EK et al. 2017/18. Understanding self-reflection: how people reflect on personal data through visual data exploration. *PervasiveHealth*. https://doi.org/10.1145/3154862.3154881 [abstract]
- Clarsen B, Myklebust G, Bahr R. 2013. Development and validation of a new method for the registration of overuse injuries in sports injury epidemiology: the OSTRC overuse injury questionnaire. *BJSM* 47:495–502. https://pubmed.ncbi.nlm.nih.gov/23038786/
- Cosio PL et al. 2024. Hamstring responders after repeated sprints. *Front Physiol* 14:1331878. https://www.frontiersin.org/articles/10.3389/fphys.2023.1331878/full (exact title not copied; check before citing in-app)
- Daza EJ. 2018. Causal analysis of self-tracked time series data using a counterfactual framework for N-of-1 trials. *Methods Inf Med* 57:e10–e21. https://pmc.ncbi.nlm.nih.gov/articles/PMC6087468
- Depper A, Howe PD. 2017. Are we fit yet? English adolescent girls' experiences of health and fitness apps. *Health Sociol Rev* 26:98–112. https://doi.org/10.1080/14461242.2016.1196599 [abstract]
- DiFiori JP et al. 2014. Overuse injuries and burnout in youth sports: a position statement from the AMSSM. *BJSM* 48:287–288 / *Clin J Sport Med* 24:3–20. https://bjsm.bmj.com/content/48/4/287 [abstract]
- Epstein DA et al. 2015. A lived informatics model of personal informatics. *UbiComp '15*:731–742. https://my.eng.utah.edu/~cs5540/au16/readings/PersonalInformatics-Epstein2015.pdf [abstract]
- Esmaeilpour Z et al. 2024. Detection of common respiratory infections, including COVID-19, using consumer wearable devices in health care workers: prospective model validation study. *JMIR Form Res* 8:e53716. https://doi.org/10.2196/53716 [abstract]
- Garmin. Heart Rate Variability Status (manual). https://www8.garmin.com/manuals/webhelp/fenix66s6xpro/EN-US/GUID-9282196F-D969-404D-B678-F48A13D8D0CB.html
- Gelman A, Loken E. 2013. The garden of forking paths (working paper; *American Scientist* 2014 as "The statistical crisis in science"). https://www.americanscientist.org/node/3579
- Grgic J et al. 2018. Effect of resistance training frequency on gains in muscular strength: a systematic review and meta-analysis. *Sports Med* 48:1207–1220. https://doi.org/10.1007/s40279-018-0872-x [abstract]
- Grgic J et al. 2020. Test–retest reliability of the one-repetition maximum (1RM) strength assessment: a systematic review. *Sports Med Open* 6:31. https://pmc.ncbi.nlm.nih.gov/articles/PMC7367986
- Hecksteden A et al. 2015. Individual response to exercise training – a statistical perspective. *J Appl Physiol* 118:1450–1459. https://doi.org/10.1152/japplphysiol.00714.2014 [abstract]
- Hernando D et al. 2018. Validation of the Apple Watch for heart rate variability measurements during relax and mental stress in healthy subjects. *Sensors* 18:2619. https://pmc.ncbi.nlm.nih.gov/articles/PMC6111985
- Hopkins WG. 2004 (updated 2011). How to interpret changes in an athletic performance test. *Sportscience* 8:1–7. https://sportsci.org/jour/04/wghtests.htm
- Ihsan M et al. 2017. Pre-game perceived wellness highly associated with match running performances during an international field hockey tournament. *Eur J Sport Sci* 17:593–602. https://doi.org/10.1080/17461391.2017.1301559 [abstract]
- Impellizzeri FM et al. 2020. Acute:chronic workload ratio: conceptual issues and fundamental pitfalls. *IJSPP* 15:907–913. https://opus.lib.uts.edu.au/handle/10453/141898 [abstract]
- Karkar R et al. 2017. TummyTrials: a feasibility study of using self-experimentation to detect individualized food triggers. *CHI '17*:6850–6863. https://pmc.ncbi.nlm.nih.gov/articles/PMC5432136
- Kocielnik R et al. 2018. Reflection Companion: a conversational system for engaging users in reflection on physical activity. *IMWUT* 2(2):70. https://faculty.washington.edu/garyhs/docs/kocielnik-UBICOMP2018-reflection.pdf
- Li I, Dey A, Forlizzi J. 2010. A stage-based model of personal informatics systems. *CHI '10*:557–566. https://doi.org/10.1145/1753326.1753409
- Lupton D. 2021. Young people's use of digital health technologies in the Global North: narrative review. *JMIR* 23:e18286. https://pmc.ncbi.nlm.nih.gov/articles/7834940
- Mah CD et al. 2011. The effects of sleep extension on the athletic performance of collegiate basketball players. *Sleep* 34:943–950. https://pmc.ncbi.nlm.nih.gov/articles/PMC3119836
- Milewski MD et al. 2014. Chronic lack of sleep is associated with increased sports injuries in adolescent athletes. *J Pediatr Orthop* 34:129–133. https://pubmed.ncbi.nlm.nih.gov/25028798/
- Mishra T et al. 2020. Pre-symptomatic detection of COVID-19 from smartwatch data. *Nat Biomed Eng* 4:1208–1220. https://www.nature.com/articles/s41551-020-00640-6 [abstract]
- Morán-Navarro R et al. 2017. Time course of recovery following resistance training leading or not to failure. *Eur J Appl Physiol* 117:2387–2399. https://pubmed.ncbi.nlm.nih.gov/28965198/
- Oura. Readiness contributors (support). https://support.ouraring.com/hc/en-us/articles/360057791533
- Plews DJ, Laursen PB, Kilding AE, Buchheit M. 2013. Evaluating training adaptation with heart-rate measures: a methodological comparison. *IJSPP* 8:688–691. https://openrepository.aut.ac.nz/handle/10292/7122 (citation verified; full text not read)
- Saw AE, Main LC, Gastin PB. 2016. Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures: a systematic review. *BJSM* 50:281–291. https://bjsm.bmj.com/content/50/5/281
- Sawczuk T et al. 2018. Relationships between training load, sleep duration, and daily well-being and recovery measures in youth athletes. *Pediatr Exerc Sci* 30:345–352. https://pubmed.ncbi.nlm.nih.gov/29478381/
- Silva JR et al. 2018. Acute and residual soccer match-related fatigue: a systematic review and meta-analysis. *Sports Med* 48:539–583. https://pubmed.ncbi.nlm.nih.gov/29098658/
- Swinton PA et al. 2018. A statistical framework to interpret individual response to intervention: paving the way for personalized nutrition and exercise prescription. *Front Nutr* 5:41. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5985399/
- Tang LM, Kay J. 2017. Harnessing long term physical activity data—how long-term trackers use data and how an adherence-based interface supports new insights. *IMWUT* 1(2). https://doi.org/10.1145/3090091 [abstract]
- Watson A et al. 2017. Subjective well-being and training load predict in-season injury and illness risk in female youth soccer players. *BJSM* 51:194–199. https://pubmed.ncbi.nlm.nih.gov/27919919/
- WHOOP. The Locker / community posts on calibration. https://community.whoop.com/t/how-long-does-it-take-for-whoop-to-learn-your-baseline-metrics/359 (**not official; unverified**)

**Not verified / not found.**

- Strava's insight design was not researched.
- No adolescent validation exists for wearable illness signals.
- No study tests a monthly reflective cadence or user correction of a model.
- The claim that pre-match wellness is unrelated to match load (Bellinger 2020) came from a search summary only and is not cited above.
