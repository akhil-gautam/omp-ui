import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import App from "./App";
import type { Project } from "./schema";

// `vi.mock` is hoisted above the imports, so the mock functions have to be
// hoisted with it.
const { pickFolder, addProject, openProject, onUiEvent } = vi.hoisted(() => ({
	pickFolder: vi.fn<() => Promise<string | null>>(),
	addProject: vi.fn<(path: string) => Promise<Project>>(),
	openProject: vi.fn<(id: string) => Promise<unknown>>(),
	onUiEvent: vi.fn<(handler: (event: unknown) => void) => Promise<() => void>>(),
}));

vi.mock("./api", () => ({
	listProjects: async () => [],
	activeProject: async () => null,
	openProject: (id: string) => openProject(id),
	pickFolder: () => pickFolder(),
	addProject: (path: string) => addProject(path),
	removeProject: async () => undefined,
	closeProject: async () => undefined,
	sendMessage: async () => undefined,
	abortTurn: async () => undefined,
	setModel: async () => undefined,
	setThinking: async () => undefined,
	listModels: async () => [],
	compact: async () => undefined,
	newSession: async () => undefined,
	listSessions: async () => [],
	switchSession: async () => undefined,
	refreshState: async () => ({}),
	answerUi: async () => undefined,
	onUiEvent: (handler: (event: unknown) => void) => onUiEvent(handler),
}));



const project: Project = {
	id: "p1",
	path: "/tmp/example",
	displayPath: "~/example",
	name: "example",
	createdAt: 0,
};

describe("App", () => {
	beforeEach(() => {
		pickFolder.mockReset();
		addProject.mockReset();
		openProject.mockReset();
		pickFolder.mockResolvedValue(null);
		onUiEvent.mockResolvedValue(() => undefined);
	});

	it("adds a project and opens it", async () => {
		pickFolder.mockResolvedValue("/tmp/example");
		addProject.mockResolvedValue(project);
		openProject.mockResolvedValue({ project, state: {}, blocks: [], commands: [] });

		render(<App />);
		fireEvent.click(screen.getByTitle("Add a project (⌘N)"));

		await waitFor(() => expect(addProject).toHaveBeenCalledWith("/tmp/example"));
		await waitFor(() => expect(openProject).toHaveBeenCalledWith("p1"));
	});

	it("says so when the folder picker cannot be opened", async () => {
		// A missing Tauri permission rejects inside the webview; the app has
		// to show it rather than swallow it.
		pickFolder.mockRejectedValue(
			"dialog.open not allowed. Permissions associated with this command: dialog:allow-open",
		);

		render(<App />);
		fireEvent.click(screen.getByTitle("Add a project (⌘N)"));

		await waitFor(() => expect(screen.getByRole("alert")).toBeTruthy());
		expect(screen.getByRole("alert").textContent).toContain("dialog:allow-open");
	});

	it("says so when the event stream cannot be started", async () => {
		onUiEvent.mockRejectedValueOnce("event.listen not allowed");

		render(<App />);

		await waitFor(() => expect(screen.getByRole("alert").textContent).toContain("event stream"));
	});
});
