import { describe, expect, it } from "vitest";

import type { SessionState, UiEvent } from "./schema";
import { initialStore, reducer, type Store } from "./store";

const project = { id: "p1", path: "/tmp/example", name: "example", createdAt: 0 };

const state: SessionState = {
	sessionId: "s1",
	isStreaming: false,
	isCompacting: false,
	isSettled: true,
	messageCount: 0,
	queuedMessageCount: 0,
	todoPhases: [],
	queuedMessages: { steering: [], followUp: [] },
};

function opened(): Store {
	return reducer(initialStore, {
		type: "open",
		result: { project, state, blocks: [], commands: [] },
	});
}

describe("the workspace reducer", () => {
	it("replaces the optimistic user message with the confirmed one", () => {
		let store = opened();
		store = reducer(store, { type: "localUser", projectId: "p1", text: "hello" });
		expect(store.workspaces.p1?.blocks).toHaveLength(1);

		const event: UiEvent = {
			projectId: "p1",
			kind: "messageStart",
			payload: { messageId: "m1", role: "user", text: "hello" },
		};
		store = reducer(store, { type: "event", event });

		const blocks = store.workspaces.p1?.blocks ?? [];
		expect(blocks).toHaveLength(1);
		expect(blocks[0]).toEqual({ kind: "user", id: "m1", text: "hello" });
	});

	it("appends streamed text to the message it belongs to", () => {
		let store = opened();

		const first: UiEvent = {
			projectId: "p1",
			kind: "messageDelta",
			payload: { messageId: "m1", channel: "text", delta: "Hello" },
		};
		const second: UiEvent = {
			projectId: "p1",
			kind: "messageDelta",
			payload: { messageId: "m1", channel: "text", delta: " there" },
		};
		store = reducer(store, { type: "event", event: first });
		store = reducer(store, { type: "event", event: second });

		const blocks = store.workspaces.p1?.blocks ?? [];
		expect(blocks).toHaveLength(1);
		expect(blocks[0]).toEqual({ kind: "text", id: "m1:text", text: "Hello there" });
	});

	it("keeps thinking apart from the reply", () => {
		let store = opened();

		const thinking: UiEvent = {
			projectId: "p1",
			kind: "messageDelta",
			payload: { messageId: "m1", channel: "thinking", delta: "hmm" },
		};
		const text: UiEvent = {
			projectId: "p1",
			kind: "messageDelta",
			payload: { messageId: "m1", channel: "text", delta: "answer" },
		};
		store = reducer(store, { type: "event", event: thinking });
		store = reducer(store, { type: "event", event: text });

		const blocks = store.workspaces.p1?.blocks ?? [];
		expect(blocks.map((block) => block.kind)).toEqual(["thinking", "text"]);
	});

	it("fills a tool card in when the tool finishes", () => {
		let store = opened();

		const start: UiEvent = {
			projectId: "p1",
			kind: "toolStart",
			payload: { toolCallId: "t1", name: "read", args: { path: "a.txt" } },
		};
		const end: UiEvent = {
			projectId: "p1",
			kind: "toolEnd",
			payload: { toolCallId: "t1", name: "read", result: "contents", isError: false },
		};
		store = reducer(store, { type: "event", event: start });

		let blocks = store.workspaces.p1?.blocks ?? [];
		expect(blocks[0]).toMatchObject({ kind: "tool", id: "t1", running: true });

		store = reducer(store, { type: "event", event: end });
		blocks = store.workspaces.p1?.blocks ?? [];
		expect(blocks[0]).toMatchObject({
			kind: "tool",
			id: "t1",
			running: false,
			output: "contents",
			isError: false,
		});
	});

	it("holds the pending dialog until it is answered", () => {
		let store = opened();

		const request: UiEvent = {
			projectId: "p1",
			kind: "uiRequest",
			payload: { method: "confirm", id: "ui1", title: "Approve?", message: "Run it?" },
		};
		store = reducer(store, { type: "event", event: request });
		expect(store.workspaces.p1?.pendingRequest?.id).toBe("ui1");

		store = reducer(store, { type: "dismissRequest", projectId: "p1" });
		expect(store.workspaces.p1?.pendingRequest).toBeNull();
	});

	it("follows the session status", () => {
		let store = opened();

		const busy: UiEvent = { projectId: "p1", kind: "status", payload: { status: "busy" } };
		const idle: UiEvent = { projectId: "p1", kind: "status", payload: { status: "idle" } };
		store = reducer(store, { type: "event", event: busy });
		expect(store.workspaces.p1?.status).toBe("busy");

		store = reducer(store, { type: "event", event: idle });
		expect(store.workspaces.p1?.status).toBe("idle");
	});

	it("keeps the queued messages the session reports", () => {
		let store = opened();

		const queue: UiEvent = {
			projectId: "p1",
			kind: "queue",
			payload: { steering: ["steer me"], followUp: ["then this"] },
		};
		store = reducer(store, { type: "event", event: queue });

		expect(store.workspaces.p1?.queue).toEqual({ steering: ["steer me"], followUp: ["then this"] });
	});

	it("drops events for projects it does not know", () => {
		const store = opened();
		const event: UiEvent = { projectId: "other", kind: "status", payload: { status: "busy" } };
		expect(reducer(store, { type: "event", event })).toEqual(store);
	});
});
