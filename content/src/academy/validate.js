/**
 * The Academy seed validator (docs/ACADEMY-PLAN.md §7). The content build
 * refuses to write the app's lessons while it reports a problem, and
 * `npm test` runs it too. Users are 13+ minors, so besides the structure it
 * enforces what the Academy must never teach: calorie restriction, weight
 * cutting, supplements, or load prescriptions (that is the Workout tab's job,
 * with a coach).
 */
import { SOURCES } from '../guides/sources.js';
import { SPORTS } from '../sports.js';
import { BODY_AREAS, LEGEND_TRAITS, PHASES, PILLARS, SIDES, SPORT_BODY_AREAS } from './model.js';

/** Never in Academy text, whatever the sentence around it says. */
export const BANNED = [
  [/calorie|kcal/i, 'calories'],
  [/\bdiet(ing|s)?\b/i, 'dieting'],
  [/weight[- ]?cut|cut(ting)?\s+weight|making weight/i, 'weight cutting'],
  [/(lose|losing|lost|drop|dropping|shed|shedding)\s+(some\s+)?(weight|pounds|kilos)/i, 'weight loss'],
  [/fasting|skip(ping)? meals? to/i, 'restriction'],
  [/supplement|creatine|pre-?workout|protein (powder|shakes?)|fat burner|energy drink|caffeine (pill|tablet)|steroid/i, 'supplements'],
  [/\b\d+\s*(x|×)\s*\d+\b/i, 'sets × reps'],
  [/\b\d+\s*(sets?|reps?|repetitions)\b/i, 'sets or reps'],
  [/\b1\s?RM\b|%\s*of\s*(your\s*)?max/i, 'percent of max'],
  [/\b\d+(\.\d+)?\s*(kg|kgs|kilos?|lbs?|pounds)\b/i, 'loads'],
];

/** Lesson length by words: about 3–5 minutes with the questions. */
export const WORDS = { min: 120, max: 700 };

const ID = /^[a-z0-9]+(-[a-z0-9]+)*$/;

function texts(lesson) {
  const out = [lesson.title];
  for (const s of lesson.sections ?? []) out.push(s.heading, s.body);
  if (lesson.legend) out.push(lesson.legend.title, lesson.legend.body);
  for (const q of lesson.questions ?? []) {
    out.push(q.prompt, q.explain ?? '');
    for (const o of q.options ?? []) out.push(o.text);
  }
  return out.filter(Boolean);
}

export function wordCount(lesson) {
  const parts = (lesson.sections ?? []).flatMap((s) => [s.heading, s.body]);
  if (lesson.legend) parts.push(lesson.legend.body);
  return parts.join(' ').split(/\s+/).filter(Boolean).length;
}

function checkEffect(e, where, problems, lessonPillar) {
  if (!PILLARS.includes(e.pillar)) problems.push(`${where}: unknown pillar ${e.pillar}`);
  if (!SIDES.includes(e.side)) problems.push(`${where}: unknown side ${e.side}`);
  if (!Number.isInteger(e.delta) || e.delta < 1 || e.delta > 10) problems.push(`${where}: delta must be 1–10, got ${e.delta}`);
  if (e.area !== undefined) {
    if (!BODY_AREAS.includes(e.area)) problems.push(`${where}: unknown body area ${e.area}`);
    if (e.pillar !== 'body') problems.push(`${where}: only Body effects light up a body area`);
  }
  if (e.trait !== undefined && !LEGEND_TRAITS.some((t) => t.id === e.trait)) problems.push(`${where}: unknown trait ${e.trait}`);
  if (e.ego !== undefined && (!Number.isInteger(e.ego) || Math.abs(e.ego) > 2 || e.ego === 0)) problems.push(`${where}: ego must be ±1 or ±2`);
  if (lessonPillar && e.pillar !== lessonPillar) problems.push(`${where}: effect on ${e.pillar} in a ${lessonPillar} lesson`);
}

/** Every problem in the lessons, as readable lines (empty = valid). */
export function validateAcademy(lessons) {
  const problems = [];
  const sportSlugs = new Set(SPORTS.map((s) => s.slug));
  const ids = new Set();
  for (const lesson of lessons) {
    const at = lesson.id ?? '(no id)';
    if (!ID.test(lesson.id ?? '')) problems.push(`${at}: id must be kebab-case`);
    if (ids.has(lesson.id)) problems.push(`${at}: duplicate id`);
    ids.add(lesson.id);
    if (!lesson.title?.trim()) problems.push(`${at}: missing title`);
    if (!PILLARS.includes(lesson.pillar)) problems.push(`${at}: unknown pillar ${lesson.pillar}`);
    if (!Array.isArray(lesson.sports) || lesson.sports.length === 0) problems.push(`${at}: needs sports (or ["all"])`);
    for (const s of lesson.sports ?? []) {
      if (s !== 'all' && !sportSlugs.has(s)) problems.push(`${at}: unknown sport ${s}`);
    }
    if ((lesson.sports ?? []).includes('all') && lesson.sports.length > 1) problems.push(`${at}: "all" stands alone`);
    const [minAge, maxAge] = lesson.ages ?? [];
    if (!Number.isInteger(minAge) || minAge < 13 || !Number.isInteger(maxAge) || maxAge < minAge) {
      problems.push(`${at}: ages must be [min ≥ 13, max ≥ min]`);
    }
    if (!Array.isArray(lesson.phases) || lesson.phases.length === 0 || lesson.phases.some((p) => !PHASES.includes(p))) {
      problems.push(`${at}: phases must be from ${PHASES.join(', ')}`);
    }
    if (!Number.isInteger(lesson.minutes) || lesson.minutes < 3 || lesson.minutes > 5) problems.push(`${at}: minutes must be 3–5`);
    if (!Array.isArray(lesson.sections) || lesson.sections.length < 2) problems.push(`${at}: needs at least two sections`);
    for (const s of lesson.sections ?? []) {
      if (!s.heading?.trim() || !s.body?.trim()) problems.push(`${at}: a section needs heading and body`);
    }
    const words = wordCount(lesson);
    if (words < WORDS.min || words > WORDS.max) problems.push(`${at}: ${words} words — a 3–5 minute lesson has ${WORDS.min}–${WORDS.max}`);
    if (lesson.legend && (!lesson.legend.athlete?.trim() || !lesson.legend.title?.trim() || !lesson.legend.body?.trim())) {
      problems.push(`${at}: a legend insight needs athlete, title and body`);
    }
    for (const key of lesson.sources ?? []) {
      if (!SOURCES[key]) problems.push(`${at}: unknown source ${key}`);
    }
    if (lesson.pillar === 'mind' && lesson.support !== true) problems.push(`${at}: Mind lessons carry the support row (support: true)`);

    const questions = lesson.questions ?? [];
    if (questions.length < 2 || questions.length > 4) problems.push(`${at}: needs 2–4 questions, has ${questions.length}`);
    if (!questions.some((q) => q.kind === 'knowledge')) problems.push(`${at}: needs at least one knowledge check`);
    const qids = new Set();
    for (const q of questions) {
      const where = `${at}/${q.id}`;
      if (!q.id || qids.has(q.id)) problems.push(`${where}: question ids must be unique`);
      qids.add(q.id);
      if (!['knowledge', 'reflection'].includes(q.kind)) problems.push(`${where}: kind must be knowledge or reflection`);
      if (!q.prompt?.trim()) problems.push(`${where}: missing prompt`);
      const options = q.options ?? [];
      if (options.length < 2 || options.length > 4) problems.push(`${where}: needs 2–4 options`);
      const correct = options.filter((o) => o.correct === true).length;
      if (q.kind === 'knowledge') {
        if (correct !== 1) problems.push(`${where}: a knowledge check has exactly one right answer`);
        if (!q.explain?.trim()) problems.push(`${where}: a knowledge check explains its answer`);
        for (const o of options) {
          if (o.correct !== true && (o.effects ?? []).length) problems.push(`${where}: a wrong answer changes nothing`);
          for (const e of o.effects ?? []) if (e.side !== 'knowledge') problems.push(`${where}: quiz answers build knowledge, not habits`);
        }
      } else if (q.kind === 'reflection') {
        if (correct !== 0) problems.push(`${where}: a reflection has no right answer`);
        for (const o of options) for (const e of o.effects ?? []) if (e.side !== 'habits') problems.push(`${where}: reflections build habits & mindset`);
      }
      for (const o of options) {
        if (!o.text?.trim()) problems.push(`${where}: an option needs text`);
        for (const e of o.effects ?? []) checkEffect(e, where, problems, lesson.pillar);
      }
    }
    if (!Array.isArray(lesson.completion) || lesson.completion.length === 0) problems.push(`${at}: finishing a lesson must move the twin (completion)`);
    for (const e of lesson.completion ?? []) {
      checkEffect(e, `${at}/completion`, problems, lesson.pillar);
      if (e.side !== 'knowledge') problems.push(`${at}/completion: finishing builds knowledge`);
    }

    for (const text of texts(lesson)) {
      for (const [pattern, what] of BANNED) {
        if (pattern.test(text)) problems.push(`${at}: not for the Academy (${what}): “${text.slice(0, 80)}”`);
      }
    }
  }

  // Prerequisites exist and never loop.
  const byId = new Map(lessons.map((l) => [l.id, l]));
  for (const lesson of lessons) {
    for (const r of lesson.requires ?? []) if (!byId.has(r)) problems.push(`${lesson.id}: requires unknown lesson ${r}`);
  }
  const state = new Map();
  const visit = (id, path) => {
    if (state.get(id) === 'done') return;
    if (state.get(id) === 'open') { problems.push(`prerequisite loop: ${[...path, id].join(' → ')}`); return; }
    state.set(id, 'open');
    for (const r of byId.get(id)?.requires ?? []) if (byId.has(r)) visit(r, [...path, id]);
    state.set(id, 'done');
  };
  for (const lesson of lessons) visit(lesson.id, []);

  for (const [sport, areas] of Object.entries(SPORT_BODY_AREAS)) {
    if (sport !== 'default' && !sportSlugs.has(sport)) problems.push(`body areas: unknown sport ${sport}`);
    for (const a of areas) if (!BODY_AREAS.includes(a)) problems.push(`body areas for ${sport}: unknown area ${a}`);
  }
  return problems;
}

/** The JSON the app decodes (AcademyContent.swift). */
export function academyPayload(lessons) {
  return {
    lessons: lessons.map((l) => ({
      id: l.id,
      title: l.title,
      pillar: l.pillar,
      sports: l.sports,
      minAge: l.ages[0],
      maxAge: l.ages[1],
      phases: l.phases,
      requires: l.requires ?? [],
      minutes: l.minutes,
      support: l.support === true,
      sections: l.sections.map((s) => ({ heading: s.heading, body: s.body })),
      legend: l.legend ? { athlete: l.legend.athlete, title: l.legend.title, body: l.legend.body } : null,
      questions: l.questions.map((q) => ({
        id: q.id,
        kind: q.kind,
        prompt: q.prompt,
        explain: q.explain ?? null,
        options: q.options.map((o) => ({ text: o.text, correct: o.correct === true, effects: o.effects ?? [] })),
      })),
      completion: l.completion,
      sources: (l.sources ?? []).map((key) => ({ title: SOURCES[key].title, detail: SOURCES[key].detail, url: SOURCES[key].url })),
    })),
    sportAreas: SPORT_BODY_AREAS,
    traits: LEGEND_TRAITS,
  };
}
