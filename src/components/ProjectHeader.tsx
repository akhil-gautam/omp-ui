import { useEffect, useMemo, useState } from "react";

import * as api from "../api";
import type { ModelListEntry, SessionSummary } from "../schema";
import type { Workspace } from "../store";
import Picker from "./Picker";
import TodoPanel from "./TodoPanel";

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

	const modelOptions = useMemo(
		() =>
			models.map((model) => ({
				value: model.id,
				label: model.name ?? model.id,
				hint: model.contextWindow ? `${Math.round(model.contextWindow / 1000)}k` : undefined,
			})),
		[models],
	);

	const thinkingOptions = useMemo(
		() => THINKING_LEVELS.map((level) => ({ value: level, label: level })),
		[],
	);

	const currentModel = state?.model?.id ?? "";
	const context = state?.contextUsage;

	const pickModel = (id: string) => {
		const picked = models.find((model) => model.id === id);
		if (!picked) {
			return;
		}
		void api
			.setModel(project.id, picked.provider ?? "", picked.id)
			.catch((error: unknown) => onError(String(error)));
	};

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
					<Picker
						value={currentModel}
						options={modelOptions}
						onSelect={pickModel}
						fallback="no model"
					/>
					<Picker
						value={state?.thinkingLevel ?? "off"}
						options={thinkingOptions}
						onSelect={(level) =>
							void api
								.setThinking(project.id, level)
								.catch((error: unknown) => onError(String(error)))
						}
					/>
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

			<TodoPanel phases={state?.todoPhases ?? []} />

			{context ? (
				<div className="context" title={`${context.tokens} of ${context.contextWindow} tokens`}>
					<div className="context-track">
						<div
							className={`context-fill ${context.percent > 1 ? "over" : ""}`}
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
