//! Checks that drive a real `omp` process.
//!
//! The tests in this file need the `omp` executable on `PATH` (or
//! `OMP_UI_OMP_BIN` pointing at it) and a writable home directory. They do
//! not need model credentials unless they are marked `#[ignore]`.

use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use omp_ui_lib::manager::{EventSink, Manager};
use omp_ui_lib::store::ProjectStore;
use omp_ui_lib::types::{Block, EventKind, Project, SessionStatus, UiEvent};

/// Collects the events the backend emits.
#[derive(Clone, Default)]
struct Collector {
	events: Arc<Mutex<Vec<UiEvent>>>,
}

impl EventSink for Collector {
	fn emit(&self, event: UiEvent) {
		self.events.lock().expect("the collector is not poisoned").push(event);
	}
}

impl Collector {
	fn kinds(&self) -> Vec<EventKind> {
		self.events.lock().expect("the collector is not poisoned").iter().map(|event| event.kind).collect()
	}

	fn statuses(&self) -> Vec<SessionStatus> {
		self.events.lock().expect("the collector is not poisoned").iter().filter_map(UiEvent::status).collect()
	}
}

fn manager(dir: &Path) -> (Collector, Manager) {
	let collector = Collector::default();
	let store = ProjectStore::new(dir.join("projects.json"));
	let manager = Manager::new(Arc::new(collector.clone()), store);
	(collector, manager)
}

/// The visible text of a transcript.
fn transcript(blocks: &[Block]) -> String {
	blocks
		.iter()
		.filter_map(|block| match block {
			Block::User { text, .. } | Block::Text { text, .. } => Some(text.clone()),
			_ => None,
		})
		.collect::<Vec<_>>()
		.join("\n")
}

#[test]
fn the_store_round_trips_the_active_project() {
	let temp = tempfile::tempdir().expect("a temp dir");
	let store = ProjectStore::new(temp.path().join("projects.json"));

	let project = Project {
		id: "p1".to_owned(),
		path: "/tmp/example".to_owned(),
		display_path: "/tmp/example".to_owned(),
		name: "example".to_owned(),
		created_at: 0,
	};
	store.save(std::slice::from_ref(&project), Some("p1")).expect("the store writes");

	let loaded = store.load();
	assert_eq!(loaded.projects.len(), 1, "the project should survive the round trip");
	assert_eq!(loaded.projects[0].id, "p1");
	assert_eq!(loaded.active_id.as_deref(), Some("p1"), "the active project should survive the round trip");
}

#[test]
fn projects_saved_without_a_display_path_get_one() {
	let temp = tempfile::tempdir().expect("a temp dir");
	let path = temp.path().join("projects.json");
	// A store written before the display path existed.
	std::fs::write(
		&path,
		r#"{"projects":[{"id":"p1","path":"/tmp/example","name":"example","createdAt":0}]}"#,
	)
	.expect("the file is written");

	let loaded = ProjectStore::new(path).load();
	assert_eq!(loaded.projects.len(), 1);
	assert_eq!(loaded.projects[0].display_path, "/tmp/example");
}

#[test]
fn opening_a_project_reports_its_session() {
	let temp = tempfile::tempdir().expect("a temp dir");
	let (collector, manager) = manager(temp.path());

	let path = temp.path().to_str().expect("a utf-8 path");
	let project = manager.add(path).expect("the project is added");
	let opened = manager.open(&project.id).expect("the project opens");

	assert_eq!(opened.project.id, project.id);
	assert!(
		!opened.state["sessionId"].as_str().unwrap_or_default().is_empty(),
		"omp should report a session id, got {opened:?}",
	);
	assert!(!opened.commands.is_empty(), "omp should expose its slash commands");

	let statuses = collector.statuses();
	assert!(statuses.contains(&SessionStatus::Starting), "the session should announce that it is starting, got {statuses:?}");
}

#[test]
fn two_projects_run_at_the_same_time() {
	let first = tempfile::tempdir().expect("a temp dir");
	let second = tempfile::tempdir().expect("a temp dir");
	let (_collector, manager) = manager(first.path());

	let one = manager.add(first.path().to_str().expect("a utf-8 path")).expect("added");
	let two = manager.add(second.path().to_str().expect("a utf-8 path")).expect("added");

	let opened_one = manager.open(&one.id).expect("the first project opens");
	let opened_two = manager.open(&two.id).expect("the second project opens");

	assert_ne!(
		opened_one.state["sessionId"], opened_two.state["sessionId"],
		"each project should get its own session",
	);
	assert_eq!(manager.list().len(), 2);
}

#[test]
fn stopping_a_project_ends_its_omp_process() {
	let temp = tempfile::tempdir().expect("a temp dir");
	let (_collector, manager) = manager(temp.path());

	let path = temp.path().to_str().expect("a utf-8 path");
	let project = manager.add(path).expect("the project is added");
	manager.open(&project.id).expect("the project opens");

	let pid = manager.omp_pid(&project.id).expect("omp should be running");
	assert!(process_alive(pid), "omp should be running, pid {pid}");

	manager.close(&project.id);
	assert!(manager.omp_pid(&project.id).is_none(), "the project should have no omp left");

	let deadline = Instant::now() + Duration::from_secs(10);
	while process_alive(pid) {
		assert!(Instant::now() < deadline, "omp (pid {pid}) should have exited: {}", process_state(pid));
		std::thread::sleep(Duration::from_millis(100));
	}
}

/// What the operating system says about a process.
fn process_state(pid: u32) -> String {
	std::process::Command::new("ps")
		.arg("-p")
		.arg(pid.to_string())
		.arg("-o")
		.arg("pid,ppid,stat,command")
		.output()
		.map(|output| String::from_utf8_lossy(&output.stdout).into_owned())
		.unwrap_or_default()
}

/// Whether a process is still running.
fn process_alive(pid: u32) -> bool {
	std::process::Command::new("ps")
		.arg("-p")
		.arg(pid.to_string())
		.arg("-o")
		.arg("pid=")
		.output()
		.map(|output| !String::from_utf8_lossy(&output.stdout).trim().is_empty())
		.unwrap_or(false)
}

/// Needs a working model and network access.
#[test]
#[ignore = "needs a model with credentials"]
fn a_reply_arrives_in_the_transcript() {
	let temp = tempfile::tempdir().expect("a temp dir");
	let (collector, manager) = manager(temp.path());

	let path = temp.path().to_str().expect("a utf-8 path");
	let project = manager.add(path).expect("the project is added");
	manager.open(&project.id).expect("the project opens");

	manager.send(&project.id, "Reply with exactly: PONG", None).expect("the prompt is accepted");

	let deadline = Instant::now() + Duration::from_secs(180);
	loop {
		let state = manager.refresh_state(&project.id).expect("the state is readable");
		let messages = state["messageCount"].as_u64().unwrap_or(0);
		let settled = state["isSettled"].as_bool().unwrap_or(false);
		if messages >= 2 && settled {
			break;
		}
		assert!(Instant::now() < deadline, "the turn did not settle: {state}");
		std::thread::sleep(Duration::from_millis(400));
	}

	let reopened = manager.open(&project.id).expect("the project reopens");
	let text = transcript(&reopened.blocks);
	assert!(text.contains("PONG"), "the transcript should hold the reply, got: {text}");

	let kinds = collector.kinds();
	assert!(kinds.contains(&EventKind::MessageDelta), "the reply should have been streamed, got {kinds:?}");
}
