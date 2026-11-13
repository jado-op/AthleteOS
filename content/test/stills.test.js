import assert from 'node:assert/strict';
import { test } from 'node:test';
import { POSE_PATTERNS } from '../src/poses.js';
import { stillsFor } from '../src/stills.js';

test('every movement has two or three stills to cross-fade, starting from its first position', () => {
  for (const p of POSE_PATTERNS) {
    const stills = stillsFor(p);
    assert.ok(stills.length >= 2 && stills.length <= 3, `${p.slug}: ${stills.length} stills`);
    assert.equal(new Set(stills).size, stills.length, `${p.slug}: a still twice`);
    for (const i of stills) assert.ok(Number.isInteger(i) && i >= 0 && i < p.keyframes.length, `${p.slug}: still ${i} out of range`);
    if (!p.stills) assert.equal(stills[0], 0, `${p.slug}: starts somewhere else`);
  }
});

test('a sit-up is lying down, then sitting up', () => {
  const p = POSE_PATTERNS.find((x) => x.slug === 'sit-up');
  const [down, up] = stillsFor(p).map((i) => p.keyframes[i].pose);
  assert.ok(Math.abs(up.spine - down.spine) > 40, 'the trunk should come up');
});
