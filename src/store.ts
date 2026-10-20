/** The application state and the reducer that keeps it in sync with omp. */

import { parseUiRequest } from "./schema";
import type {
	Block,
	CommandInfo,
	OpenResult,
	Project,
	SessionState,
	SessionStatus,
	UiEvent,
	UiRequest,
} from "./schema";

export type Notice = {
	level: string;
	message: string;
};

export type SubagentSummary = {
	id: string;
	agent: string;
	status: "started" | "completed" | "failed" | "aborted";
	description?: string;
};

export type Workspace = {
	project: Project;
	status: SessionStatus;
	blocks: Block[];
	state: SessionState | null;
	commands: CommandInfo[];
	/** A dialog the agent is waiting on. */
	pendingRequest: UiRequest | null;
	queue: { steering: string[]; followUp: string[] };
	notices: Notice[];
	subagents: SubagentSummary[];
	error: string | null;
};

export type Store = {
	projects: Project[];
	activeId: string | null;
	workspaces: Record<string, Workspace>;
};

export const initialStore: Store = { projects: [], activeId: null, workspaces: {} };

export type Action =
	| { type: "projects"; projects: Project[] }
	| { type: "active"; id: string | null }
	| { type: "open"; result: OpenResult }
	| { type: "event"; event: UiEvent }
	| { type: "state"; projectId: string; state: SessionState }
	| { type: "localUser"; projectId: string; text: string }
	| { type: "forget"; projectId: string }
	| { type: "error"; projectId: string; message: string }
	| { type: "clearError"; projectId: string }
	| { type: "dismissRequest"; projectId: string };

/** Renders a tool result for display. */
export const renderToolResult = (result: unknown): string | undefined => {
	if (result === undefined || result === null) {
		return undefined;
	}
	if (typeof result === "string") {
		return result;
	}
	try {
		return JSON.stringify(result, null, 2);
	} catch {
		return String(result);
	}
};

let pendingCounter = 0;

export function reducer(store: Store, action: Action): Store {
	switch (action.type) {
		case "projects":
			return { ...store, projects: action.projects };

		case "active":
			return { ...store, activeId: action.id };

		case "open": {
			const { project, state, blocks, commands } = action.result;
			const previous = store.workspaces[project.id];
			return {
				...store,
				projects: store.projects.some((entry) => entry.id === project.id)
					? store.projects
					: [...store.projects, project],
				workspaces: {
					...store.workspaces,
					[project.id]: {
						project,
						status: previous?.status ?? "starting",
						blocks,
						state,
						commands,
						pendingRequest: previous?.pendingRequest ?? null,
						queue: previous?.queue ?? { steering: [], followUp: [] },
						notices: previous?.notices ?? [],
						subagents: previous?.subagents ?? [],
						error: null,
					},
				},
			};
		}

		case "event": {
			const workspace = store.workspaces[action.event.projectId];
			if (!workspace) {
				return store;
			}
			return {
				...store,
				workspaces: {
					...store.workspaces,
					[action.event.projectId]: applyEvent(workspace, action.event),
				},
			};
		}

		case "state": {
			const workspace = store.workspaces[action.projectId];
			if (!workspace) {
				return store;
			}
			return {
				...store,
				workspaces: {
					...store.workspaces,
					[action.projectId]: { ...workspace, state: action.state },
				},
			};
		}

		case "localUser": {
			const workspace = store.workspaces[action.projectId];
			if (!workspace) {
				return store;
			}
			pendingCounter += 1;
			const block: Block = {
				kind: "user",
				id: `pending:${pendingCounter}`,
				text: action.text,
			};
			return {
				...store,
				workspaces: {
					...store.workspaces,
					[action.projectId]: { ...workspace, blocks: [...workspace.blocks, block] },
				},
			};
		}

		case "forget": {
			const workspaces = { ...store.workspaces };
			delete workspaces[action.projectId];
			return {
				...store,
				activeId: store.activeId === action.projectId ? null : store.activeId,
				projects: store.projects.filter((project) => project.id !== action.projectId),
				workspaces,
			};
		}

		case "error": {
			const workspace = store.workspaces[action.projectId];
			if (!workspace) {
				return store;
			}
			return {
				...store,
				workspaces: {
					...store.workspaces,
					[action.projectId]: { ...workspace, error: action.message },
				},
			};
		}

		case "clearError": {
			const workspace = store.workspaces[action.projectId];
			if (!workspace) {
				return store;
			}
			return {
				...store,
				workspaces: {
					...store.workspaces,
					[action.projectId]: { ...workspace, error: null },
				},
			};
		}

		case "dismissRequest": {
			const workspace = store.workspaces[action.projectId];
			if (!workspace) {
				return store;
			}
			return {
				...store,
				workspaces: {
					...store.workspaces,
					[action.projectId]: { ...workspace, pendingRequest: null },
				},
			};
		}
	}
}

function applyEvent(workspace: Workspace, event: UiEvent): Workspace {
	switch (event.kind) {
		case "status":
			return {
				...workspace,
				status: event.payload.status,
				error: event.payload.detail ?? workspace.error,
			};

		case "messageStart": {
			const { messageId, role, text } = event.payload;
			if (role !== "user" || !text) {
				return workspace;
			}
			// The user's own message is rendered optimistically; the confirmed
			// one replaces it.
			const pending = workspace.blocks.findIndex(
				(block) => block.kind === "user" && block.id.startsWith("pending:"),
			);
			if (pending < 0) {
				return { ...workspace, blocks: [...workspace.blocks, { kind: "user", id: messageId, text }] };
			}
			const blocks = [...workspace.blocks];
			blocks[pending] = { kind: "user", id: messageId, text };
			return { ...workspace, blocks };
		}

		case "messageDelta": {
			const { messageId, channel, delta } = event.payload;
			if (channel === "toolCall") {
				return workspace;
			}
			const id = `${messageId}:${channel}`;
			const index = workspace.blocks.findIndex((block) => block.id === id);
			if (index < 0) {
				const block: Block =
					channel === "thinking"
						? { kind: "thinking", id, text: delta }
						: { kind: "text", id, text: delta };
				return { ...workspace, blocks: [...workspace.blocks, block] };
			}
			const block = workspace.blocks[index];
			if (!block || (block.kind !== "text" && block.kind !== "thinking")) {
				return workspace;
			}
			const blocks = [...workspace.blocks];
			blocks[index] =
				block.kind === "text"
					? { kind: "text", id: block.id, text: block.text + delta }
					: { kind: "thinking", id: block.id, text: block.text + delta };
			return { ...workspace, blocks };
		}

		case "messageEnd":
			return workspace;

		case "toolStart": {
			const { toolCallId, name, args } = event.payload;
			const index = workspace.blocks.findIndex((block) => block.id === toolCallId);
			if (index < 0) {
				const block: Block = {
					kind: "tool",
					id: toolCallId,
					name,
					args,
					isError: false,
					running: true,
				};
				return { ...workspace, blocks: [...workspace.blocks, block] };
			}
			const block = workspace.blocks[index];
			if (!block || block.kind !== "tool") {
				return workspace;
			}
			const blocks = [...workspace.blocks];
			blocks[index] = { ...block, name, args, running: true };
			return { ...workspace, blocks };
		}

		case "toolEnd": {
			const { toolCallId, name, result, isError } = event.payload;
			const output = renderToolResult(result);
			const index = workspace.blocks.findIndex((block) => block.id === toolCallId);
			if (index < 0) {
				const block: Block = {
					kind: "tool",
					id: toolCallId,
					name,
					output,
					isError,
					running: false,
				};
				return { ...workspace, blocks: [...workspace.blocks, block] };
			}
			const block = workspace.blocks[index];
			if (!block || block.kind !== "tool") {
				return workspace;
			}
			const blocks = [...workspace.blocks];
			blocks[index] = {
				...block,
				name: block.name || name,
				output,
				isError,
				running: false,
			};
			return { ...workspace, blocks };
		}

		case "agentStart":
			return { ...workspace, status: "busy" };

		case "agentEnd":
			return { ...workspace, status: "idle" };

		case "queue":
			return {
				...workspace,
				queue: { steering: event.payload.steering, followUp: event.payload.followUp },
			};

		case "notice":
			return {
				...workspace,
				notices: [...workspace.notices, { level: event.payload.level, message: event.payload.message }].slice(
					-20,
				),
			};

		case "uiRequest": {
			const request = parseUiRequest(event.payload);
			return request ? { ...workspace, pendingRequest: request } : workspace;
		}

		case "subagent": {
			const { payload } = event.payload;
			const known = workspace.subagents.some((entry) => entry.id === payload.id);
			if (!known) {
				return {
					...workspace,
					subagents: [
						...workspace.subagents,
						{
							id: payload.id,
							agent: payload.agent,
							status: payload.status,
							description: payload.description,
						},
					],
				};
			}
			return {
				...workspace,
				subagents: workspace.subagents.map((entry) =>
					entry.id === payload.id ? { ...entry, status: payload.status } : entry,
				),
			};
		}

		case "commands":
			return { ...workspace, commands: event.payload.commands };

		case "promptResult":
			return event.payload.status === "error"
				? { ...workspace, error: "the turn failed" }
				: workspace;

		case "error":
			return { ...workspace, error: event.payload.message };
	}
}
