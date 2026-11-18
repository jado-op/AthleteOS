/**
 * The twin's birth: eight quick questions across the pillars, asked once when
 * the athlete creates their twin. They set the starting point — mostly honest
 * habits (no right answer), one knowledge check. Validated like lesson
 * questions (validate.js).
 * CONTENT: needs expert review
 */

const k = (pillar, delta, extra = {}) => ({ pillar, side: 'knowledge', delta, ...extra });
const h = (pillar, delta, extra = {}) => ({ pillar, side: 'habits', delta, ...extra });

export const BASELINE = [
  {
    id: 'b-sleep', kind: 'reflection',
    prompt: 'How long do you usually sleep on a school night?',
    options: [
      { text: 'Eight hours or more', effects: [h('recovery', 8)] },
      { text: 'About seven', effects: [h('recovery', 5)] },
      { text: 'Less than seven', effects: [h('recovery', 2)] },
    ],
  },
  {
    id: 'b-fuel', kind: 'reflection',
    prompt: 'Do you eat a proper meal before training or games?',
    options: [
      { text: 'Almost always', effects: [h('fuel', 8)] },
      { text: 'Sometimes', effects: [h('fuel', 4)] },
      { text: 'Rarely', effects: [h('fuel', 1)] },
    ],
  },
  {
    id: 'b-body', kind: 'knowledge',
    prompt: 'Which muscles brake your leg just before your foot lands in a sprint?',
    explain: 'The hamstrings — at full stretch. That is why they need strength in that position.',
    options: [
      { text: 'Hamstrings', correct: true, effects: [k('body', 6, { area: 'thighBack' })] },
      { text: 'Biceps', effects: [] },
      { text: 'Chest', effects: [] },
    ],
  },
  {
    id: 'b-warmup', kind: 'reflection',
    prompt: 'Do you do the full warm-up before training?',
    options: [
      { text: 'Every time', effects: [h('body', 6)] },
      { text: 'Most of the time', effects: [h('body', 3)] },
      { text: 'I often skip it', effects: [h('body', 1)] },
    ],
  },
  {
    id: 'b-mistake', kind: 'reflection',
    prompt: 'After a mistake in a game, you usually…',
    options: [
      { text: 'Reset quickly and play on', effects: [h('mind', 6)] },
      { text: 'Carry it for a few minutes', effects: [h('mind', 3)] },
      { text: 'Get angry at myself or others', effects: [h('mind', 1, { ego: -1 })] },
      { text: 'Want the ball less', effects: [h('mind', 1, { ego: 1 })] },
    ],
  },
  {
    id: 'b-feedback', kind: 'reflection',
    prompt: 'When a coach corrects you, you usually…',
    options: [
      { text: 'Listen and ask how to fix it', effects: [h('mind', 4, { ego: 1 })] },
      { text: 'Explain why it happened', effects: [h('mind', 1, { ego: -1 })] },
      { text: 'Think I’m not good enough', effects: [h('mind', 2, { ego: 1 })] },
    ],
  },
  {
    id: 'b-scan', kind: 'reflection',
    prompt: 'Before you get the ball or make a play, do you check what’s around you?',
    options: [
      { text: 'Almost every time', effects: [h('sportIQ', 6)] },
      { text: 'Sometimes', effects: [h('sportIQ', 3)] },
      { text: 'Rarely', effects: [h('sportIQ', 1)] },
    ],
  },
  {
    id: 'b-legends', kind: 'reflection',
    prompt: 'Do you study how the best players in your sport do things?',
    options: [
      { text: 'Regularly', effects: [h('legends', 6)] },
      { text: 'Now and then', effects: [h('legends', 3)] },
      { text: 'Not yet', effects: [h('legends', 1)] },
    ],
  },
];
