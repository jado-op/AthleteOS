/**
 * Academy lessons (Beta v0.1): 12 seed lessons for soccer, two per pillar.
 * Body, Fuel, Recovery and Mind lessons that hold for any sport are tagged
 * "all". Education only — no workout plans, no loads, no diets
 * (validate.js enforces it).
 *
 * Every lesson below is a first draft.
 * CONTENT: needs expert review — a coach / sports scientist for Body and Sport IQ,
 * a sports dietitian for Fuel, a sports psychologist for Mind, and a fact check
 * of every Legend insight, before the Academy leaves the beta.
 *
 * Effects: what an answer (or finishing the lesson) does to the twin —
 * { pillar, side: 'knowledge' | 'habits', delta, area?, trait?, ego? }.
 * ego < 0 leans towards confidence, > 0 towards humility; the twin shows the balance.
 */

const k = (pillar, delta, extra = {}) => ({ pillar, side: 'knowledge', delta, ...extra });
const h = (pillar, delta, extra = {}) => ({ pillar, side: 'habits', delta, ...extra });

export const LESSONS = [
  // ── Body ────────────────────────────────────────────────────────────────
  // CONTENT: needs expert review
  {
    id: 'body-sprint-chain',
    title: 'How your legs share a sprint',
    pillar: 'body',
    sports: ['soccer'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'One chain, not single muscles', body: 'A sprint is a relay. Your glutes drive the hip back, your hamstrings pull the leg through and catch it before the foot lands, your quads straighten the knee, and your calves push you off the ground. If one link is weak, the others take extra load.' },
      { heading: 'Why hamstrings matter so much in soccer', body: 'At top speed the hamstring works while it is being stretched, braking the lower leg just before contact. That is the moment most hamstring strains happen. Players who build strength in that lengthened position get injured less often.' },
      { heading: 'Which exercises do what', body: 'Nordic curls teach the hamstring to be strong while it lengthens. Hip thrusts and bridges train the glutes to drive. Calf raises build the spring at the ankle. Your coach or the Workout tab decides how much — here you learn why.' },
      { heading: 'What this means for you', body: 'When a session includes hamstring or glute work, it is not random. It is protecting the muscles that carry your sprints.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'When does the hamstring work hardest in a sprint?',
        options: [
          { text: 'While it is stretched, braking the leg before the foot lands', correct: true, effects: [k('body', 5, { area: 'thighBack' })] },
          { text: 'Only when you stand still', effects: [] },
          { text: 'When you jog slowly', effects: [] },
        ],
        explain: 'The hamstring brakes the lower leg at full stretch — that is why strength in a lengthened position protects it.',
      },
      {
        id: 'q2', kind: 'knowledge',
        prompt: 'Which muscle group drives your hip back to push you forward?',
        options: [
          { text: 'Glutes', correct: true, effects: [k('body', 4, { area: 'glutes' })] },
          { text: 'Biceps', effects: [] },
          { text: 'Neck', effects: [] },
        ],
        explain: 'The glutes are the engine of hip extension — every sprint step starts there.',
      },
      {
        id: 'q3', kind: 'reflection',
        prompt: 'How often do you skip the warm-up or the strength part of training?',
        options: [
          { text: 'Almost never', effects: [h('body', 4)] },
          { text: 'Sometimes', effects: [h('body', 2)] },
          { text: 'Often', effects: [] },
        ],
      },
    ],
    completion: [k('body', 3, { area: 'shinBack' })],
    sources: ['nordic', 'fifa11'],
  },
  // CONTENT: needs expert review
  {
    id: 'body-core-link',
    title: 'Your core is a link, not a six-pack',
    pillar: 'body',
    sports: ['all'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 3,
    sections: [
      { heading: 'What the core really does', body: 'Your core is every muscle between your ribs and your hips — front, sides and back. Its job is to pass force from your legs to your upper body and back, and to stop your trunk from twisting or folding when you do not want it to.' },
      { heading: 'Stiff when it counts', body: 'When you shoot, jump or get bumped, a strong core stays stiff for a split second so the force goes into the ball or the ground instead of leaking out. That is why planks and anti-rotation holds are more useful for athletes than endless crunches.' },
      { heading: 'What this means for you', body: 'A good core does not show in the mirror. It shows when you hold your line in a duel or strike the ball cleanly while off balance.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'What is the core’s main job in sport?',
        options: [
          { text: 'Passing force between legs and upper body, and resisting unwanted twisting', correct: true, effects: [k('body', 5, { area: 'abs' })] },
          { text: 'Looking good', effects: [] },
          { text: 'Only breathing', effects: [] },
        ],
        explain: 'The core is a link: it transfers force and keeps the trunk stable.',
      },
      {
        id: 'q2', kind: 'knowledge',
        prompt: 'Which muscles belong to the core?',
        options: [
          { text: 'Front, sides and back of the trunk', correct: true, effects: [k('body', 4, { area: 'lowerBack' })] },
          { text: 'Only the six-pack', effects: [] },
        ],
        explain: 'The back and side muscles matter as much as the front.',
      },
    ],
    completion: [k('body', 3, { area: 'abs' })],
  },

  // ── Fuel ────────────────────────────────────────────────────────────────
  // CONTENT: needs expert review (sports dietitian)
  {
    id: 'fuel-match-day',
    title: 'Fuel for a match day',
    pillar: 'fuel',
    sports: ['all'],
    ages: [13, 19],
    phases: ['preSeason', 'inSeason'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'Your main fuel for sprints', body: 'Repeated sprints run mostly on carbohydrate stored in your muscles. Rice, pasta, bread, potatoes, oats and fruit refill those stores. Arrive at a game with them full and you can keep your speed late in the second half.' },
      { heading: 'Timing', body: 'Have a normal meal three to four hours before kick-off: carbohydrate, some protein, not too much fat or fibre so it sits well. If the gap is long, a small snack like a banana or a sandwich one to two hours before tops you up.' },
      { heading: 'Drink before you are thirsty', body: 'Start the game well hydrated: drink with your meals and sip water in the hours before. In the heat you lose more through sweat, so drink at every break.' },
      { heading: 'What this means for you', body: 'A match day plan is simple: a familiar meal, a small top-up, water. Try new foods on training days, never before a game.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'What fuels repeated sprints the most?',
        options: [
          { text: 'Carbohydrate stored in the muscles', correct: true, effects: [k('fuel', 5)] },
          { text: 'Nothing — you run on willpower', effects: [] },
          { text: 'Only water', effects: [] },
        ],
        explain: 'Muscle carbohydrate is the main fuel for high-intensity efforts.',
      },
      {
        id: 'q2', kind: 'knowledge',
        prompt: 'When is a good time for your main pre-game meal?',
        options: [
          { text: 'Three to four hours before', correct: true, effects: [k('fuel', 4)] },
          { text: 'Right before warm-up', effects: [] },
          { text: 'The evening before only', effects: [] },
        ],
        explain: 'Three to four hours gives time to digest; a small snack can follow later.',
      },
      {
        id: 'q3', kind: 'reflection',
        prompt: 'Before your last game, did you eat a proper meal?',
        options: [
          { text: 'Yes, a real meal at a good time', effects: [h('fuel', 5)] },
          { text: 'Something small', effects: [h('fuel', 2)] },
          { text: 'Not really', effects: [] },
        ],
      },
    ],
    completion: [k('fuel', 3)],
  },
  // CONTENT: needs expert review (sports dietitian)
  {
    id: 'fuel-enough-to-grow',
    title: 'Eating enough to train and grow',
    pillar: 'fuel',
    sports: ['all'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'Two jobs at once', body: 'As a teenage athlete your body is fuelling training and growing at the same time. Bones, muscles and hormones all need energy. When food does not cover both jobs, the body starts saving energy where it can.' },
      { heading: 'Signs the tank runs low', body: 'Feeling tired for days, getting sick often, slower recovery, stress fractures, missed periods, and performances that drop even though you train hard. Experts call this low energy availability. It is common, and it is fixable.' },
      { heading: 'What helps', body: 'Regular meals and snacks across the day, especially around training. Every meal with carbohydrate, protein and colour from fruit or vegetables. Eat more on heavy training days, not less.' },
      { heading: 'What this means for you', body: 'If you notice those signs, or if eating starts to feel stressful, tell a parent, coach or doctor. That is a smart move, not a weakness.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'Why do teenage athletes need plenty of food?',
        options: [
          { text: 'They fuel training and growth at the same time', correct: true, effects: [k('fuel', 5)] },
          { text: 'They don’t — less is better', effects: [] },
        ],
        explain: 'Growth and training both cost energy; too little slows both.',
      },
      {
        id: 'q2', kind: 'knowledge',
        prompt: 'What is a sign the energy tank may be running low?',
        options: [
          { text: 'Tired for days and getting sick often', correct: true, effects: [k('fuel', 4)] },
          { text: 'Feeling hungry after training', effects: [] },
          { text: 'Sleeping well', effects: [] },
        ],
        explain: 'Long tiredness and frequent illness can mean you are not eating enough for your training.',
      },
      {
        id: 'q3', kind: 'reflection',
        prompt: 'On training days, how many times do you usually eat?',
        options: [
          { text: 'Three meals and a snack or two', effects: [h('fuel', 5)] },
          { text: 'Two or three meals', effects: [h('fuel', 3)] },
          { text: 'I often skip meals', effects: [] },
        ],
      },
    ],
    completion: [k('fuel', 3)],
    sources: ['reds'],
  },

  // ── Recovery ────────────────────────────────────────────────────────────
  // CONTENT: needs expert review
  {
    id: 'recovery-sleep',
    title: 'Sleep is part of training',
    pillar: 'recovery',
    sports: ['all'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'Where you actually get better', body: 'Training is the signal; sleep is where the body answers it. During deep sleep your body releases growth hormone, repairs muscle and stores what you practised, from a new move to a game pattern.' },
      { heading: 'How much', body: 'Teenagers need about eight to ten hours a night. In one study, young athletes who slept less than eight hours were about 1.7 times more likely to get injured than those who slept more.' },
      { heading: 'Easy wins', body: 'The same bedtime most nights, the phone away for the last half hour, a dark and cool room. After a late game, wind down first — a shower, something to eat, no scrolling.' },
      { heading: 'What this means for you', body: 'Going to bed on time is not lazy. It is the training session nobody sees.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'How much sleep do teenage athletes need?',
        options: [
          { text: 'About eight to ten hours', correct: true, effects: [k('recovery', 5)] },
          { text: 'Five hours is enough', effects: [] },
          { text: 'It doesn’t matter', effects: [] },
        ],
        explain: 'Eight to ten hours lets your body repair and your brain store what you learned.',
      },
      {
        id: 'q2', kind: 'knowledge',
        prompt: 'What happens during deep sleep?',
        options: [
          { text: 'Muscle repair and storing new skills', correct: true, effects: [k('recovery', 4)] },
          { text: 'Nothing useful', effects: [] },
        ],
        explain: 'Deep sleep is when repair and learning happen.',
      },
      {
        id: 'q3', kind: 'reflection',
        prompt: 'How many hours did you sleep on most nights this week?',
        options: [
          { text: 'Eight or more', effects: [h('recovery', 6)] },
          { text: 'Seven or so', effects: [h('recovery', 3)] },
          { text: 'Less than seven', effects: [h('recovery', 1)] },
        ],
      },
    ],
    completion: [k('recovery', 3)],
    sources: ['sleep'],
  },
  // CONTENT: needs expert review
  {
    id: 'recovery-after-the-game',
    title: 'The 24 hours after a game',
    pillar: 'recovery',
    sports: ['all'],
    ages: [13, 19],
    phases: ['preSeason', 'inSeason'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'Recovery starts at the final whistle', body: 'A short, easy cool-down, then food and drink within the next hour or two: carbohydrate to refill, protein to repair, water to replace sweat.' },
      { heading: 'The night after', body: 'Adrenaline makes it hard to sleep after a game. Give yourself time to come down — a shower, a meal, a calm routine — and protect the next morning if you can.' },
      { heading: 'The day after', body: 'Light movement like an easy walk, a bike ride or mobility work helps you feel less stiff than lying still all day. Normal soreness fades within a day or two.' },
      { heading: 'Soreness or pain?', body: 'Soreness is a dull, even ache on both sides that eases as you move. Sharp pain, pain in one spot, swelling, or pain that gets worse as you move is different: stop and get it checked.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'What helps most in the first hours after a game?',
        options: [
          { text: 'A cool-down, then food and drink', correct: true, effects: [k('recovery', 5)] },
          { text: 'Skipping food to feel light', effects: [] },
          { text: 'A hard extra session', effects: [] },
        ],
        explain: 'Refuelling and rehydrating early speeds up recovery.',
      },
      {
        id: 'q2', kind: 'knowledge',
        prompt: 'Sharp pain in one spot after a game means…',
        options: [
          { text: 'Stop and get it checked', correct: true, effects: [k('recovery', 4)] },
          { text: 'Train through it', effects: [] },
        ],
        explain: 'Soreness is normal; sharp, local pain is a signal to get checked.',
      },
      {
        id: 'q3', kind: 'reflection',
        prompt: 'After your last game, what did you do first?',
        options: [
          { text: 'Ate and drank something soon', effects: [h('recovery', 5)] },
          { text: 'Not much until later', effects: [h('recovery', 2)] },
          { text: 'Nothing in particular', effects: [] },
        ],
      },
    ],
    completion: [k('recovery', 3)],
  },

  // ── Mind ────────────────────────────────────────────────────────────────
  // CONTENT: needs expert review (sports psychologist)
  {
    id: 'mind-after-a-mistake',
    title: 'Bouncing back from a mistake',
    pillar: 'mind',
    sports: ['all'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 4,
    support: true,
    sections: [
      { heading: 'Everyone makes them', body: 'The best players in the world lose the ball, miss chances and misjudge passes every game. What separates them is how quickly they are ready for the next action.' },
      { heading: 'A three-step reset', body: 'Breathe: one slow breath out, longer than the breath in. Cue: a short word you say to yourself, like “next” or “now”. Act: name your next job — find space, press, talk to a teammate.' },
      { heading: 'Learn later, not now', body: 'During the game, reset and play. After the game, look back calmly at what happened and what you would try next time. Dwelling in the moment costs you the next play.' },
      { heading: 'What this means for you', body: 'Pick your cue word today and use it at your next training. A reset you have practised is one you can use under pressure.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'What is the first step of the reset?',
        options: [
          { text: 'A slow breath out', correct: true, effects: [k('mind', 5)] },
          { text: 'Shouting at yourself', effects: [] },
          { text: 'Replaying the mistake', effects: [] },
        ],
        explain: 'A long breath out calms the body so your head can follow.',
      },
      {
        id: 'q2', kind: 'reflection',
        prompt: 'How do you usually react after a mistake?',
        options: [
          { text: 'I reset quickly and play on', effects: [h('mind', 6, { trait: 'composure' })] },
          { text: 'It stays with me for a few minutes', effects: [h('mind', 3)] },
          { text: 'I get angry at myself or others', effects: [h('mind', 1, { ego: -1 })] },
          { text: 'I hide and avoid the ball', effects: [h('mind', 1, { ego: 1 })] },
        ],
      },
    ],
    completion: [k('mind', 3)],
  },
  // CONTENT: needs expert review (sports psychologist)
  {
    id: 'mind-confidence-humility',
    title: 'Confidence and humility',
    pillar: 'mind',
    sports: ['all'],
    ages: [13, 19],
    phases: ['all'],
    requires: ['mind-after-a-mistake'],
    minutes: 4,
    support: true,
    sections: [
      { heading: 'Two tools, two moments', body: 'Confidence helps in the moment: taking on a defender, asking for the ball, taking the penalty. Humility helps between moments: listening to feedback, admitting what you missed, learning from someone better.' },
      { heading: 'When ego gets in the way', body: 'Ego says “that wasn’t my fault” and stops you from learning. Too little confidence says “I’m not good enough” and stops you from trying. Both cost you.' },
      { heading: 'The balance', body: 'Strong athletes are confident in what they have trained and humble about what they have not mastered yet. They back themselves in the game and ask “what can I do better?” after it.' },
      { heading: 'What this means for you', body: 'Next time a coach gives you feedback, try saying “okay, show me” before explaining why it happened.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'When does humility help you most?',
        options: [
          { text: 'When you get feedback and want to learn', correct: true, effects: [k('mind', 5)] },
          { text: 'When you take a penalty', effects: [] },
        ],
        explain: 'Humility opens the door to learning; confidence helps you act in the moment.',
      },
      {
        id: 'q2', kind: 'reflection',
        prompt: 'A coach points out a mistake you made. What do you usually do?',
        options: [
          { text: 'Listen and ask how to fix it', effects: [h('mind', 5, { ego: 1 })] },
          { text: 'Explain why it wasn’t really my fault', effects: [h('mind', 1, { ego: -2 })] },
          { text: 'Agree, but feel like I’m not good enough', effects: [h('mind', 2, { ego: 2 })] },
        ],
      },
      {
        id: 'q3', kind: 'reflection',
        prompt: 'In a big moment of a game, do you want the ball?',
        options: [
          { text: 'Yes, I back myself', effects: [h('mind', 4, { ego: -1 })] },
          { text: 'Sometimes', effects: [h('mind', 3)] },
          { text: 'I’d rather someone else had it', effects: [h('mind', 1, { ego: 1 })] },
        ],
      },
    ],
    completion: [k('mind', 3)],
  },

  // ── Legends ─────────────────────────────────────────────────────────────
  // CONTENT: needs expert review (fact check of the legend insight)
  {
    id: 'legends-not-picked',
    title: 'Not picked — then what?',
    pillar: 'legends',
    sports: ['all'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'Setbacks are part of the story', body: 'Almost every great career has a moment where the athlete was told “not yet”: not selected, injured, or behind someone else. What they did next mattered more than the setback itself.' },
      { heading: 'From feeling to plan', body: 'It is normal to be disappointed. The useful step comes after: ask what you need to improve, make one concrete plan, and keep showing up.' },
      { heading: 'What this means for you', body: 'If you get left out, ask the coach one question: “What should I work on?” Then work on exactly that.' },
    ],
    legend: {
      athlete: 'Michael Jordan',
      title: 'The junior varsity year',
      body: 'As a high school sophomore, Michael Jordan was not put on his school’s varsity basketball team and played junior varsity instead. He has described using that disappointment as motivation to work harder — and a year later he made the varsity team.',
    },
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'What is the most useful step after not being picked?',
        options: [
          { text: 'Ask what to work on and make a plan', correct: true, effects: [k('legends', 5, { trait: 'resilience' })] },
          { text: 'Quit before it happens again', effects: [] },
          { text: 'Blame the coach', effects: [] },
        ],
        explain: 'Turning the feeling into a concrete plan is what great careers have in common.',
      },
      {
        id: 'q2', kind: 'reflection',
        prompt: 'Think of your last big setback. What did you do next?',
        options: [
          { text: 'Made a plan and worked on it', effects: [h('legends', 5)] },
          { text: 'Needed a while, then got going', effects: [h('legends', 3)] },
          { text: 'I’m still stuck on it', effects: [h('legends', 1)] },
        ],
      },
    ],
    completion: [k('legends', 3)],
  },
  // CONTENT: needs expert review (fact check of the legend insight)
  {
    id: 'legends-extra-work',
    title: 'The work nobody sees',
    pillar: 'legends',
    sports: ['soccer'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'Focused, not just more', body: 'What makes extra practice valuable is not the number of hours but the focus: one skill, a clear goal, honest feedback, and repeating it until it holds under pressure.' },
      { heading: 'Small and often', body: 'Ten focused minutes after training — weak-foot passes, first touches, free kicks — add up over a season to hundreds of quality repetitions.' },
      { heading: 'What this means for you', body: 'Pick one skill that would change your game. Practise it for a few minutes after training, with a clear target, and notice how it changes over a month.' },
    ],
    legend: {
      athlete: 'Cristiano Ronaldo',
      title: 'Staying after training',
      body: 'Coaches and teammates from his years at Manchester United have described how young Cristiano Ronaldo often stayed behind after training to practise free kicks and skills on his own. The goals people saw later were built in sessions nobody watched.',
    },
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'What makes extra practice valuable?',
        options: [
          { text: 'Focus on one skill with a clear goal', correct: true, effects: [k('legends', 5, { trait: 'craft' })] },
          { text: 'Hours, no matter what you do', effects: [] },
        ],
        explain: 'Focused repetitions with feedback beat long, unfocused sessions.',
      },
      {
        id: 'q2', kind: 'reflection',
        prompt: 'Do you work on one specific skill on your own?',
        options: [
          { text: 'Yes, regularly', effects: [h('legends', 5)] },
          { text: 'Now and then', effects: [h('legends', 3)] },
          { text: 'Not yet', effects: [h('legends', 1)] },
        ],
      },
    ],
    completion: [k('legends', 3)],
  },

  // ── Sport IQ ────────────────────────────────────────────────────────────
  // CONTENT: needs expert review (coach; fact check of the legend insight)
  {
    id: 'iq-scan-before-you-receive',
    title: 'Scan before you receive',
    pillar: 'sportIQ',
    sports: ['soccer'],
    ages: [13, 19],
    phases: ['all'],
    requires: [],
    minutes: 4,
    sections: [
      { heading: 'Know before the ball arrives', body: 'Scanning means short looks over your shoulder before the ball reaches you: where is the space, where is the pressure, where are your teammates? With that picture, your first touch can already take you somewhere useful.' },
      { heading: 'Quick and often', body: 'A scan is a glance, not a stare. Good players look away from the ball briefly, several times, especially just before a pass is played to them.' },
      { heading: 'What this means for you', body: 'In your next training, try two looks before every pass you receive: one over each shoulder. It will feel slow at first, then it becomes part of how you play.' },
    ],
    legend: {
      athlete: 'Xavi Hernández',
      title: 'Always looking',
      body: 'Research by Geir Jordet and colleagues, who counted how often Premier League and Barcelona midfielders turned their heads before receiving the ball, found Xavi among the most frequent scanners they studied — and players who scanned more completed more forward passes.',
    },
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'When is the best moment to scan?',
        options: [
          { text: 'Just before the ball is passed to you', correct: true, effects: [k('sportIQ', 5, { trait: 'vision' })] },
          { text: 'After your first touch only', effects: [] },
          { text: 'Never — watch the ball', effects: [] },
        ],
        explain: 'Scanning before the pass lets your first touch use the picture you already have.',
      },
      {
        id: 'q2', kind: 'reflection',
        prompt: 'How often do you look around before receiving?',
        options: [
          { text: 'Almost every time', effects: [h('sportIQ', 5)] },
          { text: 'Sometimes', effects: [h('sportIQ', 3)] },
          { text: 'Rarely', effects: [h('sportIQ', 1)] },
        ],
      },
    ],
    completion: [k('sportIQ', 3)],
  },
  // CONTENT: needs expert review (coach)
  {
    id: 'iq-third-player',
    title: 'Triangles and the third player',
    pillar: 'sportIQ',
    sports: ['soccer'],
    ages: [13, 19],
    phases: ['all'],
    requires: ['iq-scan-before-you-receive'],
    minutes: 4,
    sections: [
      { heading: 'Why triangles', body: 'When three teammates form a triangle around the ball, the player on the ball always has two passing options. One defender cannot block both.' },
      { heading: 'The third player', body: 'The pass that breaks a line is often not to the first player, but to the third: A passes to B, B lays it off, and C — already running — receives it free. The run starts before the second pass.' },
      { heading: 'Angles and distance', body: 'A triangle only works if the angles are open. Stand where the passer can see you past the nearest defender, and not so close that one opponent can press you both. A few steps wider often turns a blocked lane into a free one.' },
      { heading: 'What this means for you', body: 'When you pass, move. When a teammate has the ball, ask yourself: can I be the third player? Your scan tells you where.' },
    ],
    questions: [
      {
        id: 'q1', kind: 'knowledge',
        prompt: 'Why do triangles help keep the ball?',
        options: [
          { text: 'The player on the ball always has two options', correct: true, effects: [k('sportIQ', 5)] },
          { text: 'They look nice', effects: [] },
        ],
        explain: 'Two passing lanes are hard for one defender to close.',
      },
      {
        id: 'q2', kind: 'knowledge',
        prompt: 'When should the third player start the run?',
        options: [
          { text: 'Before the second pass is played', correct: true, effects: [k('sportIQ', 4)] },
          { text: 'After receiving the ball', effects: [] },
        ],
        explain: 'Timing the run early is what lets the third player receive free.',
      },
      {
        id: 'q3', kind: 'reflection',
        prompt: 'After you pass, what do you usually do?',
        options: [
          { text: 'Move into a new space', effects: [h('sportIQ', 5)] },
          { text: 'Watch where the ball goes', effects: [h('sportIQ', 2)] },
        ],
      },
    ],
    completion: [k('sportIQ', 3)],
  },
];
