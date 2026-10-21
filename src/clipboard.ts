/** Copying text to the clipboard. */

/** Copies text, falling back to a selection when the clipboard is refused. */
export const copyText = async (text: string): Promise<void> => {
	try {
		await navigator.clipboard.writeText(text);
		return;
	} catch {
		// The webview may refuse the clipboard API; fall through.
	}
	const area = document.createElement("textarea");
	area.value = text;
	area.style.position = "fixed";
	area.style.opacity = "0";
	document.body.append(area);
	area.select();
	document.execCommand("copy");
	area.remove();
};
