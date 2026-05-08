use std::env;
use std::path::{Path, PathBuf};

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AgentProvider {
    pub id: AgentProviderId,
    pub display_name: &'static str,
    pub executable_path: Option<PathBuf>,
    pub available: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentProviderId {
    Codex,
    Claude,
    Gemini,
}

pub fn detect_agent_providers() -> Vec<AgentProvider> {
    detect_agent_providers_in_path(env::var_os("PATH").as_deref())
}

pub fn detect_agent_providers_in_path(path: Option<&std::ffi::OsStr>) -> Vec<AgentProvider> {
    let search_paths = agent_search_paths(path);
    [
        (AgentProviderId::Codex, "Codex", "codex"),
        (AgentProviderId::Claude, "Claude Code", "claude"),
        (AgentProviderId::Gemini, "Gemini", "gemini"),
    ]
    .into_iter()
    .map(|(id, display_name, executable_name)| {
        let executable_path = find_executable(executable_name, &search_paths);
        AgentProvider {
            id,
            display_name,
            available: executable_path.is_some(),
            executable_path,
        }
    })
    .collect()
}

fn agent_search_paths(path: Option<&std::ffi::OsStr>) -> Vec<PathBuf> {
    let mut paths: Vec<PathBuf> = path.map(env::split_paths).into_iter().flatten().collect();

    paths.extend([
        PathBuf::from("/opt/homebrew/bin"),
        PathBuf::from("/usr/local/bin"),
        PathBuf::from("/usr/bin"),
        PathBuf::from("/bin"),
    ]);

    if let Some(home) = env::var_os("HOME") {
        let home = PathBuf::from(home);
        paths.push(home.join(".local/bin"));
        paths.push(home.join("bin"));
    }

    dedupe_paths(paths)
}

fn find_executable(name: &str, paths: &[PathBuf]) -> Option<PathBuf> {
    paths
        .iter()
        .map(|path| path.join(name))
        .find(|candidate| is_executable(candidate))
}

fn is_executable(path: &Path) -> bool {
    path.is_file()
}

fn dedupe_paths(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut deduped = Vec::new();
    for path in paths {
        if !deduped.contains(&path) {
            deduped.push(path);
        }
    }
    deduped
}
