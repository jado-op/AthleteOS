/**
 * The Academy (docs/ACADEMY-PLAN.md, v3): the Digital Twin analyses the
 * athlete's own data, finds insights, and the coach assigns briefings —
 * long-form reads — for them. This file holds the shared vocabulary.
 */

/** What a briefing is about. */
export const TOPICS = ['recovery', 'strength', 'mind', 'fuel'];

/** The insights the twin can find (TwinAnalysis.swift); each briefing answers one. */
export const INSIGHTS = [
  'sleepBeforeGames', 'recoveryAfterGames', 'gameDayFuel', 'strengthNotSpeed', 'mistakeReplay', 'pressureConfidence',
];

/** Where the app inserts the athlete's own chart in a briefing, and which insight's evidence fills it. */
export const YOUR_DATA = {
  sleepByNight: 'sleepBeforeGames',
  sorenessAfterGames: 'recoveryAfterGames',
  gameDayEnergy: 'gameDayFuel',
  strengthVsSprint: 'strengthNotSpeed',
  reflectionsMistakes: 'mistakeReplay',
  reflectionsConfidence: 'pressureConfidence',
};

/** The placeholders each insight fills in a briefing's "why your coach gave you this". */
export const WHY_PLACEHOLDERS = {
  sleepBeforeGames: ['sleepGap', 'gameCount'],
  recoveryAfterGames: ['sorenessDays', 'gameCount'],
  gameDayFuel: ['energyGap', 'gameCount'],
  strengthNotSpeed: ['strengthGain', 'sprintChange'],
  mistakeReplay: ['mistakeCount', 'reflectionCount'],
  pressureConfidence: ['confidenceCount', 'reflectionCount'],
};
