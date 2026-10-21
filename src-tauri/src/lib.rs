//! omp-ui: a desktop front end for omp.
//!
//! The app owns one `omp --mode rpc-ui` process per open project and streams
//! everything omp produces to the webview.

pub mod commands;
pub mod manager;
pub mod omp_bin;
pub mod project;
pub mod protocol;
pub mod sessions;
pub mod store;
pub mod types;

use std::path::PathBuf;
use std::sync::Arc;

use tauri::Manager as _;

use crate::manager::Manager;
use crate::store::ProjectStore;

/// Starts the desktop application.
pub fn run() {
	tauri::Builder::default()
		.plugin(tauri_plugin_dialog::init())
		.plugin(tauri_plugin_opener::init())
		.setup(|app| {
			let config_dir = app.path().app_config_dir().unwrap_or_else(|_| PathBuf::from("."));
			let store = ProjectStore::new(manager::store_path(config_dir));
			app.manage(Manager::new(Arc::new(app.handle().clone()), store));
			Ok(())
		})
		.invoke_handler(tauri::generate_handler![
			commands::list_projects,
			commands::add_project,
			commands::active_project,
			commands::remove_project,
			commands::open_project,
			commands::close_project,
			commands::send_message,
			commands::abort_turn,
			commands::set_model,
			commands::set_thinking,
			commands::list_models,
			commands::compact,
			commands::new_session,
			commands::list_sessions,
			commands::switch_session,
			commands::refresh_state,
			commands::branch,
			commands::set_session_mode,
			commands::inventory,
			commands::user_name,
			commands::approval_mode,
			commands::answer_ui,
		])
		.run(tauri::generate_context!())
		.expect("omp-ui failed to start");
}
