/**
 * Turns an agent's reply into HTML.
 *
 * Agent output is markdown: fenced code, lists, tables, inline code. Rendering
 * it as plain text loses most of its meaning, so it is parsed, highlighted
 * and sanitised here. The result is inserted with `dangerouslySetInnerHTML`,
 * which is why sanitisation is not optional.
 */

import DOMPurify from "dompurify";
import hljs from "highlight.js/lib/core";
import type { LanguageFn } from "highlight.js";
import { Marked, type Tokens } from "marked";

import bash from "highlight.js/lib/languages/bash";
import c from "highlight.js/lib/languages/c";
import cpp from "highlight.js/lib/languages/cpp";
import csharp from "highlight.js/lib/languages/csharp";
import css from "highlight.js/lib/languages/css";
import diff from "highlight.js/lib/languages/diff";
import dockerfile from "highlight.js/lib/languages/dockerfile";
import go from "highlight.js/lib/languages/go";
import graphql from "highlight.js/lib/languages/graphql";
import ini from "highlight.js/lib/languages/ini";
import java from "highlight.js/lib/languages/java";
import javascript from "highlight.js/lib/languages/javascript";
import json from "highlight.js/lib/languages/json";
import kotlin from "highlight.js/lib/languages/kotlin";
import lua from "highlight.js/lib/languages/lua";
import markdown from "highlight.js/lib/languages/markdown";
import nginx from "highlight.js/lib/languages/nginx";
import objectivec from "highlight.js/lib/languages/objectivec";
import perl from "highlight.js/lib/languages/perl";
import php from "highlight.js/lib/languages/php";
import plaintext from "highlight.js/lib/languages/plaintext";
import python from "highlight.js/lib/languages/python";
import r from "highlight.js/lib/languages/r";
import ruby from "highlight.js/lib/languages/ruby";
import rust from "highlight.js/lib/languages/rust";
import scss from "highlight.js/lib/languages/scss";
import sql from "highlight.js/lib/languages/sql";
import swift from "highlight.js/lib/languages/swift";
import typescript from "highlight.js/lib/languages/typescript";
import xml from "highlight.js/lib/languages/xml";
import yaml from "highlight.js/lib/languages/yaml";

import { COPY_ICON } from "./icons";

/** The languages worth carrying around; highlight.js has over 190. */
const DEFINITIONS: Record<string, LanguageFn> = {
	bash,
	c,
	cpp,
	csharp,
	css,
	diff,
	dockerfile,
	go,
	graphql,
	ini,
	java,
	javascript,
	json,
	kotlin,
	lua,
	markdown,
	nginx,
	objectivec,
	perl,
	php,
	plaintext,
	python,
	r,
	ruby,
	rust,
	scss,
	sql,
	swift,
	typescript,
	xml,
	yaml,
};

for (const [name, definition] of Object.entries(DEFINITIONS)) {
	hljs.registerLanguage(name, definition);
}

/** Names agents use that are not highlight.js language names. */
const ALIASES: Record<string, string> = {
	sh: "bash",
	shell: "bash",
	zsh: "bash",
	console: "bash",
	terminal: "bash",
	rs: "rust",
	golang: "go",
	py: "python",
	rb: "ruby",
	yml: "yaml",
	md: "markdown",
	htm: "xml",
	html: "xml",
	svg: "xml",
	"c++": "cpp",
	"c#": "csharp",
	cs: "csharp",
	js: "javascript",
	mjs: "javascript",
	cjs: "javascript",
	ts: "typescript",
	tsx: "typescript",
	jsx: "javascript",
	plain: "plaintext",
	text: "plaintext",
	txt: "plaintext",
	toml: "ini",
	objc: "objectivec",
	docker: "dockerfile",
};

const escapeHtml = (text: string): string =>
	text
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;");

/** The highlight.js name for a fence label, or null when it is unknown. */
const resolveLanguage = (raw: string | undefined): string | null => {
	if (!raw) {
		return null;
	}
	// Fences carry more than a name: ```rust,ignore {1,3} or ``` rust title=…
	const head = raw.trim().split(/[\s:{]/)[0]?.toLowerCase() ?? "";
	if (!head) {
		return null;
	}
	const name = ALIASES[head] ?? head;
	return hljs.getLanguage(name) ? name : null;
};

const marked = new Marked({ gfm: true, breaks: true });

marked.use({
	renderer: {
		code({ text, lang }: Tokens.Code) {
			const language = resolveLanguage(lang);
			const body = language ? hljs.highlight(text, { language }).value : escapeHtml(text);
			const label = language ?? lang?.trim() ?? "";
			return [
				'<div class="code">',
				'<div class="code-head">',
				`<span class="code-language">${escapeHtml(label || "text")}</span>`,
				'<button class="code-copy" type="button" data-code-copy aria-label="Copy code">',
				COPY_ICON,
				"</button>",
				"</div>",
				`<pre><code class="hljs${language ? ` language-${language}` : ""}">${body}</code></pre>`,
				"</div>",
			].join("");
		},
		// Raw HTML in a reply is shown literally rather than interpreted.
		html({ text }: Tokens.HTML | Tokens.Tag) {
			return escapeHtml(text);
		},
		link({ href, title, text }: Tokens.Link) {
			const label = marked.parseInline(text);
			const titleAttribute = title ? ` title="${escapeHtml(title)}"` : "";
			return `<a href="${escapeHtml(href ?? "")}"${titleAttribute} target="_blank" rel="noopener noreferrer">${label}</a>`;
		},
	},
});

const PURIFY_CONFIG = {
	ADD_ATTR: ["target", "rel", "data-code-copy", "aria-label"],
	FORBID_TAGS: ["style", "form", "textarea", "select", "option", "iframe", "object", "embed", "link", "meta", "base", "math"],
	FORBID_ATTR: ["style", "formaction", "ping", "srcset"],
};

// Task lists need a checkbox; nothing else in a reply does. Anything that
// is not a checkbox is dropped, and the survivors are inert.
DOMPurify.addHook("afterSanitizeAttributes", (node) => {
	if (!(node instanceof HTMLInputElement)) {
		return;
	}
	if (node.type !== "checkbox") {
		node.remove();
		return;
	}
	node.setAttribute("disabled", "");
	node.setAttribute("tabindex", "-1");
});

/** Parses an agent's reply into sanitised HTML. */
export const renderMarkdown = (source: string): string => {
	if (!source) {
		return "";
	}
	return DOMPurify.sanitize(marked.parse(source, { async: false }), PURIFY_CONFIG);
};
