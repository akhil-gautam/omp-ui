/** Grouping a transcript for display. */

import type { Block, ToolBlock } from "./schema";

/** A run of transcript entries: either one entry or a group of tool calls. */
export type TranscriptItem =
	| { kind: "entry"; block: Block }
	| { kind: "tools"; blocks: ToolBlock[] };

/**
 * Folds runs of consecutive tool calls into one group.
 *
 * A single agent turn can make a dozen tool calls in a row. Showing each one
 * as its own card buries the reply in a wall of identical boxes, so a run
 * becomes a single row that can be opened.
 */
export const groupTranscript = (blocks: Block[]): TranscriptItem[] => {
	const items: TranscriptItem[] = [];
	let run: ToolBlock[] = [];

	const flush = () => {
		if (run.length === 0) {
			return;
		}
		items.push({ kind: "tools", blocks: run });
		run = [];
	};

	for (const block of blocks) {
		if (block.kind === "tool") {
			run.push(block);
			continue;
		}
		flush();
		items.push({ kind: "entry", block });
	}
	flush();

	return items;
};

/** How a group of tool calls is summarised. */
export const summariseTools = (blocks: ToolBlock[]): { counts: { name: string; count: number }[] } => {
	const counts = new Map<string, number>();
	for (const block of blocks) {
		counts.set(block.name, (counts.get(block.name) ?? 0) + 1);
	}
	return {
		counts: [...counts.entries()]
			.map(([name, count]) => ({ name, count }))
			.sort((left, right) => right.count - left.count || left.name.localeCompare(right.name)),
	};
};
