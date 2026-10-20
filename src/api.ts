/** Typed wrappers around the backend's commands and events. */

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";

import {
	modelListSchema,
	openResultSchema,
	projectSchema,
	sessionSummarySchema,
	uiEventSchema,
	type ModelListEntry,
	type OpenResult,
	type Project,
	type SessionSummary,
	type UiAnswer,
	type UiEvent,
} from "./schema";

export const listProjects = async (): Promise<Project[]> => {
	const projects = await invoke<unknown[]>("list_projects");
	return projects.map((project) => projectSchema.parse(project));
};

export const addProject = async (path: string): Promise<Project> =>
	projectSchema.parse(await invoke<unknown>("add_project", { path }));

export const removeProject = (id: string) => invoke<void>("remove_project", { id });

/** The project that was open when the app last closed. */
export const activeProject = () => invoke<string | null>("active_project");

export const openProject = async (id: string): Promise<OpenResult> =>
	openResultSchema.parse(await invoke<unknown>("open_project", { id }));

export const closeProject = (id: string) => invoke<void>("close_project", { id });

/** Sends a prompt. `behavior` steers a running turn instead of queueing a follow-up. */
export const sendMessage = (id: string, text: string, behavior?: "steer") =>
	invoke<void>("send_message", { id, text, behavior });

export const abortTurn = (id: string) => invoke<void>("abort_turn", { id });

export const setModel = (id: string, provider: string, modelId: string) =>
	invoke<void>("set_model", { id, provider, modelId });

export const setThinking = (id: string, level: string) => invoke<void>("set_thinking", { id, level });

export const listModels = async (id: string): Promise<ModelListEntry[]> =>
	modelListSchema.parse(await invoke<unknown>("list_models", { id }));

export const compact = (id: string) => invoke<void>("compact", { id });

export const newSession = (id: string) => invoke<void>("new_session", { id });

export const listSessions = async (id: string): Promise<SessionSummary[]> =>
	sessionSummarySchema.array().parse(await invoke<unknown>("list_sessions", { id }));

export const switchSession = (id: string, path: string) => invoke<void>("switch_session", { id, path });

export const refreshState = (id: string) => invoke<unknown>("refresh_state", { id });

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
