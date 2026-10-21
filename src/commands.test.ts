import { describe, expect, it } from "vitest";

import { matchCommands } from "./commands";
import type { CommandInfo } from "./schema";

const command = (name: string, extra: Partial<CommandInfo> = {}): CommandInfo => ({
	name,
	source: "builtin",
	...extra,
});

const catalog: CommandInfo[] = [
	command("model", { description: "Change the model", input: { hint: "<provider/model>" } }),
	command("compact", { description: "Compact the transcript" }),
	command("security", {
		description: "Security scans",
		input: { hint: "<plan|scan>" },
		subcommands: [
			{ name: "plan", description: "Plan a scan" },
			{ name: "scan", description: "Run a scan" },
		],
	}),
	command("memory", { aliases: ["mem"] }),
];

describe("matchCommands", () => {
	it("offers every command for an empty query", () => {
		expect(matchCommands(catalog, "").map((match) => match.label)).toEqual([
			"/compact",
			"/memory",
			"/model",
			"/security",
		]);
	});

	it("matches on a prefix", () => {
		expect(matchCommands(catalog, "mo").map((match) => match.label)).toEqual(["/model"]);
	});

	it("matches an alias", () => {
		expect(matchCommands(catalog, "mem").map((match) => match.label)).toEqual(["/memory"]);
	});

	it("puts an exact name first", () => {
		const matches = matchCommands([command("model"), command("modelpreset")], "model");
		expect(matches[0]?.label).toBe("/model");
	});

	it("carries the argument hint", () => {
		expect(matchCommands(catalog, "model")[0]?.hint).toBe("<provider/model>");
	});

	it("matches a subcommand after a space", () => {
		const matches = matchCommands(catalog, "security pl");
		expect(matches.map((match) => match.label)).toEqual(["/security plan"]);
	});

	it("offers the subcommands once the command is chosen", () => {
		const matches = matchCommands(catalog, "security ");
		expect(matches.map((match) => match.label)).toEqual(["/security plan", "/security scan"]);
	});

	it("offers nothing for a command that has no subcommands", () => {
		expect(matchCommands(catalog, "model ")).toEqual([]);
	});

	it("offers nothing for an unknown command", () => {
		expect(matchCommands(catalog, "nope")).toEqual([]);
		expect(matchCommands(catalog, "nope sub")).toEqual([]);
	});

	it("does not match past the first space", () => {
		expect(matchCommands(catalog, "model extra")).toEqual([]);
	});
});
