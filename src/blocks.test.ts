import { describe, expect, it } from "vitest";

import { groupTranscript, summariseTools } from "./blocks";
import type { Block, ToolBlock } from "./schema";

const tool = (id: string, name: string): ToolBlock => ({
	kind: "tool",
	id,
	name,
	isError: false,
	running: false,
});

const text = (id: string): Block => ({ kind: "text", id, text: "hello" });

describe("groupTranscript", () => {
	it("keeps a lone tool call as its own entry", () => {
		const items = groupTranscript([tool("t1", "read")]);

		expect(items).toHaveLength(1);
		expect(items[0]).toEqual({ kind: "tools", blocks: [tool("t1", "read")] });
	});

	it("folds consecutive tool calls into one group", () => {
		const items = groupTranscript([tool("t1", "read"), tool("t2", "write"), tool("t3", "bash")]);

		expect(items).toHaveLength(1);
		expect(items[0]?.kind).toBe("tools");
	});

	it("separates groups that are broken up by prose", () => {
		const items = groupTranscript([tool("t1", "read"), text("m1"), tool("t2", "write")]);

		expect(items.map((item) => item.kind)).toEqual(["tools", "entry", "tools"]);
	});

	it("leaves prose alone", () => {
		const items = groupTranscript([text("m1"), text("m2")]);

		expect(items).toHaveLength(2);
		expect(items[0]?.kind).toBe("entry");
	});
});

describe("summariseTools", () => {
	it("counts the calls of each tool, most used first", () => {
		const { counts } = summariseTools([
			tool("t1", "read"),
			tool("t2", "bash"),
			tool("t3", "read"),
		]);

		expect(counts).toEqual([
			{ name: "read", count: 2 },
			{ name: "bash", count: 1 },
		]);
	});

	it("handles an empty group", () => {
		expect(summariseTools([]).counts).toEqual([]);
	});
});
