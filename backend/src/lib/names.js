import { isObjectionable } from './moderation.js';

/** A nickname: 2–20 letters, digits, spaces, dots, dashes or underscores. */
export function cleanNickname(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim().replace(/\s+/g, ' ');
  return /^[\p{L}\p{N} ._-]{2,20}$/u.test(trimmed) && !isObjectionable(trimmed) ? trimmed : null;
}

export function cleanName(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim().replace(/\s+/g, ' ');
  return trimmed.length >= 2 && trimmed.length <= 40 && !isObjectionable(trimmed) ? trimmed : null;
}
