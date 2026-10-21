import { useEffect, useMemo, useRef, useState } from "react";

export type PickerOption = {
	value: string;
	label: string;
	hint?: string;
};

type Props = {
	/** The selected value. */
	value: string;
	options: PickerOption[];
	onSelect: (value: string) => void;
	/** Shown when the value is not among the options. */
	fallback?: string;
	className?: string;
};

/**
 * A dropdown with a filter box.
 *
 * omp can have hundreds of models, and a native select cannot be searched.
 */
export default function Picker({ value, options, onSelect, fallback, className }: Props) {
	const [open, setOpen] = useState(false);
	const [filter, setFilter] = useState("");
	const [active, setActive] = useState(0);
	const root = useRef<HTMLDivElement>(null);
	const search = useRef<HTMLInputElement>(null);

	const filtered = useMemo(() => {
		const needle = filter.trim().toLowerCase();
		if (!needle) {
			return options;
		}
		return options.filter(
			(option) =>
				option.label.toLowerCase().includes(needle) || option.value.toLowerCase().includes(needle),
		);
	}, [filter, options]);

	const selected = options.find((option) => option.value === value);

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
		document.addEventListener("mousedown", onPointerDown);
		return () => document.removeEventListener("mousedown", onPointerDown);
	}, [open]);

	useEffect(() => {
		if (open) {
			search.current?.focus();
		} else {
			setFilter("");
			setActive(0);
		}
	}, [open]);

	const onKeyDown = (event: React.KeyboardEvent) => {
		if (event.key === "ArrowDown") {
			event.preventDefault();
			setActive((index) => Math.min(index + 1, filtered.length - 1));
			return;
		}
		if (event.key === "ArrowUp") {
			event.preventDefault();
			setActive((index) => Math.max(index - 1, 0));
			return;
		}
		if (event.key === "Enter") {
			event.preventDefault();
			const option = filtered[active];
			if (option) {
				onSelect(option.value);
				setOpen(false);
			}
			return;
		}
		if (event.key === "Escape") {
			event.preventDefault();
			setOpen(false);
		}
	};

	return (
		<div className={`picker ${className ?? ""}`} ref={root}>
			<button className="picker-trigger" onClick={() => setOpen((value) => !value)} title={value}>
				<span className="picker-label">{selected?.label ?? fallback ?? value}</span>
				<span className="picker-caret" aria-hidden="true">
					▾
				</span>
			</button>

			{open ? (
				<div className="picker-pop">
					<input
						className="picker-search"
						ref={search}
						value={filter}
						placeholder="Filter…"
						onChange={(event) => {
							setFilter(event.target.value);
							setActive(0);
						}}
						onKeyDown={onKeyDown}
					/>
					<div className="picker-list" role="listbox">
						{filtered.length === 0 ? <p className="picker-empty">No matches</p> : null}
						{filtered.map((option, index) => (
							<button
								className={`picker-option ${option.value === value ? "selected" : ""} ${
									index === active ? "active" : ""
								}`}
								key={option.value}
								role="option"
								aria-selected={option.value === value}
								onMouseEnter={() => setActive(index)}
								onClick={() => {
									onSelect(option.value);
									setOpen(false);
								}}
							>
								<span className="picker-option-label">{option.label}</span>
								{option.hint ? <span className="picker-option-hint">{option.hint}</span> : null}
							</button>
						))}
					</div>
				</div>
			) : null}
		</div>
	);
}
