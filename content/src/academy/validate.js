/**
 * The Academy validator (docs/ACADEMY-PLAN.md). The content build refuses to
 * write the app's briefings while it reports a problem, and `npm test` runs
 * it too. Readers are 13–19, so besides the structure it enforces what a
 * briefing must never contain: calories, dieting, weight loss, supplements,
 * or load prescriptions (that is the Workout tab's job, with a coach).
 */
import { SOURCES } from '../guides/sources.js';
import { INSIGHTS, TOPICS, WHY_PLACEHOLDERS, YOUR_DATA } from './model.js';

/** Never in Academy text, whatever the sentence around it says. */
export const BANNED = [
  [/calorie|kcal/i, 'calories'],
  [/\bdiet(ing|s)?\b/i, 'dieting'],
  [/weight[- ]?cut|cut(ting)?\s+weight|making weight/i, 'weight cutting'],
  [/(lose|losing|lost|drop|dropping|shed|shedding)\s+(some\s+)?(weight|pounds|kilos)/i, 'weight loss'],
  [/fasting|skip(ping)? meals? to/i, 'restriction'],
  [/supplement|creatine|pre-?workout|protein (powder|shakes?)|fat burner|energy drink|caffeine|steroid/i, 'supplements'],
  [/\b\d+\s*(x|×)\s*\d+\b/i, 'sets × reps'],
  [/\b\d+\s*(sets?|reps?|repetitions)\b/i, 'sets or reps'],
  [/\b1\s?RM\b|%\s*of\s*(your\s*)?max/i, 'percent of max'],
  [/\b\d+(\.\d+)?\s*(kg|kgs|kilos?|lbs?|pounds)\b/i, 'loads'],
];

/** A briefing is a real read: about 9–14 minutes. */
export const WORDS = { min: 1700, max: 2800 };
export const WORDS_PER_MINUTE = 200;

const ID = /^[a-z0-9]+(-[a-z0-9]+)*$/;

function blockTexts(block) {
  if (block.p) return [block.p];
  if (block.h) return [block.h];
  if (block.quote) return [block.quote];
  if (block.example) return [block.example.title, block.example.body];
  if (block.protocol) return [block.protocol.title, ...block.protocol.steps];
  return [];
}

export function briefingTexts(b) {
  return [b.title, b.dek, b.why, ...b.chapters.flatMap((c) => [c.title, ...c.blocks.flatMap(blockTexts)])].filter(Boolean);
}

export function wordCount(b) {
  return b.chapters.flatMap((c) => [c.title, ...c.blocks.flatMap(blockTexts)]).join(' ').split(/\s+/).filter(Boolean).length;
}

function safety(texts, at, problems) {
  for (const text of texts) {
    for (const [pattern, what] of BANNED) {
      if (pattern.test(text)) problems.push(`${at}: not for the Academy (${what}): “${text.slice(0, 90)}”`);
    }
  }
}

/** Every problem in the briefings, as readable lines (empty = valid). */
export function validateBriefings(briefings) {
  const problems = [];
  const ids = new Set();
  for (const b of briefings) {
    const at = b.id ?? '(no id)';
    if (!ID.test(b.id ?? '')) problems.push(`${at}: id must be kebab-case`);
    if (ids.has(b.id)) problems.push(`${at}: duplicate id`);
    ids.add(b.id);
    if (!TOPICS.includes(b.topic)) problems.push(`${at}: topic must be one of ${TOPICS.join(', ')}`);
    if (!INSIGHTS.includes(b.insight)) problems.push(`${at}: unknown insight ${b.insight}`);
    for (const key of ['title', 'dek', 'why']) if (!b[key]?.trim()) problems.push(`${at}: missing ${key}`);
    const allowed = WHY_PLACEHOLDERS[b.insight] ?? [];
    for (const [, name] of (b.why ?? '').matchAll(/\{(\w+)\}/g)) {
      if (!allowed.includes(name)) problems.push(`${at}: why uses {${name}}, ${b.insight} only fills ${allowed.join(', ')}`);
    }
    const chapters = b.chapters ?? [];
    if (chapters.length < 3 || chapters.length > 5) problems.push(`${at}: needs 3–5 chapters, has ${chapters.length}`);
    let protocols = 0, yourData = 0, examples = 0;
    for (const [i, c] of chapters.entries()) {
      if (!c.title?.trim()) problems.push(`${at}: chapter ${i + 1} needs a title`);
      if (!Array.isArray(c.blocks) || c.blocks.length < 2) problems.push(`${at}: chapter ${i + 1} needs blocks`);
      for (const block of c.blocks ?? []) {
        const kinds = ['p', 'h', 'quote', 'example', 'yourData', 'protocol'].filter((k) => block[k] !== undefined);
        if (kinds.length !== 1) { problems.push(`${at}: a block has one kind, got ${kinds.join('+') || 'none'}`); continue; }
        if (block.example && (!block.example.title?.trim() || !block.example.body?.trim())) problems.push(`${at}: example needs title and body`);
        if (block.protocol && (!block.protocol.title?.trim() || !(block.protocol.steps?.length >= 3))) problems.push(`${at}: protocol needs a title and 3+ steps`);
        if (block.yourData !== undefined) {
          if (YOUR_DATA[block.yourData] !== b.insight) problems.push(`${at}: yourData ${block.yourData} doesn't belong to ${b.insight}`);
          yourData += 1;
        }
        if (block.protocol) protocols += 1;
        if (block.example) examples += 1;
      }
    }
    if (protocols !== 1) problems.push(`${at}: needs exactly one protocol, has ${protocols}`);
    if (yourData > 1) problems.push(`${at}: the athlete's chart appears at most once`);
    if (examples < 1) problems.push(`${at}: needs at least one example`);
    const words = wordCount(b);
    if (words < WORDS.min || words > WORDS.max) problems.push(`${at}: ${words} words — a briefing has ${WORDS.min}–${WORDS.max}`);
    for (const key of b.sources ?? []) if (!SOURCES[key]) problems.push(`${at}: unknown source ${key}`);
    if (b.topic === 'mind' && !/counsellor|counselor|helpline|talk(ing)? to/i.test(briefingTexts(b).join(' '))) {
      problems.push(`${at}: mind briefings say who to talk to when it feels heavy`);
    }
    safety(briefingTexts(b), at, problems);
  }
  for (const insight of INSIGHTS) {
    if (!briefings.some((b) => b.insight === insight)) problems.push(`no briefing answers the insight ${insight}`);
  }
  return problems;
}

/** Problems in the intake interview. */
export function validateIntake(intake) {
  const problems = [];
  const ids = new Set();
  for (const q of intake) {
    const at = `intake/${q.id}`;
    if (!q.id || ids.has(q.id)) problems.push(`${at}: ids must be unique`);
    ids.add(q.id);
    if (!q.prompt?.trim() || !q.label?.trim()) problems.push(`${at}: needs prompt and label`);
    if (q.freeText) {
      if (q.options) problems.push(`${at}: free text has no options`);
    } else {
      if (!(q.options?.length >= 2 && q.options.length <= 5)) problems.push(`${at}: needs 2–5 options`);
      const oids = new Set(q.options?.map((o) => o.id));
      if (oids.size !== q.options?.length) problems.push(`${at}: option ids must be unique`);
      for (const o of q.options ?? []) if (!o.id || !o.text?.trim() || !o.summary?.trim()) problems.push(`${at}: option needs id, text, summary`);
      if (q.options?.some((o) => o.correct !== undefined)) problems.push(`${at}: the intake has no right answers`);
    }
    safety([q.prompt, ...(q.options ?? []).flatMap((o) => [o.text, o.summary])], at, problems);
  }
  return problems;
}

/** The JSON the app decodes (AcademyModels.swift). */
export function academyPayload(briefings, intake) {
  return {
    briefings: briefings.map((b) => ({
      id: b.id,
      topic: b.topic,
      title: b.title,
      dek: b.dek,
      insight: b.insight,
      why: b.why,
      minutes: Math.max(1, Math.round(wordCount(b) / WORDS_PER_MINUTE)),
      chapters: b.chapters.map((c) => ({
        title: c.title,
        blocks: c.blocks.map((block) => {
          if (block.p) return { kind: 'p', text: block.p };
          if (block.h) return { kind: 'h', text: block.h };
          if (block.quote) return { kind: 'quote', text: block.quote };
          if (block.example) return { kind: 'example', title: block.example.title, text: block.example.body };
          if (block.yourData) return { kind: 'yourData', key: block.yourData };
          return { kind: 'protocol', title: block.protocol.title, steps: block.protocol.steps };
        }),
      })),
      sources: (b.sources ?? []).map((key) => ({ title: SOURCES[key].title, detail: SOURCES[key].detail, url: SOURCES[key].url })),
    })),
    intake: intake.map((q) => ({
      id: q.id,
      label: q.label,
      prompt: q.prompt,
      freeText: q.freeText === true,
      placeholder: q.placeholder ?? null,
      options: (q.options ?? []).map((o) => ({ id: o.id, text: o.text, summary: o.summary })),
    })),
  };
}
