import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// Testing Library only cleans up automatically when the test framework
// exposes globals; this project imports them explicitly instead.
afterEach(() => {
	cleanup();
});
