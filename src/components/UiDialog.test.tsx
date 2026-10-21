import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import type { UiRequest } from "../schema";
import UiDialog from "./UiDialog";

const noop = () => {};

describe("UiDialog", () => {
	it("lists the options of a select request", () => {
		const request: UiRequest = {
			method: "select",
			id: "1",
			title: "Approve bash",
			options: ["Allow once", "Deny"],
		};
		render(<UiDialog request={request} onAnswer={noop} onCancel={noop} />);

		expect(screen.getByText("Approve bash")).toBeTruthy();
		expect(screen.getByText("Allow once")).toBeTruthy();
		expect(screen.getByText("Deny")).toBeTruthy();
	});

	it("answers a select with the chosen option", () => {
		const onAnswer = vi.fn();
		const request: UiRequest = {
			method: "select",
			id: "1",
			options: ["Allow once", "Deny"],
		};
		render(<UiDialog request={request} onAnswer={onAnswer} onCancel={noop} />);

		fireEvent.click(screen.getByText("Deny"));
		expect(onAnswer).toHaveBeenCalledWith({ type: "value", value: "Deny" });
	});

	it("answers a confirm", () => {
		const onAnswer = vi.fn();
		const request: UiRequest = { method: "confirm", id: "2", message: "Run it?" };
		render(<UiDialog request={request} onAnswer={onAnswer} onCancel={noop} />);

		fireEvent.click(screen.getByText("Approve"));
		expect(onAnswer).toHaveBeenCalledWith({ type: "confirm", confirmed: true });
	});

	it("cancels a request when the dialog is dismissed", () => {
		const onCancel = vi.fn();
		const request: UiRequest = { method: "confirm", id: "3", message: "Run it?" };
		render(<UiDialog request={request} onAnswer={noop} onCancel={onCancel} />);

		fireEvent.click(screen.getByText("Cancel"));
		expect(onCancel).toHaveBeenCalledWith("3");
	});

	it("shows every question of an ask request", () => {
		const request: UiRequest = {
			method: "ask",
			id: "4",
			questions: [
				{
					id: "db",
					question: "Which database?",
					options: [{ label: "Postgres" }, { label: "SQLite" }],
					multi: false,
				},
			],
		};
		render(<UiDialog request={request} onAnswer={noop} onCancel={noop} />);

		expect(screen.getByText("Which database?")).toBeTruthy();
		expect(screen.getByText("Postgres")).toBeTruthy();
		expect(screen.getByText("SQLite")).toBeTruthy();
	});

	it("submits the chosen answer of an ask request", () => {
		const onAnswer = vi.fn();
		const request: UiRequest = {
			method: "ask",
			id: "5",
			questions: [
				{
					id: "db",
					question: "Which database?",
					options: [{ label: "Postgres" }],
					multi: false,
				},
			],
		};
		render(<UiDialog request={request} onAnswer={onAnswer} onCancel={noop} />);

		fireEvent.click(screen.getByText("Postgres"));
		fireEvent.click(screen.getByText("Submit"));
		expect(onAnswer).toHaveBeenCalledWith({
			type: "answers",
			answers: [{ id: "db", selectedOptions: ["Postgres"], customInput: undefined }],
		});
	});

	it("shows the link of an open_url request", () => {
		const request: UiRequest = {
			method: "open_url",
			id: "6",
			url: "https://example.com/authorize",
		};
		render(<UiDialog request={request} onAnswer={noop} onCancel={noop} />);

		expect(screen.getByText("https://example.com/authorize")).toBeTruthy();
	});

	it("offers a dismiss button for a request it does not model", () => {
		const onCancel = vi.fn();
		const request: UiRequest = { method: "unknown", id: "7" };
		render(<UiDialog request={request} onAnswer={noop} onCancel={onCancel} />);

		fireEvent.click(screen.getByText("Dismiss"));
		expect(onCancel).toHaveBeenCalledWith("7");
	});
});
