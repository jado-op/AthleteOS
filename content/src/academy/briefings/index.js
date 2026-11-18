/** Every briefing, one file each (validated by ../validate.js). */
import confidenceUnderPressure from './confidence-under-pressure.js';
import fuelOnGameDay from './fuel-on-game-day.js';
import recoveryAfterGames from './recovery-after-games.js';
import resetAfterMistakes from './reset-after-mistakes.js';
import sleepBeforeGames from './sleep-before-games.js';
import strengthIntoSpeed from './strength-into-speed.js';

export const BRIEFINGS = [
  sleepBeforeGames, recoveryAfterGames, fuelOnGameDay, strengthIntoSpeed, resetAfterMistakes, confidenceUnderPressure,
];
