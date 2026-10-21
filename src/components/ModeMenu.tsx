import { IconBolt, IconChevronDown, IconGear, IconMessage } from "./Icons";
import Popover from "./Popover";

/** How the session behaves. */
export type SessionMode = "interactive" | "autopilot";

const MODES: { value: SessionMode; label: string; hint: string; icon: React.ReactNode }[] = [
	{
		value: "interactive",
		label: "Interactive",
		hint: "A steer lands on the running turn; messages queue up",
		icon: <IconMessage />,
	},
	{
		value: "autopilot",
		label: "Autopilot",
		hint: "The agent finishes what it is doing first; messages queue up",
		icon: <IconBolt />,
	},
];

export const modeLabel = (mode: SessionMode) =>
	mode === "autopilot" ? "Autopilot" : "Interactive";

const APPROVAL_LABELS: Record<string, string> = {
	"always-ask": "Manual",
	"always-ask-cached": "Manual, remembered",
	write: "Writes only",
	yolo: "Automatic",
};

/** How omp's configured approval mode reads in the interface. */
export const approvalLabel = (mode: string | null) =>
	mode ? (APPROVAL_LABELS[mode] ?? mode) : null;

type Props = {
	mode: SessionMode;
	onChange: (mode: SessionMode) => void;
	/** How omp asks before it acts, as configured. */
	approval: string | null;
};

/** The session mode popover, and the approval row underneath it. */
export default function ModeMenu({ mode, onChange, approval }: Props) {
	return (
		<Popover
			className="mode-popover"
			side="top"
			label={
				<>
					<IconBolt />
					<span>{modeLabel(mode)}</span>
					<IconChevronDown className="chip-caret" />
				</>
			}
		>
			<div className="menu">
				<div className="menu-head">
					<span className="menu-head-title">
						<IconChevronDown />
						Session
					</span>
					<span className="menu-head-value">{modeLabel(mode)}</span>
				</div>
				{MODES.map((entry) => (
					<button
						key={entry.value}
						className={`menu-item ${entry.value === mode ? "active" : ""}`}
						onClick={() => onChange(entry.value)}
					>
						<span className="menu-item-icon">{entry.icon}</span>
						<span className="menu-item-text">
							<strong>{entry.label}</strong>
							<small>{entry.hint}</small>
						</span>
					</button>
				))}
				<div className="menu-separator" />
				<div className="menu-row">
					<span className="menu-row-label">
						<IconGear />
						Permissions
					</span>
					<span className="menu-row-value">{approvalLabel(approval) ?? "omp's default"}</span>
				</div>
			</div>
		</Popover>
	);
}
