import type { Project } from "../schema";
import type { Workspace } from "../store";

type Props = {
	projects: Project[];
	workspaces: Record<string, Workspace>;
	activeId: string | null;
	onSelect: (id: string) => void;
	onAdd: () => void;
	onRemove: (id: string) => void;
};

export default function Sidebar({ projects, workspaces, activeId, onSelect, onAdd, onRemove }: Props) {
	return (
		<aside className="sidebar">
			<div className="sidebar-head">
				<span className="brand">
					omp<span className="brand-dim">-ui</span>
				</span>
				<button className="icon-button" onClick={onAdd} title="Add a project" aria-label="Add a project">
					+
				</button>
			</div>

			<nav className="project-list">
				{projects.length === 0 ? <p className="hint">No projects yet.</p> : null}
				{projects.map((project) => {
					const status = workspaces[project.id]?.status ?? "stopped";
					return (
						<div className={`project ${project.id === activeId ? "active" : ""}`} key={project.id}>
							<button className="project-main" onClick={() => onSelect(project.id)}>
								<span className={`dot ${status}`} aria-hidden="true" />
								<span className="project-name">{project.name}</span>
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
		</aside>
	);
}
