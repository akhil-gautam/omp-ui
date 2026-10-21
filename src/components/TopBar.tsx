import type { Project } from "../schema";
import { IconChevronDown, IconChevronLeft, IconChevronRight, IconFolder } from "./Icons";
import Popover from "./Popover";

type Props = {
	projects: Project[];
	activeId: string | null;
	onSelect: (id: string) => void;
	onBack: () => void;
	onForward: () => void;
	canBack: boolean;
	canForward: boolean;
	/** What the top bar shows on the right. */
	children?: React.ReactNode;
};

/** The bar across the top of the main column. */
export default function TopBar({
	projects,
	activeId,
	onSelect,
	onBack,
	onForward,
	canBack,
	canForward,
	children,
}: Props) {
	const active = projects.find((project) => project.id === activeId);

	return (
		<header className="topbar">
			<div className="topbar-left">
				<button
					className="icon-button"
					onClick={onBack}
					disabled={!canBack}
					title="Back"
					aria-label="Back"
				>
					<IconChevronLeft />
				</button>
				<button
					className="icon-button"
					onClick={onForward}
					disabled={!canForward}
					title="Forward"
					aria-label="Forward"
				>
					<IconChevronRight />
				</button>
			</div>

			<div className="topbar-center">
				<Popover
					side="bottom"
					align="center"
					label={
						<>
							<IconFolder />
							<span className="topbar-project">{active?.name ?? "No project"}</span>
							<IconChevronDown className="chip-caret" />
						</>
					}
				>
					<div className="menu menu-list">
						{projects.length === 0 ? (
							<div className="menu-empty">No projects yet</div>
						) : (
							projects.map((project) => (
								<button
									key={project.id}
									className={`menu-item ${project.id === activeId ? "active" : ""}`}
									onClick={() => onSelect(project.id)}
								>
									<span className="menu-item-icon">
										<IconFolder />
									</span>
									<span className="menu-item-text">
										<strong>{project.name}</strong>
										<small>{project.path}</small>
									</span>
								</button>
							))
						)}
					</div>
				</Popover>
			</div>

			<div className="topbar-right">{children}</div>
		</header>
	);
}
