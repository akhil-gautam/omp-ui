//! Checks for the facts the interface shows about a project.

use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex};

use omp_ui_lib::manager::{Host, Manager};
use omp_ui_lib::project;
use omp_ui_lib::store::ProjectStore;
use omp_ui_lib::types::UiEvent;

/// Collects the events the backend emits.
#[derive(Clone, Default)]
struct Collector {
	events: Arc<Mutex<Vec<UiEvent>>>,
}

impl Host for Collector {
	fn emit(&self, event: UiEvent) {
		self.events.lock().expect("the collector is not poisoned").push(event);
	}

	fn set_title(&self, _title: &str) {}
}

fn manager(dir: &Path) -> Manager {
	let collector = Collector::default();
	let store = ProjectStore::new(dir.join("projects.json"));
	Manager::new(Arc::new(collector), store)
}

#[test]
fn the_branch_comes_from_the_git_head() {
	let temp = tempfile::tempdir().expect("a temp dir");
	fs::create_dir_all(temp.path().join(".git")).expect("the git directory is created");
	fs::write(temp.path().join(".git").join("HEAD"), "ref: refs/heads/main\n")
		.expect("the head is written");

	assert_eq!(project::branch(temp.path()).as_deref(), Some("main"));
}

#[test]
fn a_detached_head_names_the_commit() {
	let temp = tempfile::tempdir().expect("a temp dir");
	fs::create_dir_all(temp.path().join(".git")).expect("the git directory is created");
	fs::write(temp.path().join(".git").join("HEAD"), "0f1e2d3c4b5a6978\n")
		.expect("the head is written");

	assert_eq!(project::branch(temp.path()).as_deref(), Some("0f1e2d3"));
}

#[test]
fn a_directory_without_git_has_no_branch() {
	let temp = tempfile::tempdir().expect("a temp dir");

	assert_eq!(project::branch(temp.path()), None);
}

#[test]
fn the_greeting_uses_the_account_name() {
	assert_eq!(project::first_name("Akhil Gautam,,,"), "Akhil Gautam");
	assert_eq!(project::first_name("Akhil Gautam"), "Akhil Gautam");
	assert_eq!(project::first_name(""), "");
}

#[test]
fn the_approval_mode_is_read_from_the_configuration() {
	assert_eq!(project::parse_approval_mode("approvalMode: always-ask\n").as_deref(), Some("always-ask"));
	assert_eq!(project::parse_approval_mode("  approvalMode: \"yolo\"\n").as_deref(), Some("yolo"));
	assert_eq!(project::parse_approval_mode("approvalMode: 'write'\n").as_deref(), Some("write"));
	assert_eq!(project::parse_approval_mode("other: 1\n"), None);
	assert_eq!(project::parse_approval_mode("approvalMode:\n"), None);
}

#[test]
fn a_project_reports_its_branch() {
	let temp = tempfile::tempdir().expect("a temp dir");
	fs::create_dir_all(temp.path().join(".git")).expect("the git directory is created");
	fs::write(temp.path().join(".git").join("HEAD"), "ref: refs/heads/feature\n")
		.expect("the head is written");

	let manager = manager(temp.path());
	let project = manager.add(temp.path().to_str().expect("a utf-8 path")).expect("the project is added");

	assert_eq!(manager.branch(&project.id).as_deref(), Some("feature"));
}

#[test]
fn the_inventory_lists_what_the_project_has() {
	let temp = tempfile::tempdir().expect("a temp dir");
	let manager = manager(temp.path());
	let project = manager.add(temp.path().to_str().expect("a utf-8 path")).expect("the project is added");
	manager.open(&project.id).expect("the project opens");

	let inventory = manager.inventory(&project.id).expect("the inventory is readable");
	assert!(!inventory.tools.is_empty(), "omp should expose its tools: {inventory:?}");
	assert!(inventory.commands > 0, "omp should expose its commands: {inventory:?}");
}

#[test]
fn the_session_mode_is_the_mode_omp_is_in() {
	let temp = tempfile::tempdir().expect("a temp dir");
	let manager = manager(temp.path());
	let project = manager.add(temp.path().to_str().expect("a utf-8 path")).expect("the project is added");
	manager.open(&project.id).expect("the project opens");

	manager.set_session_mode(&project.id, "autopilot").expect("autopilot is set");
	let state = manager.refresh_state(&project.id).expect("the state is readable");
	assert_eq!(state["steeringMode"], "all", "autopilot keeps every steer: {state}");
	assert_eq!(state["followUpMode"], "all", "autopilot keeps every message: {state}");
	assert_eq!(state["interruptMode"], "wait", "autopilot lets the turn finish: {state}");

	manager.set_session_mode(&project.id, "interactive").expect("interactive is set");
	let state = manager.refresh_state(&project.id).expect("the state is readable");
	assert_eq!(state["steeringMode"], "one-at-a-time", "interactive takes the last steer: {state}");
	assert_eq!(state["followUpMode"], "all", "interactive still queues every message: {state}");
	assert_eq!(state["interruptMode"], "immediate", "interactive lands a steer at once: {state}");
}
