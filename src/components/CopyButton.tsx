import { useState } from "react";

import { copyText } from "../clipboard";
import { CHECK_ICON, COPY_ICON } from "../icons";

type Props = {
	/** The text to copy. */
	text: string;
	title?: string;
	className?: string;
};

/** Copies text and says so, briefly. */
export default function CopyButton({ text, title = "Copy", className }: Props) {
	const [copied, setCopied] = useState(false);

	return (
		<button
			className={`copy-button ${copied ? "copied" : ""} ${className ?? ""}`}
			title={copied ? "Copied" : title}
			aria-label={copied ? "Copied" : title}
			onClick={() => {
				void copyText(text).then(() => {
					setCopied(true);
					window.setTimeout(() => setCopied(false), 1400);
				});
			}}
			dangerouslySetInnerHTML={{ __html: copied ? CHECK_ICON : COPY_ICON }}
		/>
	);
}
