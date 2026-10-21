//! The JSON contract between the Rust backend and the webview.
//!
//! The webview never sees omp's RPC frames directly: the backend normalises
//! them into the event vocabulary below so that upstream protocol churn stays
//! on this side of the boundary.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use omp_rpc::wire::AskAnswer;

/// A project the user has opened in the app.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Project {
	pub id: String,
	/// Absolute path of the project directory.
	pub path: String,
	/// The path with the home directory written as `~`.
	#[serde(default)]
	pub display_path: String,
	/// Display name; defaults to the directory name.
	pub name: String,
	pub created_at: u64,
}

/// Discriminates the payload carried by a [`UiEvent`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum EventKind {
	Status,
	MessageStart,
	MessageDelta,
	MessageEnd,
	ToolStart,
	ToolEnd,
	AgentStart,
	AgentEnd,
	Queue,
	Notice,
	UiRequest,
	UiRequestCancelled,
	StatusText,
	Commands,
	Subagent,
	PromptResult,
	Error,
}

/// One event for one project, pushed to the webview over `omp://event`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UiEvent {
	pub project_id: String,
	pub kind: EventKind,
	pub payload: Value,
}

impl UiEvent {
	/// The session status this event carries, if it carries one.
	pub fn status(&self) -> Option<SessionStatus> {
		if self.kind != EventKind::Status {
			return None;
		}
		let Value::Object(object) = &self.payload else {
			return None;
		};
		match object.get("status").and_then(Value::as_str) {
			Some("starting") => Some(SessionStatus::Starting),
			Some("idle") => Some(SessionStatus::Idle),
			Some("busy") => Some(SessionStatus::Busy),
			Some("stopped") => Some(SessionStatus::Stopped),
			Some("error") => Some(SessionStatus::Error),
			_ => None,
		}
	}
}

/// Lifecycle of a project's agent session.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SessionStatus {
	/// The omp process is starting or reconnecting.
	Starting,
	/// Connected and not working.
	Idle,
	/// A turn is running.
	Busy,
	/// The omp process is gone.
	Stopped,
	/// The session failed to start or died unexpectedly.
	Error,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StatusPayload {
	pub status: SessionStatus,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub detail: Option<String>,
}

/// Which part of an assistant message a delta belongs to.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum DeltaChannel {
	Text,
	Thinking,
	ToolCall,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageStartPayload {
	pub message_id: String,
	pub role: String,
	/// Text of a user message, so the webview can render what was sent.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub text: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageDeltaPayload {
	pub message_id: String,
	pub channel: DeltaChannel,
	pub delta: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageEndPayload {
	pub message_id: String,
	pub role: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolStartPayload {
	pub tool_call_id: String,
	pub name: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub args: Option<Value>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolEndPayload {
	pub tool_call_id: String,
	pub name: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub result: Option<Value>,
	pub is_error: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueuePayload {
	pub steering: Vec<String>,
	pub follow_up: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoticePayload {
	pub level: String,
	pub message: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub source: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentEndPayload {
	pub yielded: bool,
	pub is_terminal: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptResultPayload {
	pub status: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub error: Option<Value>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandInfo {
	pub name: String,
	pub source: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub description: Option<String>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub aliases: Option<Vec<String>>,
	/// The argument the command takes, when it takes one.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub input: Option<CommandInput>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub subcommands: Option<Vec<CommandSubcommand>>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandInput {
	#[serde(skip_serializing_if = "Option::is_none")]
	pub hint: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandSubcommand {
	pub name: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub description: Option<String>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub usage: Option<String>,
}

/// A normalised transcript entry.
///
/// A tool call and its result are one block: the result fills in the call's
/// `output` once it arrives.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum Block {
	User {
		id: String,
		text: String,
	},
	Text {
		id: String,
		text: String,
	},
	Thinking {
		id: String,
		text: String,
	},
	Tool {
		id: String,
		name: String,
		#[serde(skip_serializing_if = "Option::is_none")]
		args: Option<Value>,
		#[serde(skip_serializing_if = "Option::is_none")]
		output: Option<String>,
		is_error: bool,
	},
}

/// The answer the webview sends back for a pending UI request.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", tag = "type")]
pub enum UiAnswer {
	/// `select` and `input`: the chosen option or typed text.
	Value { value: String },
	/// `confirm`.
	Confirm { confirmed: bool },
	/// `ask`: one entry per question, in question order.
	Answers { answers: Vec<AskAnswer> },
	/// The user dismissed the dialog.
	Cancelled { #[serde(default)] timed_out: bool },
}
