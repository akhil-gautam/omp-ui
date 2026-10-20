import { useEffect, useRef } from "react";

import type { Block } from "../schema";
import ToolCard from "./ToolCard";

export default function Transcript({ blocks }: { blocks: Block[] }) {
	const end = useRef<HTMLDivElement>(null);

	useEffect(() => {
		end.current?.scrollIntoView({ block: "end" });
	}, [blocks]);

	if (blocks.length === 0) {
		return (
			<div className="transcript">
				<div className="transcript-empty">
					<p>Nothing here yet. Ask omp something to get started.</p>
				</div>
			</div>
		);
	}

	return (
		<div className="transcript">
			{blocks.map((block) => (
				<div className={`block block-${block.kind}`} key={`${block.kind}:${block.id}`}>
					{block.kind === "user" ? (
						<div className="bubble">{block.text}</div>
					) : null}
					{block.kind === "text" ? <div className="prose">{block.text}</div> : null}
					{block.kind === "thinking" ? (
						<details className="thinking">
							<summary>thinking</summary>
							<div className="prose dim">{block.text}</div>
						</details>
					) : null}
					{block.kind === "tool" ? <ToolCard block={block} /> : null}
				</div>
			))}
			<div ref={end} />
		</div>
	);
}
