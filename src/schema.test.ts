import { describe, expect, it } from "vitest";

import { modelListSchema, openResultSchema, sessionStateSchema } from "./schema";

describe("the session state contract", () => {
	it("takes the state omp sends for a session that is not streaming", () => {
		// omp writes `null` for the values it does not have, so a state that
		// has never streamed carries a null throughput.
		const state = sessionStateSchema.parse({
			sessionId: "s1",
			model: { id: "m1", name: "MiniMax M3.1 Flash", provider: "minimax" },
			thinkingLevel: "high",
			isStreaming: false,
			isCompacting: false,
			isSettled: true,
			messageCount: 0,
			queuedMessageCount: 0,
			tokensPerSecond: null,
			contextUsage: null,
			todoPhases: [],
			queuedMessages: { steering: [], followUp: [] },
		});

		expect(state.tokensPerSecond).toBeNull();
		expect(state.contextUsage).toBeNull();
		expect(state.model?.name).toBe("MiniMax M3.1 Flash");
	});

	it("takes a model whose provider reports no context window", () => {
		const model = modelListSchema.parse([
			{ id: "m1", name: "A model", provider: "acme", api: "openai", contextWindow: null },
		]);

		expect(model[0]?.contextWindow).toBeNull();
	});

	it("takes a session opened for a project with no history", () => {
		const result = openResultSchema.parse({
			project: {
				id: "p1",
				path: "/tmp/example",
				displayPath: "~/example",
				name: "example",
				createdAt: 0,
			},
			state: {
				sessionId: "s1",
				model: null,
				thinkingLevel: null,
				tokensPerSecond: null,
				contextUsage: null,
			},
			blocks: [],
			commands: [],
		});

		expect(result.state.model).toBeNull();
		expect(result.state.tokensPerSecond).toBeNull();
	});

	it("still refuses a state that is not a state", () => {
		expect(sessionStateSchema.safeParse({ sessionId: 7 }).success).toBe(false);
	});
});
