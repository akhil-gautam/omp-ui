import { useEffect, useState } from "react";

import * as api from "../api";
import type { ModelListEntry, SessionSummary } from "../schema";
import type { Workspace } from "../store";

type Props = {
	workspace: Workspace;
	onError: (message: string) => void;
};

const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];

export default function ProjectHeader({ workspace, onError }: Props) {
	const { project, state } = workspace;
	const [models, setModels] = useState<ModelListEntry[]>([]);
	const [sessions, setSessions] = useState<SessionSummary[] | null>(null);

	useEffect(() => {
		let cancelled = false;
		void api
			.listModels(project.id)
			.then((list) => {
				if (!cancelled) {
					setModels(list);
				}
			})
			.catch((error: unknown) => onError(String(error)));
		return () => {
			cancelled = true;
		};
	}, [project.id, onError]);

	const currentModel = state?.model?.id ?? "";
	const context = state?.contextUsage;

	return (
		<header className="header">
			<div className="header-row">
				<div className="header-title">
					<h1>{project.name}</h1>
					<span className="path" title={project.path}>
						{project.path}
					</span>
				</div>

				<div className="header-actions">
					<select
						className="select"
						value={currentModel}
						onChange={(event) => {
							const picked = models.find((model) => model.id === event.target.value);
							if (!picked) {
								return;
							}
							void api
								.setModel(project.id, picked.provider ?? "", picked.id)
								.catch((error: unknown) => onError(String(error)));
						}}
					>
						{models.length === 0 ? (
							<option value={currentModel}>{currentModel || "no model"}</option>
						) : null}
						{models.map((model) => (
							<option key={model.id} value={model.id}>
								{model.name ?? model.id}
							</option>
						))}
					</select>

					<select
						className="select"
						value={state?.thinkingLevel ?? "off"}
						onChange={(event) =>
							void api
								.setThinking(project.id, event.target.value)
								.catch((error: unknown) => onError(String(error)))
						}
					>
						{THINKING_LEVELS.map((level) => (
							<option key={level} value={level}>
								{level}
							</option>
						))}
					</select>

					<button
						className="ghost"
						onClick={() =>
							void api.compact(project.id).catch((error: unknown) => onError(String(error)))
						}
					>
						compact
					</button>
					<button
						className="ghost"
						onClick={() =>
							void api.newSession(project.id).catch((error: unknown) => onError(String(error)))
						}
					>
						new
					</button>
					<button
						className="ghost"
						title="Stop omp for this project and free its memory"
						onClick={() =>
							void api.closeProject(project.id).catch((error: unknown) => onError(String(error)))
						}
					>
						stop
					</button>
					<button
						className="ghost"
						onClick={() => {
							if (sessions) {
								setSessions(null);
								return;
							}
							void api
								.listSessions(project.id)
								.then(setSessions)
								.catch((error: unknown) => onError(String(error)));
						}}
					>
						sessions
					</button>
				</div>
			</div>

			{context ? (
				<div className="context" title={`${context.tokens} of ${context.contextWindow} tokens`}>
					<div className="context-track">
						<div
							className="context-fill"
							style={{ width: `${Math.min(100, Math.round(context.percent * 100))}%` }}
						/>
					</div>
					<span className="context-label">{Math.round(context.percent * 100)}% context</span>
				</div>
			) : null}

			{sessions ? (
				<div className="session-panel">
					{sessions.length === 0 ? <p className="hint">No saved sessions for this project yet.</p> : null}
					{sessions.slice(0, 8).map((session) => (
						<button
							className="session-row"
							key={session.path}
							onClick={() => {
								setSessions(null);
								void api
									.switchSession(project.id, session.path)
									.catch((error: unknown) => onError(String(error)));
							}}
						>
							<span className="session-title">{session.title ?? session.id}</span>
							<span className="session-time">{new Date(session.modified * 1000).toLocaleString()}</span>
						</button>
					))}
				</div>
			) : null}
		</header>
	);
}
