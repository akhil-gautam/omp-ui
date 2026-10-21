import { useEffect, useMemo, useRef, useState } from "react";

import { groupTranscript } from "../blocks";
import type { Block } from "../schema";
import CopyButton from "./CopyButton";
import Markdown from "./Markdown";
import ToolCard from "./ToolCard";
import ToolGroup from "./ToolGroup";

/** How close to the bottom counts as "following the conversation". */
const STICKY_THRESHOLD = 80;

type Props = {
	blocks: Block[];
	/** Called when the reader picks a starter prompt. */
	onSuggest: (text: string) => void;
};

const SUGGESTIONS = [
	"Map the tools this project has and what they are for",
	"Find every TODO in this repo and propose fixes",
	"Write a short architecture summary of this project",
];

export default function Transcript({ blocks, onSuggest }: Props) {
	const scroller = useRef<HTMLDivElement>(null);
	const end = useRef<HTMLDivElement>(null);
	const [following, setFollowing] = useState(true);
	const items = useMemo(() => groupTranscript(blocks), [blocks]);

	useEffect(() => {
		if (following) {
			end.current?.scrollIntoView({ block: "end" });
		}
	}, [blocks, following]);

	const onScroll = () => {
		const element = scroller.current;
		if (!element) {
			return;
		}
		const distance = element.scrollHeight - element.scrollTop - element.clientHeight;
		setFollowing(distance < STICKY_THRESHOLD);
	};

	const jumpToLatest = () => {
		setFollowing(true);
		end.current?.scrollIntoView({ behavior: "smooth", block: "end" });
	};

	return (
		<div className="transcript-wrap">
			<div className="transcript" ref={scroller} onScroll={onScroll}>
				{blocks.length === 0 ? (
					<div className="transcript-empty">
						<p>Nothing here yet. Ask omp something to get started.</p>
						<div className="suggestions">
							{SUGGESTIONS.map((suggestion) => (
								<button
									className="suggestion"
									key={suggestion}
									onClick={() => onSuggest(suggestion)}
								>
									{suggestion}
								</button>
							))}
						</div>
					</div>
				) : null}

				{items.map((item) =>
					item.kind === "tools" ? (
						<div className="block" key={`tools:${item.blocks[0]?.id ?? "group"}`}>
							<ToolGroup blocks={item.blocks} />
						</div>
					) : (
						<div className={`block block-${item.block.kind}`} key={`${item.block.kind}:${item.block.id}`}>
							{item.block.kind === "user" ? <div className="bubble">{item.block.text}</div> : null}
							{item.block.kind === "text" ? (
								<div className="message">
									<Markdown text={item.block.text} className="prose" />
									<CopyButton text={item.block.text} className="message-copy" />
								</div>
							) : null}
							{item.block.kind === "thinking" ? (
								<details className="thinking">
									<summary>thinking</summary>
									<Markdown text={item.block.text} className="prose dim" />
								</details>
							) : null}
							{item.block.kind === "tool" ? <ToolCard block={item.block} /> : null}
						</div>
					),
				)}
				<div ref={end} />
			</div>

			{following ? null : (
				<button className="jump-latest" onClick={jumpToLatest}>
					Jump to latest
				</button>
			)}
		</div>
	);
}
