import { useMemo, useState } from "react";

import type { Project } from "../schema";
import type { Workspace } from "../store";

type Props = {
	projects: Project[];
	workspaces: Record<string, Workspace>;
	activeId: string | null;
	theme: "dark" | "light";
	onToggleTheme: () => void;
	onSelect: (id: string) => void;
	onAdd: () => void;
	onRemove: (id: string) => void;
};

/** The tail of a path, enough to tell two projects apart. */
const shortPath = (project: Project): string => {
	if (project.displayPath) {
		return project.displayPath;
	}
	const parts = project.path.split("/").filter(Boolean);
	return parts.length <= 2 ? project.path : `…/${parts.slice(-2).join("/")}`;
};

export default function Sidebar({
	projects,
	workspaces,
	activeId,
	theme,
	onToggleTheme,
	onSelect,
	onAdd,
	onRemove,
}: Props) {
	const [filter, setFilter] = useState("");

	const shown = useMemo(() => {
		const needle = filter.trim().toLowerCase();
		if (!needle) {
			return projects;
		}
		return projects.filter(
			(project) =>
				project.name.toLowerCase().includes(needle) || project.path.toLowerCase().includes(needle),
		);
	}, [filter, projects]);

	return (
		<aside className="sidebar">
			<div className="sidebar-head">
				<span className="brand">
					omp<span className="brand-dim">-ui</span>
				</span>
				<button className="icon-button" onClick={onAdd} title="Add a project (⌘N)" aria-label="Add a project">
					+
				</button>
			</div>

			{projects.length > 4 ? (
				<div className="sidebar-filter">
					<input
						value={filter}
						placeholder="Filter projects"
						onChange={(event) => setFilter(event.target.value)}
					/>
				</div>
			) : null}

			<nav className="project-list">
				{projects.length === 0 ? <p className="hint">No projects yet.</p> : null}
				{projects.length > 0 && shown.length === 0 ? <p className="hint">No matches.</p> : null}
				{shown.map((project, index) => {
					const status = workspaces[project.id]?.status ?? "stopped";
					return (
						<div className={`project ${project.id === activeId ? "active" : ""}`} key={project.id}>
							<button className="project-main" onClick={() => onSelect(project.id)}>
								<span className={`dot ${status}`} aria-hidden="true" />
								<span className="project-text">
									<span className="project-name">{project.name}</span>
									<span className="project-path" title={project.path}>
										{shortPath(project)}
									</span>
								</span>
								{index < 9 ? <span className="project-shortcut">⌘{index + 1}</span> : null}
							</button>
							<button
								className="project-remove"
								onClick={() => onRemove(project.id)}
								aria-label={`Remove ${project.name}`}
								title="Remove project"
							>
								×
							</button>
						</div>
					);
				})}
			</nav>

			<div className="sidebar-foot">
				<span>
					<kbd>⌘K</kbd> composer
				</span>
				<span>
					<kbd>⌘N</kbd> add
				</span>
				<button
					className="icon-button"
					onClick={onToggleTheme}
					title={theme === "dark" ? "Switch to the light theme" : "Switch to the dark theme"}
					aria-label="Toggle the theme"
				>
					{theme === "dark" ? "☀" : "☾"}
				</button>
			</div>
		</aside>
	);
}
