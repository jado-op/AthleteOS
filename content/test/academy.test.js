import assert from 'node:assert/strict';
import test from 'node:test';

import { BRIEFINGS } from '../src/academy/briefings/index.js';
import { INTAKE } from '../src/academy/intake.js';
import { INSIGHTS } from '../src/academy/model.js';
import { academyPayload, validateBriefings, validateIntake, wordCount } from '../src/academy/validate.js';

test('the briefings are valid, one per insight', () => {
  assert.deepEqual(validateBriefings(BRIEFINGS), []);
  for (const insight of INSIGHTS) assert.equal(BRIEFINGS.filter((b) => b.insight === insight).length, 1, insight);
});

test('every briefing is a real read', () => {
  for (const b of BRIEFINGS) assert.ok(wordCount(b) >= 1700, `${b.id}: ${wordCount(b)} words`);
});

test('the intake interview is valid and has no right answers', () => {
  assert.deepEqual(validateIntake(INTAKE), []);
  assert.ok(INTAKE.length >= 8);
});

const sample = (over = {}) => ({
  ...BRIEFINGS[0],
  ...over,
});

test('safety: calorie talk, weight loss, supplements and loads are refused', () => {
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
    'An energy drink before kick-off.',
  ];
  for (const text of cases) {
    const chapters = [{ ...BRIEFINGS[0].chapters[0], blocks: [{ p: text }, ...BRIEFINGS[0].chapters[0].blocks] }, ...BRIEFINGS[0].chapters.slice(1)];
    const problems = validateBriefings([sample({ chapters }), ...BRIEFINGS.slice(1)]);
    assert.ok(problems.some((p) => p.includes('not for the Academy')), text);
  }
});

test('structure problems are reported', () => {
  const others = BRIEFINGS.slice(1);
  const problems = (over) => validateBriefings([sample(over), ...others]).join('\n');
  assert.match(problems({ topic: 'magic' }), /topic/);
  assert.match(problems({ why: 'You slept {sorenessDays} less.' }), /only fills/);
  assert.match(problems({ chapters: BRIEFINGS[0].chapters.slice(0, 2) }), /3–5 chapters|words|protocol/);
  assert.match(problems({ sources: ['made-up'] }), /unknown source/);
});

test('the intake refuses right answers', () => {
  const bad = [{ ...INTAKE[0], options: INTAKE[0].options.map((o, i) => ({ ...o, correct: i === 0 })) }];
  assert.ok(validateIntake(bad).some((p) => p.includes('no right answers')));
});

test('the payload carries reading time, blocks and the interview', () => {
  const payload = academyPayload(BRIEFINGS, INTAKE);
  assert.equal(payload.briefings.length, 6);
  assert.ok(payload.briefings.every((b) => b.minutes >= 8));
  assert.ok(payload.briefings.every((b) => b.chapters.every((c) => c.blocks.every((x) => ['p', 'h', 'quote', 'example', 'yourData', 'protocol'].includes(x.kind)))));
  assert.equal(payload.intake.length, INTAKE.length);
  assert.ok(!JSON.stringify(payload).includes('"#'));
});
