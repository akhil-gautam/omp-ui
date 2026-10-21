/** Matching slash commands for the composer's autocomplete. */

import type { CommandInfo } from "./schema";

export type CommandMatch = {
	/** What the command becomes when it is chosen, e.g. `/model`. */
	value: string;
	/** What is shown in the list. */
	label: string;
	description?: string;
	/** The argument placeholder, when the command takes one. */
	hint?: string;
	source: string;
};

/** How many matches the list shows at once. */
const MAX_MATCHES = 12;

/**
 * Finds the commands that a `/query` could mean.
 *
 * A query is a command name, optionally followed by a space and a
 * subcommand: `sec` matches `/security`, `security pl` matches
 * `/security plan`. A trailing space means the command is chosen and its
 * argument is being typed, so only its subcommands are offered.
 */
export const matchCommands = (commands: CommandInfo[], query: string): CommandMatch[] => {
	const parts = query.split(" ");
	const name = parts[0] ?? "";
	const argument = parts.slice(1).join(" ").trim();
	const lower = name.toLowerCase();

	const owner = commands.find((command) => command.name.toLowerCase() === lower);

	if (argument) {
		return (owner?.subcommands ?? [])
			.filter((subcommand) => subcommand.name.toLowerCase().startsWith(argument.toLowerCase()))
			.slice(0, MAX_MATCHES)
			.map((subcommand) => ({
				value: `/${owner?.name} ${subcommand.name}`,
				label: `/${owner?.name} ${subcommand.name}`,
				description: subcommand.description,
				hint: subcommand.usage,
				source: owner?.source ?? "",
			}));
	}

	// The command is chosen; offer its subcommands, if it has any.
	if (parts.length > 1) {
		return (owner?.subcommands ?? []).slice(0, MAX_MATCHES).map((subcommand) => ({
			value: `/${owner?.name} ${subcommand.name}`,
			label: `/${owner?.name} ${subcommand.name}`,
			description: subcommand.description,
			hint: subcommand.usage,
			source: owner?.source ?? "",
		}));
	}

	const matches: CommandMatch[] = [];
	for (const command of commands) {
		const matchesName = command.name.toLowerCase().startsWith(lower);
		const matchesAlias = (command.aliases ?? []).some((alias) =>
			alias.toLowerCase().startsWith(lower),
		);
		if (!matchesName && !matchesAlias) {
			continue;
		}
		matches.push({
			value: `/${command.name}`,
			label: `/${command.name}`,
			description: command.description,
			hint: command.input?.hint,
			source: command.source,
		});
	}

	// An exact name first, then the rest alphabetically.
	matches.sort((left, right) => {
		const leftExact = left.label.toLowerCase() === `/${lower}` ? 0 : 1;
		const rightExact = right.label.toLowerCase() === `/${lower}` ? 0 : 1;
		return leftExact - rightExact || left.label.localeCompare(right.label);
	});

	return matches.slice(0, MAX_MATCHES);
};
