//! The app's Tauri capabilities.
//!
//! Tauri denies any plugin command that no capability grants, and the
//! denial happens in the webview: the folder picker does nothing and no
//! events arrive from the agent, with nothing on screen to say why. These
//! checks make the declarations part of the build.

use std::fs;
use std::path::PathBuf;

use serde_json::Value;

/// What the window has to be allowed to do.
const REQUIRED: &[&str] = &[
	// Listen for the events the backend pushes.
	"core:default",
	// Pick a project directory.
	"dialog:allow-open",
	// Open a login link in the user's browser.
	"opener:allow-open-url",
	"opener:allow-default-urls",
];

#[test]
fn the_window_is_granted_the_capabilities_the_app_needs() {
	let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("gen/schemas/capabilities.json");
	let text = fs::read_to_string(&path).expect("the capability schema is generated during the build");
	let schema: Value = serde_json::from_str(&text).expect("the capability schema is json");

	let granted: Vec<&str> = schema
		.as_object()
		.into_iter()
		.flat_map(|capabilities| capabilities.values())
		.filter_map(|capability| capability.get("permissions").and_then(Value::as_array))
		.flatten()
		.filter_map(|permission| permission.as_str())
		.collect();

	for needed in REQUIRED {
		assert!(granted.contains(needed), "the window should be granted {needed}, granted: {granted:?}");
	}
}
