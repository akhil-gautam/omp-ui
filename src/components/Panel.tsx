import type { Inventory } from "../schema";
import type { Workspace } from "../store";
import { IconFolder, IconMessage, IconWrench } from "./Icons";
import { modeLabel, type SessionMode } from "./ModeMenu";

type Props = {
	view: string;
	workspace: Workspace;
	inventory: Inventory | null;
	branch: string | null;
	mode: SessionMode;
	approval: string | null;
};

/** The pages behind the sidebar's customizations. */
export default function Panel({ view, workspace, inventory, branch, mode, approval }: Props) {
	const { project, state } = workspace;

	if (view === "overview") {
		return (
			<div className="panel">
				<h1 className="panel-title">Overview</h1>
				<dl className="facts">
					<Fact label="Project" value={project.name} />
					<Fact label="Folder" value={project.path} />
					<Fact label="Branch" value={branch ?? "Not a git repository"} />
					<Fact label="Model" value={state?.model?.name ?? state?.model?.id ?? "—"} />
					<Fact label="Session" value={state?.sessionName ?? state?.sessionId ?? "—"} />
					<Fact label="Mode" value={modeLabel(mode)} />
					<Fact label="Permissions" value={approval ?? "omp's default"} />
					<Fact label="Messages" value={String(state?.messageCount ?? 0)} />
					<Fact
						label="Context"
						value={
							state?.contextUsage
								? `${state.contextUsage.tokens.toLocaleString()} of ${state.contextUsage.contextWindow.toLocaleString()} tokens (${state.contextUsage.percent}%)`
								: "—"
						}
					/>
				</dl>
			</div>
		);
	}

	const lists: Record<string, { title: string; items: string[] }> = {
		tools: { title: "Tools", items: inventory?.tools ?? [] },
		skills: { title: "Skills", items: inventory?.skills ?? [] },
		extensions: { title: "Extensions", items: inventory?.extensions ?? [] },
		prompts: { title: "Prompts", items: inventory?.prompts ?? [] },
	};

	const list = lists[view];
	if (!list) {
		return null;
	}

	return (
		<div className="panel">
			<h1 className="panel-title">{list.title}</h1>
			{list.items.length === 0 ? (
				<p className="panel-empty">Nothing here yet.</p>
			) : (
				<ul className="panel-list">
					{list.items.map((item) => (
						<li key={item} className="panel-row">
							<span className="panel-row-icon">
								{view === "tools" ? <IconWrench /> : <IconFolder />}
							</span>
							<span className="panel-row-name">{item}</span>
						</li>
					))}
				</ul>
			)}
		</div>
	);
}

function Fact({ label, value }: { label: string; value: string }) {
	return (
		<div className="fact">
			<dt>
				<IconMessage className="fact-icon" />
				{label}
			</dt>
			<dd>{value}</dd>
		</div>
	);
}
