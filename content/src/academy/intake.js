/**
 * The intake interview: who the athlete is, in their own words. Not a quiz —
 * no answer is right or wrong. The twin uses some answers in its analysis
 * (TwinAnalysis.swift reads the option ids), and shows all of them under
 * "Who you are as an athlete". Editable any time.
 * CONTENT: needs expert review (sports psychologist)
 */
export const INTAKE = [
  {
    id: 'drive', label: 'Driven by',
    prompt: 'On a hard day, what keeps you going?',
    options: [
      { id: 'mastery', text: 'Getting better at what I do', summary: 'Getting better — mastery' },
      { id: 'winning', text: 'Winning', summary: 'Winning' },
      { id: 'team', text: 'Not letting my team down', summary: 'The team' },
      { id: 'proving', text: 'Proving people wrong', summary: 'Proving people wrong' },
      { id: 'unsure', text: 'Honestly, I’m not sure yet', summary: 'Still finding out' },
    ],
  },
  {
    id: 'pressure', label: 'Under pressure',
    prompt: 'In a big moment of a {event}, you usually…',
    options: [
      { id: 'narrow', text: 'Lock in — my focus gets sharper', summary: 'Locks in' },
      { id: 'tense', text: 'Tense up and play safer', summary: 'Tenses up, plays safe' },
      { id: 'wantBall', text: 'Want the moment even more', summary: 'Wants the big moment' },
      { id: 'hide', text: 'Hope it passes me by', summary: 'Would rather avoid it' },
    ],
  },
  {
    id: 'mistake', label: 'After a mistake',
    prompt: 'After you make a mistake in a {event}, you…',
    options: [
      { id: 'reset', text: 'Reset quickly and play the next action', summary: 'Resets quickly' },
      { id: 'replay', text: 'Replay it in my head for a while', summary: 'Replays it' },
      { id: 'angry', text: 'Get angry — at myself or others', summary: 'Gets angry' },
      { id: 'quiet', text: 'Go quiet and play it safe', summary: 'Goes quiet' },
    ],
  },
  {
    id: 'confidence', label: 'Confidence comes from',
    prompt: 'Your confidence comes mostly from…',
    options: [
      { id: 'preparation', text: 'How well I prepared', summary: 'Preparation' },
      { id: 'form', text: 'How my last {events} went', summary: 'Recent form' },
      { id: 'others', text: 'What coaches and others say', summary: 'What others say' },
      { id: 'swings', text: 'It comes and goes', summary: 'It comes and goes' },
    ],
  },
  {
    id: 'feedback', label: 'With feedback',
    prompt: 'When a coach corrects you, you usually…',
    options: [
      { id: 'ask', text: 'Ask how to fix it', summary: 'Asks how to fix it' },
      { id: 'explain', text: 'Explain why it happened', summary: 'Explains first' },
      { id: 'personal', text: 'Take it personally for a while', summary: 'Takes it personally' },
    ],
  },
  {
    id: 'teammates', label: 'Others would say',
    prompt: 'How would the people you train with describe you?',
    options: [
      { id: 'leader', text: 'A leader', summary: 'A leader' },
      { id: 'worker', text: 'The hardest worker', summary: 'The hardest worker' },
      { id: 'creator', text: 'The creative one', summary: 'Creative' },
      { id: 'calm', text: 'The calm head', summary: 'The calm head' },
      { id: 'competitor', text: 'The fiercest competitor', summary: 'A fierce competitor' },
    ],
  },
  {
    id: 'sleep', label: 'School-night sleep',
    prompt: 'On school nights, you usually sleep…',
    options: [
      { id: 'eightPlus', text: 'Eight hours or more', summary: '8 hours or more' },
      { id: 'seven', text: 'About seven', summary: 'About 7 hours' },
      { id: 'underSeven', text: 'Less than seven', summary: 'Under 7 hours' },
    ],
  },
  {
    id: 'gameFood', label: 'Before competing',
    prompt: 'Before a {event}, you usually eat…',
    options: [
      { id: 'meal', text: 'A proper meal a few hours before', summary: 'A proper meal' },
      { id: 'small', text: 'Something small', summary: 'Something small' },
      { id: 'nothing', text: 'Often nothing — nerves or no time', summary: 'Often nothing' },
    ],
  },
  {
    id: 'goal', label: 'Season goal', freeText: true,
    prompt: 'What do you want to achieve this season?',
    placeholder: 'For example: start every game by spring',
  },
  {
    id: 'injuries', label: 'Injury history', freeText: true,
    prompt: 'Any injuries in the last two years?',
    placeholder: 'For example: left ankle sprain, 2025 — or none',
  },
];
