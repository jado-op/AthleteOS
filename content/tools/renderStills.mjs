// Dev-only: renders the stills the app cross-fades for each pattern (SVG → PNG
// with rsvg-convert), framed the way the app frames them.
//   node tools/renderStills.mjs out.png [slug,slug,...|all] [columns=6]
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { POSE_PATTERNS } from '../src/poses.js';
import { cycleSeconds, frameAt, placeFixture, placeKeyframes } from '../src/rig3d.js';
import { sceneShapes } from '../src/rigDraw.js';
import { stillsFor } from '../src/stills.js';

const out = process.argv[2] ?? '/tmp/stills.png';
const only = process.argv[3] && process.argv[3] !== 'all' ? process.argv[3].split(',') : null;
const columns = Number(process.argv[4] ?? 6);
const patterns = POSE_PATTERNS.filter((p) => !only || only.includes(p.slug));
const [cellW, cellH] = [110, 130];
const SLOTS = 3; // room for a movement with three stills

/** Cycle position of keyframe i (the end of the cycle for a last keyframe that doesn't loop). */
function positionOf(p, i) {
  const moves = p.loop ? p.keyframes.length : p.keyframes.length - 1;
  let at = 0;
  for (let k = 0; k < i; k++) at += (p.keyframes[k].hold ?? 0) + (k < moves ? p.keyframes[k].move ?? 0.6 : 0);
  return Math.min((at + 1e-6) / cycleSeconds(p), 0.999999);
}

let body = '';
patterns.forEach((p, index) => {
  const placed = placeKeyframes(p);
  const place = placeFixture(p, placed);
  const options = { scheme: 'light', implement: p.implement, fixture: p.fixture, fixturePlace: place, ball: p.ball, prosthetic: p.prosthetic, wear: p.wear };
  const frames = stillsFor(p).map((i) => frameAt(p, positionOf(p, i), placed));
  const boxes = frames.map((s) => sceneShapes(s, options).filter((sh) => sh.depth > -1e5 && !sh.isBall).flatMap((sh) => sh.points));
  const all = boxes.flat();
  const xs = all.map((q) => q[0]), ys = all.map((q) => q[1]);
  const minY = Math.min(...ys) - 4, maxY = Math.max(4, Math.max(...ys)) + 4;
  // A movement that travels with nothing standing on the ground: each still centred on the athlete (RigFraming in the app).
  const spans = boxes.map((b) => [Math.min(...b.map((q) => q[0])), Math.max(...b.map((q) => q[0]))]);
  const widest = Math.max(...spans.map(([lo, hi]) => hi - lo)), centres = spans.map(([lo, hi]) => (lo + hi) / 2);
  const travels = !p.fixture && !p.cast && Math.max(...centres) - Math.min(...centres) > widest * 0.5;
  const span = (f) => (travels ? [centres[f] - widest / 2 - 4, centres[f] + widest / 2 + 4] : [Math.min(...xs) - 4, Math.max(...xs) + 4]);
  const k = Math.min((cellW - 8) / (span(0)[1] - span(0)[0]), (cellH - 26) / (maxY - minY));
  const row = Math.floor(index / columns), col0 = (index % columns) * SLOTS;
  frames.forEach((s, f) => {
    const x0 = (col0 + f) * cellW + (index % columns) * 8, y0 = row * cellH, [minX, maxX] = span(f);
    body += `<rect x="${x0 + 1}" y="${y0 + 1}" width="${cellW - 2}" height="${cellH - 2}" rx="8" fill="#f4f4f6"/>`;
    const tx = x0 + 4 - minX * k + ((cellW - 8) - (maxX - minX) * k) / 2, ty = y0 + 20 - minY * k;
    const clip = `c${index}_${f}`;
    body += `<clipPath id="${clip}"><rect x="${x0 + 1}" y="${y0 + 1}" width="${cellW - 2}" height="${cellH - 2}" rx="8"/></clipPath><g clip-path="url(#${clip})"><g transform="translate(${tx},${ty}) scale(${k})">`;
    for (const sh of sceneShapes(s, options)) {
      if (sh.points.length < 2) continue;
      const d = `M${sh.points.map((q) => `${q[0].toFixed(2)},${q[1].toFixed(2)}`).join(' L')} Z`;
      body += `<path d="${d}" fill="${sh.fill === 'none' ? 'none' : sh.fill}"${sh.opacity != null ? ` fill-opacity="${sh.opacity.toFixed(2)}"` : ''}${sh.stroke ? ` stroke="${sh.stroke}" stroke-width="${sh.width ?? 1}"` : ''}/>`;
    }
    if (p.fixture?.kind !== 'water') body += `<line x1="${minX}" y1="0" x2="${maxX}" y2="0" stroke="#c9c9d0" stroke-width="${1.2 / k}"/>`;
    body += '</g></g>';
    if (f === 0) body += `<text x="${x0 + 6}" y="${y0 + 13}" font-family="Helvetica" font-size="9" fill="#555">${p.slug.slice(0, 30)}</text>`;
  });
});
const width = columns * (SLOTS * cellW + 8), height = Math.ceil(patterns.length / columns) * cellH;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="#fff"/>${body}</svg>`;
fs.writeFileSync(out.replace(/\.png$/, '.svg'), svg);
execFileSync('rsvg-convert', ['-o', out, out.replace(/\.png$/, '.svg')]);
console.log(`wrote ${out} (${patterns.length} patterns)`);
