import { useState } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";

import type { UiAnswer, UiRequest } from "../schema";

type Props = {
	request: UiRequest;
	onAnswer: (answer: UiAnswer) => void;
	onCancel: (requestId: string) => void;
};

type AskDraft = Record<string, { selected: string[]; custom: string }>;

export default function UiDialog({ request, onAnswer, onCancel }: Props) {
	const [text, setText] = useState("");
	const [answers, setAnswers] = useState<AskDraft>({});

	const title = "title" in request ? request.title : undefined;
	const message = "message" in request ? request.message : undefined;

	return (
		<div className="overlay" role="dialog" aria-modal="true">
			<div className="dialog">
				{title ? <h2>{title}</h2> : null}
				{message ? <p className="dialog-message">{message}</p> : null}

				{request.method === "select" ? (
					<div className="dialog-options">
						{request.options.map((option) => (
							<button
								className="option"
								key={option}
								onClick={() => onAnswer({ type: "value", value: option })}
							>
								{option}
							</button>
						))}
						<button className="option ghost" onClick={() => onCancel(request.id)}>
							Cancel
						</button>
					</div>
				) : null}

				{request.method === "confirm" ? (
					<div className="dialog-options">
						<button className="option" onClick={() => onAnswer({ type: "confirm", confirmed: true })}>
							Approve
						</button>
						<button className="option" onClick={() => onAnswer({ type: "confirm", confirmed: false })}>
							Deny
						</button>
						<button className="option ghost" onClick={() => onCancel(request.id)}>
							Cancel
						</button>
					</div>
				) : null}

				{request.method === "input" || request.method === "editor" ? (
					<form
						className="dialog-form"
						onSubmit={(event) => {
							event.preventDefault();
							onAnswer({ type: "value", value: text });
						}}
					>
						<textarea
							className="dialog-input"
							autoFocus
							rows={request.method === "editor" ? 8 : 1}
							placeholder={request.placeholder ?? ""}
							value={text}
							onChange={(event) => setText(event.target.value)}
						/>
						<div className="dialog-options row">
							<button className="option primary" type="submit" disabled={text.length === 0}>
								Send
							</button>
							<button className="option ghost" type="button" onClick={() => onCancel(request.id)}>
								Cancel
							</button>
						</div>
					</form>
				) : null}

				{request.method === "ask" ? (
					<div className="dialog-form">
						{request.questions.map((question) => {
							const draft = answers[question.id] ?? { selected: [], custom: "" };
							return (
								<div className="ask-question" key={question.id}>
									{question.header ? <div className="tool-label">{question.header}</div> : null}
									<div className="ask-text">{question.question}</div>
									<div className="dialog-options">
										{question.options.map((option) => {
											const active = draft.selected.includes(option.label);
											return (
												<button
													className={`option ${active ? "active" : ""}`}
													key={option.label}
													onClick={() =>
														setAnswers((current) => {
															const existing = current[question.id] ?? { selected: [], custom: "" };
															const selected = question.multi
																? active
																	? existing.selected.filter((entry) => entry !== option.label)
																	: [...existing.selected, option.label]
																: [option.label];
															return { ...current, [question.id]: { ...existing, selected } };
														})
													}
												>
													{option.label}
												</button>
											);
										})}
									</div>
									<input
										className="dialog-input"
										placeholder="Or type your own answer"
										value={draft.custom}
										onChange={(event) =>
											setAnswers((current) => ({
												...current,
												[question.id]: { ...(current[question.id] ?? { selected: [], custom: "" }), custom: event.target.value },
											}))
										}
									/>
								</div>
							);
						})}
						<div className="dialog-options row">
							<button
								className="option primary"
								onClick={() =>
									onAnswer({
										type: "answers",
										answers: request.questions.map((question) => {
											const draft = answers[question.id] ?? { selected: [], custom: "" };
											return {
												id: question.id,
												selectedOptions: draft.selected,
												customInput: draft.custom.trim() || undefined,
											};
										}),
									})
								}
							>
								Submit
							</button>
							<button className="option ghost" onClick={() => onCancel(request.id)}>
								Cancel
							</button>
						</div>
					</div>
				) : null}

				{request.method === "unknown" ? (
					<div className="dialog-options">
						<button className="option ghost" onClick={() => onCancel(request.id)}>
							Dismiss
						</button>
					</div>
				) : null}

				{request.method === "open_url" ? (
					<div className="dialog-form">
						<code className="dialog-url">{request.launchUrl ?? request.url}</code>
						{request.instructions ? <p className="dialog-message">{request.instructions}</p> : null}
						<div className="dialog-options row">
							<button
								className="option primary"
								onClick={() => {
									void openUrl(request.launchUrl ?? request.url).catch(() => undefined);
									onCancel(request.id);
								}}
							>
								Open in browser
							</button>
							<button className="option ghost" onClick={() => onCancel(request.id)}>
								Dismiss
							</button>
						</div>
					</div>
				) : null}
			</div>
		</div>
	);
}
