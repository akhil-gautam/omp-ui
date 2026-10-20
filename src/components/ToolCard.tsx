import { useState } from "react";

import type { Block } from "../schema";

/** A tool call, with its arguments and result folded into one card. */
export default function ToolCard({ block }: { block: Extract<Block, { kind: "tool" }> }) {
	const [open, setOpen] = useState(false);

	const summary = block.running
		? "running…"
		: block.isError
			? "failed"
			: block.output
				? "done"
				: "no output";

	return (
		<div className={`tool ${block.running ? "running" : ""} ${block.isError ? "failed" : ""}`}>
			<button className="tool-head" onClick={() => setOpen((value) => !value)}>
				<span className="tool-name">{block.name}</span>
				<span className="tool-summary">{summary}</span>
				<span className="tool-chevron" aria-hidden="true">
					{open ? "▾" : "▸"}
				</span>
			</button>

			{open ? (
				<div className="tool-body">
					{block.args !== undefined ? (
						<>
							<div className="tool-label">arguments</div>
							<pre className="tool-pre">{format(block.args)}</pre>
						</>
					) : null}
					{block.output !== undefined ? (
						<>
							<div className="tool-label">{block.isError ? "error" : "output"}</div>
							<pre className="tool-pre">{block.output}</pre>
						</>
					) : null}
				</div>
			) : null}
		</div>
	);
}

function format(value: unknown): string {
	if (typeof value === "string") {
		return value;
	}
	try {
		return JSON.stringify(value, null, 2) ?? String(value);
	} catch {
		return String(value);
	}
}
