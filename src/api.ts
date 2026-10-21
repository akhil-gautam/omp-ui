/** Typed wrappers around the backend's commands and events. */

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import type { z } from "zod";

import {
	inventorySchema,
	modelListSchema,
	openResultSchema,
	projectSchema,
	sessionStateSchema,
	sessionSummarySchema,
	uiEventSchema,
	type Inventory,
	type ModelListEntry,
	type OpenResult,
	type Project,
	type SessionSummary,
	type SessionState,
	type UiAnswer,
	type UiEvent,
} from "./schema";

/**
 * Reads a payload from the backend.
 *
 * A payload that does not match means the two halves disagree, which the
 * reader should be told about in words rather than as a wall of JSON. The
 * details go to the console, where they are useful.
 */
function parse<T>(schema: z.ZodType<T>, value: unknown, what: string): T {
	const parsed = schema.safeParse(value);
	if (parsed.success) {
		return parsed.data;
	}
	console.error(`the backend sent a ${what} the app does not understand`, parsed.error.issues);
	const issue = parsed.error.issues[0];
	const where = issue && issue.path.length > 0 ? ` (${issue.path.join(".")})` : "";
	throw new Error(`The app and the backend disagree about the ${what}${where}.`);
}

export const listProjects = async (): Promise<Project[]> => {
	const projects = await invoke<unknown[]>("list_projects");
	return projects.map((project) => parse(projectSchema, project, "project"));
};

export const addProject = async (path: string): Promise<Project> =>
	parse(projectSchema, await invoke<unknown>("add_project", { path }), "project");

export const removeProject = (id: string) => invoke<void>("remove_project", { id });

/** The project that was open when the app last closed. */
export const activeProject = () => invoke<string | null>("active_project");

export const openProject = async (id: string): Promise<OpenResult> =>
	parse(openResultSchema, await invoke<unknown>("open_project", { id }), "session");

export const closeProject = (id: string) => invoke<void>("close_project", { id });

/** Sends a prompt. `behavior` steers a running turn instead of queueing a follow-up. */
export const sendMessage = (id: string, text: string, behavior?: "steer") =>
	invoke<void>("send_message", { id, text, behavior });

export const abortTurn = (id: string) => invoke<void>("abort_turn", { id });

export const setModel = (id: string, provider: string, modelId: string) =>
	invoke<void>("set_model", { id, provider, modelId });

export const setThinking = (id: string, level: string) => invoke<void>("set_thinking", { id, level });

export const listModels = async (id: string): Promise<ModelListEntry[]> =>
	parse(modelListSchema, await invoke<unknown>("list_models", { id }), "model list");

export const compact = (id: string) => invoke<void>("compact", { id });

export const newSession = (id: string) => invoke<void>("new_session", { id });

export const listSessions = async (id: string): Promise<SessionSummary[]> =>
	parse(sessionSummarySchema.array(), await invoke<unknown>("list_sessions", { id }), "session list");

export const switchSession = (id: string, path: string) => invoke<void>("switch_session", { id, path });

/** The session's state after a turn. */
export const refreshState = async (id: string): Promise<SessionState> =>
	parse(sessionStateSchema, await invoke<unknown>("refresh_state", { id }), "session state");

/** The branch the project is on, when it is a git repository. */
export const branch = (id: string) => invoke<string | null>("branch", { id });

/** How the session behaves: `interactive` or `autopilot`. */
export const setSessionMode = (id: string, mode: string) => invoke<void>("set_session_mode", { id, mode });

/** What the project has, for the sidebar's counts. */
export const inventory = async (id: string): Promise<Inventory> =>
	parse(inventorySchema, await invoke<unknown>("inventory", { id }), "inventory");

/** The name of the user, for the greeting. */
export const userName = async (): Promise<string> => (await invoke<string>("user_name")) ?? "";

/** How omp asks before it acts, as configured. */
export const approvalMode = async (): Promise<string | null> =>
	(await invoke<string | null>("approval_mode")) ?? null;

export const answerUi = (id: string, requestId: string, answer: UiAnswer) =>
	invoke<void>("answer_ui", { id, requestId, answer });

/** Opens the native folder picker. */
export const pickFolder = async (): Promise<string | null> => {
	const picked = await open({ directory: true, multiple: false, title: "Add a project" });
	return typeof picked === "string" ? picked : null;
};

/**
 * Subscribes to backend events.
 *
 * Payloads that do not match the contract are dropped: a malformed frame
 * must never corrupt the UI state.
 */
export function onUiEvent(handler: (event: UiEvent) => void): Promise<UnlistenFn> {
	return listen<unknown>("omp://event", ({ payload }) => {
		const parsed = uiEventSchema.safeParse(payload);
		if (parsed.success) {
			handler(parsed.data);
		}
	});
}
