import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";

import * as api from "./api";
import { sessionStateSchema, type UiEvent } from "./schema";
import { initialStore, reducer } from "./store";
import Composer from "./components/Composer";
import ProjectHeader from "./components/ProjectHeader";
import Sidebar from "./components/Sidebar";
import Transcript from "./components/Transcript";
import UiDialog from "./components/UiDialog";

type Theme = "dark" | "light";

const THEME_KEY = "omp-ui.theme";

export default function App() {
	const [store, dispatch] = useReducer(reducer, initialStore);
	const [banner, setBanner] = useState<string | null>(null);
	const [theme, setTheme] = useState<Theme>(() => {
		const stored = localStorage.getItem(THEME_KEY);
		if (stored === "light" || stored === "dark") {
			return stored;
		}
		return window.matchMedia?.("(prefers-color-scheme: light)").matches ? "light" : "dark";
	});
	const composer = useRef<HTMLTextAreaElement>(null);
	const [suggestion, setSuggestion] = useState<string | null>(null);
	const onSuggestionApplied = useCallback(() => setSuggestion(null), []);

	useEffect(() => {
		document.documentElement.dataset.theme = theme;
		localStorage.setItem(THEME_KEY, theme);
	}, [theme]);

	useEffect(() => {
		// macOS draws the window controls over the app's top-left corner, so
		// the app's own header has to start below them. Other platforms have
		// a title bar of their own and need no room.
		const mac = navigator.userAgent.includes("Mac");
		document.documentElement.style.setProperty("--titlebar-height", mac ? "38px" : "0px");
	}, []);

	const handleEvent = useCallback((event: UiEvent) => {
		dispatch({ type: "event", event });
		if (event.kind !== "agentEnd") {
			return;
		}
		void api
			.refreshState(event.projectId)
			.then((state) => {
				const parsed = sessionStateSchema.safeParse(state);
				if (parsed.success) {
					dispatch({ type: "state", projectId: event.projectId, state: parsed.data });
				}
			})
			.catch(() => undefined);
	}, []);

	const openProject = useCallback(async (id: string) => {
		dispatch({ type: "active", id });
		try {
			const result = await api.openProject(id);
			dispatch({ type: "open", result });
		} catch (error) {
			setBanner(String(error));
		}
	}, []);

	useEffect(() => {
		let dispose: (() => void) | undefined;
		let cancelled = false;

		void (async () => {
			// Subscribe first: opening a project starts omp, and omp has
			// things to say the moment it connects.
			try {
				const unlisten = await api.onUiEvent(handleEvent);
				if (cancelled) {
					unlisten();
					return;
				}
				dispose = unlisten;
			} catch (error) {
				// Without the event stream the UI would sit there looking
				// idle while the agent worked; say so instead.
				setBanner(`The event stream failed: ${String(error)}`);
				return;
			}

			try {
				const projects = await api.listProjects();
				if (!cancelled) {
					dispatch({ type: "projects", projects });
				}
				// Reopen whatever was open when the app last closed.
				const previous = await api.activeProject();
				if (!cancelled && previous && projects.some((project) => project.id === previous)) {
					await openProject(previous);
				}
			} catch (error) {
				setBanner(String(error));
			}
		})();

		return () => {
			cancelled = true;
			dispose?.();
		};
	}, [handleEvent, openProject]);

	const active = useMemo(
		() => (store.activeId ? store.workspaces[store.activeId] : undefined),
		[store.activeId, store.workspaces],
	);

	const addProject = useCallback(async () => {
		try {
			const path = await api.pickFolder();
			if (!path) {
				return;
			}
			const project = await api.addProject(path);
			dispatch({ type: "projects", projects: [...store.projects, project] });
			await openProject(project.id);
		} catch (error) {
			setBanner(String(error));
		}
	}, [openProject, store.projects]);

	const removeProject = useCallback(async (id: string) => {
		try {
			await api.removeProject(id);
			dispatch({ type: "forget", projectId: id });
		} catch (error) {
			setBanner(String(error));
		}
	}, []);

	const send = useCallback(
		async (text: string, behavior?: "steer") => {
			if (!active) {
				return;
			}
			dispatch({ type: "localUser", projectId: active.project.id, text });
			try {
				await api.sendMessage(active.project.id, text, behavior);
			} catch (error) {
				setBanner(String(error));
			}
		},
		[active],
	);

	const answer = useCallback(
		async (requestId: string, answerBody: Parameters<typeof api.answerUi>[2]) => {
			if (!active) {
				return;
			}
			dispatch({ type: "dismissRequest", projectId: active.project.id });
			try {
				await api.answerUi(active.project.id, requestId, answerBody);
			} catch (error) {
				setBanner(String(error));
			}
		},
		[active],
	);

	useEffect(() => {
		const onKeyDown = (event: KeyboardEvent) => {
			if (!(event.metaKey || event.ctrlKey) || event.altKey) {
				return;
			}
			const key = event.key.toLowerCase();
			if (key === "k" || key === "/") {
				event.preventDefault();
				composer.current?.focus();
				return;
			}
			if (key === "n") {
				event.preventDefault();
				void addProject();
				return;
			}
			const index = Number(key) - 1;
			const project = store.projects[index];
			if (project) {
				event.preventDefault();
				void openProject(project.id);
			}
		};
		window.addEventListener("keydown", onKeyDown);
		return () => window.removeEventListener("keydown", onKeyDown);
	}, [addProject, openProject, store.projects]);

	return (
		<div className="app">
			<Sidebar
				projects={store.projects}
				workspaces={store.workspaces}
				activeId={store.activeId}
				theme={theme}
				onToggleTheme={() => setTheme((value) => (value === "dark" ? "light" : "dark"))}
				onSelect={(id) => void openProject(id)}
				onAdd={() => void addProject()}
				onRemove={(id) => void removeProject(id)}
			/>

			<main className="main">
				{active ? (
					<>
						<ProjectHeader workspace={active} onError={setBanner} />
						<Transcript blocks={active.blocks} onSuggest={setSuggestion} />
						<Composer
							workspace={active}
							inputRef={composer}
							suggestion={suggestion}
							onSuggestionApplied={onSuggestionApplied}
							onSend={(text, behavior) => void send(text, behavior)}
							onAbort={() =>
								void api
									.abortTurn(active.project.id)
									.catch((error: unknown) => setBanner(String(error)))
							}
						/>
					</>
				) : (
					<div className="empty">
						<h1>omp-ui</h1>
						<p>Add a project to give omp a place to work.</p>
						<button className="primary" onClick={() => void addProject()}>
							Add a project
						</button>
					</div>
				)}
			</main>

			{banner ? (
				<div className="banner" role="alert">
					<span>{banner}</span>
					<button onClick={() => setBanner(null)} aria-label="Dismiss">
						×
					</button>
				</div>
			) : null}

			{active?.pendingRequest ? (
				<UiDialog
					request={active.pendingRequest}
					onAnswer={(body) => void answer(active.pendingRequest!.id, body)}
					onCancel={(requestId) => void answer(requestId, { type: "cancelled", timedOut: false })}
				/>
			) : null}
		</div>
	);
}
