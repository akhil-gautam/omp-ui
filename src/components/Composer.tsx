import { useEffect, useMemo, useState, type RefObject } from "react";

import { matchCommands, type CommandMatch } from "../commands";
import type { Workspace } from "../store";
import SlashMenu from "./SlashMenu";

type Props = {
	workspace: Workspace;
	/** The textarea, so the app can focus it from a shortcut. */
	inputRef: RefObject<HTMLTextAreaElement | null>;
	/** A prompt the reader picked from the empty state. */
	suggestion: string | null;
	onSuggestionApplied: () => void;
	onSend: (text: string, behavior?: "steer") => void;
	onAbort: () => void;
};

/** The composer grows with its content, up to this height. */
const MAX_HEIGHT = 220;

export default function Composer({
	workspace,
	inputRef,
	suggestion,
	onSuggestionApplied,
	onSend,
	onAbort,
}: Props) {
	const [draft, setDraft] = useState("");
	const [dismissed, setDismissed] = useState(false);
	const [active, setActive] = useState(0);
	const { status, queue, state, commands } = workspace;
	const busy = status === "busy";

	// The query is the text after a leading slash, with at most one space.
	const query = useMemo(() => {
		const trimmed = draft.trimStart();
		if (!trimmed.startsWith("/")) {
			return null;
		}
		const rest = trimmed.slice(1);
		return rest.split(" ").length > 2 ? null : rest;
	}, [draft]);

	const matches = useMemo(
		() => (query === null ? [] : matchCommands(commands, query)),
		[commands, query],
	);
	const menuOpen = query !== null && matches.length > 0 && !dismissed;

	useEffect(() => {
		setActive(0);
	}, [query]);

	useEffect(() => {
		const element = inputRef.current;
		if (!element) {
			return;
		}
		element.style.height = "auto";
		element.style.height = `${Math.min(element.scrollHeight, MAX_HEIGHT)}px`;
	}, [draft]);

	useEffect(() => {
		if (suggestion === null) {
			return;
		}
		setDraft(suggestion);
		inputRef.current?.focus();
		onSuggestionApplied();
	}, [suggestion, onSuggestionApplied]);

	const submit = (behavior?: "steer") => {
		const text = draft.trim();
		if (!text) {
			return;
		}
		setDraft("");
		onSend(text, behavior);
	};

	const pick = (match: CommandMatch) => {
		setDraft(`${match.value} `);
		inputRef.current?.focus();
	};

	const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
		if (menuOpen) {
			if (event.key === "ArrowDown") {
				event.preventDefault();
				setActive((index) => (index + 1) % matches.length);
				return;
			}
			if (event.key === "ArrowUp") {
				event.preventDefault();
				setActive((index) => (index - 1 + matches.length) % matches.length);
				return;
			}
			if (event.key === "Tab" || (event.key === "Enter" && !event.shiftKey)) {
				event.preventDefault();
				const match = matches[active];
				if (match) {
					pick(match);
				}
				return;
			}
			if (event.key === "Escape") {
				event.preventDefault();
				setDismissed(true);
				return;
			}
		}
		if (event.key === "Enter" && !event.shiftKey) {
			event.preventDefault();
			submit(event.metaKey || event.ctrlKey ? "steer" : undefined);
		}
	};

	return (
		<div className="composer">
			{queue.steering.length > 0 || queue.followUp.length > 0 ? (
				<div className="queue-chips">
					{queue.steering.map((text, index) => (
						<span className="chip" key={`steering-${index}`}>
							{text}
						</span>
					))}
					{queue.followUp.map((text, index) => (
						<span className="chip follow" key={`follow-${index}`}>
							{text}
						</span>
					))}
				</div>
			) : null}

			<div className="composer-shell">
				{menuOpen ? (
					<SlashMenu
						matches={matches}
						active={active}
						onPick={pick}
						onHover={setActive}
					/>
				) : null}

				<div className="composer-row">
					<textarea
						className="composer-input"
						ref={inputRef}
						value={draft}
						rows={1}
						placeholder={busy ? "Queue a follow-up…" : "Ask omp anything…"}
						onChange={(event) => {
							setDraft(event.target.value);
							setDismissed(false);
						}}
						onKeyDown={onKeyDown}
					/>
					{busy ? (
						<button className="danger" onClick={onAbort}>
							Stop
						</button>
					) : (
						<button className="primary" onClick={() => submit()} disabled={draft.trim().length === 0}>
							Send
						</button>
					)}
				</div>
			</div>

			<div className="composer-foot">
				<span>{state?.messageCount ?? 0} messages</span>
				{state?.tokensPerSecond ? <span>{Math.round(state.tokensPerSecond)} tok/s</span> : null}
				{state?.isCompacting ? <span>compacting…</span> : null}
				{busy ? <span>enter queues a follow-up · ⌘enter steers</span> : null}
			</div>
		</div>
	);
}
