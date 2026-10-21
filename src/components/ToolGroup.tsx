import { useState } from "react";

import { summariseTools } from "../blocks";
import type { ToolBlock } from "../schema";
import ToolCard from "./ToolCard";

type Props = {
	blocks: ToolBlock[];
};

/** A run of consecutive tool calls, folded into one row. */
export default function ToolGroup({ blocks }: Props) {
	const [open, setOpen] = useState(false);
	const { counts } = summariseTools(blocks);
	const failed = blocks.some((block) => block.isError);
	const running = blocks.some((block) => block.running);

	return (
		<div className={`tool-group ${open ? "open" : ""}`}>
			<button className="tool-group-head" onClick={() => setOpen((value) => !value)}>
				<span className="tool-group-chevron" aria-hidden="true">
					{open ? "▾" : "▸"}
				</span>
				<span className="tool-group-title">
					{running ? "running" : failed ? "failed" : `${blocks.length} tool ${blocks.length === 1 ? "call" : "calls"}`}
				</span>
				<span className="tool-group-summary">
					{counts.map((entry) => (
						<span className="tool-group-chip" key={entry.name}>
							{entry.name}
							{entry.count > 1 ? ` ×${entry.count}` : ""}
						</span>
					))}
				</span>
			</button>

			{open ? (
				<div className="tool-group-body">
					{blocks.map((block) => (
						<ToolCard block={block} key={block.id} />
					))}
				</div>
			) : null}
		</div>
	);
}
