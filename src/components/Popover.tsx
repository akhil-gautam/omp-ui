import { useEffect, useRef, useState, type ReactNode } from "react";

type Props = {
	/** The chip or button that opens the popover. */
	label: ReactNode;
	children: ReactNode | ((close: () => void) => ReactNode);
	/** Which edge of the trigger the panel lines up with. */
	align?: "start" | "end" | "center";
	/** The panel opens above the trigger. */
	side?: "top" | "bottom";
	className?: string;
};

/** A menu anchored to a chip. */
export default function Popover({
	label,
	children,
	align = "start",
	side = "top",
	className,
}: Props) {
	const [open, setOpen] = useState(false);
	const root = useRef<HTMLDivElement>(null);

	useEffect(() => {
		if (!open) {
			return;
		}
		const onPointerDown = (event: MouseEvent) => {
			const target = event.target;
			if (!(target instanceof Node) || !root.current?.contains(target)) {
				setOpen(false);
			}
		};
		const onKeyDown = (event: KeyboardEvent) => {
			if (event.key === "Escape") {
				setOpen(false);
			}
		};
		document.addEventListener("mousedown", onPointerDown);
		document.addEventListener("keydown", onKeyDown);
		return () => {
			document.removeEventListener("mousedown", onPointerDown);
			document.removeEventListener("keydown", onKeyDown);
		};
	}, [open]);

	return (
		<div className={`popover ${className ?? ""}`} ref={root}>
			<button className="popover-trigger" onClick={() => setOpen((value) => !value)}>
				{label}
			</button>
			{open ? (
				<div className={`popover-panel ${align} ${side}`}>
					{typeof children === "function" ? children(() => setOpen(false)) : children}
				</div>
			) : null}
		</div>
	);
}
