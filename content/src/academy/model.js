/**
 * The Academy's building blocks (docs/ACADEMY-PLAN.md): six pillars, the body
 * areas the Digital Twin can light up, which of them matter most per sport,
 * and the legend traits a Legends lesson can unlock. The app reads all of
 * this from the generated AcademyContent.swift — nothing is hard-coded there.
 */

export const PILLARS = ['body', 'fuel', 'recovery', 'mind', 'legends', 'sportIQ'];

/** Knowledge comes from quiz answers, habits from self-reflection. */
export const SIDES = ['knowledge', 'habits'];

/** The phases a lesson can be tagged with ("all" = any time of the year). */
export const PHASES = ['all', 'offSeason', 'preSeason', 'inSeason', 'postSeason'];

/**
 * Regions the twin's body can glow on — the same keys the 3D rig's muscle
 * glow uses (RigMuscleRegion in the app).
 */
export const BODY_AREAS = [
  'thighFront', 'thighBack', 'thigh', 'shinFront', 'shinBack', 'chest', 'abs', 'upperBack', 'lowerBack',
  'glutes', 'shoulderCap', 'upperArmFront', 'upperArmBack', 'forearm', 'neck', 'foot',
];

/** What the twin lights up first as Body knowledge grows, per sport. */
export const SPORT_BODY_AREAS = {
  soccer: ['thighBack', 'glutes', 'abs', 'shinBack', 'thigh', 'thighFront'],
  basketball: ['thighFront', 'glutes', 'shinBack', 'abs', 'shoulderCap', 'foot'],
  'track-and-field': ['thighBack', 'glutes', 'shinBack', 'thighFront', 'abs', 'foot'],
  default: ['thighFront', 'glutes', 'abs', 'upperBack', 'shinBack', 'thighBack'],
};

/** The sports the beta's sport-specific lessons are written for. */
export const BETA_SPORTS = ['soccer', 'basketball', 'track-and-field'];

/** Unlocked by Legends lessons; shown as rings around the twin. */
export const LEGEND_TRAITS = [
  { id: 'resilience', title: 'Resilience', detail: 'Turns a setback into the next plan.' },
  { id: 'craft', title: 'Craft', detail: 'Does the focused extra work nobody sees.' },
  { id: 'vision', title: 'Vision', detail: 'Knows the picture before the ball arrives.' },
  { id: 'composure', title: 'Composure', detail: 'Resets after a mistake and plays the next action.' },
];

/** Which anatomical muscles (the muscle map's slugs) make up each body area on the twin. */
export const AREA_MUSCLES = {
  thighBack: ['biceps-femoris', 'semitendinosus', 'semimembranosus'],
  thighFront: ['rectus-femoris', 'vastus-lateralis', 'vastus-medialis', 'sartorius'],
  thigh: ['adductors'],
  glutes: ['gluteus-maximus', 'gluteus-medius'],
  abs: ['rectus-abdominis', 'obliques-external'],
  lowerBack: ['erector-spinae', 'quadratus-lumborum'],
  upperBack: ['trapezius-upper', 'trapezius-middle', 'trapezius-lower', 'rhomboids', 'latissimus-dorsi'],
  chest: ['pectoralis-major', 'serratus-anterior'],
  shoulderCap: ['deltoid-anterior', 'deltoid-lateral', 'deltoid-posterior'],
  upperArmFront: ['biceps-brachii', 'brachialis'],
  upperArmBack: ['triceps-brachii'],
  forearm: ['forearm-flexors', 'forearm-extensors', 'brachioradialis'],
  neck: ['sternocleidomastoid', 'neck-extensors'],
  shinBack: ['gastrocnemius', 'soleus'],
  shinFront: ['tibialis-anterior', 'peroneals'],
  foot: ['foot-intrinsics'],
};
