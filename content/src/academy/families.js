/**
 * Sport families: the Academy speaks each athlete's language. A tennis player
 * reads "match", a swimmer "race", a gymnast "competition"; individual sports
 * get no teammate questions; the strength-into-speed insight only runs where
 * speed decides. Briefings carry examples per family (validate.js).
 */
export const FAMILIES = {
  field:     { name: 'Field team sports',  event: 'game',        events: 'games',        team: true,  speed: true },
  court:     { name: 'Court team sports',  event: 'game',        events: 'games',        team: true,  speed: true },
  batBall:   { name: 'Bat-and-ball sports', event: 'game',       events: 'games',        team: true,  speed: true },
  racket:    { name: 'Racket sports',      event: 'match',       events: 'matches',      team: false, speed: true },
  endurance: { name: 'Endurance sports',   event: 'race',        events: 'races',        team: false, speed: false },
  track:     { name: 'Track and field',    event: 'meet',        events: 'meets',        team: false, speed: true },
  combat:    { name: 'Combat sports',      event: 'match',       events: 'matches',      team: false, speed: true },
  artistic:  { name: 'Artistic sports',    event: 'competition', events: 'competitions', team: false, speed: false },
  precision: { name: 'Precision sports',   event: 'round',       events: 'rounds',       team: false, speed: false },
  strength:  { name: 'Strength sports',    event: 'meet',        events: 'meets',        team: false, speed: false },
  board:     { name: 'Board and snow sports', event: 'competition', events: 'competitions', team: false, speed: false },
};

/** Every sport → its family. */
export const SPORT_FAMILY = {
  soccer: 'field', football: 'field', 'flag-football': 'field', lacrosse: 'field', 'field-hockey': 'field', rugby: 'field',
  'ice-hockey': 'field', ultimate: 'field', 'water-polo': 'field', 'unified-sports': 'field', goalball: 'court',
  basketball: 'court', volleyball: 'court', 'team-handball': 'court', netball: 'court', spikeball: 'court',
  baseball: 'batBall', softball: 'batBall',
  tennis: 'racket', badminton: 'racket', 'table-tennis': 'racket', squash: 'racket', pickleball: 'racket', racquetball: 'racket',
  'cross-country': 'endurance', 'swimming-diving': 'endurance', rowing: 'endurance', cycling: 'endurance', 'mountain-biking': 'endurance',
  triathlon: 'endurance', orienteering: 'endurance', sailing: 'endurance',
  'track-and-field': 'track', 'indoor-track-and-field': 'track',
  wrestling: 'combat', judo: 'combat', fencing: 'combat',
  gymnastics: 'artistic', 'competitive-spirit': 'artistic', 'competitive-dance': 'artistic', 'step-team': 'artistic',
  'color-guard': 'artistic', 'marching-band-athletics': 'artistic', equestrian: 'artistic',
  golf: 'precision', bowling: 'precision', rifle: 'precision', archery: 'precision', 'disc-golf': 'precision', boccia: 'precision',
  weightlifting: 'strength', powerlifting: 'strength', 'crossfit-style-conditioning': 'strength', 'esports-physical-conditioning': 'strength',
  climbing: 'board', skiing: 'board', snowboarding: 'board', surfing: 'board', skateboarding: 'board', bmx: 'board',
};

/** The family briefings fall back to when no variant fits. */
export const DEFAULT_FAMILY = 'field';
