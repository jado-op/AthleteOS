# Plan changes, notifications, routine inference: research → design rules

Scope: one saved plan, "what changed and why", one evening notification, inferred practice schedule with
one-tap morning confirmation. Every source below was checked (DOI via Crossref or the publisher page).
**Evidence** = the source supports it directly. **Design choice** = our own number where nothing better exists.

## Rules

**Plan changes**
- **P1 One plan, one writer.** The engine writes one saved plan (per day: type, focus, duration, start time,
  reason codes, version, `changedAt`). App, widget, Lock Screen, Watch and notification only read it. When the
  plan changes, reload widget timelines in the same transaction. If a surface can't refresh, show the time the plan
  was made rather than an older plan that looks current. Evidence: Apple HIG Widgets ("Keep your widget up to date",
  "show content quickly without hiding stale data", deep-link to the matching place in the app); Amershi G18.
- **P2 Tell only changes the athlete would act on.** A change is worth telling when a day's *type* changes
  (gym, practice, rest, game), a day moves, the start time moves by ≥ 60 min, or the duration moves by ≥ 15 min.
  Exercise swaps, set/rep tweaks and reordering stay silent but can be seen under "Why this plan?". (Design choice;
  basis: adaptive UIs are trusted when they're predictable and their changes are accurate, Gajos 2008; static beat
  adaptive menus when changes were frequent, Findlater & McGrenere 2004; "update and adapt cautiously", Amershi G14.)
- **P3 One line, cause first, before → after.** Format: *"Thursday: legs → upper body. Practice moved to Thursday."*
  At most one line per changed day, ≤ ~90 characters. More detail goes in "Why?" (progressive disclosure). Say what
  the system knew ("from your team calendar", "you said legs are dead"), never a model score. Evidence: Amershi G11
  (make clear why), G4 (show contextually relevant information); PAIR "partial explanations" and output-specific
  explanations; Höök 2000 (transparency, predictability).
- **P4 Batch.** Changes from one cause, or several causes within ~10 min (calendar sync, Health import), merge into
  one change set and one line per day. If more than 3 days change, use one summary line ("This week rebuilt around
  Saturday's game: 3 days changed") and a list on tap. (Design choice; basis: batching notifications into a few
  predictable deliveries improved well-being versus "as they come", Fitz et al. 2019.)
- **P5 Show it where they look, once.** The change line appears on the affected day (Home now slot / week strip) until
  it has been seen once, then it goes into "Why?". No badges, no separate change feed. A push only goes out for a change
  to *today* or *tomorrow*, and only after P6's evening note (P11). Evidence: Apple HIG Notifications (when the app is in
  the foreground, show new data quietly in the view rather than notifying); Amershi G3 (time services based on context).
- **P6 Undo where the athlete caused it; "keep old plan" where it's safe.** Changes the athlete started (Tell, Edit
  week, a check-in answer) get one-tap undo for the rest of the day. Changes from outside (calendar, game added) offer
  "Keep the old plan" only when the safety rules allow it (never after pain, illness, or a game within the leg-taper window).
  Evidence: Amershi G9 (support efficient correction), G8 (efficient dismissal), G17 (global controls); PAIR Feedback +
  Control; Horvitz 1999 (let users refine or reverse automated actions); Findlater & McGrenere 2004 (users preferred
  the menu they could adapt themselves).
- **P7 Never surprise on the day.** After 20:00 the next day's plan is frozen except for safety reasons (pain, illness,
  check-in) or a new or moved event. Morning changes say so explicitly in the now slot. (Design choice; Gajos 2008:
  predictability raises satisfaction; Kocielnik et al. 2019: setting expectations up front increases acceptance of an
  imperfect AI.)

**Notifications**
- **P8 One planning notification a day, evening.** A single "tomorrow" note at a set time (default 19:30 local time,
  athlete can change it; never 22:00–07:00 for under-18s). It replaces generic nudges. It is `active` only when
  tomorrow has training or a game, otherwise `passive` or not sent at all. Evidence: Apple HIG (concise, high-value,
  "avoid sending multiple notifications for the same thing"); `UNNotificationInterruptionLevel`; Fitz 2019 (batching);
  teens already get a median of 237 notifications a day (Common Sense Media 2023).
- **P9 Content = the plan itself, as a when/where/what.** *"Tomorrow: upper body 40 min after practice (16:00).
  Thursday's game is why legs are off."* The title holds the information. No "Don't forget to train!". Evidence:
  implementation intentions (if-when-then plans) have a medium-to-large effect on goal attainment, d = 0.65
  (Gollwitzer & Sheeran 2006); tailored push messages raised next-24 h engagement versus none (Bidargaddi 2018,
  MRT, n = 1,255); contextually tailored suggestions increased the next 30 min's steps (Klasnja 2019).
- **P10 Actions, not instructions.** Up to two actions: "Looks right" (silent ack) and "Change" (opens Edit week on
  that day). Never an action that only opens the app. Evidence: Apple HIG notification actions.
- **P11 Update, don't stack.** A later change to tomorrow *replaces* the delivered note (same identifier / thread),
  not a second note. A change to **today** after the morning is `timeSensitive` only when the start time or venue of a
  game/practice moved; everything else is `active` or shows in the app. At most 2 pushes a day, all types combined.
  Evidence: Apple HIG (multiple notifications for the same thing make people turn all of them off); Pielot et al.
  2018 and Mehrotra et al. 2016 (receptivity depends on content and context; many notifications are dismissed unseen).
- **P12 Expect the effect to fade; protect it.** Effects of prompts are biggest in the first weeks and fade
  (Klasnja 2019: 66% early → 14% averaged). Skip the evening note on days with nothing new (rest day already known,
  same plan as stated yesterday) and track "Looks right" taps; if the note goes unopened 7 evenings in a row, offer to
  switch it to Lock Screen widget only. (Design choice; Nahum-Shani 2018: JITAIs give support only when the person
  needs it and is able to receive it, and treat not intervening as an option.)
- **P13 Nothing private on the Lock Screen.** No pain, mood, body or reflection words in notification text; use
  neutral wording ("Tomorrow's plan changed"). Evidence: Apple HIG ("avoid including sensitive, personal, or confidential
  information"); app privacy rules for minors.

**Routine inference**
- **P14 Propose after 3 in 4.** Propose a recurring practice when the same weekday and start time (±30 min) appears in
  ≥ 3 of the last 4 weeks (from logged practice, Health workouts or calendar events), and the athlete hasn't said no to
  that slot. Never act on it silently: one card, "Practice Tue + Thu at 16:00? [Yes] [Not quite] [No]". (Design choice;
  routines are probabilistic with regular variations, Banovic et al. 2016; when unsure, ask instead of acting, Horvitz
  1999; "scope services when in doubt", Amershi G10; CAP learned calendar preferences but offered them as suggestions,
  Mitchell et al. 1994.)
- **P15 Confirmed ≠ certain.** Until confirmed, inferred practice shows as "probably practice" (half-filled mark), and gym
  days are placed around it, but it never claims practice *happened*.
- **P16 Breaks don't erase the routine.** One missed week = keep; 2 missed weeks in a row = ask "Is Tuesday practice still on?";
  known gaps (holidays from the team or phone calendar, exam weeks, injury, season end) pause the routine instead of
  breaking it. A "No" suppresses the same proposal for 6 weeks. (Design choice; Amershi G12/G13: remember and learn from
  the athlete's answers.)

**Next-morning confirmation**
- **P17 One tap, yesterday only.** If yesterday's scheduled or inferred practice wasn't logged, the morning check-in shows
  one row: "Yesterday's practice: [Went · normal] [Went · hard] [Didn't go]". Optional effort (CR-10) on a second tap. Ask
  only until ~36 h after the session; after that, record "not said" (never guess). Evidence: session RPE (Foster 2001)
  gave the same values from 5 min to 24 h after exercise (Christen et al. 2016, trained cyclists); in adolescent athletes
  a rating 24 h later matched the 30-min rating (r = 0.99, trivial bias), while a weekly recall had ~29% error
  (Phibbs et al. 2017) → no "fill in last week" forms.
- **P18 Keep the daily ask tiny.** ≤ 1 morning card + the existing check-in; total under ~30 s. Youth EMA compliance averages
  78% (Wen et al. 2017), so design for missing answers: a skipped confirmation leaves the practice as "from your schedule",
  it never shifts the plan by itself. Heron et al. 2017 recommend keeping prompts short and protocols light for youth.

## 1. Communicating automated plan changes
Automatic change costs trust unless it is predictable, accurate and cheap to ignore. Static menus beat adaptive ones,
and users preferred menus they controlled (Findlater & McGrenere). Accuracy matters most, and predictability adds
satisfaction on top (Gajos 2006, 2008). Höök calls for transparency and control. Amershi's guidelines name the behaviours
(G8, G9, G11, G14, G17, G18), and PAIR adds partial, output-specific explanations. No study gives a numeric threshold:
the 15/60 min values in P2 are for testing.

## 2. Notifications for fitness apps and teens
Teens get a median of 237 notifications a day and act on about a quarter (Common Sense Media 2023). Batching to three
predictable deliveries a day improved well-being, productivity and sense of control; hourly batching did little
(Fitz 2019, n = 237). Micro-randomized trials show tailored prompts work in the short term (Bidargaddi 2018: more
engagement within 24 h; mid-day weekend best for that adult population), and the effect fades over weeks (Klasnja 2019).
JITAI theory (Nahum-Shani 2018) says to send support only at decision points where the person needs it and can act on it.
Implementation-intention research supports a concrete "tomorrow at X after Y" plan over a generic reminder. Apple: `relevanceScore` decides which notification leads a scheduled summary (set it high for the evening plan). There is little evidence on evening vs morning for teens. We pick evening because it allows a when/where plan, and the
Morning card covers wake-up.

## 3. Inferring routines
Banovic et al. model routines as probabilistic patterns with variation, not fixed rules. Mitchell's CAP learned calendar
habits over ~5 user-years but presented them as advice to accept. Horvitz's mixed-initiative principles: weigh the
cost of a wrong guess and ask when uncertain. No study gives a repetition count for proposing a weekly event. "3 of the last 4
weeks" is a conservative design choice (it tolerates one cancellation) and should be tuned with acceptance rates
(the share of "Yes" answers; aim for ≥ 80%).

## 4. Retrospective logging
Foster's session RPE (CR-10 × minutes) is the standard internal-load measure (25-year review: Foster et al. 2021). Christen
et al. found no difference in sRPE taken 5 min to 24 h after exercise. Phibbs et al. validated a 24 h-later rating in
16–17-year-old rugby players but showed weekly recall is too noisy. Youth EMA compliance is ~78% (Wen 2017). So: ask the
next morning, one tap, and accept "not said".

## 5. Consistency across surfaces
Apple HIG Widgets: keep content up to date, don't hide stale data, say when it was last updated, and deep-link to the exact
item. That is P1: one versioned plan, and every surface quotes the same sentence.

## Sources
- Amershi S. et al. (2019). Guidelines for Human-AI Interaction. CHI '19. https://doi.org/10.1145/3290605.3300233
- Banovic N., Buzali T., Chevalier F., Mankoff J., Dey A. (2016). Modeling and Understanding Human Routine Behavior. CHI '16. https://doi.org/10.1145/2858036.2858557
- Bidargaddi N. et al. (2018). To Prompt or Not to Prompt? A Microrandomized Trial of Time-Varying Push Notifications… JMIR mHealth uHealth 6(11):e10123. https://doi.org/10.2196/10123
- Christen J., Foster C., Porcari J., Mikat R. (2016). Temporal Robustness of the Session Rating of Perceived Exertion. IJSPP 11(8). https://doi.org/10.1123/ijspp.2015-0438
- Common Sense Media (2023). Constant Companion: A Week in the Life of a Young Person's Smartphone Use. https://www.commonsensemedia.org/press-releases/teens-are-bombarded-with-hundreds-of-notifications-a-day
- Findlater L., McGrenere J. (2004). A Comparison of Static, Adaptive, and Adaptable Menus. CHI '04. https://doi.org/10.1145/985692.985704
- Fitz N. et al. (2019). Batching smartphone notifications can improve well-being. Computers in Human Behavior 101:84–94. https://doi.org/10.1016/j.chb.2019.07.016
- Foster C. et al. (2001). A new approach to monitoring exercise training. J Strength Cond Res 15(1):109–115. https://pubmed.ncbi.nlm.nih.gov/11708692/
- Foster C. et al. (2021). 25 Years of Session Rating of Perceived Exertion. IJSPP 16(5). https://doi.org/10.1123/ijspp.2020-0599
- Gajos K., Czerwinski M., Tan D., Weld D. (2006). Exploring the design space for adaptive graphical user interfaces. AVI '06. https://doi.org/10.1145/1133265.1133306
- Gajos K., Everitt K., Tan D., Czerwinski M., Weld D. (2008). Predictability and accuracy in adaptive user interfaces. CHI '08. https://doi.org/10.1145/1357054.1357252
- Gollwitzer P., Sheeran P. (2006). Implementation Intentions and Goal Achievement: A Meta-analysis. Adv Exp Soc Psychol 38:69–119. https://doi.org/10.1016/S0065-2601(06)38002-1
- Heron K. et al. (2017). Using Mobile-Technology-Based EMA Methods With Youth: A Systematic Review and Recommendations. J Pediatr Psychol 42(10):1087–1107. https://doi.org/10.1093/jpepsy/jsx078
- Höök K. (2000). Steps to take before intelligent user interfaces become real. Interacting with Computers 12(4):409–426. https://doi.org/10.1016/S0953-5438(99)00006-5
- Horvitz E. (1999). Principles of mixed-initiative user interfaces. CHI '99. https://doi.org/10.1145/302979.303030
- Klasnja P. et al. (2019). Efficacy of Contextually Tailored Suggestions for Physical Activity: A Micro-randomized Optimization Trial of HeartSteps. Ann Behav Med 53(6):573–582. https://doi.org/10.1093/abm/kay067
- Kocielnik R., Amershi S., Bennett P. (2019). Will You Accept an Imperfect AI? CHI '19. https://doi.org/10.1145/3290605.3300641
- Mehrotra A. et al. (2016). My Phone and Me: Understanding People's Receptivity to Mobile Notifications. CHI '16. https://doi.org/10.1145/2858036.2858566
- Mitchell T. et al. (1994). Experience with a learning personal assistant. CACM 37(7):81–91. https://doi.org/10.1145/176789.176798
- Nahum-Shani I. et al. (2018). Just-in-Time Adaptive Interventions (JITAIs) in Mobile Health. Ann Behav Med 52(6):446–462. https://doi.org/10.1007/s12160-016-9830-8
- Phibbs P. et al. (2017). Validity of Daily and Weekly Self-Reported Training Load Measures in Adolescent Athletes. JSCR 31(4):1121–1126. https://doi.org/10.1519/JSC.0000000000001708
- Pielot M., Vradi A., Park S. (2018). Dismissed! A detailed exploration of how mobile phone users handle push notifications. MobileHCI '18. https://doi.org/10.1145/3229434.3229445
- Wen C.K.F. et al. (2017). Compliance With Mobile EMA Protocols in Children and Adolescents: Systematic Review and Meta-Analysis. JMIR 19(4):e132. https://doi.org/10.2196/jmir.6641
- Apple HIG, Notifications. https://developer.apple.com/design/human-interface-guidelines/notifications
- Apple HIG, Widgets. https://developer.apple.com/design/human-interface-guidelines/widgets
- Apple, UNNotificationInterruptionLevel. https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel
- Apple, relevanceScore. https://developer.apple.com/documentation/usernotifications/unnotificationcontent/relevancescore
- Google PAIR Guidebook: Explainability + Trust https://pair.withgoogle.com/chapter/explainability-trust/ ; Feedback + Controls https://pair.withgoogle.com/chapter/feedback-controls/
