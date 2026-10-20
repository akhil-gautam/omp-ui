//! Locating the `omp` executable and building a PATH that can run it.

use std::env;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// Points at an explicit omp executable, bypassing the search.
const OVERRIDE_VAR: &str = "OMP_UI_OMP_BIN";

/// Locations searched when `omp` is not on PATH.
const FALLBACKS: &[&str] = &[
	"~/.bun/bin/omp",
	"~/.local/bin/omp",
	"/opt/homebrew/bin/omp",
	"/usr/local/bin/omp",
	"/usr/bin/omp",
];

/// Absolute path of the omp executable.
pub fn resolve() -> Result<PathBuf, String> {
	if let Some(raw) = env::var_os(OVERRIDE_VAR) {
		let path = PathBuf::from(raw);
		if path.is_file() {
			return Ok(path);
		}
		return Err(format!("{OVERRIDE_VAR} points at {}, which is not a file", path.display()));
	}

	if let Some(found) = search_path() {
		return Ok(found);
	}

	for candidate in FALLBACKS {
		let path = expand_home(candidate);
		if path.is_file() {
			return Ok(path);
		}
	}

	Err("could not find the `omp` executable. Install omp (https://omp.sh) or set OMP_UI_OMP_BIN.".to_owned())
}

fn search_path() -> Option<PathBuf> {
	let paths = env::var_os("PATH")?;
	env::split_paths(&paths).map(|directory| directory.join("omp")).find(|candidate| candidate.is_file())
}

fn expand_home(candidate: &str) -> PathBuf {
	let Some(rest) = candidate.strip_prefix("~/") else {
		return PathBuf::from(candidate);
	};
	match home_dir() {
		Some(home) => home.join(rest),
		None => PathBuf::from(candidate),
	}
}

/// The user's home directory.
pub fn home_dir() -> Option<PathBuf> {
	env::var_os("HOME").filter(|value| !value.is_empty()).map(PathBuf::from)
}

/// PATH for the omp child process.
///
/// `omp` ships as a `#!/usr/bin/env bun` script, so the directory holding
/// `bun` has to be reachable even when the app was launched from a GUI where
/// PATH is minimal.
pub fn child_path(omp: &Path) -> OsString {
	let mut entries: Vec<PathBuf> = Vec::new();
	if let Some(directory) = omp.parent() {
		entries.push(directory.to_path_buf());
	}
	if let Some(home) = home_dir() {
		entries.push(home.join(".bun/bin"));
	}
	entries.push(PathBuf::from("/opt/homebrew/bin"));
	entries.push(PathBuf::from("/usr/local/bin"));

	let mut path = OsString::new();
	if let Some(existing) = env::var_os("PATH") {
		path.push(existing);
		path.push(":");
	}
	match env::join_paths(entries) {
		Ok(joined) => path.push(joined),
		Err(_) => path.push("/usr/bin:/bin"),
	}
	path
}
