//! The commands the webview can invoke.

use tauri::State;

use crate::manager::{Manager, OpenResult};
use crate::sessions::SessionSummary;
use crate::types::{Project, UiAnswer};

#[tauri::command]
pub fn list_projects(manager: State<'_, Manager>) -> Vec<Project> {
	manager.list()
}

#[tauri::command]
pub fn add_project(manager: State<'_, Manager>, path: String) -> Result<Project, String> {
	manager.add(&path)
}

/// The project that was open when the app last closed.
#[tauri::command]
pub fn active_project(manager: State<'_, Manager>) -> Option<String> {
	manager.active_id()
}

#[tauri::command]
pub fn remove_project(manager: State<'_, Manager>, id: String) -> Result<(), String> {
	manager.remove(&id)
}

#[tauri::command]
pub fn open_project(manager: State<'_, Manager>, id: String) -> Result<OpenResult, String> {
	manager.open(&id)
}

#[tauri::command]
pub fn close_project(manager: State<'_, Manager>, id: String) -> Result<(), String> {
	manager.close(&id);
	Ok(())
}

#[tauri::command]
pub fn send_message(
	manager: State<'_, Manager>,
	id: String,
	text: String,
	behavior: Option<String>,
) -> Result<(), String> {
	manager.send(&id, &text, behavior.as_deref())
}

#[tauri::command]
pub fn abort_turn(manager: State<'_, Manager>, id: String) -> Result<(), String> {
	manager.abort(&id)
}

#[tauri::command]
pub fn set_model(
	manager: State<'_, Manager>,
	id: String,
	provider: String,
	model_id: String,
) -> Result<(), String> {
	manager.set_model(&id, &provider, &model_id)
}

#[tauri::command]
pub fn set_thinking(manager: State<'_, Manager>, id: String, level: String) -> Result<(), String> {
	manager.set_thinking(&id, &level)
}

#[tauri::command]
pub fn list_models(manager: State<'_, Manager>, id: String) -> Result<serde_json::Value, String> {
	manager.models(&id)
}

#[tauri::command]
pub fn compact(manager: State<'_, Manager>, id: String) -> Result<(), String> {
	manager.compact(&id)
}

#[tauri::command]
pub fn new_session(manager: State<'_, Manager>, id: String) -> Result<(), String> {
	manager.new_session(&id)
}

#[tauri::command]
pub fn list_sessions(manager: State<'_, Manager>, id: String) -> Result<Vec<SessionSummary>, String> {
	manager.sessions(&id)
}

#[tauri::command]
pub fn switch_session(
	manager: State<'_, Manager>,
	id: String,
	path: String,
) -> Result<(), String> {
	manager.switch_session(&id, &path)
}

#[tauri::command]
pub fn refresh_state(manager: State<'_, Manager>, id: String) -> Result<serde_json::Value, String> {
	manager.refresh_state(&id)
}

#[tauri::command]
pub fn answer_ui(
	manager: State<'_, Manager>,
	id: String,
	request_id: String,
	answer: UiAnswer,
) -> Result<(), String> {
	manager.answer(&id, &request_id, answer)
}
