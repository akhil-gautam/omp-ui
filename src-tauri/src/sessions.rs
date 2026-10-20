//! Finding the omp session files that belong to a project directory.
//!
//! omp stores sessions in `~/.omp/agent/sessions/<bucket>/<timestamp>_<id>.jsonl`.
//! The bucket name is a path encoding that omp may change, so this module
//! discovers sessions by reading each file's header record instead of
//! computing bucket names.

use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use serde::Serialize;
use serde_json::Value;

/// A session file on disk.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionSummary {
	pub path: String,
	pub id: String,
	pub cwd: String,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub title: Option<String>,
	/// Unix seconds of the file's last modification.
	pub modified: u64,
}

/// Root of omp's session store.
pub fn root() -> Option<PathBuf> {
	crate::omp_bin::home_dir().map(|home| home.join(".omp/agent/sessions"))
}

/// Sessions recorded for `cwd`, newest first.
pub fn for_cwd(cwd: &Path) -> Vec<SessionSummary> {
	let Some(root) = root() else {
		return Vec::new();
	};
	let Ok(buckets) = fs::read_dir(&root) else {
		return Vec::new();
	};

	let wanted = canonical(cwd);
	let mut found = Vec::new();
	for bucket in buckets.flatten() {
		let Ok(files) = fs::read_dir(bucket.path()) else {
			continue;
		};
		for file in files.flatten() {
			let path = file.path();
			if path.extension().and_then(|extension| extension.to_str()) != Some("jsonl") {
				continue;
			}
			let Some(header) = read_header(&path) else {
				continue;
			};
			if canonical(Path::new(&header.cwd)) != wanted {
				continue;
			}
			found.push(SessionSummary {
				path: path.to_string_lossy().into_owned(),
				id: header.id,
				cwd: header.cwd,
				title: header.title,
				modified: modified(&path),
			});
		}
	}
	found.sort_by(|left, right| right.modified.cmp(&left.modified));
	found
}

struct Header {
	id: String,
	cwd: String,
	title: Option<String>,
}

/// Reads the header record (and any title record) from the head of a session
/// file.
fn read_header(path: &Path) -> Option<Header> {
	let mut file = File::open(path).ok()?;
	let mut buffer = vec![0u8; 16 * 1024];
	let read = file.read(&mut buffer).ok()?;
	buffer.truncate(read);

	let mut id = None;
	let mut cwd = None;
	let mut title = None;
	for line in String::from_utf8_lossy(&buffer).lines() {
		let Ok(value) = serde_json::from_str::<Value>(line) else {
			continue;
		};
		match value.get("type").and_then(Value::as_str) {
			Some("session") => {
				id = value.get("id").and_then(Value::as_str).map(str::to_owned);
				cwd = value.get("cwd").and_then(Value::as_str).map(str::to_owned);
			},
			Some("title") => {
				title = value
					.get("title")
					.and_then(Value::as_str)
					.map(|text| text.trim().to_owned())
					.filter(|text| !text.is_empty());
			},
			_ => {},
		}
		if id.is_some() && cwd.is_some() {
			break;
		}
	}

	Some(Header { id: id?, cwd: cwd?, title })
}

/// Absolute path of `path` with symlinks resolved, falling back to the path
/// itself when it cannot be resolved.
fn canonical(path: &Path) -> String {
	fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf()).to_string_lossy().into_owned()
}

fn modified(path: &Path) -> u64 {
	let Ok(time) = fs::metadata(path).and_then(|metadata| metadata.modified()) else {
		return 0;
	};
	time.duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_secs()).unwrap_or(0)
}
