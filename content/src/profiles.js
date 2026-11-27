/**
 * V6 exercise knowledge base (docs/VERSION-6.md §10): what each exercise IS
 * for the planner — its movement pattern, its role in a session, how much
 * it costs — so sessions are built by purpose, not by keyword.
 *
 * Every base exercise in the core library is tagged by hand below. Variants
 * (tempo, unilateral, equipment tiers) inherit their base's profile; sport
 * drills, which are skill work first, get a rule-based profile from their
 * qualities.
 *
 *   pattern     squat · hinge · push · pull · carry · rotation · anti-rotation ·
 *               unilateral-lower · jump · throw · sprint · deceleration ·
 *               change-of-direction · locomotion · conditioning · mobility ·
 *               isolation · balance · breathing · skill
 *   role        where it goes in a session: prep · power · speed · primary ·
 *               secondary · accessory · trunk · conditioning · mobility ·
 *               recovery · skill
 *   regions     l (lower body) · u (upper body) · t (trunk)
 *   fatigue     1 (barely any) … 5 (a hard, heavy compound or a hard interval set)
 *   impact      0 none · 1 low · 2 moderate (running) · 3 high (jumps, max sprints)
 *   technique   1 simple · 2 needs practice · 3 needs coaching
 *   legLoad     0 … 3: how much it adds to leg fatigue (the after-practice budget)
 *   group       replacement group: exercises that can stand in for each other
 *   conditioning (conditioning items only) { type, modality }
 *
 * What each exercise TRAINS (docs/TRAINING-RESEARCH.md §2) — the second table:
 *
 *   quality     the main physical quality it develops (TRAINING_QUALITIES):
 *               max-strength · strength-speed (heavy and fast: cleans, loaded
 *               jumps) · speed-strength (light and fast: jumps, throws) ·
 *               reactive (short ground contacts, the stretch-shortening cycle) ·
 *               acceleration · max-velocity · change-of-direction · deceleration
 *               (braking and landing) · hypertrophy · strength-endurance ·
 *               aerobic · anaerobic · repeated-sprint · mobility · stability ·
 *               injury-prevention · recovery
 *   energy      the energy system that pays for it (after "/"): alactic
 *               (phosphocreatine, ≤ ~10 s all-out) · glycolytic · aerobic ·
 *               mixed (repeated efforts). Derived from the quality when left out.
 *   muscles     primary | secondary, in the FOCUS_MUSCLES vocabulary below —
 *               each name is a set of the anatomical muscles in muscles.js, so
 *               the body map, the Library's muscle filter and the planner
 *               speak about the same muscles. Checked against every item's own
 *               weighted muscle map (test/profiles.test.js).
 */

// slug: pattern role regions fatigue impact technique legLoad group
const TABLE = `
acceleration-wall-drill: sprint prep l 1 1 1 1 sprint-accel-drill
acceleration-march: locomotion prep l 1 1 1 1 sprint-accel-drill
sled-push: sprint speed l 3 1 1 3 sprint-accel-resisted
flying-sprint: sprint speed l 3 3 2 2 sprint-maxv
lateral-shuffle-cone-drill: change-of-direction speed l 2 2 1 2 cod
5-10-5-shuttle: change-of-direction speed l 3 2 1 2 cod
lateral-bound: jump power l 2 3 2 2 jump-lateral
deceleration-drop-stick: deceleration power l 2 2 1 2 decel
countermovement-jump: jump power l 2 3 1 2 jump-vertical
weighted-jump-squat: jump power l 3 3 2 2 jump-vertical
broad-jump: jump power l 2 3 1 2 jump-horizontal
rotational-step-through-throw: throw power ut 1 0 1 0 throw-rotational
med-ball-rotational-throw: throw power ut 2 0 1 0 throw-rotational
explosive-wall-reach-jump: jump power lu 2 3 1 2 jump-vertical
med-ball-overhead-throw: throw power ut 2 0 1 0 throw-overhead
pogo-hop: jump power l 1 3 1 1 reactive-hop
trap-bar-deadlift: hinge primary lt 5 0 2 3 hinge-bilateral
goblet-squat: squat primary lt 3 0 1 2 squat-bilateral
barbell-back-squat: squat primary lt 5 0 3 3 squat-bilateral
bulgarian-split-squat: unilateral-lower primary l 4 0 2 3 single-leg-knee
split-squat: unilateral-lower secondary l 2 0 1 2 single-leg-knee
nordic-hamstring-curl: hinge accessory l 3 0 2 2 hamstring-eccentric
bodyweight-squat: squat secondary l 1 0 1 1 squat-bilateral
push-up: push primary ut 2 0 1 0 push-horizontal
bench-press: push primary u 4 0 2 0 push-horizontal
incline-push-up: push secondary u 1 0 1 0 push-horizontal
pull-up: pull primary u 3 0 2 0 pull-vertical
band-assisted-pull-up: pull primary u 2 0 1 0 pull-vertical
inverted-row: pull primary ut 2 0 1 0 pull-horizontal
prone-y-t-w-raise: isolation accessory u 1 0 1 0 shoulder-health
band-pull-apart: isolation accessory u 1 0 1 0 shoulder-health
plank-shoulder-tap: anti-rotation trunk tu 1 0 1 0 anti-rotation
pallof-press: anti-rotation trunk t 1 0 1 0 anti-rotation
bear-crawl-hold: anti-rotation trunk tu 1 0 1 0 anti-extension
farmers-carry: carry accessory lut 3 0 1 1 carry
continuous-easy-run: conditioning conditioning l 2 2 1 2 conditioning-aerobic
hill-sprint-repeats: sprint conditioning l 4 2 1 3 conditioning-anaerobic
shuttle-repeat-sprints: conditioning conditioning l 4 2 1 3 conditioning-rsa
tempo-run: conditioning conditioning l 3 2 1 2 conditioning-tempo
single-leg-balance-reach: balance accessory l 1 0 1 1 balance
single-leg-rdl: hinge secondary l 2 0 2 1 single-leg-hip
90-90-hip-switch: mobility mobility l 1 0 1 0 mobility-hip
mobility-flow-series: mobility mobility lut 1 0 1 0 mobility-flow
scapular-wall-slide: isolation prep u 1 0 1 0 shoulder-health
single-leg-ankle-hop: jump power l 1 3 1 1 reactive-hop
drop-landing-stick: deceleration power l 1 2 1 1 landing
shadow-cutting-drill: change-of-direction speed l 2 2 1 2 cod
in-place-suicide-sprints: conditioning conditioning l 3 2 1 2 conditioning-rsa
a-skip: locomotion prep l 1 1 1 1 sprint-mechanics
b-skip: locomotion prep l 1 1 2 1 sprint-mechanics
straight-leg-bound: sprint speed l 2 3 2 2 sprint-maxv
falling-start: sprint speed l 2 2 1 2 sprint-accel
sprint-from-push-up-start: sprint speed l 2 2 1 2 sprint-accel
resisted-band-sprint: sprint speed l 3 2 1 2 sprint-accel-resisted
wicket-runs: sprint speed l 2 2 2 2 sprint-maxv
build-up-strides: sprint prep l 1 2 1 1 sprint-mechanics
hill-bounds: jump power l 3 3 2 3 jump-horizontal
t-drill: change-of-direction speed l 2 2 1 2 cod
l-drill: change-of-direction speed l 2 2 1 2 cod
pro-agility-plant-hold: deceleration power l 2 2 1 2 decel
reactive-mirror-drill: change-of-direction speed l 2 2 1 2 cod
crossover-run-drill: change-of-direction speed l 2 2 2 2 cod
backpedal-to-sprint: change-of-direction speed l 2 2 1 2 cod
eccentric-step-down: unilateral-lower accessory l 2 0 1 1 single-leg-knee
box-jump: jump power l 2 2 1 2 jump-vertical
depth-jump: jump power l 3 3 3 2 reactive-hop
tuck-jump: jump power l 2 3 1 2 jump-vertical
hurdle-hops: jump power l 2 3 2 2 reactive-hop
skater-hops: jump power l 2 3 1 2 jump-lateral
single-leg-hop-and-hold: deceleration power l 2 3 2 2 landing
split-squat-jump: jump power l 3 3 2 2 jump-vertical
lateral-line-hops: jump prep l 1 2 1 1 reactive-hop
jump-rope-intervals: conditioning conditioning l 2 2 1 1 conditioning-interval
broad-jump-to-sprint: jump power l 3 3 2 2 jump-horizontal
med-ball-scoop-toss: throw power lut 2 0 1 1 throw-rotational
med-ball-shotput-throw: throw power ut 2 0 1 0 throw-rotational
med-ball-slam: throw power ut 2 0 1 1 throw-overhead
med-ball-chest-pass: throw power u 1 0 1 0 throw-chest
band-woodchop: rotation trunk t 1 0 1 0 rotation
landmine-rotation: rotation trunk tu 2 0 2 1 rotation
barbell-front-squat: squat primary lt 5 0 3 3 squat-bilateral
romanian-deadlift: hinge primary lt 4 0 2 3 hinge-bilateral
hip-thrust: hinge secondary l 3 0 1 2 hinge-hip-extension
step-up: unilateral-lower secondary l 3 0 1 2 single-leg-knee
reverse-lunge: unilateral-lower secondary l 3 0 1 2 single-leg-knee
lateral-lunge: unilateral-lower secondary l 2 0 1 2 single-leg-lateral
cossack-squat: unilateral-lower mobility l 1 0 2 1 single-leg-lateral
wall-sit: squat accessory l 2 0 1 2 knee-isometric
spanish-squat: squat accessory l 2 0 1 2 knee-isometric
sissy-squat-assisted: squat accessory l 2 0 2 2 knee-isometric
hamstring-slider-curl: hinge accessory l 2 0 1 2 hamstring-eccentric
leg-curl-machine: isolation accessory l 2 0 1 1 hamstring-eccentric
kettlebell-swing: hinge power l 3 0 2 2 hinge-ballistic
single-leg-glute-bridge: hinge accessory l 1 0 1 1 hinge-hip-extension
dumbbell-bench-press: push primary u 3 0 1 0 push-horizontal
overhead-press-dumbbell: push primary ut 3 0 1 0 push-vertical
landmine-press: push secondary ut 2 0 1 0 push-vertical
dips-parallel: push secondary u 3 0 2 0 push-vertical
pike-push-up: push secondary u 2 0 1 0 push-vertical
plyo-push-up: push power u 2 0 2 0 throw-chest
tempo-push-up: push secondary ut 2 0 1 0 push-horizontal
dumbbell-row: pull primary u 2 0 1 0 pull-horizontal
lat-pulldown: pull primary u 2 0 1 0 pull-vertical
chin-up: pull primary u 3 0 2 0 pull-vertical
seated-cable-row: pull primary u 2 0 1 0 pull-horizontal
face-pull: isolation accessory u 1 0 1 0 shoulder-health
towel-row: pull secondary u 2 0 1 0 pull-horizontal
scap-pull-up: pull accessory u 1 0 1 0 shoulder-health
band-external-rotation: isolation accessory u 1 0 1 0 shoulder-health
sleeper-stretch: mobility mobility u 1 0 1 0 mobility-shoulder
serratus-wall-slide: isolation prep u 1 0 1 0 shoulder-health
prone-i-raise: isolation accessory u 1 0 1 0 shoulder-health
dumbbell-curl: isolation accessory u 1 0 1 0 arm-isolation
triceps-extension-band: isolation accessory u 1 0 1 0 arm-isolation
dead-hang: carry accessory u 1 0 1 0 grip
suitcase-carry: carry trunk tlu 2 0 1 1 carry
overhead-carry: carry trunk tu 2 0 1 1 carry
plate-pinch: isolation accessory u 1 0 1 0 grip
wrist-roller: isolation accessory u 1 0 1 0 grip
band-wrist-extension: isolation accessory u 1 0 1 0 grip
dead-bug: anti-rotation trunk t 1 0 1 0 anti-extension
bird-dog: anti-rotation trunk t 1 0 1 0 anti-rotation
side-plank: anti-rotation trunk t 1 0 1 0 anti-lateral
hollow-hold: anti-rotation trunk t 1 0 1 0 anti-extension
ab-wheel-rollout: anti-rotation trunk tu 2 0 2 0 anti-extension
half-kneeling-chop: rotation trunk t 1 0 1 0 rotation
hanging-knee-raise: anti-rotation trunk tu 2 0 1 0 anti-extension
stir-the-pot: anti-rotation trunk t 2 0 1 0 anti-extension
sit-up: isolation trunk t 1 0 1 0 trunk-flexion
back-extension: hinge accessory lt 2 0 1 1 hinge-hip-extension
superman-hold: hinge trunk t 1 0 1 0 back-extension
copenhagen-plank: anti-rotation accessory lt 2 0 2 1 hip-adductor
adductor-squeeze: isolation accessory l 1 0 1 0 hip-adductor
tibialis-raise: isolation accessory l 1 0 1 1 calf-ankle
standing-calf-raise: isolation accessory l 1 0 1 1 calf-ankle
bent-knee-calf-raise: isolation accessory l 1 0 1 1 calf-ankle
ankle-alphabet: mobility recovery l 1 0 1 0 mobility-ankle
short-foot-drill: balance accessory l 1 0 1 0 foot
towel-toe-curls: isolation recovery l 1 0 1 0 foot
single-leg-balance-eyes-closed: balance accessory l 1 0 1 1 balance
star-excursion-reach: balance accessory l 1 0 1 1 balance
lateral-band-walk: locomotion prep l 1 0 1 1 hip-activation
clamshell: isolation prep l 1 0 1 0 hip-activation
reverse-nordic: squat accessory l 2 0 2 2 knee-eccentric
neck-isometrics: isolation accessory u 1 0 1 0 neck
band-neck-extension: isolation accessory u 1 0 1 0 neck
chin-tuck: isolation recovery u 1 0 1 0 neck
worlds-greatest-stretch: mobility prep lut 1 0 1 0 mobility-flow
couch-stretch: mobility mobility l 1 0 1 0 mobility-hip
deep-squat-hold: mobility mobility l 1 0 1 0 mobility-hip
pigeon-stretch: mobility mobility l 1 0 1 0 mobility-hip
hamstring-floss: mobility mobility l 1 0 1 0 mobility-hamstring
thoracic-open-book: mobility mobility tu 1 0 1 0 mobility-thoracic
cat-camel: mobility recovery t 1 0 1 0 mobility-spine
ankle-knee-to-wall: mobility prep l 1 0 1 0 mobility-ankle
foam-roll-quads-calves: mobility recovery l 1 0 1 0 soft-tissue
hip-circles-standing: mobility prep l 1 0 1 0 mobility-hip
shoulder-dislocates-band: mobility prep u 1 0 1 0 mobility-shoulder
bike-intervals: conditioning conditioning l 4 0 1 2 conditioning-interval
easy-bike-ride: conditioning conditioning l 1 0 1 1 conditioning-aerobic
burpee: conditioning conditioning lut 3 2 1 2 conditioning-interval
mountain-climbers: conditioning conditioning lt 2 1 1 1 conditioning-interval
30-15-intermittent-run: conditioning conditioning l 4 2 1 2 conditioning-rsa
fartlek-run: conditioning conditioning l 3 2 1 2 conditioning-aerobic
sled-drag-backward: locomotion conditioning l 2 0 1 2 conditioning-sled
battle-rope-waves: conditioning conditioning ut 3 0 1 0 conditioning-upper
stair-runs: conditioning conditioning l 3 2 1 3 conditioning-anaerobic
rowing-machine-intervals: conditioning conditioning lut 4 0 2 2 conditioning-interval
hang-power-clean: hinge power lut 4 0 3 2 olympic
clean-pull-dumbbell: hinge power lu 2 0 2 1 olympic
push-press: push power ult 3 0 2 1 push-vertical-power
barbell-bent-over-row: pull primary ut 3 0 2 1 pull-horizontal
barbell-deadlift: hinge primary lt 5 0 3 3 hinge-bilateral
barbell-overhead-squat-pvc: mobility prep lut 1 0 2 0 mobility-flow
lateral-box-jump: jump power l 2 2 1 2 jump-lateral
single-leg-box-jump: jump power l 2 2 2 2 jump-vertical
triple-broad-jump: jump power l 3 3 2 2 jump-horizontal
medball-overhead-backward-toss: throw power lut 2 0 1 1 throw-overhead
medball-side-toss-lateral-step: throw power lut 2 0 1 1 throw-rotational
dumbbell-snatch-single-arm: hinge power lut 3 0 2 1 olympic
repeat-shuttle-10m: conditioning conditioning l 3 2 1 2 conditioning-rsa
tempo-200s: conditioning conditioning l 3 2 1 2 conditioning-tempo
long-easy-run: conditioning conditioning l 2 2 1 2 conditioning-aerobic
box-step-over-conditioning: conditioning conditioning l 2 1 1 2 conditioning-interval
goblet-lateral-squat: unilateral-lower secondary l 2 0 1 2 single-leg-lateral
split-squat-bottom-hold: unilateral-lower accessory l 2 0 1 2 knee-isometric
kickstand-rdl: hinge secondary l 2 0 1 2 single-leg-hip
inverted-row-feet-elevated: pull primary ut 2 0 1 0 pull-horizontal
push-up-plus: push accessory u 1 0 1 0 shoulder-health
bear-crawl-forward: locomotion prep lut 1 0 1 1 crawl
turkish-get-up: carry trunk lut 2 0 2 1 get-up
pallof-hold-split-stance: anti-rotation trunk t 1 0 1 0 anti-rotation
farmers-march: carry trunk lt 2 0 1 1 carry
nordic-assisted-band: hinge accessory l 2 0 1 2 hamstring-eccentric
hip-airplane: balance accessory l 1 0 2 1 balance
lateral-hop-to-stick: deceleration power l 2 2 1 2 landing
drop-squat: deceleration power l 2 1 1 2 decel
sprint-arm-drill: sprint prep u 1 0 1 0 sprint-mechanics
curtsy-lunge: unilateral-lower secondary l 2 0 1 2 single-leg-lateral
dumbbell-incline-press: push primary u 3 0 1 0 push-incline
reverse-fly-dumbbell: isolation accessory u 1 0 1 0 shoulder-health
breathing-90-90: breathing recovery t 1 0 1 0 breathing
`;

const CONDITIONING = {
  'continuous-easy-run': ['aerobic-base', 'run'],
  'long-easy-run': ['aerobic-base', 'run'],
  'fartlek-run': ['aerobic-base', 'run'],
  'tempo-run': ['tempo', 'run'],
  'tempo-200s': ['tempo', 'run'],
  '30-15-intermittent-run': ['aerobic-power', 'run'],
  'bike-intervals': ['aerobic-power', 'bike'],
  'easy-bike-ride': ['aerobic-base', 'bike'],
  'rowing-machine-intervals': ['aerobic-power', 'row'],
  'jump-rope-intervals': ['aerobic-power', 'rope'],
  'box-step-over-conditioning': ['aerobic-power', 'bodyweight'],
  'burpee': ['anaerobic', 'bodyweight'],
  'mountain-climbers': ['anaerobic', 'bodyweight'],
  'battle-rope-waves': ['anaerobic', 'rope'],
  'stair-runs': ['anaerobic', 'stairs'],
  'hill-sprint-repeats': ['repeated-sprint', 'run'],
  'shuttle-repeat-sprints': ['repeated-sprint', 'run'],
  'in-place-suicide-sprints': ['repeated-sprint', 'run'],
  'repeat-shuttle-10m': ['repeated-sprint', 'run'],
  'sled-drag-backward': ['tempo', 'sled'],
};

/**
 * The muscle words the planner and the Workout tab use: the names a coach
 * says ("glutes", "lats"), each one a set of the anatomical muscles in
 * muscles.js. Order is head to toe, for display.
 */
export const FOCUS_MUSCLES = {
  neck: ['sternocleidomastoid', 'neck-extensors'],
  traps: ['trapezius-upper', 'levator-scapulae'],
  'front-delts': ['deltoid-anterior'],
  'side-delts': ['deltoid-lateral'],
  'rear-delts': ['deltoid-posterior'],
  'rotator-cuff': ['supraspinatus', 'infraspinatus', 'subscapularis', 'teres-minor'],
  chest: ['pectoralis-major', 'pectoralis-minor'],
  serratus: ['serratus-anterior'],
  lats: ['latissimus-dorsi', 'teres-major'],
  'upper-back': ['trapezius-middle', 'trapezius-lower', 'rhomboids'],
  biceps: ['biceps-brachii', 'brachialis'],
  triceps: ['triceps-brachii'],
  forearms: ['forearm-flexors', 'forearm-extensors', 'brachioradialis'],
  abs: ['rectus-abdominis', 'transverse-abdominis'],
  obliques: ['obliques-external', 'obliques-internal'],
  'lower-back': ['erector-spinae', 'quadratus-lumborum', 'multifidus'],
  glutes: ['gluteus-maximus', 'deep-hip-rotators'],
  'glute-med': ['gluteus-medius', 'gluteus-minimus', 'tensor-fasciae-latae'],
  'hip-flexors': ['iliopsoas', 'sartorius'],
  adductors: ['adductors'],
  quads: ['rectus-femoris', 'vastus-lateralis', 'vastus-medialis'],
  hamstrings: ['biceps-femoris', 'semitendinosus', 'semimembranosus'],
  calves: ['gastrocnemius', 'soleus', 'peroneals'],
  shins: ['tibialis-anterior'],
  feet: ['foot-intrinsics'],
};
export const FOCUS_NAMES = Object.keys(FOCUS_MUSCLES);
const FOCUS_OF_MUSCLE = new Map(Object.entries(FOCUS_MUSCLES).flatMap(([focus, slugs]) => slugs.map((m) => [m, focus])));
/** The focus name an anatomical muscle belongs to. */
export const focusOf = (muscle) => FOCUS_OF_MUSCLE.get(muscle);

export const TRAINING_QUALITIES = ['max-strength', 'strength-speed', 'speed-strength', 'reactive', 'acceleration', 'max-velocity',
  'change-of-direction', 'deceleration', 'hypertrophy', 'strength-endurance', 'aerobic', 'anaerobic', 'repeated-sprint',
  'mobility', 'stability', 'injury-prevention', 'recovery'];
export const ENERGY_SYSTEMS = ['alactic', 'glycolytic', 'aerobic', 'mixed'];

/** The energy system a quality runs on when the table doesn't say. */
const DEFAULT_ENERGY = {
  'strength-speed': 'alactic', 'speed-strength': 'alactic', reactive: 'alactic', acceleration: 'alactic', 'max-velocity': 'alactic',
  'change-of-direction': 'alactic', deceleration: 'alactic', aerobic: 'aerobic', anaerobic: 'glycolytic', 'repeated-sprint': 'mixed',
};

// slug: quality[/energy] | primary muscles | secondary muscles ("-": none)
const TRAINS = `
acceleration-wall-drill: acceleration/alactic | glutes calves | hip-flexors quads abs
acceleration-march: acceleration/alactic | glutes calves | hip-flexors quads
sled-push: acceleration/alactic | glutes quads | calves hamstrings abs
flying-sprint: max-velocity/alactic | hamstrings glutes calves | hip-flexors quads
lateral-shuffle-cone-drill: change-of-direction/alactic | glute-med adductors quads | calves glutes
5-10-5-shuttle: change-of-direction/alactic | glute-med quads | glutes adductors calves
lateral-bound: speed-strength/alactic | glute-med glutes quads | adductors calves
deceleration-drop-stick: deceleration/alactic | quads glutes | hamstrings glute-med calves
countermovement-jump: speed-strength/alactic | glutes quads calves | hamstrings
weighted-jump-squat: strength-speed/alactic | glutes quads | calves hamstrings lower-back
broad-jump: speed-strength/alactic | glutes hamstrings quads | calves
rotational-step-through-throw: speed-strength/alactic | obliques glutes | abs chest front-delts
med-ball-rotational-throw: speed-strength/alactic | obliques glutes | abs chest adductors
explosive-wall-reach-jump: speed-strength/alactic | glutes quads front-delts | calves
med-ball-overhead-throw: speed-strength/alactic | front-delts abs | lats glutes triceps
pogo-hop: reactive/alactic | calves | shins quads feet
trap-bar-deadlift: max-strength | glutes quads lower-back | hamstrings forearms traps
goblet-squat: max-strength | quads glutes | adductors abs upper-back
barbell-back-squat: max-strength | quads glutes | adductors lower-back abs
bulgarian-split-squat: max-strength | quads glutes | glute-med adductors hip-flexors
split-squat: max-strength | quads glutes | glute-med adductors
nordic-hamstring-curl: injury-prevention | hamstrings | calves glutes
bodyweight-squat: strength-endurance | quads glutes | adductors
push-up: max-strength | chest triceps | front-delts abs serratus
bench-press: max-strength | chest triceps front-delts | lats
incline-push-up: strength-endurance | chest triceps | front-delts abs
pull-up: max-strength | lats biceps | upper-back forearms abs
band-assisted-pull-up: max-strength | lats biceps | upper-back forearms
inverted-row: max-strength | lats upper-back | biceps rear-delts abs
prone-y-t-w-raise: injury-prevention | upper-back rear-delts | rotator-cuff
band-pull-apart: injury-prevention | upper-back rear-delts | rotator-cuff
plank-shoulder-tap: stability | abs obliques | front-delts serratus
pallof-press: stability | obliques abs | glutes
bear-crawl-hold: stability | abs front-delts | forearms quads serratus
farmers-carry: strength-endurance | forearms traps abs | obliques glutes
continuous-easy-run: aerobic/aerobic | calves hamstrings glutes | quads
hill-sprint-repeats: anaerobic/glycolytic | glutes hamstrings calves | quads
shuttle-repeat-sprints: repeated-sprint/mixed | glutes hamstrings calves | quads adductors
tempo-run: aerobic/aerobic | hamstrings calves glutes | quads
single-leg-balance-reach: stability | glute-med feet | glutes calves
single-leg-rdl: max-strength | hamstrings glutes | glute-med lower-back feet
90-90-hip-switch: mobility | glutes adductors glute-med | hip-flexors
mobility-flow-series: mobility | hip-flexors adductors | calves hamstrings
scapular-wall-slide: injury-prevention | upper-back serratus | rotator-cuff
single-leg-ankle-hop: reactive/alactic | calves | feet glute-med
drop-landing-stick: deceleration/alactic | quads glutes | hamstrings glute-med
shadow-cutting-drill: change-of-direction/alactic | glute-med quads | adductors glutes calves
in-place-suicide-sprints: repeated-sprint/mixed | glutes hamstrings calves | quads
a-skip: max-velocity/alactic | hip-flexors calves | glutes
b-skip: max-velocity/alactic | hamstrings hip-flexors | calves glutes
straight-leg-bound: max-velocity/alactic | hamstrings calves | glutes
falling-start: acceleration/alactic | glutes quads | calves hamstrings
sprint-from-push-up-start: acceleration/alactic | glutes quads | calves chest
resisted-band-sprint: acceleration/alactic | glutes quads calves | hamstrings
wicket-runs: max-velocity/alactic | hamstrings hip-flexors calves | glutes
build-up-strides: max-velocity/aerobic | hamstrings calves glutes | hip-flexors
hill-bounds: speed-strength/alactic | glutes quads | calves hamstrings
t-drill: change-of-direction/alactic | glute-med adductors quads | calves glutes
l-drill: change-of-direction/alactic | quads glute-med | calves adductors
pro-agility-plant-hold: deceleration/alactic | quads glute-med | glutes adductors
reactive-mirror-drill: change-of-direction/alactic | glute-med adductors | calves quads
crossover-run-drill: change-of-direction/alactic | glute-med adductors | obliques hip-flexors
backpedal-to-sprint: change-of-direction/alactic | quads glutes | hamstrings calves
eccentric-step-down: injury-prevention | quads | glute-med hip-flexors
box-jump: speed-strength/alactic | glutes quads | calves
depth-jump: reactive/alactic | calves quads | glutes
tuck-jump: reactive/alactic | hip-flexors calves | abs quads
hurdle-hops: reactive/alactic | calves | quads glutes
skater-hops: speed-strength/alactic | glute-med glutes | adductors quads
single-leg-hop-and-hold: deceleration/alactic | glute-med quads | calves glutes
split-squat-jump: speed-strength/alactic | glutes quads | hip-flexors calves
lateral-line-hops: reactive/alactic | calves | glute-med
jump-rope-intervals: aerobic/mixed | calves | forearms shins
broad-jump-to-sprint: speed-strength/alactic | glutes quads | calves hamstrings
med-ball-scoop-toss: speed-strength/alactic | obliques glutes | hamstrings lower-back
med-ball-shotput-throw: speed-strength/alactic | chest triceps obliques | front-delts glutes
med-ball-slam: speed-strength/alactic | lats abs | triceps
med-ball-chest-pass: speed-strength/alactic | chest triceps | front-delts
band-woodchop: stability | obliques | abs front-delts
landmine-rotation: speed-strength/alactic | obliques | abs front-delts glutes
barbell-front-squat: max-strength | quads glutes | upper-back abs adductors
romanian-deadlift: max-strength | hamstrings glutes | lower-back forearms
hip-thrust: max-strength | glutes | hamstrings
step-up: max-strength | glutes quads | glute-med calves
reverse-lunge: max-strength | glutes quads | adductors glute-med
lateral-lunge: max-strength | adductors glute-med | quads glutes
cossack-squat: mobility | adductors | glutes quads
wall-sit: strength-endurance | quads | glutes
spanish-squat: injury-prevention | quads | glutes
sissy-squat-assisted: injury-prevention | quads | hip-flexors
hamstring-slider-curl: injury-prevention | hamstrings | glutes calves
leg-curl-machine: hypertrophy | hamstrings | calves
kettlebell-swing: speed-strength/alactic | glutes hamstrings | lower-back forearms
single-leg-glute-bridge: stability | glutes | glute-med hamstrings
dumbbell-bench-press: max-strength | chest triceps front-delts | rotator-cuff
overhead-press-dumbbell: max-strength | front-delts triceps side-delts | abs traps serratus
landmine-press: max-strength | front-delts serratus | triceps chest abs
dips-parallel: max-strength | triceps chest | front-delts
pike-push-up: strength-endurance | front-delts triceps | traps serratus
plyo-push-up: speed-strength/alactic | chest triceps | front-delts
tempo-push-up: hypertrophy | chest triceps | serratus abs
dumbbell-row: max-strength | lats upper-back | biceps rear-delts
lat-pulldown: max-strength | lats | biceps upper-back
chin-up: max-strength | lats biceps | forearms
seated-cable-row: max-strength | upper-back lats | biceps rear-delts
face-pull: injury-prevention | rear-delts rotator-cuff | upper-back
towel-row: strength-endurance | upper-back forearms | biceps
scap-pull-up: injury-prevention | upper-back | lats
band-external-rotation: injury-prevention | rotator-cuff | rear-delts
sleeper-stretch: mobility | rotator-cuff | rear-delts
serratus-wall-slide: injury-prevention | serratus | upper-back
prone-i-raise: injury-prevention | upper-back | rear-delts
dumbbell-curl: hypertrophy | biceps | forearms
triceps-extension-band: hypertrophy | triceps | forearms
dead-hang: strength-endurance | forearms | lats
suitcase-carry: stability | obliques lower-back forearms | glute-med
overhead-carry: stability | side-delts traps serratus | abs
plate-pinch: strength-endurance | forearms | -
wrist-roller: strength-endurance | forearms | biceps
band-wrist-extension: injury-prevention | forearms | -
dead-bug: stability | abs | hip-flexors
bird-dog: stability | lower-back glutes | abs
side-plank: stability | obliques lower-back | glute-med
hollow-hold: stability | abs | hip-flexors
ab-wheel-rollout: stability | abs | lats serratus
half-kneeling-chop: stability | obliques | glutes
hanging-knee-raise: stability | abs hip-flexors | forearms
sit-up: strength-endurance | abs | hip-flexors obliques
stir-the-pot: stability | abs obliques | serratus
back-extension: strength-endurance | lower-back | glutes hamstrings
superman-hold: stability | lower-back | glutes upper-back
copenhagen-plank: injury-prevention | adductors | obliques glute-med
adductor-squeeze: injury-prevention | adductors | abs
tibialis-raise: injury-prevention | shins | calves
standing-calf-raise: injury-prevention | calves | feet
bent-knee-calf-raise: injury-prevention | calves | -
ankle-alphabet: mobility | shins calves | feet
short-foot-drill: stability | feet | shins
towel-toe-curls: injury-prevention | feet | -
single-leg-balance-eyes-closed: stability | calves glute-med feet | -
star-excursion-reach: stability | glute-med | quads calves
lateral-band-walk: injury-prevention | glute-med | hip-flexors
clamshell: injury-prevention | glute-med | glutes
reverse-nordic: injury-prevention | quads | hip-flexors
neck-isometrics: injury-prevention | neck | traps
band-neck-extension: injury-prevention | neck | traps
chin-tuck: recovery | neck | -
worlds-greatest-stretch: mobility | hip-flexors adductors | obliques hamstrings
couch-stretch: mobility | quads hip-flexors | -
deep-squat-hold: mobility | adductors | glutes calves
pigeon-stretch: mobility | glutes | glute-med
hamstring-floss: mobility | hamstrings | calves
thoracic-open-book: mobility | obliques chest | upper-back
cat-camel: recovery | lower-back | abs
ankle-knee-to-wall: mobility | calves | shins
foam-roll-quads-calves: recovery | quads calves | -
hip-circles-standing: mobility | hip-flexors glute-med | adductors
shoulder-dislocates-band: mobility | front-delts chest | upper-back
bike-intervals: aerobic/mixed | quads glutes | calves
easy-bike-ride: aerobic/aerobic | quads | glutes calves
burpee: anaerobic/glycolytic | quads chest glutes | triceps abs
mountain-climbers: anaerobic/glycolytic | hip-flexors abs | front-delts
30-15-intermittent-run: aerobic/mixed | calves hamstrings quads | glutes
fartlek-run: aerobic/aerobic | calves quads hamstrings | glutes
sled-drag-backward: aerobic/aerobic | quads | calves glutes
battle-rope-waves: anaerobic/glycolytic | front-delts forearms | abs side-delts
stair-runs: anaerobic/glycolytic | glutes quads | calves
rowing-machine-intervals: aerobic/mixed | lats quads | lower-back glutes biceps
hang-power-clean: strength-speed/alactic | glutes traps quads | hamstrings lower-back calves
clean-pull-dumbbell: speed-strength/alactic | traps glutes | side-delts hamstrings
push-press: strength-speed/alactic | front-delts triceps | quads glutes abs
barbell-bent-over-row: max-strength | lats upper-back | lower-back biceps
barbell-deadlift: max-strength | glutes hamstrings lower-back | quads forearms traps
barbell-overhead-squat-pvc: mobility | upper-back front-delts | glutes quads
lateral-box-jump: speed-strength/alactic | glute-med quads | calves
single-leg-box-jump: speed-strength/alactic | glutes quads calves | glute-med
triple-broad-jump: speed-strength/alactic | glutes quads calves | hamstrings
medball-overhead-backward-toss: speed-strength/alactic | glutes lower-back | front-delts hamstrings
medball-side-toss-lateral-step: speed-strength/alactic | obliques glute-med | glutes
dumbbell-snatch-single-arm: speed-strength/alactic | glutes traps side-delts | hamstrings
repeat-shuttle-10m: repeated-sprint/mixed | quads glutes calves | adductors
tempo-200s: aerobic/aerobic | calves hamstrings | glutes
long-easy-run: aerobic/aerobic | calves | quads
box-step-over-conditioning: aerobic/mixed | glutes quads | calves
goblet-lateral-squat: max-strength | adductors glutes quads | -
split-squat-bottom-hold: strength-endurance | quads glutes | hip-flexors
kickstand-rdl: max-strength | hamstrings glutes | glute-med
inverted-row-feet-elevated: max-strength | upper-back lats | biceps
push-up-plus: injury-prevention | serratus | chest triceps
bear-crawl-forward: stability | front-delts abs | quads
turkish-get-up: stability | front-delts obliques | glutes
pallof-hold-split-stance: stability | obliques | abs
farmers-march: stability | forearms hip-flexors glute-med | -
nordic-assisted-band: injury-prevention | hamstrings | -
hip-airplane: stability | glute-med | glutes
lateral-hop-to-stick: deceleration/alactic | glute-med calves | quads
drop-squat: deceleration/alactic | quads glutes | -
sprint-arm-drill: max-velocity/alactic | front-delts rear-delts | lats
curtsy-lunge: max-strength | glute-med glutes | adductors quads
dumbbell-incline-press: max-strength | chest front-delts | triceps
reverse-fly-dumbbell: injury-prevention | rear-delts | upper-back
breathing-90-90: recovery | abs | -
`;

function parseTrains() {
  const out = new Map();
  for (const line of TRAINS.trim().split('\n')) {
    const [slug, rest] = line.split(':');
    const [head, primary, secondary] = rest.split('|').map((part) => part.trim());
    const [quality, energy] = head.split('/');
    const words = (text) => (text === '-' ? [] : text.split(/\s+/).filter(Boolean));
    out.set(slug.trim(), {
      quality,
      energy: energy ?? DEFAULT_ENERGY[quality],
      muscles: { primary: words(primary), secondary: words(secondary) },
    });
  }
  return out;
}

export const HAND_TRAINS = parseTrains();

/** Item quality → the physical quality it trains (drills and untagged items). */
const QUALITY_TRAINS = {
  acceleration: 'acceleration', 'max-velocity': 'max-velocity', 'change-of-direction': 'change-of-direction',
  'lateral-power': 'change-of-direction', deceleration: 'deceleration', 'landing-mechanics': 'deceleration',
  'vertical-power': 'speed-strength', 'horizontal-power': 'speed-strength', 'rotational-power': 'speed-strength',
  'overhead-power': 'speed-strength', 'reactive-strength': 'reactive', 'ankle-stiffness': 'reactive',
  'lower-body-strength': 'max-strength', 'upper-body-push': 'max-strength', 'upper-body-pull': 'max-strength',
  'trunk-anti-rotation': 'stability', 'single-leg-stability': 'stability', grip: 'strength-endurance',
  'aerobic-base': 'aerobic', 'anaerobic-capacity': 'anaerobic', 'repeat-sprint': 'repeated-sprint',
  'hip-mobility': 'mobility', 'shoulder-stability': 'injury-prevention',
};

/**
 * Primary and secondary muscles from an item's own weighted map: ≥ 0.7 is a
 * main mover, 0.4–0.7 helps; at least one primary.
 */
export function focusFromMuscles(muscles = {}) {
  const best = new Map();
  for (const [slug, weight] of Object.entries(muscles)) {
    const focus = focusOf(slug);
    if (focus) best.set(focus, Math.max(best.get(focus) ?? 0, weight));
  }
  const ranked = [...best.entries()].sort((a, b) => b[1] - a[1] || FOCUS_NAMES.indexOf(a[0]) - FOCUS_NAMES.indexOf(b[0]));
  let primary = ranked.filter(([, w]) => w >= 0.7).map(([f]) => f).slice(0, 3);
  if (primary.length === 0 && ranked.length) primary = [ranked[0][0]];
  const secondary = ranked.filter(([f, w]) => !primary.includes(f) && w >= 0.4).map(([f]) => f).slice(0, 3);
  return { primary, secondary };
}

/** What an item trains when it has no hand row: from its qualities and muscles. */
function derivedTrains(item, profile) {
  const top = Object.entries(item.qualities ?? {}).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0];
  let quality = QUALITY_TRAINS[top] ?? 'stability';
  if (profile.conditioning) {
    quality = { 'aerobic-base': 'aerobic', 'aerobic-power': 'aerobic', tempo: 'aerobic', 'repeated-sprint': 'repeated-sprint', anaerobic: 'anaerobic' }[profile.conditioning.type] ?? quality;
  }
  return { quality, energy: DEFAULT_ENERGY[quality], muscles: focusFromMuscles(item.muscles) };
}

function withTrains(item, profile) {
  const own = HAND_TRAINS.get(item.slug) ?? (item.baseSlug ? HAND_TRAINS.get(item.baseSlug) : undefined);
  const trains = own ?? derivedTrains(item, profile);
  const out = { ...profile, quality: trains.quality, muscles: trains.muscles };
  if (trains.energy) out.energy = trains.energy;
  // An explosive tempo variant trains speed-strength, whatever its base is for.
  if (item.variant?.tempo === 'explosive' && ['max-strength', 'hypertrophy', 'strength-endurance'].includes(out.quality)) {
    out.quality = 'speed-strength';
    out.energy = 'alactic';
  }
  return out;
}

export const PATTERNS = ['squat', 'hinge', 'push', 'pull', 'carry', 'rotation', 'anti-rotation', 'unilateral-lower', 'jump', 'throw', 'sprint',
  'deceleration', 'change-of-direction', 'locomotion', 'conditioning', 'mobility', 'isolation', 'balance', 'breathing', 'skill'];
export const ROLES = ['prep', 'power', 'speed', 'primary', 'secondary', 'accessory', 'trunk', 'conditioning', 'mobility', 'recovery', 'skill'];

function parseTable() {
  const out = new Map();
  for (const line of TABLE.trim().split('\n')) {
    const [slug, rest] = line.split(':');
    const [pattern, role, regions, fatigue, impact, technique, legLoad, group] = rest.trim().split(/\s+/);
    const profile = {
      pattern,
      role,
      regions: [...regions].map((c) => ({ l: 'lower', u: 'upper', t: 'trunk' })[c]),
      fatigue: Number(fatigue),
      impact: Number(impact),
      technique: Number(technique),
      legLoad: Number(legLoad),
      group,
    };
    if (CONDITIONING[slug]) profile.conditioning = { type: CONDITIONING[slug][0], modality: CONDITIONING[slug][1] };
    out.set(slug.trim(), profile);
  }
  return out;
}

export const HAND_PROFILES = parseTable();

const SPEED_Q = ['acceleration', 'max-velocity', 'change-of-direction', 'lateral-power', 'deceleration'];
const POWER_Q = ['vertical-power', 'horizontal-power', 'rotational-power', 'overhead-power', 'reactive-strength'];

/**
 * The profile of one (expanded) catalogue item. Variants take their base's;
 * a tempo variant costs a little more, a unilateral one stays the same.
 */
export function profileFor(item) {
  return withTrains(item, planProfile(item));
}

function planProfile(item) {
  const own = HAND_PROFILES.get(item.slug);
  if (own) return own;
  if (item.baseSlug && HAND_PROFILES.has(item.baseSlug)) {
    const base = HAND_PROFILES.get(item.baseSlug);
    const tempo = item.variant?.axis === 'tempo';
    return { ...base, fatigue: Math.min(5, base.fatigue + (tempo ? 1 : 0)) };
  }
  return derived(item);
}

/** Sport drills (and anything new not yet tagged): from their qualities. */
function derived(item) {
  const q = item.qualities ?? {};
  const top = Object.entries(q).sort((a, b) => b[1] - a[1])[0]?.[0] ?? '';
  const contacts = item.defaultDose?.kind === 'contacts';
  const lowerHeavy = (q['lower-body-strength'] ?? 0) >= 0.7;
  if (item.kind === 'drill') {
    const speedy = SPEED_Q.includes(top) || ['repeat-sprint', 'anaerobic-capacity'].includes(top);
    return {
      pattern: 'skill', role: 'skill',
      regions: lowerHeavy || speedy || contacts ? ['lower'] : ['upper', 'trunk'],
      fatigue: speedy || contacts ? 2 : 1,
      impact: contacts ? 3 : speedy ? 2 : 0,
      technique: 2,
      legLoad: speedy || contacts ? 2 : 1,
      group: `skill-${item.sport ?? 'general'}`,
    };
  }
  if (SPEED_Q.includes(top)) return { pattern: 'sprint', role: 'speed', regions: ['lower'], fatigue: 2, impact: 2, technique: 1, legLoad: 2, group: 'speed' };
  if (POWER_Q.includes(top)) return { pattern: contacts ? 'jump' : 'throw', role: 'power', regions: ['lower'], fatigue: 2, impact: contacts ? 3 : 0, technique: 1, legLoad: contacts ? 2 : 1, group: 'power' };
  if (['aerobic-base', 'anaerobic-capacity', 'repeat-sprint'].includes(top)) {
    return { pattern: 'conditioning', role: 'conditioning', regions: ['lower'], fatigue: 3, impact: 2, technique: 1, legLoad: 2, group: 'conditioning-interval', conditioning: { type: 'aerobic-power', modality: 'run' } };
  }
  if (top === 'hip-mobility') return { pattern: 'mobility', role: 'mobility', regions: ['lower'], fatigue: 1, impact: 0, technique: 1, legLoad: 0, group: 'mobility-hip' };
  if (top === 'trunk-anti-rotation') return { pattern: 'anti-rotation', role: 'trunk', regions: ['trunk'], fatigue: 1, impact: 0, technique: 1, legLoad: 0, group: 'anti-rotation' };
  if (top === 'upper-body-push') return { pattern: 'push', role: 'secondary', regions: ['upper'], fatigue: 2, impact: 0, technique: 1, legLoad: 0, group: 'push-horizontal' };
  if (top === 'upper-body-pull') return { pattern: 'pull', role: 'secondary', regions: ['upper'], fatigue: 2, impact: 0, technique: 1, legLoad: 0, group: 'pull-horizontal' };
  if (top === 'lower-body-strength') return { pattern: 'squat', role: 'secondary', regions: ['lower'], fatigue: 3, impact: 0, technique: 1, legLoad: 2, group: 'squat-bilateral' };
  return { pattern: 'isolation', role: 'accessory', regions: ['lower'], fatigue: 1, impact: 0, technique: 1, legLoad: 1, group: 'accessory' };
}
