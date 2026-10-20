import { useCallback, useEffect, useMemo, useReducer, useState } from "react";

import * as api from "./api";
import { sessionStateSchema, type UiEvent } from "./schema";
import { initialStore, reducer } from "./store";
import Composer from "./components/Composer";
import ProjectHeader from "./components/ProjectHeader";
import Sidebar from "./components/Sidebar";
import Transcript from "./components/Transcript";
import UiDialog from "./components/UiDialog";

export default function App() {
	const [store, dispatch] = useReducer(reducer, initialStore);
	const [banner, setBanner] = useState<string | null>(null);

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
			const unlisten = await api.onUiEvent(handleEvent);
			if (cancelled) {
				unlisten();
				return;
			}
			dispose = unlisten;
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
		const path = await api.pickFolder();
		if (!path) {
			return;
		}
		try {
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

	return (
		<div className="app">
			<Sidebar
				projects={store.projects}
				workspaces={store.workspaces}
				activeId={store.activeId}
				onSelect={(id) => void openProject(id)}
				onAdd={() => void addProject()}
				onRemove={(id) => void removeProject(id)}
			/>

			<main className="main">
				{active ? (
					<>
						<ProjectHeader workspace={active} onError={setBanner} />
						<Transcript blocks={active.blocks} />
						<Composer
							workspace={active}
							onSend={(text) => void send(text)}
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
