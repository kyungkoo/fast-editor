use std::env;
use std::ffi::OsStr;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[cfg(test)]
mod tests;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskProviderId {
    Android,
    SwiftPackage,
    Web,
    Custom(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskKind {
    Build,
    Run,
    Test,
    Script,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DetectionConfidence {
    High,
    Medium,
    Low,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectDetection {
    pub provider_id: TaskProviderId,
    pub confidence: DetectionConfidence,
    pub project_root: PathBuf,
    pub evidence: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TaskDefinition {
    pub provider_id: TaskProviderId,
    pub id: String,
    pub label: String,
    pub kind: TaskKind,
    pub detail: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TaskExecutionPlan {
    pub provider_id: TaskProviderId,
    pub task_id: String,
    pub program: String,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub environment: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TaskOutput {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: Option<i32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DiagnosticSeverity {
    Error,
    Warning,
    Note,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TaskDiagnostic {
    pub severity: DiagnosticSeverity,
    pub message: String,
    pub file: Option<PathBuf>,
    pub line: Option<usize>,
    pub column: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AndroidEnvironmentInspection {
    pub sdk_location: Option<PathBuf>,
    pub android_home: Option<PathBuf>,
    pub android_sdk_root: Option<PathBuf>,
    pub android_cli_path: Option<PathBuf>,
    pub gradle_wrapper_path: Option<PathBuf>,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AndroidProjectDescription {
    pub project_root: PathBuf,
    pub settings_files: Vec<PathBuf>,
    pub root_build_files: Vec<PathBuf>,
    pub module_build_files: Vec<PathBuf>,
    pub manifest_files: Vec<PathBuf>,
    pub has_gradle_wrapper: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AndroidDeviceIntegrationStatus {
    Placeholder,
    Planned,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AndroidDeviceIntegrationPlan {
    pub device_listing: AndroidDeviceIntegrationStatus,
    pub emulator_listing: AndroidDeviceIntegrationStatus,
    pub app_deployment: AndroidDeviceIntegrationStatus,
    pub notes: Vec<String>,
}

#[derive(Debug)]
pub enum TaskProviderError {
    Io(std::io::Error),
    InvalidPackageJson(PathBuf, serde_json::Error),
    ProviderNotFound(TaskProviderId),
    TaskNotFound {
        provider_id: TaskProviderId,
        task_id: String,
    },
}

impl fmt::Display for TaskProviderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TaskProviderError::Io(error) => write!(f, "{error}"),
            TaskProviderError::InvalidPackageJson(path, error) => {
                write!(f, "invalid package.json at {}: {error}", path.display())
            }
            TaskProviderError::ProviderNotFound(provider_id) => {
                write!(f, "provider {provider_id:?} not found")
            }
            TaskProviderError::TaskNotFound {
                provider_id,
                task_id,
            } => write!(f, "task {task_id} not found for provider {provider_id:?}"),
        }
    }
}

impl std::error::Error for TaskProviderError {}

impl From<std::io::Error> for TaskProviderError {
    fn from(error: std::io::Error) -> Self {
        TaskProviderError::Io(error)
    }
}

pub trait BuildToolProvider: Send + Sync {
    fn id(&self) -> TaskProviderId;
    fn display_name(&self) -> &'static str;
    fn detect(&self, project_root: &Path) -> Option<ProjectDetection>;
    fn list_tasks(&self, project_root: &Path) -> Result<Vec<TaskDefinition>, TaskProviderError>;
    fn execution_plan(
        &self,
        project_root: &Path,
        task_id: &str,
    ) -> Result<TaskExecutionPlan, TaskProviderError>;

    fn parse_diagnostics(&self, output: &TaskOutput) -> Vec<TaskDiagnostic> {
        parse_generic_diagnostics(output)
    }
}

#[derive(Default)]
pub struct TaskProviderRegistry {
    providers: Vec<Box<dyn BuildToolProvider>>,
}

impl TaskProviderRegistry {
    pub fn new() -> Self {
        Self {
            providers: Vec::new(),
        }
    }

    pub fn with_builtin_providers() -> Self {
        let mut registry = Self::new();
        registry.register(SwiftPackageProvider);
        registry.register(WebProvider);
        registry.register(AndroidProvider);
        registry
    }

    pub fn register(&mut self, provider: impl BuildToolProvider + 'static) {
        self.providers.push(Box::new(provider));
    }

    pub fn detect_project(&self, project_root: &Path) -> Vec<ProjectDetection> {
        self.providers
            .iter()
            .filter_map(|provider| provider.detect(project_root))
            .collect()
    }

    pub fn list_project_tasks(
        &self,
        project_root: &Path,
    ) -> Result<Vec<TaskDefinition>, TaskProviderError> {
        let mut tasks = Vec::new();
        for provider in &self.providers {
            if provider.detect(project_root).is_some() {
                tasks.extend(provider.list_tasks(project_root)?);
            }
        }
        Ok(tasks)
    }

    pub fn execution_plan(
        &self,
        provider_id: &TaskProviderId,
        project_root: &Path,
        task_id: &str,
    ) -> Result<TaskExecutionPlan, TaskProviderError> {
        self.provider(provider_id)?
            .execution_plan(project_root, task_id)
    }

    pub fn parse_diagnostics(
        &self,
        provider_id: &TaskProviderId,
        output: &TaskOutput,
    ) -> Result<Vec<TaskDiagnostic>, TaskProviderError> {
        Ok(self.provider(provider_id)?.parse_diagnostics(output))
    }

    fn provider(
        &self,
        provider_id: &TaskProviderId,
    ) -> Result<&dyn BuildToolProvider, TaskProviderError> {
        self.providers
            .iter()
            .map(Box::as_ref)
            .find(|provider| provider.id() == *provider_id)
            .ok_or_else(|| TaskProviderError::ProviderNotFound(provider_id.clone()))
    }
}

pub fn builtin_task_providers() -> TaskProviderRegistry {
    TaskProviderRegistry::with_builtin_providers()
}

#[derive(Debug, Clone, Copy)]
pub struct SwiftPackageProvider;

impl BuildToolProvider for SwiftPackageProvider {
    fn id(&self) -> TaskProviderId {
        TaskProviderId::SwiftPackage
    }

    fn display_name(&self) -> &'static str {
        "Swift Package"
    }

    fn detect(&self, project_root: &Path) -> Option<ProjectDetection> {
        let manifest = project_root.join("Package.swift");
        manifest.exists().then(|| ProjectDetection {
            provider_id: self.id(),
            confidence: DetectionConfidence::High,
            project_root: project_root.to_path_buf(),
            evidence: vec!["Package.swift".to_owned()],
        })
    }

    fn list_tasks(&self, _project_root: &Path) -> Result<Vec<TaskDefinition>, TaskProviderError> {
        Ok(vec![
            task(self.id(), "swift-build", "swift build", TaskKind::Build),
            task(self.id(), "swift-test", "swift test", TaskKind::Test),
        ])
    }

    fn execution_plan(
        &self,
        project_root: &Path,
        task_id: &str,
    ) -> Result<TaskExecutionPlan, TaskProviderError> {
        match task_id {
            "swift-build" => Ok(plan(self.id(), task_id, "swift", ["build"], project_root)),
            "swift-test" => Ok(plan(self.id(), task_id, "swift", ["test"], project_root)),
            _ => Err(TaskProviderError::TaskNotFound {
                provider_id: self.id(),
                task_id: task_id.to_owned(),
            }),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct WebProvider;

impl BuildToolProvider for WebProvider {
    fn id(&self) -> TaskProviderId {
        TaskProviderId::Web
    }

    fn display_name(&self) -> &'static str {
        "Web"
    }

    fn detect(&self, project_root: &Path) -> Option<ProjectDetection> {
        let package_json = project_root.join("package.json");
        package_json.exists().then(|| {
            let mut evidence = vec!["package.json".to_owned()];
            if let Some(lockfile) = web_lockfile(project_root) {
                evidence.push(lockfile);
            }

            ProjectDetection {
                provider_id: self.id(),
                confidence: DetectionConfidence::High,
                project_root: project_root.to_path_buf(),
                evidence,
            }
        })
    }

    fn list_tasks(&self, project_root: &Path) -> Result<Vec<TaskDefinition>, TaskProviderError> {
        let scripts = package_json_scripts(project_root)?;
        Ok(scripts
            .into_iter()
            .map(|script| {
                let kind = match script.as_str() {
                    "build" => TaskKind::Build,
                    "dev" | "start" => TaskKind::Run,
                    "test" => TaskKind::Test,
                    _ => TaskKind::Script,
                };
                task(
                    self.id(),
                    format!("web-script:{script}"),
                    format!("{script} script"),
                    kind,
                )
            })
            .collect())
    }

    fn execution_plan(
        &self,
        project_root: &Path,
        task_id: &str,
    ) -> Result<TaskExecutionPlan, TaskProviderError> {
        let Some(script) = task_id.strip_prefix("web-script:") else {
            return Err(TaskProviderError::TaskNotFound {
                provider_id: self.id(),
                task_id: task_id.to_owned(),
            });
        };

        let scripts = package_json_scripts(project_root)?;
        if !scripts.iter().any(|candidate| candidate == script) {
            return Err(TaskProviderError::TaskNotFound {
                provider_id: self.id(),
                task_id: task_id.to_owned(),
            });
        }

        let package_manager = web_package_manager(project_root);
        Ok(plan(
            self.id(),
            task_id,
            package_manager,
            ["run", script],
            project_root,
        ))
    }
}

#[derive(Debug, Clone, Copy)]
pub struct AndroidProvider;

impl AndroidProvider {
    pub fn inspect_environment(&self, project_root: &Path) -> AndroidEnvironmentInspection {
        self.inspect_environment_from(
            project_root,
            env::var_os("ANDROID_HOME").map(PathBuf::from),
            env::var_os("ANDROID_SDK_ROOT").map(PathBuf::from),
            env::var_os("PATH"),
        )
    }

    pub fn inspect_environment_from(
        &self,
        project_root: &Path,
        android_home: Option<PathBuf>,
        android_sdk_root: Option<PathBuf>,
        path: Option<impl AsRef<OsStr>>,
    ) -> AndroidEnvironmentInspection {
        let sdk_location = android_sdk_root.clone().or_else(|| android_home.clone());
        let android_cli_path = find_program("android", path.as_ref().map(|path| path.as_ref()));
        let gradle_wrapper_path = project_root
            .join("gradlew")
            .exists()
            .then(|| project_root.join("gradlew"));
        let mut notes = Vec::new();

        if sdk_location.is_none() {
            notes.push("ANDROID_HOME or ANDROID_SDK_ROOT is not set".to_owned());
        }
        if android_cli_path.is_none() {
            notes.push("android CLI was not found on PATH".to_owned());
        }
        if gradle_wrapper_path.is_none() {
            notes.push("Gradle wrapper not found; falling back to gradle when needed".to_owned());
        }

        AndroidEnvironmentInspection {
            sdk_location,
            android_home,
            android_sdk_root,
            android_cli_path,
            gradle_wrapper_path,
            notes,
        }
    }

    pub fn describe_project_shape(&self, project_root: &Path) -> AndroidProjectDescription {
        let settings_files =
            existing_child_files(project_root, ["settings.gradle", "settings.gradle.kts"]);
        let root_build_files =
            existing_child_files(project_root, ["build.gradle", "build.gradle.kts"]);
        let module_build_files =
            existing_grandchild_files(project_root, ["build.gradle", "build.gradle.kts"]);
        let manifest_files = existing_descendant_files(project_root, ["AndroidManifest.xml"]);

        AndroidProjectDescription {
            project_root: project_root.to_path_buf(),
            settings_files,
            root_build_files,
            module_build_files,
            manifest_files,
            has_gradle_wrapper: project_root.join("gradlew").exists(),
        }
    }

    pub fn device_integration_plan(&self) -> AndroidDeviceIntegrationPlan {
        AndroidDeviceIntegrationPlan {
            device_listing: AndroidDeviceIntegrationStatus::Planned,
            emulator_listing: AndroidDeviceIntegrationStatus::Planned,
            app_deployment: AndroidDeviceIntegrationStatus::Placeholder,
            notes: vec![
                "Future device listing should map to android run --device and emulator commands"
                    .to_owned(),
                "Future deployment should consume android describe artifact metadata".to_owned(),
            ],
        }
    }
}

impl BuildToolProvider for AndroidProvider {
    fn id(&self) -> TaskProviderId {
        TaskProviderId::Android
    }

    fn display_name(&self) -> &'static str {
        "Android"
    }

    fn detect(&self, project_root: &Path) -> Option<ProjectDetection> {
        let evidence: Vec<String> = [
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts",
            "gradlew",
        ]
        .into_iter()
        .filter(|candidate| project_root.join(candidate).exists())
        .map(ToOwned::to_owned)
        .collect();

        (!evidence.is_empty()).then(|| ProjectDetection {
            provider_id: self.id(),
            confidence: if evidence.iter().any(|item| item == "gradlew") {
                DetectionConfidence::High
            } else {
                DetectionConfidence::Medium
            },
            project_root: project_root.to_path_buf(),
            evidence,
        })
    }

    fn list_tasks(&self, _project_root: &Path) -> Result<Vec<TaskDefinition>, TaskProviderError> {
        Ok(vec![
            task_with_detail(
                self.id(),
                "android-describe",
                "android describe",
                TaskKind::Other,
                "Generate project metadata for build targets and artifacts",
            ),
            task(self.id(), "android-build", "assembleDebug", TaskKind::Build),
            task_with_detail(
                self.id(),
                "android-run",
                "android run",
                TaskKind::Run,
                "Placeholder for deployment after artifact and device selection are wired",
            ),
            task(
                self.id(),
                "android-test",
                "testDebugUnitTest",
                TaskKind::Test,
            ),
        ])
    }

    fn execution_plan(
        &self,
        project_root: &Path,
        task_id: &str,
    ) -> Result<TaskExecutionPlan, TaskProviderError> {
        let program = if project_root.join("gradlew").exists() {
            "./gradlew"
        } else {
            "gradle"
        };

        match task_id {
            "android-describe" => Ok(plan(
                self.id(),
                task_id,
                "android",
                ["describe", "--project_dir", &project_root.to_string_lossy()],
                project_root,
            )),
            "android-build" => Ok(plan(
                self.id(),
                task_id,
                program,
                ["assembleDebug"],
                project_root,
            )),
            "android-test" => Ok(plan(
                self.id(),
                task_id,
                program,
                ["testDebugUnitTest"],
                project_root,
            )),
            "android-run" => Ok(plan(
                self.id(),
                task_id,
                "android",
                ["run", "--debug"],
                project_root,
            )),
            _ => Err(TaskProviderError::TaskNotFound {
                provider_id: self.id(),
                task_id: task_id.to_owned(),
            }),
        }
    }

    fn parse_diagnostics(&self, output: &TaskOutput) -> Vec<TaskDiagnostic> {
        output
            .stderr
            .lines()
            .chain(output.stdout.lines())
            .filter_map(parse_android_diagnostic_line)
            .collect()
    }
}

fn task(
    provider_id: TaskProviderId,
    id: impl Into<String>,
    label: impl Into<String>,
    kind: TaskKind,
) -> TaskDefinition {
    TaskDefinition {
        provider_id,
        id: id.into(),
        label: label.into(),
        kind,
        detail: None,
    }
}

fn task_with_detail(
    provider_id: TaskProviderId,
    id: impl Into<String>,
    label: impl Into<String>,
    kind: TaskKind,
    detail: impl Into<String>,
) -> TaskDefinition {
    TaskDefinition {
        provider_id,
        id: id.into(),
        label: label.into(),
        kind,
        detail: Some(detail.into()),
    }
}

fn plan<const N: usize>(
    provider_id: TaskProviderId,
    task_id: &str,
    program: impl Into<String>,
    args: [&str; N],
    cwd: &Path,
) -> TaskExecutionPlan {
    TaskExecutionPlan {
        provider_id,
        task_id: task_id.to_owned(),
        program: program.into(),
        args: args.into_iter().map(ToOwned::to_owned).collect(),
        cwd: cwd.to_path_buf(),
        environment: Vec::new(),
    }
}

fn existing_child_files<const N: usize>(project_root: &Path, names: [&str; N]) -> Vec<PathBuf> {
    names
        .into_iter()
        .map(|name| project_root.join(name))
        .filter(|path| path.exists())
        .collect()
}

fn existing_grandchild_files<const N: usize>(
    project_root: &Path,
    names: [&str; N],
) -> Vec<PathBuf> {
    let Ok(children) = fs::read_dir(project_root) else {
        return Vec::new();
    };

    let mut files: Vec<PathBuf> = children
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .flat_map(|child| {
            names
                .iter()
                .map(move |name| child.join(name))
                .filter(|path| path.exists())
        })
        .collect();
    files.sort();
    files
}

fn existing_descendant_files<const N: usize>(
    project_root: &Path,
    names: [&str; N],
) -> Vec<PathBuf> {
    let mut files = Vec::new();
    collect_descendant_files(project_root, &names, &mut files);
    files.sort();
    files
}

fn collect_descendant_files(project_root: &Path, names: &[&str], files: &mut Vec<PathBuf>) {
    let Ok(children) = fs::read_dir(project_root) else {
        return;
    };

    for child in children.flatten().map(|entry| entry.path()) {
        if child.is_dir() {
            if should_skip_project_directory(&child) {
                continue;
            }
            collect_descendant_files(&child, names, files);
        } else if child
            .file_name()
            .and_then(OsStr::to_str)
            .is_some_and(|file_name| names.contains(&file_name))
        {
            files.push(child);
        }
    }
}

fn should_skip_project_directory(path: &Path) -> bool {
    matches!(
        path.file_name().and_then(OsStr::to_str),
        Some(".git" | ".gradle" | ".swiftpm" | "build" | "node_modules" | "target")
    )
}

fn find_program(name: &str, path: Option<&OsStr>) -> Option<PathBuf> {
    path.map(env::split_paths)
        .into_iter()
        .flatten()
        .map(|directory| directory.join(name))
        .find(|candidate| candidate.is_file())
}

fn package_json_scripts(project_root: &Path) -> Result<Vec<String>, TaskProviderError> {
    let path = project_root.join("package.json");
    let text = fs::read_to_string(&path)?;
    let value: serde_json::Value = serde_json::from_str(&text)
        .map_err(|error| TaskProviderError::InvalidPackageJson(path.clone(), error))?;
    let mut scripts: Vec<String> = value
        .get("scripts")
        .and_then(serde_json::Value::as_object)
        .map(|scripts| scripts.keys().cloned().collect())
        .unwrap_or_default();
    scripts.sort();
    Ok(scripts)
}

fn web_package_manager(project_root: &Path) -> &'static str {
    if project_root.join("pnpm-lock.yaml").exists() {
        "pnpm"
    } else if project_root.join("bun.lock").exists() || project_root.join("bun.lockb").exists() {
        "bun"
    } else if project_root.join("yarn.lock").exists() {
        "yarn"
    } else {
        "npm"
    }
}

fn web_lockfile(project_root: &Path) -> Option<String> {
    [
        "pnpm-lock.yaml",
        "bun.lock",
        "bun.lockb",
        "yarn.lock",
        "package-lock.json",
    ]
    .into_iter()
    .find(|candidate| project_root.join(candidate).exists())
    .map(ToOwned::to_owned)
}

fn parse_generic_diagnostics(output: &TaskOutput) -> Vec<TaskDiagnostic> {
    output
        .stderr
        .lines()
        .chain(output.stdout.lines())
        .filter_map(parse_generic_diagnostic_line)
        .collect()
}

fn parse_generic_diagnostic_line(line: &str) -> Option<TaskDiagnostic> {
    let lower = line.to_lowercase();
    let severity = if lower.contains("error:") || lower.starts_with("error ") {
        DiagnosticSeverity::Error
    } else if lower.contains("warning:") || lower.starts_with("warning ") {
        DiagnosticSeverity::Warning
    } else if lower.contains("note:") || lower.starts_with("note ") {
        DiagnosticSeverity::Note
    } else {
        return None;
    };

    let (file, line_number, column, message) = parse_file_location(line);
    Some(TaskDiagnostic {
        severity,
        message,
        file,
        line: line_number,
        column,
    })
}

fn parse_android_diagnostic_line(line: &str) -> Option<TaskDiagnostic> {
    parse_kotlin_diagnostic_line(line).or_else(|| parse_generic_diagnostic_line(line))
}

fn parse_kotlin_diagnostic_line(line: &str) -> Option<TaskDiagnostic> {
    let rest = line.strip_prefix('e').or_else(|| line.strip_prefix('w'))?;
    let severity = if line.starts_with('e') {
        DiagnosticSeverity::Error
    } else {
        DiagnosticSeverity::Warning
    };
    let rest = rest.trim_start();
    let (file_and_location, message) = rest.split_once(':')?;
    let (file, line_number, column) = parse_kotlin_location(file_and_location)?;

    Some(TaskDiagnostic {
        severity,
        message: message.trim().to_owned(),
        file: Some(file),
        line: Some(line_number),
        column: Some(column),
    })
}

fn parse_kotlin_location(value: &str) -> Option<(PathBuf, usize, usize)> {
    let line_start = value.rfind('(')?;
    let line_end = value.rfind(')')?;
    let file = value[..line_start].trim();
    let location = &value[line_start + 1..line_end];
    let (line_number, column) = location.split_once(", ")?;
    Some((
        PathBuf::from(file),
        line_number.parse().ok()?,
        column.parse().ok()?,
    ))
}

fn parse_file_location(line: &str) -> (Option<PathBuf>, Option<usize>, Option<usize>, String) {
    let parts: Vec<&str> = line.splitn(4, ':').collect();
    if parts.len() >= 4 {
        let line_number = parts[1].parse::<usize>().ok();
        let column = parts[2].parse::<usize>().ok();
        if line_number.is_some() && column.is_some() {
            return (
                Some(PathBuf::from(parts[0])),
                line_number,
                column,
                parts[3].trim().to_owned(),
            );
        }
    }

    (None, None, None, line.trim().to_owned())
}
