import type { CommandMatch } from "../commands";

type Props = {
	matches: CommandMatch[];
	active: number;
	onPick: (match: CommandMatch) => void;
	onHover: (index: number) => void;
};

export default function SlashMenu({ matches, active, onPick, onHover }: Props) {
	if (matches.length === 0) {
		return null;
	}

	return (
		<div className="slash-menu" role="listbox" aria-label="Slash commands">
			{matches.map((match, index) => (
				<button
					className={`slash-item ${index === active ? "active" : ""}`}
					key={match.value}
					role="option"
					aria-selected={index === active}
					onMouseEnter={() => onHover(index)}
					onMouseDown={(event) => {
						// Keep the textarea's focus so the draft survives.
						event.preventDefault();
						onPick(match);
					}}
				>
					<span className="slash-label">{match.label}</span>
					{match.hint ? <span className="slash-hint">{match.hint}</span> : null}
					{match.description ? <span className="slash-description">{match.description}</span> : null}
					<span className="slash-source">{match.source.replace("_", " ")}</span>
				</button>
			))}
		</div>
	);
}
