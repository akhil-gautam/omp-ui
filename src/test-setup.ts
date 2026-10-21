import { cleanup } from "@testing-library/react";
import { afterEach, vi } from "vitest";

// Testing Library only cleans up automatically when the test framework
// exposes globals; this project imports them explicitly instead.
afterEach(() => {
	cleanup();
});

// jsdom has no layout, so it has no scrolling either.
Element.prototype.scrollIntoView = vi.fn();
