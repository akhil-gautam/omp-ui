//! Persistence for the list of projects.

use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::types::Project;

#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoreFile {
	#[serde(default)]
	projects: Vec<Project>,
	/// The project that was open when the app last closed.
	#[serde(default)]
	active_id: Option<String>,
}

/// What the store holds.
#[derive(Debug, Default)]
pub struct StoredProjects {
	pub projects: Vec<Project>,
	pub active_id: Option<String>,
}

/// The project list, backed by a JSON file in the app config directory.
pub struct ProjectStore {
	path: PathBuf,
}

impl ProjectStore {
	pub fn new(path: PathBuf) -> Self {
		Self { path }
	}

	pub fn load(&self) -> StoredProjects {
		let Ok(text) = fs::read_to_string(&self.path) else {
			return StoredProjects::default();
		};
		serde_json::from_str::<StoreFile>(&text)
			.map(|file| StoredProjects { projects: file.projects, active_id: file.active_id })
			.unwrap_or_default()
	}

	pub fn save(&self, projects: &[Project], active_id: Option<&str>) -> Result<(), String> {
		if let Some(parent) = self.path.parent() {
			fs::create_dir_all(parent)
				.map_err(|error| format!("could not create {}: {error}", parent.display()))?;
		}
		let file = StoreFile { projects: projects.to_vec(), active_id: active_id.map(str::to_owned) };
		let text = serde_json::to_string_pretty(&file).map_err(|error| error.to_string())?;
		fs::write(&self.path, text).map_err(|error| format!("could not write {}: {error}", self.path.display()))
	}
}
