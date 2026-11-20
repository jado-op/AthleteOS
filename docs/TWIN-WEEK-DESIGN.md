# "Your last 7 days": design notes (owner, 2026-11-20)

The owner's idea: tap the twin, see the last 7 days — the body in the middle,
coloured by how hard each muscle group worked, Apple Health's numbers around
it. Ask: "make it look expensive and not AI". Code: `TwinWeek.swift` (rules,
harness), `TwinWeekView.swift`, `MuscleTraining.week`, `HeatScale` in
`TrainingBodyView.swift`. Mockup: the claude.ai design canvas "Twin: Your last 7 days".

## Which build
- A 2D front/back body map is the established pattern for per-muscle load
  (Fitbod's muscle recovery map, BodyAtlas, MuscleMap); 3D models add weight
  and gimmick, not information. We keep our anatomy paths, one side at a time,
  with a Front / Back switch.
- Colour = effort, not just volume: per group Σ (sets that worked it × the
  session's 0–10 effort) over 7 days. Light < 12, solid 12–35, very hard ≥ 35
  (`MuscleTraining.band(forLoad:)`). Health workouts count through the
  athlete's answer (band → effort 3 / 5 / 8; sets 2 / 3 / 5 per group).
- Tap a muscle: its band, hard sets, days, average effort, what worked it,
  when it's ready again. Tap a number: its seven days.

## Expensive, not AI
- Restraint: black, one accent, hairlines, generous space, big light numbers
  with tabular digits. No boxes around every number, no glow everywhere, no
  gradient washes, no glassmorphism, no emoji — the patterns that read as
  generated.
- Numbers are product-style callouts (label, value, unit, change) joined to
  the body by 0.75 pt hairlines with a bend, ending in a small ring.
- Motion only when something happens: lines draw in once, callouts fade up
  in sequence, the body turns when Front/Back changes; haptic on each pick.
  No perpetual floating. Reduce Motion: no animation.

## The heat scale
- One hue whose lightness rises with effort: rested graphite #2A2A30 →
  light deep ember #7C2D12 → solid ember #EA6A1F → very hard peach #FFC08A.
  Sequential data wants monotonic lightness, not a rainbow: readable in grey
  and for colour-blind athletes; no red–green.

## Sources
- Premium feel through restraint and type: 1000logos "What makes an app feel
  expensive"; mantlr "Stripe, Linear, Vercel premium UI"; Lickability "Plussing
  your iOS app".
- Muscle maps: Fitbod "Muscle recovery" (fitbod.me/blog/muscle-recovery);
  BodyAtlas and MuscleMap (App Store).
- Colour scales: matplotlib colormap guide; CMasher (arXiv 2003.01069);
  Crameri et al., "The misuse of colour in science communication" (PMC7595127).
