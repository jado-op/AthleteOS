/**
 * The app shows each movement as stills that cross-fade — the start and the
 * far end of the rep (a sit-up lying down, then sitting up) — not as a played
 * animation. A pattern can name its stills (`stills: [0, 2]`, keyframe
 * indexes); otherwise they are the first keyframe and the one whose body is
 * furthest from it, plus — for a movement with several distinct phases (a
 * burpee, a clean and jerk) — the keyframe least like both.
 */
import { bodyPoints, keyframeAt, placeKeyframes, sub } from './rig3d.js';

/** How different two placed skeletons look: limbs relative to the pelvis, plus how far the pelvis rose or sank. */
function poseDistance(a, b) {
  const pa = bodyPoints(a).map((p) => sub(p, a.pelvis)), pb = bodyPoints(b).map((p) => sub(p, b.pelvis));
  let total = 0;
  for (let i = 0; i < pa.length; i++) total += Math.hypot(pa[i][0] - pb[i][0], pa[i][1] - pb[i][1], pa[i][2] - pb[i][2]);
  return total / pa.length + Math.abs(a.pelvis[1] - b.pelvis[1]);
}

/** A third still has to be this different from both others, relative to how far apart those two are. */
const THIRD_STILL_SHARE = 0.55;

export function stillsFor(pattern) {
  const n = pattern.keyframes.length;
  if (Array.isArray(pattern.stills)) return pattern.stills;
  if (n < 2) return [0];
  const placed = placeKeyframes(pattern);
  const frames = pattern.keyframes.map((_, i) => keyframeAt(pattern, i, placed));
  let best = 1, bestDistance = -1;
  for (let i = 1; i < n; i++) {
    const d = poseDistance(frames[0], frames[i]);
    if (d > bestDistance + 1e-6) { best = i; bestDistance = d; }
  }
  if (n < 5) return [0, best];
  let third = -1, thirdDistance = bestDistance * THIRD_STILL_SHARE;
  for (let i = 1; i < n; i++) {
    if (i === best) continue;
    const d = Math.min(poseDistance(frames[0], frames[i]), poseDistance(frames[best], frames[i]));
    if (d > thirdDistance + 1e-6) { third = i; thirdDistance = d; }
  }
  return third < 0 ? [0, best] : [0, best, third].sort((a, b) => a - b);
}
