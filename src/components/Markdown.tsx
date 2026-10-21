import { useEffect, useRef, useState } from "react";

import { copyText } from "../clipboard";
import { renderMarkdown } from "../markdown";

type Props = {
	/** The reply, as markdown. */
	text: string;
	className?: string;
};

/**
 * Renders a reply as markdown.
 *
 * While a reply streams in, the text changes on every token. Re-parsing it
 * each time is quadratic, so the parse is throttled to one per frame: the
 * text is always at most a frame behind, and the cost stays linear.
 */
export default function Markdown({ text, className }: Props) {
	const [html, setHtml] = useState(() => renderMarkdown(text));
	const pending = useRef(text);
	const frame = useRef<number | null>(null);

	useEffect(() => {
		if (text === pending.current) {
			return;
		}
		pending.current = text;
		if (frame.current !== null) {
			return;
		}
		frame.current = requestAnimationFrame(() => {
			frame.current = null;
			setHtml(renderMarkdown(pending.current));
		});
	}, [text]);

	useEffect(
		() => () => {
			if (frame.current !== null) {
				cancelAnimationFrame(frame.current);
			}
		},
		[],
	);

	return (
		<div
			className={className}
			dangerouslySetInnerHTML={{ __html: html }}
			onClick={handleClick}
		/>
	);
}

/** Copies the code of the block whose copy button was pressed. */
function handleClick(event: React.MouseEvent<HTMLDivElement>) {
	const target = event.target;
	if (!(target instanceof HTMLElement)) {
		return;
	}
	const button = target.closest("[data-code-copy]");
	if (!(button instanceof HTMLElement)) {
		return;
	}
	const code = button.closest(".code")?.querySelector("code")?.textContent ?? "";
	void copyText(code);
	button.classList.add("copied");
	window.setTimeout(() => button.classList.remove("copied"), 1400);
}
