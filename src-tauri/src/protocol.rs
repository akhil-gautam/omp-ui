//! Translating omp RPC frames into the webview's event vocabulary.
//!
//! The webview speaks the vocabulary in [`crate::types`]; everything omp
//! sends is normalised here so that upstream protocol changes never reach the
//! frontend.

use omp_rpc::wire::{
	AgentMessage, AssistantMessageEvent, AvailableSlashCommand, ExtensionUiRequest, RpcAgentEvent,
	RpcNotification,
};
use omp_rpc::Event;
use serde_json::{json, Value};

use crate::types::{
	AgentEndPayload, Block, CommandInfo, CommandInput, CommandSubcommand, DeltaChannel, EventKind,
	MessageDeltaPayload, MessageEndPayload, MessageStartPayload, NoticePayload, PromptResultPayload,
	QueuePayload, SessionStatus, StatusPayload, ToolEndPayload, ToolStartPayload, UiEvent,
};

/// A status event for one project.
pub fn status(project_id: &str, status: SessionStatus, detail: Option<String>) -> UiEvent {
	UiEvent {
		project_id: project_id.to_owned(),
		kind: EventKind::Status,
		payload: serde_json::to_value(StatusPayload { status, detail }).unwrap_or(Value::Null),
	}
}

/// A failure event for one project.
pub fn failure(project_id: &str, message: impl Into<String>) -> UiEvent {
	UiEvent {
		project_id: project_id.to_owned(),
		kind: EventKind::Error,
		payload: json!({ "message": message.into() }),
	}
}

/// Normalises one frame from omp.
pub fn from_event(project_id: &str, event: Event) -> Option<UiEvent> {
	match event {
		Event::Notification(notification) => from_notification(project_id, notification),
		Event::UnmatchedResponse(_) => None,
		Event::Undecodable { error, .. } => Some(failure(project_id, error)),
	}
}

/// Normalises one notification from omp into the webview's event vocabulary.
pub fn from_notification(project_id: &str, notification: RpcNotification) -> Option<UiEvent> {
	match notification {
		RpcNotification::RpcAgentEvent(event) => from_agent_event(project_id, &event),
		RpcNotification::PromptResult(result) => Some(UiEvent {
			project_id: project_id.to_owned(),
			kind: EventKind::PromptResult,
			payload: serde_json::to_value(PromptResultPayload {
				status: as_string(&result.status),
				error: result.error.as_ref().and_then(|error| serde_json::to_value(error).ok()),
			})
			.unwrap_or(Value::Null),
		}),
		RpcNotification::ExtensionUiRequest(request) => match &request {
			// Only the methods that expect an answer become dialogs. The
			// presentation ones are fire-and-forget, and showing them as
			// dialogs would leave a modal the user cannot get rid of.
			ExtensionUiRequest::Select(_)
			| ExtensionUiRequest::Confirm(_)
			| ExtensionUiRequest::Input(_)
			| ExtensionUiRequest::Editor(_)
			| ExtensionUiRequest::Ask(_)
			| ExtensionUiRequest::OpenUrl(_) => Some(UiEvent {
				project_id: project_id.to_owned(),
				kind: EventKind::UiRequest,
				payload: serde_json::to_value(request).unwrap_or(Value::Null),
			}),
			// A cancelled dialog has to disappear from the UI.
			ExtensionUiRequest::Cancel(cancel) => Some(UiEvent {
				project_id: project_id.to_owned(),
				kind: EventKind::UiRequestCancelled,
				payload: json!({ "targetId": cancel.target_id }),
			}),
			// omp's own status line.
			ExtensionUiRequest::SetStatus(status) => status.status_text.as_ref().map(|text| UiEvent {
				project_id: project_id.to_owned(),
				kind: EventKind::StatusText,
				payload: json!({ "text": text }),
			}),
			// A message from an extension.
			ExtensionUiRequest::Notify(notify) => Some(UiEvent {
				project_id: project_id.to_owned(),
				kind: EventKind::Notice,
				payload: json!({ "level": "info", "message": notify.message }),
			}),
			// Widgets, titles and editor text are omp's own chrome.
			_ => None,
		},
		RpcNotification::AvailableCommandsUpdate(update) => Some(UiEvent {
			project_id: project_id.to_owned(),
			kind: EventKind::Commands,
			payload: json!({
				"commands": update.commands.iter().map(command_info).collect::<Vec<_>>(),
			}),
		}),
		RpcNotification::SubagentLifecycle(event) => Some(UiEvent {
			project_id: project_id.to_owned(),
			kind: EventKind::Subagent,
			payload: serde_json::to_value(event).unwrap_or(Value::Null),
		}),
		RpcNotification::ExtensionError(error) => Some(failure(project_id, error.error.clone())),
		_ => None,
	}
}

/// Wire value of a scalar enum, as the webview sees it.
pub fn as_string<T: serde::Serialize>(value: &T) -> String {
	serde_json::to_value(value)
		.ok()
		.and_then(|value| value.as_str().map(str::to_owned))
		.unwrap_or_default()
}

/// Normalises a slash command for the webview.
pub fn command_info(command: &AvailableSlashCommand) -> CommandInfo {
	CommandInfo {
		name: command.name.clone(),
		source: as_string(&command.source),
		description: command.description.clone(),
		aliases: command.aliases.clone(),
		input: command
			.input
			.as_ref()
			.map(|input| CommandInput { hint: input.hint.clone() }),
		subcommands: command.subcommands.as_ref().map(|subcommands| {
			subcommands
				.iter()
				.map(|subcommand| CommandSubcommand {
					name: subcommand.name.clone(),
					description: subcommand.description.clone(),
					usage: subcommand.usage.clone(),
				})
				.collect()
		}),
	}
}

fn from_agent_event(project_id: &str, event: &RpcAgentEvent) -> Option<UiEvent> {
	let (kind, payload) = match event {
		RpcAgentEvent::AgentStart(_) => (EventKind::AgentStart, json!({})),
		RpcAgentEvent::AgentEnd(end) => (
			EventKind::AgentEnd,
			serde_json::to_value(AgentEndPayload {
				yielded: end.yielded.unwrap_or(false),
				is_terminal: end.is_terminal.unwrap_or(true),
			})
			.unwrap_or(Value::Null),
		),
		RpcAgentEvent::MessageStart(start) => {
			let role = role_of(&start.message);
			let text = (role == "user").then(|| message_text(&start.message)).flatten();
			(
				EventKind::MessageStart,
				serde_json::to_value(MessageStartPayload {
					message_id: start.message_id.clone().unwrap_or_default(),
					role,
					text,
				})
				.unwrap_or(Value::Null),
			)
		},
		RpcAgentEvent::MessageUpdate(update) => {
			let (channel, delta) = match &update.assistant_message_event {
				AssistantMessageEvent::TextDelta(event) => {
					(DeltaChannel::Text, event.delta.clone().unwrap_or_default())
				},
				AssistantMessageEvent::ThinkingDelta(event) => {
					(DeltaChannel::Thinking, event.delta.clone().unwrap_or_default())
				},
				AssistantMessageEvent::ToolcallDelta(event) => {
					(DeltaChannel::ToolCall, event.delta.clone().unwrap_or_default())
				},
				_ => return None,
			};
			(
				EventKind::MessageDelta,
				serde_json::to_value(MessageDeltaPayload {
					message_id: update.message_id.clone().unwrap_or_default(),
					channel,
					delta,
				})
				.unwrap_or(Value::Null),
			)
		},
		RpcAgentEvent::MessageEnd(end) => (
			EventKind::MessageEnd,
			serde_json::to_value(MessageEndPayload {
				message_id: end.message_id.clone().unwrap_or_default(),
				role: role_of(&end.message),
			})
			.unwrap_or(Value::Null),
		),
		RpcAgentEvent::ToolExecutionStart(start) => (
			EventKind::ToolStart,
			serde_json::to_value(ToolStartPayload {
				tool_call_id: start.tool_call_id.clone(),
				name: start.tool_name.clone(),
				args: start.args.clone(),
			})
			.unwrap_or(Value::Null),
		),
		RpcAgentEvent::ToolExecutionEnd(end) => (
			EventKind::ToolEnd,
			serde_json::to_value(ToolEndPayload {
				tool_call_id: end.tool_call_id.clone(),
				name: end.tool_name.clone(),
				result: end.result.clone(),
				is_error: end.is_error.unwrap_or(false),
			})
			.unwrap_or(Value::Null),
		),
		RpcAgentEvent::QueueUpdate(queue) => (
			EventKind::Queue,
			serde_json::to_value(QueuePayload {
				steering: queue.steering.clone(),
				follow_up: queue.follow_up.clone(),
			})
			.unwrap_or(Value::Null),
		),
		RpcAgentEvent::Notice(notice) => (
			EventKind::Notice,
			serde_json::to_value(NoticePayload {
				level: as_string(&notice.level),
				message: notice.message.clone(),
				source: notice.source.clone(),
			})
			.unwrap_or(Value::Null),
		),
		_ => return None,
	};

	Some(UiEvent { project_id: project_id.to_owned(), kind, payload })
}

/// Converts a session's messages into transcript blocks.
///
/// Tool calls and their results share the tool call id so the webview can
/// render them as one card.
pub fn history_blocks(messages: &[AgentMessage]) -> Vec<Block> {
	let mut blocks = Vec::new();
	for (index, message) in messages.iter().enumerate() {
		let Ok(value) = serde_json::to_value(message) else {
			continue;
		};
		let role = value.get("role").and_then(Value::as_str).unwrap_or("assistant");
		match role {
			"user" | "developer" => {
				let text = text_of(value.get("content").unwrap_or(&Value::Null));
				if !text.trim().is_empty() {
					blocks.push(Block::User { id: format!("m{index}"), text });
				}
			},
			"assistant" => {
				let Some(content) = value.get("content").and_then(Value::as_array) else {
					continue;
				};
				for (position, item) in content.iter().enumerate() {
					let id = format!("m{index}c{position}");
					match item.get("type").and_then(Value::as_str) {
						Some("text") => {
							let text = item.get("text").and_then(Value::as_str).unwrap_or_default().to_owned();
							if !text.is_empty() {
								blocks.push(Block::Text { id, text });
							}
						},
						Some("thinking") => {
							let text =
								item.get("thinking").and_then(Value::as_str).unwrap_or_default().to_owned();
							if !text.is_empty() {
								blocks.push(Block::Thinking { id, text });
							}
						},
						Some("toolCall") => {
							let name = item.get("name").and_then(Value::as_str).unwrap_or("tool").to_owned();
							let call_id =
								item.get("id").and_then(Value::as_str).unwrap_or(&id).to_owned();
							let args = item.get("arguments").cloned();
							blocks.push(Block::Tool { id: call_id, name, args, output: None, is_error: false });
						},
						_ => {},
					}
				}
			},
			"toolResult" => {
				let call_id = value.get("toolCallId").and_then(Value::as_str).unwrap_or("").to_owned();
				let name = value.get("toolName").and_then(Value::as_str).unwrap_or("tool").to_owned();
				let output = text_of(value.get("content").unwrap_or(&Value::Null));
				let is_error = value.get("isError").and_then(Value::as_bool).unwrap_or(false);
				// Fill in the call the result belongs to; keep it standalone
				// when the call itself was pruned from the transcript.
				match blocks.iter_mut().find(|block| matches!(block, Block::Tool { id, .. } if id == &call_id)) {
					Some(Block::Tool { output: slot, is_error: flag, .. }) => {
						*slot = Some(output);
						*flag = is_error;
					},
					_ => blocks.push(Block::Tool {
						id: call_id,
						name,
						args: None,
						output: Some(output),
						is_error,
					}),
				}
			},
			_ => {},
		}
	}
	blocks
}

/// Role of a message.
fn role_of(message: &AgentMessage) -> String {
	serde_json::to_value(message)
		.ok()
		.and_then(|value| value.get("role").and_then(Value::as_str).map(str::to_owned))
		.unwrap_or_else(|| "assistant".to_owned())
}

/// Plain text of a message, used for user prompts.
fn message_text(message: &AgentMessage) -> Option<String> {
	let value = serde_json::to_value(message).ok()?;
	let text = text_of(value.get("content").unwrap_or(&Value::Null));
	if text.is_empty() {
		None
	} else {
		Some(text)
	}
}

/// Text of a content value that may be a string or a list of content blocks.
fn text_of(value: &Value) -> String {
	match value {
		Value::String(text) => text.clone(),
		Value::Array(items) => items
			.iter()
			.filter_map(|item| item.get("text").and_then(Value::as_str))
			.collect::<Vec<_>>()
			.join(""),
		Value::Object(object) => object.get("text").and_then(Value::as_str).unwrap_or_default().to_owned(),
		_ => String::new(),
	}
}
