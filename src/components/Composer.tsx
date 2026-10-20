import { useState } from "react";

import type { Workspace } from "../store";

type Props = {
	workspace: Workspace;
	onSend: (text: string, behavior?: "steer") => void;
	onAbort: () => void;
};

export default function Composer({ workspace, onSend, onAbort }: Props) {
	const [draft, setDraft] = useState("");
	const { status, queue, state } = workspace;
	const busy = status === "busy";

	const submit = (behavior?: "steer") => {
		const text = draft.trim();
		if (!text) {
			return;
		}
		setDraft("");
		onSend(text, behavior);
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

			<div className="composer-row">
				<textarea
					className="composer-input"
					value={draft}
					rows={1}
					placeholder={busy ? "Queue a follow-up…" : "Ask omp anything…"}
					onChange={(event) => setDraft(event.target.value)}
					onKeyDown={(event) => {
						if (event.key === "Enter" && !event.shiftKey) {
							event.preventDefault();
							submit(event.metaKey || event.ctrlKey ? "steer" : undefined);
						}
					}}
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

			<div className="composer-foot">
				<span>{state?.messageCount ?? 0} messages</span>
				{state?.tokensPerSecond ? <span>{Math.round(state.tokensPerSecond)} tok/s</span> : null}
				{state?.isCompacting ? <span>compacting…</span> : null}
				{busy ? <span>enter queues a follow-up · ⌘enter steers</span> : null}
			</div>
		</div>
	);
}
