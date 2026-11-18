import assert from 'node:assert/strict';
import test from 'node:test';

import { CATALOGUE } from '../src/catalogue.js';
import { HAND_PROFILES, PATTERNS, ROLES, profileFor } from '../src/profiles.js';

test('every base exercise in the core library is tagged by hand', () => {
  const base = CATALOGUE.filter((i) => i.kind === 'exercise' && !i.baseSlug);
  const missing = base.filter((i) => !HAND_PROFILES.has(i.slug)).map((i) => i.slug);
  assert.deepEqual(missing, []);
});

test('no hand profile names an exercise that does not exist', () => {
  const slugs = new Set(CATALOGUE.map((i) => i.slug));
  assert.deepEqual([...HAND_PROFILES.keys()].filter((s) => !slugs.has(s)), []);
});

test('every item gets a valid profile', () => {
  for (const item of CATALOGUE) {
    const p = profileFor(item);
    assert.ok(PATTERNS.includes(p.pattern), `${item.slug}: pattern ${p.pattern}`);
    assert.ok(ROLES.includes(p.role), `${item.slug}: role ${p.role}`);
    assert.ok(p.regions.length > 0 && p.regions.every((r) => ['lower', 'upper', 'trunk'].includes(r)), `${item.slug}: regions`);
    for (const [key, max] of [['fatigue', 5], ['impact', 3], ['technique', 3], ['legLoad', 3]]) {
      assert.ok(Number.isInteger(p[key]) && p[key] >= (key === 'fatigue' || key === 'technique' ? 1 : 0) && p[key] <= max, `${item.slug}: ${key} ${p[key]}`);
    }
    assert.ok(typeof p.group === 'string' && p.group.length > 0, `${item.slug}: group`);
    if (p.role === 'conditioning' && item.kind === 'exercise') assert.ok(p.conditioning, `${item.slug}: conditioning type`);
  }
});

test('the session roles a gym day needs all exist in the library', () => {
  const core = CATALOGUE.filter((i) => i.kind === 'exercise').map(profileFor);
  for (const role of ['prep', 'power', 'speed', 'primary', 'secondary', 'accessory', 'trunk', 'conditioning', 'mobility', 'recovery']) {
    assert.ok(core.filter((p) => p.role === role).length >= 3, `role ${role}`);
  }
  for (const pattern of ['squat', 'hinge', 'push', 'pull', 'unilateral-lower', 'carry', 'rotation', 'anti-rotation', 'jump', 'throw', 'sprint']) {
    assert.ok(core.some((p) => p.pattern === pattern), `pattern ${pattern}`);
  }
});

// What each exercise trains (docs/TRAINING-RESEARCH.md §2).
import { ENERGY_SYSTEMS, FOCUS_MUSCLES, FOCUS_NAMES, HAND_TRAINS, TRAINING_QUALITIES, focusOf } from '../src/profiles.js';
import { MUSCLE_SLUGS } from '../src/muscles.js';

test('every focus muscle names real anatomical muscles, and every muscle has one focus', () => {
  for (const [focus, slugs] of Object.entries(FOCUS_MUSCLES)) {
    for (const slug of slugs) assert.ok(MUSCLE_SLUGS.includes(slug), `${focus}: ${slug}`);
  }
  for (const slug of MUSCLE_SLUGS) assert.ok(focusOf(slug), `${slug} belongs to no focus muscle`);
});

test('every base exercise says by hand what it trains', () => {
  const base = CATALOGUE.filter((i) => i.kind === 'exercise' && !i.baseSlug);
  assert.deepEqual(base.filter((i) => !HAND_TRAINS.has(i.slug)).map((i) => i.slug), []);
  const slugs = new Set(CATALOGUE.map((i) => i.slug));
  assert.deepEqual([...HAND_TRAINS.keys()].filter((s) => !slugs.has(s)), []);
});

test('every item has a quality, an energy system where it matters, and primary muscles', () => {
  for (const item of CATALOGUE) {
    const p = profileFor(item);
    assert.ok(TRAINING_QUALITIES.includes(p.quality), `${item.slug}: quality ${p.quality}`);
    if (p.energy !== undefined) assert.ok(ENERGY_SYSTEMS.includes(p.energy), `${item.slug}: energy ${p.energy}`);
    if (p.role === 'conditioning') assert.ok(p.energy, `${item.slug}: conditioning needs an energy system`);
    assert.ok(p.muscles.primary.length >= 1 && p.muscles.primary.length <= 3, `${item.slug}: primary muscles`);
    for (const f of [...p.muscles.primary, ...p.muscles.secondary]) assert.ok(FOCUS_NAMES.includes(f), `${item.slug}: muscle ${f}`);
    assert.equal(new Set([...p.muscles.primary, ...p.muscles.secondary]).size, p.muscles.primary.length + p.muscles.secondary.length, `${item.slug}: a muscle listed twice`);
  }
});

test('the hand muscles agree with each exercise\'s own weighted muscle map', () => {
  // A primary muscle must be in the item's map (≥ 0.4), and every muscle the
  // map calls a main mover (≥ 0.7) must be primary or secondary — so the body
  // map, the Library filter and the planner never disagree.
  for (const item of CATALOGUE.filter((i) => i.kind === 'exercise' && !i.baseSlug)) {
    const { muscles } = HAND_TRAINS.get(item.slug);
    const byFocus = new Map();
    for (const [m, w] of Object.entries(item.muscles)) byFocus.set(focusOf(m), Math.max(byFocus.get(focusOf(m)) ?? 0, w));
    for (const f of muscles.primary) assert.ok((byFocus.get(f) ?? 0) >= 0.4, `${item.slug}: primary ${f} is not in its muscle map`);
    for (const [f, w] of byFocus) {
      if (w >= 0.7) assert.ok([...muscles.primary, ...muscles.secondary].includes(f), `${item.slug}: main mover ${f} missing`);
    }
  }
});

test('qualities follow the movement: jumps are fast, lifts are strength, conditioning has its energy system', () => {
  for (const [slug, t] of HAND_TRAINS) {
    const p = HAND_PROFILES.get(slug);
    if (p.role === 'primary') assert.ok(['max-strength', 'strength-endurance'].includes(t.quality), `${slug}: a main lift trains ${t.quality}`);
    if (p.role === 'power' || p.role === 'speed') {
      assert.ok(['strength-speed', 'speed-strength', 'reactive', 'acceleration', 'max-velocity', 'change-of-direction', 'deceleration'].includes(t.quality), `${slug}: ${t.quality}`);
      assert.equal(t.energy, 'alactic', `${slug}: fast work is short and alactic`);
    }
    if (p.conditioning) assert.ok(['aerobic', 'anaerobic', 'repeated-sprint'].includes(t.quality), `${slug}: ${t.quality}`);
  }
  // Every quality the planner asks for has at least a few exercises.
  for (const q of ['max-strength', 'speed-strength', 'reactive', 'acceleration', 'max-velocity', 'change-of-direction', 'deceleration', 'injury-prevention', 'stability', 'mobility', 'aerobic']) {
    assert.ok([...HAND_TRAINS.values()].filter((t) => t.quality === q).length >= 3, `quality ${q}`);
  }
});

test('the Swift profile decoder knows every training quality', async () => {
  const fs = await import('node:fs');
  const swift = fs.readFileSync(new URL('../../app/Shared/Sources/ExerciseProfile.swift', import.meta.url), 'utf8');
  const body = swift.slice(swift.indexOf('public enum TrainingQuality'), swift.indexOf('public var title', swift.indexOf('public enum TrainingQuality')));
  for (const q of TRAINING_QUALITIES) {
    assert.ok(body.includes(`= "${q}"`) || new RegExp(`case ${q}\\b`).test(body), `ExerciseProfile.swift has no case for ${q}`);
  }
});
