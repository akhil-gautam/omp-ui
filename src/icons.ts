/**
 * Icon markup.
 *
 * The icons are plain SVG strings so they can be used both in React and in
 * the sanitised HTML the markdown pipeline produces.
 */

const COPY_BODY =
	'<rect x="5.75" y="1.75" width="8.5" height="10.5" rx="2"/><path d="M10.25 13.75h-6.5a2 2 0 0 1-2-2v-6.5a2 2 0 0 1 2-2h6"/>';

const CHECK_BODY = '<path d="M3 8.5 6.5 12 13 4.5"/>';

export const COPY_ICON = `<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true">${COPY_BODY}</svg>`;

export const CHECK_ICON = `<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">${CHECK_BODY}</svg>`;
