import { useEffect, useMemo, useState, type RefObject } from "react";

import { matchCommands, type CommandMatch } from "../commands";
import type { ModelListEntry, Project } from "../schema";
import type { Workspace } from "../store";
import { IconArrowUp, IconBolt, IconChevronDown, IconFolder, IconGitBranch, IconMessage, IconMic, IconPlus, IconStop } from "./Icons";
import ModeMenu, { approvalLabel, modeLabel, type SessionMode } from "./ModeMenu";
import Popover from "./Popover";
import SlashMenu from "./SlashMenu";

/** The controls that sit around the text box. */
export type ComposerChrome = {
	projects: Project[];
	onProject: (id: string) => void;
	models: ModelListEntry[];
	model: string;
	onModel: (id: string) => void;
	mode: SessionMode;
	onMode: (mode: SessionMode) => void;
	thinking: string;
	onThinking: (level: string) => void;
	branch: string | null;
	approval: string | null;
};

type Props = {
	workspace: Workspace;
	/** The textarea, so the app can focus it from a shortcut. */
	inputRef: RefObject<HTMLTextAreaElement | null>;
	/** A prompt the reader picked from the empty state. */
	suggestion: string | null;
	onSuggestionApplied: () => void;
	onSend: (text: string, behavior?: "steer") => void;
	onAbort: () => void;
	chrome: ComposerChrome;
};

/** The composer grows with its content, up to this height. */
const MAX_HEIGHT = 200;

const THINKING_LEVELS: { value: string; label: string }[] = [
	{ value: "off", label: "Off" },
	{ value: "minimal", label: "Minimal" },
	{ value: "low", label: "Low" },
	{ value: "medium", label: "Medium" },
	{ value: "high", label: "High" },
	{ value: "xhigh", label: "Extra high" },
	{ value: "max", label: "Max" },
];

export default function Composer({
	workspace,
	inputRef,
	suggestion,
	onSuggestionApplied,
	onSend,
	onAbort,
	chrome,
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

	const model = chrome.models.find((entry) => entry.id === chrome.model);
	const modelName = model?.name ?? chrome.model ?? "Model";
	const project = workspace.project;
	const thinkingLabel =
		THINKING_LEVELS.find((level) => level.value === chrome.thinking)?.label ?? chrome.thinking;
	const used = state?.contextUsage?.percent;
	const balance = used === undefined ? null : Math.max(0, Math.round(100 - used));
	const approval = approvalLabel(chrome.approval);

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
						<span className="chip follow" key={`follow-up-${index}`}>
							{text}
						</span>
					))}
				</div>
			) : null}

			<div className="composer-card">
				<div className="composer-top">
					<Popover
						side="top"
						label={
							<>
								<IconFolder />
								<span>{project.name}</span>
								<IconChevronDown className="chip-caret" />
							</>
						}
					>
						<div className="menu menu-list">
							{chrome.projects.map((entry) => (
								<button
									key={entry.id}
									className={`menu-item ${entry.id === project.id ? "active" : ""}`}
									onClick={() => chrome.onProject(entry.id)}
								>
									<span className="menu-item-icon">
										<IconFolder />
									</span>
									<span className="menu-item-text">
										<strong>{entry.name}</strong>
										<small>{entry.path}</small>
									</span>
								</button>
							))}
						</div>
					</Popover>

					<Popover
						side="top"
						label={
							<>
								<IconBolt />
								<span>{modelName}</span>
								<IconChevronDown className="chip-caret" />
							</>
						}
					>
						<div className="menu menu-list">
							{chrome.models.map((entry) => (
								<button
									key={entry.id}
									className={`menu-item ${entry.id === chrome.model ? "active" : ""}`}
									onClick={() => chrome.onModel(entry.id)}
								>
									<span className="menu-item-text">
										<strong>{entry.name}</strong>
										<small>{entry.provider}</small>
									</span>
								</button>
							))}
						</div>
					</Popover>
				</div>

				{menuOpen ? (
					<SlashMenu
						matches={matches}
						active={active}
						onPick={pick}
						onHover={setActive}
					/>
				) : null}

				<textarea
					className="composer-input"
					ref={inputRef}
					value={draft}
					rows={1}
					placeholder={busy ? "Queue a follow-up…" : "Pitch your idea"}
					onChange={(event) => {
						setDraft(event.target.value);
						setDismissed(false);
					}}
					onKeyDown={onKeyDown}
				/>

				<div className="composer-actions">
					<button
						className="icon-button"
						title="Run a command"
						aria-label="Run a command"
						onClick={() => {
							setDraft("/");
							setDismissed(false);
							inputRef.current?.focus();
						}}
					>
						<IconPlus />
					</button>

					<ModeMenu mode={chrome.mode} onChange={chrome.onMode} approval={chrome.approval} />

					<Popover
						side="top"
						label={
							<>
								<IconBolt />
								<span>{thinkingLabel}</span>
								<IconChevronDown className="chip-caret" />
							</>
						}
					>
						<div className="menu menu-list">
							{THINKING_LEVELS.map((level) => (
								<button
									key={level.value}
									className={`menu-item ${level.value === chrome.thinking ? "active" : ""}`}
									onClick={() => chrome.onThinking(level.value)}
								>
									<span className="menu-item-text">
										<strong>{level.label}</strong>
									</span>
								</button>
							))}
						</div>
					</Popover>

					{balance === null ? null : (
						<span className="balance-chip" title="Context left in this session">
							{balance}% left
						</span>
					)}

					<div className="composer-spacer" />

					<button className="icon-button" title="Dictate" aria-label="Dictate">
						<IconMic />
					</button>

					{busy ? (
						<button className="send stop" onClick={onAbort} title="Stop" aria-label="Stop">
							<IconStop />
						</button>
					) : (
						<button
							className="send"
							onClick={() => submit()}
							disabled={draft.trim().length === 0}
							title="Send"
							aria-label="Send"
						>
							<IconArrowUp />
						</button>
					)}
				</div>
			</div>

			<div className="composer-foot">
				<span className="foot-badge">
					<IconMessage />
					{modeLabel(chrome.mode)}
				</span>
				{approval ? <span className="foot-muted">{approval} permissions</span> : null}
				{state?.isCompacting ? <span className="foot-muted">compacting…</span> : null}
				{busy ? <span className="foot-muted">enter queues · ⌘enter steers</span> : null}
				<div className="composer-spacer" />
				<span className="foot-item">
					<IconFolder />
					{project.name}
				</span>
				{chrome.branch ? (
					<span className="foot-item">
						<IconGitBranch />
						{chrome.branch}
					</span>
				) : null}
			</div>
		</div>
	);
}
