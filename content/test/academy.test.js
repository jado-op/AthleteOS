import assert from 'node:assert/strict';
import test from 'node:test';

import { LESSONS } from '../src/academy/lessons.js';
import { BODY_AREAS, PILLARS, SPORT_BODY_AREAS } from '../src/academy/model.js';
import { academyPayload, validateAcademy } from '../src/academy/validate.js';

const lesson = (over = {}) => ({
  id: 'test-lesson', title: 'A test', pillar: 'recovery', sports: ['all'], ages: [13, 19], phases: ['all'], requires: [], minutes: 4,
  sections: [
    { heading: 'One', body: 'word '.repeat(80) },
    { heading: 'Two', body: 'word '.repeat(80) },
  ],
  questions: [
    { id: 'q1', kind: 'knowledge', prompt: 'Which?', explain: 'Because.',
      options: [{ text: 'Right', correct: true, effects: [{ pillar: 'recovery', side: 'knowledge', delta: 4 }] }, { text: 'Wrong', effects: [] }] },
    { id: 'q2', kind: 'reflection', prompt: 'How?', options: [{ text: 'A', effects: [{ pillar: 'recovery', side: 'habits', delta: 3 }] }, { text: 'B', effects: [] }] },
  ],
  completion: [{ pillar: 'recovery', side: 'knowledge', delta: 3 }],
  ...over,
});

test('the seed lessons are valid', () => {
  assert.deepEqual(validateAcademy(LESSONS), []);
});

test('two seed lessons per pillar, soccer first', () => {
  for (const pillar of PILLARS) {
    assert.equal(LESSONS.filter((l) => l.pillar === pillar).length, 2, pillar);
  }
  assert.ok(LESSONS.every((l) => l.sports.includes('soccer') || l.sports.includes('all')));
  for (const pillar of ['body', 'fuel', 'recovery', 'mind']) {
    assert.ok(LESSONS.some((l) => l.pillar === pillar && l.sports.includes('all')), `${pillar} has an all-sports lesson`);
  }
});

test('a valid lesson passes', () => {
  assert.deepEqual(validateAcademy([lesson()]), []);
});

test('safety: calorie restriction, weight cutting, supplements and loads are refused', () => {
  const cases = [
    'Keep a calorie deficit before the season.',
    'Cut weight the week before a tournament.',
    'Try to lose weight to get faster.',
    'Take creatine after training.',
    'A protein shake right after.',
    'Do 3 x 10 squats.',
    'Finish with 4 sets of lunges.',
    'Lift 80% of your max.',
    'Hold 20 kg dumbbells.',
  ];
  for (const text of cases) {
    const problems = validateAcademy([lesson({ sections: [{ heading: 'One', body: `${text} ${'word '.repeat(80)}` }, { heading: 'Two', body: 'word '.repeat(80) }] })]);
    assert.ok(problems.some((p) => p.includes('not for the Academy')), text);
  }
});

test('structure problems are reported', () => {
  const problems = (over) => validateAcademy([lesson(over)]).join('\n');
  assert.match(problems({ ages: [11, 18] }), /ages/);
  assert.match(problems({ pillar: 'magic' }), /unknown pillar/);
  assert.match(problems({ sports: ['quidditch'] }), /unknown sport/);
  assert.match(problems({ questions: [lesson().questions[0]] }), /2–4 questions/);
  assert.match(problems({ pillar: 'mind', completion: [{ pillar: 'mind', side: 'knowledge', delta: 3 }] }), /support row/);
  assert.match(problems({ requires: ['missing'] }), /unknown lesson/);
  assert.match(problems({ sections: [{ heading: 'One', body: 'short' }, { heading: 'Two', body: 'short' }] }), /words/);
  const twoRight = lesson().questions[0];
  assert.match(problems({ questions: [{ ...twoRight, options: twoRight.options.map((o) => ({ ...o, correct: true })) }, lesson().questions[1]] }), /exactly one right answer/);
  assert.match(problems({ completion: [{ pillar: 'fuel', side: 'knowledge', delta: 3, area: 'glutes' }] }), /only Body effects/);
});

test('prerequisite loops are found', () => {
  const a = lesson({ id: 'a', requires: ['b'] });
  const b = lesson({ id: 'b', requires: ['a'] });
  assert.ok(validateAcademy([a, b]).some((p) => p.startsWith('prerequisite loop')));
});

test('every sport body-area table uses real areas', () => {
  for (const areas of Object.values(SPORT_BODY_AREAS)) for (const a of areas) assert.ok(BODY_AREAS.includes(a), a);
});

test('the payload keeps every lesson, option and effect', () => {
  const payload = academyPayload(LESSONS);
  assert.equal(payload.lessons.length, LESSONS.length);
  assert.ok(!JSON.stringify(payload).includes('"#'));
  const first = payload.lessons[0];
  assert.equal(first.minAge, 13);
  assert.ok(first.questions.every((q) => q.options.every((o) => typeof o.correct === 'boolean')));
});

test('the birth questions are valid and touch every pillar', async () => {
  const { BASELINE } = await import('../src/academy/baseline.js');
  const { validateBaseline } = await import('../src/academy/validate.js');
  assert.deepEqual(validateBaseline(BASELINE), []);
  const payload = academyPayload(LESSONS, BASELINE);
  assert.equal(payload.baseline.length, 8);
  assert.ok(Object.keys(payload.areaMuscles).length >= 16);
});
