import { useState } from "react";

import type { TodoPhase, TodoTask } from "../schema";

type Props = {
	phases: TodoPhase[];
};

const STATUS_MARK: Record<TodoTask["status"], string> = {
	pending: "○",
	in_progress: "◐",
	completed: "✓",
	blocked: "!",
	abandoned: "×",
};

export default function TodoPanel({ phases }: Props) {
	const [open, setOpen] = useState(false);
	const tasks = phases.flatMap((phase) => phase.tasks);
	if (tasks.length === 0) {
		return null;
	}
	const done = tasks.filter((task) => task.status === "completed").length;

	return (
		<div className={`todos ${open ? "open" : ""}`}>
			<button className="todos-head" onClick={() => setOpen((value) => !value)}>
				<span className="todos-title">Plan</span>
				<span className="todos-progress">
					<span className="todos-track">
						<span className="todos-fill" style={{ width: `${(done / tasks.length) * 100}%` }} />
					</span>
					<span className="todos-count">
						{done}/{tasks.length}
					</span>
				</span>
			</button>

			{open ? (
				<div className="todos-list">
					{phases.map((phase) => (
						<div className="todo-phase" key={phase.name}>
							{phases.length > 1 ? <div className="todo-phase-name">{phase.name}</div> : null}
							{phase.tasks.map((task) => (
								<div className={`todo todo-${task.status}`} key={task.content}>
									<span className="todo-mark" aria-hidden="true">
										{STATUS_MARK[task.status]}
									</span>
									<span className="todo-text">{task.content}</span>
									{task.blocker ? <span className="todo-blocker">{task.blocker}</span> : null}
								</div>
							))}
						</div>
					))}
				</div>
			) : null}
		</div>
	);
}
