import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import Markdown from "./Markdown";

describe("Markdown", () => {
	it("renders headings and emphasis", () => {
		render(<Markdown text={"## Plan\n\nSome **bold** text."} />);

		expect(screen.getByRole("heading").textContent).toBe("Plan");
		expect(screen.getByText("bold").tagName).toBe("STRONG");
	});

	it("renders a code block with its language", () => {
		const { container } = render(<Markdown text={"```rust\nfn main() {}\n```"} />);

		expect(screen.getByText("rust")).toBeTruthy();
		// The highlighter splits the code into spans, so read the whole block.
		expect(container.querySelector("code")?.textContent).toContain("fn main()");
	});

	it("offers a copy button on every code block", () => {
		render(<Markdown text={"```rust\nfn main() {}\n```"} />);

		expect(screen.getByRole("button", { name: "Copy code" })).toBeTruthy();
	});

	it("renders inline code", () => {
		render(<Markdown text={"Run `cargo test` now"} />);

		expect(screen.getByText("cargo test").tagName).toBe("CODE");
	});

	it("shows raw html as text", () => {
		render(<Markdown text={"<b>not bold</b>"} />);

		expect(screen.getByText("<b>not bold</b>")).toBeTruthy();
	});

	it("renders nothing for empty text", () => {
		const { container } = render(<Markdown text={""} />);

		expect(container.textContent).toBe("");
	});
});
