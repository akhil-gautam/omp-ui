import type { Inventory, Project } from "../schema";
import type { Workspace } from "../store";
import { IconBook, IconChevronRight, IconFilter, IconHome, IconMore, IconPlug, IconSearch, IconServer, IconWrench } from "./Icons";

type Props = {
	projects: Project[];
	workspaces: Record<string, Workspace>;
	activeId: string | null;
	inventory: Inventory | null;
	view: string;
	onView: (view: string) => void;
	onSelect: (id: string) => void;
	onAdd: () => void;
	onRemove: (id: string) => void;
};

export default function Sidebar({
	projects,
	workspaces,
	activeId,
	inventory,
	view,
	onView,
	onSelect,
	onAdd,
	onRemove,
}: Props) {
	return (
		<aside className="sidebar">
			<section className="side-section">
				<div className="side-head">
					<span className="side-title">Sessions</span>
					<div className="side-tools">
						<button className="new-button" onClick={onAdd} title="Add a project (⌘N)">
							New <kbd>⌘N</kbd>
						</button>
						<button className="icon-button" title="Filter" aria-label="Filter">
							<IconFilter />
						</button>
						<button className="icon-button" title="Search" aria-label="Search">
							<IconSearch />
						</button>
						<button className="icon-button" title="More" aria-label="More">
							<IconMore />
						</button>
					</div>
				</div>

				<ul className="side-list">
					{projects.length === 0 ? <li className="side-empty">No projects yet</li> : null}
					{projects.map((project) => {
						const status = workspaces[project.id]?.status ?? "stopped";
						return (
							<li key={project.id}>
								<div className={`side-item ${project.id === activeId ? "active" : ""}`}>
									<button className="side-item-main" onClick={() => onSelect(project.id)}>
										<span className={`dot ${status}`} aria-hidden="true" />
										<span className="side-item-label">{project.name}</span>
									</button>
									<button
										className="side-item-remove"
										onClick={() => onRemove(project.id)}
										aria-label={`Remove ${project.name}`}
									>
										×
									</button>
								</div>
							</li>
						);
					})}
				</ul>
			</section>

			<section className="side-section">
				<div className="side-head">
					<span className="side-title">Agents</span>
				</div>
				<ul className="side-list">
					{(inventory?.subagents ?? 0) === 0 ? (
						<li className="side-empty">No subagents running</li>
					) : (
						<li className="side-note">{inventory?.subagents} running</li>
					)}
				</ul>
			</section>

			<div className="side-spacer" />

			<section className="side-section">
				<div className="side-head">
					<span className="side-title">Customizations</span>
				</div>
				<ul className="side-list">
					<SideLink icon={<IconHome />} label="Overview" active={view === "overview"} onClick={() => onView("overview")} />
					<SideLink icon={<IconWrench />} label="Tools" count={inventory?.tools.length} active={view === "tools"} onClick={() => onView("tools")} />
					<SideLink icon={<IconBook />} label="Skills" count={inventory?.skills.length} active={view === "skills"} onClick={() => onView("skills")} />
					<SideLink icon={<IconPlug />} label="Extensions" count={inventory?.extensions.length} active={view === "extensions"} onClick={() => onView("extensions")} />
					<SideLink icon={<IconServer />} label="Prompts" count={inventory?.prompts.length} active={view === "prompts"} onClick={() => onView("prompts")} />
				</ul>
			</section>
		</aside>
	);
}

type SideLinkProps = {
	icon: React.ReactNode;
	label: string;
	count?: number;
	active?: boolean;
	onClick: () => void;
};

function SideLink({ icon, label, count, active, onClick }: SideLinkProps) {
	return (
		<li>
			<button className={`side-link ${active ? "active" : ""}`} onClick={onClick}>
				<span className="side-link-icon">{icon}</span>
				<span className="side-link-label">{label}</span>
				{count === undefined ? null : <span className="side-link-count">{count}</span>}
				{active ? <IconChevronRight className="side-link-chevron" /> : null}
			</button>
		</li>
	);
}
