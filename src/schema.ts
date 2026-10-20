/**
 * The contract between the Rust backend and this webview.
 *
 * Everything that crosses the IPC boundary is parsed here exactly once; the
 * rest of the app consumes the named types inferred from these schemas.
 */

import { z } from "zod";

export const projectSchema = z.object({
	id: z.string(),
	path: z.string(),
	name: z.string(),
	createdAt: z.number(),
});
export type Project = z.infer<typeof projectSchema>;

export const sessionStatusSchema = z.enum(["starting", "idle", "busy", "stopped", "error"]);
export type SessionStatus = z.infer<typeof sessionStatusSchema>;

export const commandSchema = z.object({
	name: z.string(),
	source: z.string(),
	description: z.string().optional(),
	aliases: z.array(z.string()).optional(),
});
export type CommandInfo = z.infer<typeof commandSchema>;

export const todoTaskSchema = z.object({
	content: z.string(),
	status: z.enum(["pending", "in_progress", "completed", "abandoned", "blocked"]),
	blocker: z.string().optional(),
});
export type TodoTask = z.infer<typeof todoTaskSchema>;

export const todoPhaseSchema = z.object({
	name: z.string(),
	tasks: z.array(todoTaskSchema),
});
export type TodoPhase = z.infer<typeof todoPhaseSchema>;

export const modelSchema = z.object({
	id: z.string(),
	name: z.string().optional(),
	provider: z.string().optional(),
	api: z.string().optional(),
	contextWindow: z.number().optional(),
});
export type ModelInfo = z.infer<typeof modelSchema>;

export const contextUsageSchema = z.object({
	tokens: z.number(),
	contextWindow: z.number(),
	percent: z.number(),
});
export type ContextUsage = z.infer<typeof contextUsageSchema>;

export const sessionStateSchema = z.object({
	sessionId: z.string().default(""),
	sessionName: z.string().optional(),
	sessionFile: z.string().optional(),
	model: modelSchema.optional(),
	thinkingLevel: z.string().optional(),
	isStreaming: z.boolean().default(false),
	isCompacting: z.boolean().default(false),
	isSettled: z.boolean().default(true),
	messageCount: z.number().default(0),
	queuedMessageCount: z.number().default(0),
	tokensPerSecond: z.number().optional(),
	contextUsage: contextUsageSchema.optional(),
	todoPhases: z.array(todoPhaseSchema).default([]),
	queuedMessages: z
		.object({ steering: z.array(z.string()).default([]), followUp: z.array(z.string()).default([]) })
		.default({ steering: [], followUp: [] }),
});
export type SessionState = z.infer<typeof sessionStateSchema>;

export const blockSchema = z.discriminatedUnion("kind", [
	z.object({ kind: z.literal("user"), id: z.string(), text: z.string() }),
	z.object({ kind: z.literal("text"), id: z.string(), text: z.string() }),
	z.object({ kind: z.literal("thinking"), id: z.string(), text: z.string() }),
	z.object({
		kind: z.literal("tool"),
		id: z.string(),
		name: z.string(),
		args: z.unknown().optional(),
		output: z.string().optional(),
		isError: z.boolean().default(false),
		/** True while the tool is still running. */
		running: z.boolean().default(false),
	}),
]);
export type Block = z.infer<typeof blockSchema>;

export const askQuestionSchema = z.object({
	id: z.string(),
	question: z.string(),
	header: z.string().optional(),
	options: z
		.array(z.object({ label: z.string(), description: z.string().optional() }))
		.default([]),
	multi: z.boolean().default(false),
	recommended: z.number().optional(),
});
export type AskQuestion = z.infer<typeof askQuestionSchema>;

/**
 * A dialog the agent is waiting on.
 *
 * `unknown` covers methods this app does not model yet; it is produced by
 * `parseUiRequest` rather than by the wire.
 */
export const uiRequestSchema = z.discriminatedUnion("method", [
	z.object({
		method: z.literal("select"),
		id: z.string(),
		title: z.string().optional(),
		message: z.string().optional(),
		options: z.array(z.string()).default([]),
	}),
	z.object({
		method: z.literal("confirm"),
		id: z.string(),
		title: z.string().optional(),
		message: z.string().optional(),
	}),
	z.object({
		method: z.literal("input"),
		id: z.string(),
		title: z.string().optional(),
		message: z.string().optional(),
		placeholder: z.string().optional(),
	}),
	z.object({
		method: z.literal("editor"),
		id: z.string(),
		title: z.string().optional(),
		message: z.string().optional(),
		placeholder: z.string().optional(),
	}),
	z.object({ method: z.literal("ask"), id: z.string(), questions: z.array(askQuestionSchema) }),
	z.object({
		method: z.literal("open_url"),
		id: z.string(),
		url: z.string(),
		launchUrl: z.string().optional(),
		instructions: z.string().optional(),
	}),
	z.object({
		method: z.literal("unknown"),
		id: z.string(),
		title: z.string().optional(),
		message: z.string().optional(),
	}),
]);
export type UiRequest = z.infer<typeof uiRequestSchema>;

const genericUiRequestSchema = z.object({
	method: z.string(),
	id: z.string(),
	title: z.string().optional(),
	message: z.string().optional(),
});

/**
 * Parses a UI request, degrading methods this app does not model to
 * `unknown` rather than dropping the request.
 */
export function parseUiRequest(value: unknown): UiRequest | null {
	const parsed = uiRequestSchema.safeParse(value);
	if (parsed.success) {
		return parsed.data;
	}
	const generic = genericUiRequestSchema.safeParse(value);
	if (!generic.success) {
		return null;
	}
	return {
		method: "unknown",
		id: generic.data.id,
		title: generic.data.title,
		message: generic.data.message,
	};
}

/** The answer sent back for a pending request. */
export const uiAnswerSchema = z.discriminatedUnion("type", [
	z.object({ type: z.literal("value"), value: z.string() }),
	z.object({ type: z.literal("confirm"), confirmed: z.boolean() }),
	z.object({
		type: z.literal("answers"),
		answers: z.array(
			z.object({
				id: z.string(),
				selectedOptions: z.array(z.string()),
				customInput: z.string().optional(),
			}),
		),
	}),
	z.object({ type: z.literal("cancelled"), timedOut: z.boolean() }),
]);
export type UiAnswer = z.infer<typeof uiAnswerSchema>;

export const sessionSummarySchema = z.object({
	path: z.string(),
	id: z.string(),
	cwd: z.string(),
	title: z.string().optional(),
	modified: z.number(),
});
export type SessionSummary = z.infer<typeof sessionSummarySchema>;

export const openResultSchema = z.object({
	project: projectSchema,
	state: sessionStateSchema,
	blocks: z.array(blockSchema),
	commands: z.array(commandSchema),
});
export type OpenResult = z.infer<typeof openResultSchema>;

export const subagentSchema = z.object({
	payload: z.object({
		id: z.string(),
		agent: z.string(),
		status: z.enum(["started", "completed", "failed", "aborted"]),
		index: z.number(),
		description: z.string().optional(),
	}),
});
export type SubagentEvent = z.infer<typeof subagentSchema>;

export const modelListSchema = z.array(
	z.object({
		id: z.string(),
		name: z.string().optional(),
		provider: z.string().optional(),
		api: z.string().optional(),
		contextWindow: z.number().optional(),
	}),
);
export type ModelListEntry = z.infer<typeof modelListSchema>[number];

/** Every event the backend pushes on `omp://event`. */
export const uiEventSchema = z.discriminatedUnion("kind", [
	z.object({
		projectId: z.string(),
		kind: z.literal("status"),
		payload: z.object({
			status: sessionStatusSchema,
			detail: z.string().optional(),
		}),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("messageStart"),
		payload: z.object({
			messageId: z.string(),
			role: z.string(),
			text: z.string().optional(),
		}),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("messageDelta"),
		payload: z.object({
			messageId: z.string(),
			channel: z.enum(["text", "thinking", "toolCall"]),
			delta: z.string(),
		}),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("messageEnd"),
		payload: z.object({ messageId: z.string(), role: z.string() }),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("toolStart"),
		payload: z.object({ toolCallId: z.string(), name: z.string(), args: z.unknown() }),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("toolEnd"),
		payload: z.object({
			toolCallId: z.string(),
			name: z.string(),
			result: z.unknown(),
			isError: z.boolean(),
		}),
	}),
	z.object({ projectId: z.string(), kind: z.literal("agentStart"), payload: z.object({}) }),
	z.object({
		projectId: z.string(),
		kind: z.literal("agentEnd"),
		payload: z.object({ yielded: z.boolean(), isTerminal: z.boolean() }),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("queue"),
		payload: z.object({ steering: z.array(z.string()), followUp: z.array(z.string()) }),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("notice"),
		payload: z.object({
			level: z.string(),
			message: z.string(),
			source: z.string().optional(),
		}),
	}),
	z.object({ projectId: z.string(), kind: z.literal("uiRequest"), payload: z.unknown() }),
	z.object({
		projectId: z.string(),
		kind: z.literal("commands"),
		payload: z.object({ commands: z.array(commandSchema) }),
	}),
	z.object({ projectId: z.string(), kind: z.literal("subagent"), payload: subagentSchema }),
	z.object({
		projectId: z.string(),
		kind: z.literal("promptResult"),
		payload: z.object({ status: z.string(), error: z.unknown() }),
	}),
	z.object({
		projectId: z.string(),
		kind: z.literal("error"),
		payload: z.object({ message: z.string() }),
	}),
]);
export type UiEvent = z.infer<typeof uiEventSchema>;
