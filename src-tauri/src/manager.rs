//! Owns the live omp sessions and exposes them to the webview.
//!
//! Each project gets its own `omp --mode rpc-ui` process. The process stays
//! alive for as long as the project is open, so the agent keeps its session,
//! its queued messages and its background work between UI visits.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command as Process, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use omp_rpc::wire::{
	AbortCommand, AnswersUiResponse, CancelUiResponse, CompactCommand, ConfirmUiResponse,
	ExtensionUiResponse, GetAvailableCommandsCommand, GetAvailableModelsCommand, GetStateCommand,
	GetSubagentsCommand, InterruptMode, NewSessionCommand, PromptCommand, QueueMode, RpcInbound,
	SessionState, SetAskDialogCommand, SetFollowUpModeCommand, SetInterruptModeCommand,
	SetModelCommand, SetSteeringModeCommand, SetThinkingLevelCommand, SlashCommandSource,
	StreamingBehavior, SwitchSessionCommand, ThinkingLevel, ValueUiResponse,
};
use omp_rpc::{Client, ClientOptions, Event};
use serde::Serialize;
use serde_json::Value;
// Imported for its methods only: `tauri::Manager` would clash with the
// application state type of the same name.
use tauri::Manager as _;

use crate::omp_bin;
use crate::project;
use crate::protocol;
use crate::sessions::{self, SessionSummary};
use crate::store::ProjectStore;
use crate::types::{
	Block, CommandInfo, EventKind, Inventory, Project, SessionStatus, UiAnswer, UiEvent,
};

/// The label of the app's only window.
const MAIN_WINDOW: &str = "main";

/// Everything the webview needs to render a freshly opened project.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenResult {
	pub project: Project,
	pub state: Value,
	pub blocks: Vec<Block>,
	pub commands: Vec<CommandInfo>,
}

/// What the backend needs from the app it runs in.
///
/// The app implements this with its Tauri handle; tests implement it with a
/// collector and no window.
pub trait Host: Send + Sync + 'static {
	/// Pushes an event to the webview.
	fn emit(&self, event: UiEvent);
	/// Shows a title in the app's window.
	fn set_title(&self, title: &str);
}

impl<R: tauri::Runtime> Host for tauri::AppHandle<R> {
	fn emit(&self, event: UiEvent) {
		let _ = tauri::Emitter::emit(self, "omp://event", event);
	}

	fn set_title(&self, title: &str) {
		let Some(window) = self.get_webview_window(MAIN_WINDOW) else {
			return;
		};
		if let Err(error) = window.set_title(title) {
			eprintln!("[omp-ui] could not set the window title: {error}");
		}
	}
}

/// The registry of projects and their live omp processes.
pub struct Manager {
	host: Arc<dyn Host>,
	store: ProjectStore,
	projects: Mutex<Vec<Project>>,
	/// The project that was open when the app last closed.
	active_id: Mutex<Option<String>>,
	workspaces: Mutex<HashMap<String, Arc<Client>>>,
}

impl Manager {
	pub fn new(host: Arc<dyn Host>, store: ProjectStore) -> Self {
		let stored = store.load();
		Self {
			host,
			store,
			projects: Mutex::new(stored.projects),
			active_id: Mutex::new(stored.active_id),
			workspaces: Mutex::new(HashMap::new()),
		}
	}

	/// The project to restore when the app starts.
	pub fn active_id(&self) -> Option<String> {
		self.active_id.lock().ok().and_then(|active| active.clone())
	}

	/// Records the project the user is looking at.
	pub fn set_active(&self, id: Option<&str>) -> Result<(), String> {
		{
			let mut active =
				self.active_id.lock().map_err(|_| "the project list is poisoned".to_owned())?;
			*active = id.map(str::to_owned);
		}
		self.persist()
	}

	pub fn list(&self) -> Vec<Project> {
		self.projects.lock().map(|projects| projects.clone()).unwrap_or_default()
	}

	/// Registers a project directory.
	pub fn add(&self, path: &str) -> Result<Project, String> {
		let canonical = fs::canonicalize(path).map_err(|error| format!("{path} is not reachable: {error}"))?;
		if !canonical.is_dir() {
			return Err(format!("{} is not a directory", canonical.display()));
		}
		let path = canonical.to_string_lossy().into_owned();

		let name = canonical
			.file_name()
			.map(|name| name.to_string_lossy().into_owned())
			.unwrap_or_else(|| path.clone());
		let project = Project {
			id: new_id(),
			display_path: omp_bin::display_path(&path),
			path,
			name,
			created_at: now_secs(),
		};

		{
			let mut projects =
				self.projects.lock().map_err(|_| "the project list is poisoned".to_owned())?;
			if projects.iter().any(|entry| entry.path == project.path) {
				return Err(format!("{} is already open", project.path));
			}
			projects.push(project.clone());
		}

		self.persist()?;
		Ok(project)
	}

	/// Forgets a project and stops its omp process.
	pub fn remove(&self, id: &str) -> Result<(), String> {
		{
			let mut projects =
				self.projects.lock().map_err(|_| "the project list is poisoned".to_owned())?;
			projects.retain(|project| project.id != id);
		}
		{
			let mut active =
				self.active_id.lock().map_err(|_| "the project list is poisoned".to_owned())?;
			if active.as_deref() == Some(id) {
				*active = None;
			}
		}
		self.persist()?;
		self.close(id);
		Ok(())
	}

	/// Writes the project list and the active project to disk.
	fn persist(&self) -> Result<(), String> {
		let projects = self.list();
		let active = self.active_id.lock().ok().and_then(|active| active.clone());
		self.store.save(&projects, active.as_deref())
	}

	/// Starts the project's omp process if it is not running yet, and returns
	/// the state the webview needs to render it.
	pub fn open(&self, id: &str) -> Result<OpenResult, String> {
		self.set_active(Some(id))?;
		self.set_window_title(id);
		if self.client(id).is_err() {
			let project = self.project(id)?;
			if let Err(error) = self.start(&project) {
				self.host.emit(protocol::status(id, SessionStatus::Error, Some(error.clone())));
				return Err(error);
			}
		}
		let client = self.client(id)?;

		let state = client.call(&GetStateCommand {}).map_err(|error| error.to_string())?;
		let blocks = client.get_messages().map(|messages| protocol::history_blocks(&messages)).unwrap_or_default();
		let commands = client
			.call(&GetAvailableCommandsCommand {})
			.map(|commands| commands.iter().map(protocol::command_info).collect())
			.unwrap_or_default();

		Ok(OpenResult {
			project: self.project(id)?,
			state: trimmed_state(&state),
			blocks,
			commands,
		})
	}

	/// Stops the project's omp process, keeping the project in the list.
	pub fn close(&self, id: &str) {
		let client = self.workspaces.lock().ok().and_then(|mut workspaces| workspaces.remove(id));
		drop(client);
	}

	/// Sends a prompt.
	///
	/// While a turn is running the message is queued as a follow-up, or
	/// steered into the running turn when `behavior` asks for it.
	pub fn send(&self, id: &str, text: &str, behavior: Option<&str>) -> Result<(), String> {
		let client = self.client(id)?;
		let streaming =
			client.call(&GetStateCommand {}).map(|state| state.is_streaming).unwrap_or(false);
		let streaming_behavior = if !streaming {
			None
		} else if behavior == Some("steer") {
			Some(StreamingBehavior::Steer)
		} else {
			Some(StreamingBehavior::FollowUp)
		};
		let command = PromptCommand {
			message: text.to_owned(),
			images: None,
			streaming_behavior,
		};
		client.call(&command).map(|_| ()).map_err(|error| error.to_string())
	}

	/// Stops the running turn.
	pub fn abort(&self, id: &str) -> Result<(), String> {
		let client = self.client(id)?;
		client.call(&AbortCommand {}).map(|_| ()).map_err(|error| error.to_string())
	}

	pub fn set_model(&self, id: &str, provider: &str, model_id: &str) -> Result<(), String> {
		let client = self.client(id)?;
		let command = SetModelCommand { provider: provider.to_owned(), model_id: model_id.to_owned() };
		client.call(&command).map(|_| ()).map_err(|error| error.to_string())
	}

	pub fn set_thinking(&self, id: &str, level: &str) -> Result<(), String> {
		let level = match level {
			"inherit" => ThinkingLevel::Inherit,
			"off" => ThinkingLevel::Off,
			"minimal" => ThinkingLevel::Minimal,
			"low" => ThinkingLevel::Low,
			"medium" => ThinkingLevel::Medium,
			"high" => ThinkingLevel::High,
			"xhigh" => ThinkingLevel::Xhigh,
			"max" => ThinkingLevel::Max,
			other => return Err(format!("unknown thinking level: {other}")),
		};
		let client = self.client(id)?;
		client.call(&SetThinkingLevelCommand { level }).map(|_| ()).map_err(|error| error.to_string())
	}

	pub fn models(&self, id: &str) -> Result<Value, String> {
		let client = self.client(id)?;
		let models = client.call(&GetAvailableModelsCommand {}).map_err(|error| error.to_string())?;
		serde_json::to_value(models).map_err(|error| error.to_string())
	}

	pub fn compact(&self, id: &str) -> Result<(), String> {
		let client = self.client(id)?;
		client.call(&CompactCommand { custom_instructions: None }).map(|_| ()).map_err(|error| error.to_string())
	}

	pub fn new_session(&self, id: &str) -> Result<(), String> {
		let client = self.client(id)?;
		client.call(&NewSessionCommand { parent_session: None }).map(|_| ()).map_err(|error| error.to_string())
	}

	pub fn sessions(&self, id: &str) -> Result<Vec<SessionSummary>, String> {
		let project = self.project(id)?;
		Ok(sessions::for_cwd(Path::new(&project.path)))
	}

	pub fn switch_session(&self, id: &str, path: &str) -> Result<(), String> {
		let client = self.client(id)?;
		let command =
			SwitchSessionCommand { session_path: path.to_owned(), provider: None, model_id: None };
		client.call(&command).map(|_| ()).map_err(|error| error.to_string())
	}

	/// Answers a pending UI request from the agent.
	pub fn answer(&self, id: &str, request_id: &str, answer: UiAnswer) -> Result<(), String> {
		let client = self.client(id)?;
		let response = match answer {
			UiAnswer::Value { value } => {
				ExtensionUiResponse::ValueUiResponse(ValueUiResponse { id: request_id.to_owned(), value })
			},
			UiAnswer::Confirm { confirmed } => {
				ExtensionUiResponse::ConfirmUiResponse(ConfirmUiResponse { id: request_id.to_owned(), confirmed })
			},
			UiAnswer::Cancelled { timed_out } => ExtensionUiResponse::CancelUiResponse(CancelUiResponse {
				id: request_id.to_owned(),
				cancelled: Default::default(),
				timed_out: Some(timed_out),
			}),
			UiAnswer::Answers { answers } => {
				ExtensionUiResponse::AnswersUiResponse(AnswersUiResponse { id: request_id.to_owned(), answers })
			},
		};
		client.send(&RpcInbound::ExtensionUiResponse(response)).map_err(|error| error.to_string())
	}

	/// The live session state, without the bulky tool catalogue.
	pub fn refresh_state(&self, id: &str) -> Result<Value, String> {
		let client = self.client(id)?;
		let state = client.call(&GetStateCommand {}).map_err(|error| error.to_string())?;
		Ok(trimmed_state(&state))
	}

	/// The process id of the project's omp, when it is running.
	pub fn omp_pid(&self, id: &str) -> Option<u32> {
		self.client(id).ok().and_then(|client| client.pid())
	}

	/// The branch the project is on, when it is a git repository.
	pub fn branch(&self, id: &str) -> Option<String> {
		let project = self.project(id).ok()?;
		project::branch(Path::new(&project.path))
	}

	/// How the session behaves.
	///
	/// `interactive` takes one message at a time and lets the reader steer
	/// straight away; `autopilot` queues everything and lets side-effecting
	/// work finish before omp takes its next turn.
	pub fn set_session_mode(&self, id: &str, mode: &str) -> Result<(), String> {
		let client = self.client(id)?;
		let (queue, interrupt) = match mode {
			"autopilot" => (QueueMode::All, InterruptMode::Wait),
			_ => (QueueMode::OneAtATime, InterruptMode::Immediate),
		};
		client
			.call(&SetSteeringModeCommand { mode: queue })
			.map_err(|error| error.to_string())?;
		client
			.call(&SetFollowUpModeCommand { mode: queue })
			.map_err(|error| error.to_string())?;
		client
			.call(&SetInterruptModeCommand { mode: interrupt })
			.map_err(|error| error.to_string())?;
		Ok(())
	}

	/// What the project has, for the sidebar's counts.
	pub fn inventory(&self, id: &str) -> Result<Inventory, String> {
		let client = self.client(id)?;
		let state = client.call(&GetStateCommand {}).map_err(|error| error.to_string())?;
		let commands =
			client.call(&GetAvailableCommandsCommand {}).map_err(|error| error.to_string())?;
		let subagents = client.call(&GetSubagentsCommand {}).map_err(|error| error.to_string())?;
		Ok(Inventory {
			tools: state.dump_tools.iter().map(|tool| tool.name.clone()).collect(),
			skills: commands
				.iter()
				.filter(|command| command.source == SlashCommandSource::Skill)
				.map(|command| command.name.clone())
				.collect(),
			extensions: commands
				.iter()
				.filter(|command| command.source == SlashCommandSource::Extension)
				.map(|command| command.name.clone())
				.collect(),
			prompts: commands
				.iter()
				.filter(|command| {
					matches!(command.source, SlashCommandSource::McpPrompt | SlashCommandSource::File)
				})
				.map(|command| command.name.clone())
				.collect(),
			commands: commands.len(),
			subagents: subagents.len(),
		})
	}

	/// Shows the open project in the window title.
	fn set_window_title(&self, id: &str) {
		if let Ok(project) = self.project(id) {
			self.host.set_title(&project.name);
		}
	}

	fn project(&self, id: &str) -> Result<Project, String> {
		self.projects
			.lock()
			.map_err(|_| "the project list is poisoned".to_owned())?
			.iter()
			.find(|project| project.id == id)
			.cloned()
			.ok_or_else(|| format!("unknown project: {id}"))
	}

	fn client(&self, id: &str) -> Result<Arc<Client>, String> {
		self.workspaces
			.lock()
			.map_err(|_| "the workspace registry is poisoned".to_owned())?
			.get(id)
			.cloned()
			.ok_or_else(|| "the project is not open".to_owned())
	}

	/// Spawns omp for a project and wires up its event pump.
	fn start(&self, project: &Project) -> Result<(), String> {
		self.host.emit(protocol::status(&project.id, SessionStatus::Starting, None));
		let omp = omp_bin::resolve()?;
		let resume = sessions::for_cwd(Path::new(&project.path)).first().map(|session| session.path.clone());

		let (client, events) = match resume {
			Some(path) => match self.spawn_omp(&omp, project, Some(&path)) {
				Ok(spawned) => spawned,
				Err(_) => self.spawn_omp(&omp, project, None)?,
			},
			None => self.spawn_omp(&omp, project, None)?,
		};

		self.workspaces
			.lock()
			.map_err(|_| "the workspace registry is poisoned".to_owned())?
			.insert(project.id.clone(), client.clone());

		// Let the `ask` tool reach the UI instead of falling back to a prompt.
		let _ = client.call(&SetAskDialogCommand { enabled: true });

		self.pump(project.id.clone(), events);
		Ok(())
	}

	fn spawn_omp(
		&self,
		omp: &Path,
		project: &Project,
		resume: Option<&str>,
	) -> Result<(Arc<Client>, Receiver<Event>), String> {
		let mut command = Process::new(omp);
		command
			.arg("--mode")
			.arg("rpc-ui")
			.arg("--cwd")
			.arg(&project.path)
			.arg("--no-title")
			.env("PATH", omp_bin::child_path(omp))
			// omp's diagnostics go to the parent's stderr. A pipe would be
			// better but would need draining, and nobody reads them here.
			.stderr(Stdio::inherit());

		if let Some(path) = resume {
			command.arg("--resume").arg(path);
		}

		let (client, events) = Client::spawn(command, ClientOptions::default()).map_err(|error| {
			eprintln!("[omp-ui] could not start omp for {}: {error}", project.path);
			error.to_string()
		})?;
		eprintln!("[omp-ui] omp is running for {}", project.path);
		Ok((Arc::new(client), events))
	}

	/// Forwards omp's frames to the webview until the process goes away.
	///
	/// The pump deliberately holds no reference to the client: dropping the
	/// client's last `Arc` is what tears the omp process down, and the frame
	/// channel closes once the server is gone.
	fn pump(&self, project_id: String, events: Receiver<Event>) {
		let host = Arc::clone(&self.host);
		thread::spawn(move || {
			while let Ok(event) = events.recv() {
				let Some(ui) = protocol::from_event(&project_id, event) else {
					continue;
				};
				let status = match ui.kind {
					EventKind::AgentStart => Some(SessionStatus::Busy),
					EventKind::AgentEnd => Some(SessionStatus::Idle),
					_ => None,
				};
				host.emit(ui);
				if let Some(status) = status {
					host.emit(protocol::status(&project_id, status, None));
				}
			}
			host.emit(protocol::status(&project_id, SessionStatus::Stopped, None));
		});
	}
}

/// The session state without the bulky tool catalogue and system prompt.
fn trimmed_state(state: &SessionState) -> Value {
	let mut value = serde_json::to_value(state).unwrap_or(Value::Null);
	if let Some(object) = value.as_object_mut() {
		object.remove("dumpTools");
		object.remove("systemPrompt");
	}
	value
}

fn new_id() -> String {
	static COUNTER: AtomicU64 = AtomicU64::new(0);
	let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_nanos()).unwrap_or(0);
	format!("p{nanos:x}{:x}", COUNTER.fetch_add(1, Ordering::Relaxed))
}

fn now_secs() -> u64 {
	SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_secs()).unwrap_or(0)
}

/// The path of the project list.
pub fn store_path(config_dir: PathBuf) -> PathBuf {
	config_dir.join("projects.json")
}
