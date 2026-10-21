import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";

import * as api from "./api";
import { type Inventory, type ModelListEntry, type SessionSummary, type UiEvent } from "./schema";
import { initialStore, reducer } from "./store";
import Composer, { type ComposerChrome } from "./components/Composer";
import IconRail from "./components/IconRail";
import { type SessionMode } from "./components/ModeMenu";
import Panel from "./components/Panel";
import Sidebar from "./components/Sidebar";
import TodoPanel from "./components/TodoPanel";
import TopBar from "./components/TopBar";
import Transcript from "./components/Transcript";
import UiDialog from "./components/UiDialog";
import { IconPlay, IconStop } from "./components/Icons";

type Theme = "dark" | "light";

const THEME_KEY = "omp-ui.theme";

/** The pages the main column can show. */
type View = "transcript" | "overview" | "tools" | "skills" | "extensions" | "prompts";

export default function App() {
	const [store, dispatch] = useReducer(reducer, initialStore);
	const [banner, setBanner] = useState<string | null>(null);
	const [theme, setTheme] = useState<Theme>(() => {
		const stored = localStorage.getItem(THEME_KEY);
		if (stored === "light" || stored === "dark") {
			return stored;
		}
		// The interface is dark by default; the rail toggles the other one.
		return "dark";
	});
	const [sidebarOpen, setSidebarOpen] = useState(true);
	const [view, setView] = useState<View>("transcript");
	const [mode, setMode] = useState<SessionMode>("interactive");
	const [branch, setBranch] = useState<string | null>(null);
	const [inventory, setInventory] = useState<Inventory | null>(null);
	const [approval, setApproval] = useState<string | null>(null);
	const [user, setUser] = useState("");
	const [models, setModels] = useState<ModelListEntry[]>([]);
	const [sessions, setSessions] = useState<SessionSummary[]>([]);
	const [sessionIndex, setSessionIndex] = useState(0);
	const composer = useRef<HTMLTextAreaElement>(null);
	const [suggestion, setSuggestion] = useState<string | null>(null);
	const onSuggestionApplied = useCallback(() => setSuggestion(null), []);

	// The session mode has to be known when a project opens, but opening a
	// project must not depend on it — a ref keeps that one-way.
	const modeRef = useRef(mode);
	useEffect(() => {
		modeRef.current = mode;
	}, [mode]);

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

	useEffect(() => {
		void api
			.userName()
			.then(setUser)
			.catch(() => undefined);
		void api
			.approvalMode()
			.then(setApproval)
			.catch(() => undefined);
	}, []);

	const handleEvent = useCallback((event: UiEvent) => {
		dispatch({ type: "event", event });
		if (event.kind !== "agentEnd") {
			return;
		}
		void api
			.refreshState(event.projectId)
			.then((state) => {
				dispatch({ type: "state", projectId: event.projectId, state });
			})
			.catch((error: unknown) => setBanner(String(error)));
	}, []);

	const openProject = useCallback(async (id: string) => {
		dispatch({ type: "active", id });
		try {
			const result = await api.openProject(id);
			dispatch({ type: "open", result });
			// omp starts in its own configuration's queue modes; the mode the
			// app shows has to be the mode omp is actually in.
			await api.setSessionMode(id, modeRef.current);
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

	// Everything that belongs to the open project is read once, when it
	// changes: the branch, the catalogue, the model list and the session
	// history.
	useEffect(() => {
		if (!active) {
			setBranch(null);
			setInventory(null);
			setModels([]);
			setSessions([]);
			setSessionIndex(0);
			return;
		}
		const id = active.project.id;
		let cancelled = false;

		void api
			.branch(id)
			.then((value) => {
				if (!cancelled) {
					setBranch(value);
				}
			})
			.catch(() => undefined);
		void api
			.inventory(id)
			.then((value) => {
				if (!cancelled) {
					setInventory(value);
				}
			})
			.catch(() => undefined);
		void api
			.listModels(id)
			.then((value) => {
				if (!cancelled) {
					setModels(value);
				}
			})
			.catch(() => undefined);
		void api
			.listSessions(id)
			.then((value) => {
				if (!cancelled) {
					setSessions(value);
					setSessionIndex(0);
				}
			})
			.catch(() => undefined);

		return () => {
			cancelled = true;
		};
	}, [active]);

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

	const changeMode = useCallback(
		(next: SessionMode) => {
			setMode(next);
			if (!active) {
				return;
			}
			void api
				.setSessionMode(active.project.id, next)
				.catch((error: unknown) => setBanner(String(error)));
		},
		[active],
	);

	const pickModel = useCallback(
		(id: string) => {
			if (!active) {
				return;
			}
			const picked = models.find((model) => model.id === id);
			if (!picked) {
				return;
			}
			void api
				.setModel(active.project.id, picked.provider ?? "", picked.id)
				.catch((error: unknown) => setBanner(String(error)));
		},
		[active, models],
	);

	const pickThinking = useCallback(
		(level: string) => {
			if (!active) {
				return;
			}
			void api
				.setThinking(active.project.id, level)
				.catch((error: unknown) => setBanner(String(error)));
		},
		[active],
	);

	// Back and forward walk the project's session history.
	const step = useCallback(
		async (delta: number) => {
			if (!active) {
				return;
			}
			const next = sessionIndex + delta;
			const target = sessions[next];
			if (!target) {
				return;
			}
			setSessionIndex(next);
			try {
				await api.switchSession(active.project.id, target.path);
				const result = await api.openProject(active.project.id);
				dispatch({ type: "open", result });
			} catch (error) {
				setBanner(String(error));
			}
		},
		[active, sessionIndex, sessions],
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

	const chrome: ComposerChrome = {
		projects: store.projects,
		onProject: (id) => void openProject(id),
		models,
		model: active?.state?.model?.id ?? "",
		onModel: pickModel,
		mode,
		onMode: changeMode,
		thinking: active?.state?.thinkingLevel ?? "off",
		onThinking: pickThinking,
		branch,
		approval,
	};

	const greeting = user ? `What are we building, ${user}?` : "What are we building?";
	const showGreeting = view === "transcript" && (active?.blocks.length ?? 0) === 0;

	return (
		<div className={`app ${sidebarOpen ? "" : "no-sidebar"}`}>
			<IconRail
				theme={theme}
				onToggleTheme={() => setTheme((value) => (value === "dark" ? "light" : "dark"))}
				onToggleSidebar={() => setSidebarOpen((value) => !value)}
				sidebarOpen={sidebarOpen}
			/>

			<Sidebar
				projects={store.projects}
				workspaces={store.workspaces}
				activeId={store.activeId}
				inventory={inventory}
				view={view}
				onView={(next) => setView(next as View)}
				onSelect={(id) => void openProject(id)}
				onAdd={() => void addProject()}
				onRemove={(id) => void removeProject(id)}
			/>

			<main className="main">
				<TopBar
					projects={store.projects}
					activeId={store.activeId}
					onSelect={(id) => {
						setView("transcript");
						void openProject(id);
					}}
					onBack={() => void step(1)}
					onForward={() => void step(-1)}
					canBack={sessionIndex < sessions.length - 1}
					canForward={sessionIndex > 0}
				>
					{active ? (
						<>
							<button
								className="icon-button"
								title="Start a new session"
								aria-label="Start a new session"
								onClick={() =>
									void api
										.newSession(active.project.id)
										.catch((error: unknown) => setBanner(String(error)))
								}
							>
								<IconPlay />
							</button>
							<button
								className="icon-button"
								title="Stop omp for this project and free its memory"
								aria-label="Stop omp"
								onClick={() =>
									void api
										.closeProject(active.project.id)
										.catch((error: unknown) => setBanner(String(error)))
								}
							>
								<IconStop />
							</button>
						</>
					) : null}
				</TopBar>

				{active ? (
					<>
						{active.state?.todoPhases?.length ? (
							<div className="todos-strip">
								<TodoPanel phases={active.state.todoPhases} />
							</div>
						) : null}

						{showGreeting ? (
							<div className="greeting">
								<h1>{greeting}</h1>
								<p>omp is ready in {active.project.name}.</p>
							</div>
						) : null}

						{view === "transcript" ? (
							<Transcript blocks={active.blocks} onSuggest={setSuggestion} />
						) : (
							<Panel
								view={view}
								workspace={active}
								inventory={inventory}
								branch={branch}
								mode={mode}
								approval={approval}
							/>
						)}

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
							chrome={chrome}
						/>
					</>
				) : (
					<div className="empty">
						<h1>{greeting}</h1>
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
