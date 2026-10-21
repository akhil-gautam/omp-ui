//! Reading what a project directory is, for the interface.

use std::fs;
use std::path::Path;

/// The branch a project is on, when it is a git repository.
///
/// Reads `.git/HEAD` directly: a full git client would be a lot of
/// machinery for one line of text.
pub fn branch(path: &Path) -> Option<String> {
	let head = fs::read_to_string(path.join(".git/HEAD")).ok()?;
	let head = head.trim();
	if let Some(reference) = head.strip_prefix("ref: ") {
		return reference.rsplit('/').next().map(str::to_owned);
	}
	// A detached HEAD names the commit.
	(head.len() >= 7).then(|| head[..7].to_owned())
}

/// The name of the user, for the greeting.
pub fn user_name() -> String {
	crate::omp_bin::home_dir()
		.and_then(|home| home.file_name().map(|name| name.to_string_lossy().into_owned()))
		.unwrap_or_default()
}

/// How omp asks before it acts, read from its own configuration.
///
/// The app cannot change this at runtime, so it is shown as it is.
pub fn approval_mode() -> Option<String> {
	let home = crate::omp_bin::home_dir()?;
	let text = fs::read_to_string(home.join(".omp").join("agent").join("config.yml")).ok()?;
	parse_approval_mode(&text)
}

/// The approval mode in a configuration file.
///
/// A targeted scan of one line: pulling in a YAML parser for a single key
/// would be a lot of machinery.
pub fn parse_approval_mode(text: &str) -> Option<String> {
	text.lines().find_map(|line| {
		let value = line.trim().strip_prefix("approvalMode:")?;
		let value = value.trim().trim_matches('"').trim_matches('\'');
		(!value.is_empty()).then(|| value.to_owned())
	})
}
