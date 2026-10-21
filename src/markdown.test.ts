import { describe, expect, it } from "vitest";

import { renderMarkdown } from "./markdown";

describe("renderMarkdown", () => {
	it("renders a fenced block with its language and a copy button", () => {
		const html = renderMarkdown("```rust\nfn main() {}\n```");

		expect(html).toContain("code-language");
		expect(html).toContain("rust");
		expect(html).toContain("data-code-copy");
		expect(html).toContain("<pre><code");
	});

	it("highlights code it recognises", () => {
		const html = renderMarkdown("```rust\nfn main() {}\n```");

		expect(html).toContain("hljs");
		expect(html).toMatch(/<span class="hljs/);
	});

	it("reads the language out of a fence with extra labels", () => {
		const html = renderMarkdown("```rust,ignore {1,3}\nfn main() {}\n```");

		expect(html).toContain("hljs");
		expect(html).toContain("rust");
	});

	it("escapes code in a language it does not recognise", () => {
		const html = renderMarkdown("```notalanguage\n<script>alert(1)</script>\n```");

		expect(html).not.toContain("<script>");
		expect(html).toContain("&lt;script&gt;");
		expect(html).toContain("notalanguage");
	});

	it("escapes code inside a recognised language", () => {
		const html = renderMarkdown("```html\n<script>alert(1)</script>\n```");

		expect(html).not.toContain("<script>");
		expect(html).toContain("&lt;");
		expect(html).toContain("alert");
	});

	it("shows raw html literally instead of interpreting it", () => {
		const html = renderMarkdown("<img src=x onerror=alert(1)>");

		expect(html).not.toContain("<img");
		expect(html).toContain("&lt;img");
	});

	it("drops script tags and event handlers", () => {
		const html = renderMarkdown("<script>alert(1)</script><a href=\"javascript:alert(1)\">x</a>");

		expect(html).not.toContain("<script");
		expect(html).not.toContain("<a ");
	});

	it("renders GFM tables", () => {
		const html = renderMarkdown("| a | b |\n| - | - |\n| 1 | 2 |");

		expect(html).toContain("<table>");
		expect(html).toContain("<th>a</th>");
	});

	it("renders task lists", () => {
		const html = renderMarkdown("- [x] done\n- [ ] todo");

		expect(html).toContain('type="checkbox"');
		expect(html).toContain("checked");
	});

	it("turns single newlines into line breaks", () => {
		expect(renderMarkdown("one\ntwo")).toContain("<br>");
	});

	it("marks links as external and safe", () => {
		const html = renderMarkdown("[omp](https://omp.sh)");

		expect(html).toContain('target="_blank"');
		expect(html).toContain('rel="noopener noreferrer"');
		expect(html).toContain('href="https://omp.sh"');
	});

	it("renders inline code", () => {
		expect(renderMarkdown("use `cargo test` now")).toContain("<code>cargo test</code>");
	});

	it("renders headings and emphasis", () => {
		const html = renderMarkdown("## Title\n\nsome **bold** and *italic*");

		expect(html).toContain("<h2>");
		expect(html).toContain("<strong>bold</strong>");
		expect(html).toContain("<em>italic</em>");
	});

	it("returns nothing for empty text", () => {
		expect(renderMarkdown("")).toBe("");
	});
});
