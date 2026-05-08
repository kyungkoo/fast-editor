use super::*;

use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

struct TempProject {
    path: PathBuf,
}

impl TempProject {
    fn new(name: &str) -> Self {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("fast-editor-{name}-{unique}"));
        fs::create_dir_all(&path).expect("create temp project");
        Self { path }
    }

    fn write(&self, relative_path: &str, text: &str) {
        fs::write(self.path.join(relative_path), text).expect("write temp project file");
    }
}

impl Drop for TempProject {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

#[derive(Debug, Clone, Copy)]
struct FakeProvider;

impl BuildToolProvider for FakeProvider {
    fn id(&self) -> TaskProviderId {
        TaskProviderId::Custom("fake".to_owned())
    }

    fn display_name(&self) -> &'static str {
        "Fake"
    }

    fn detect(&self, project_root: &Path) -> Option<ProjectDetection> {
        project_root
            .join(".fake-project")
            .exists()
            .then(|| ProjectDetection {
                provider_id: self.id(),
                confidence: DetectionConfidence::High,
                project_root: project_root.to_path_buf(),
                evidence: vec![".fake-project".to_owned()],
            })
    }

    fn list_tasks(&self, _project_root: &Path) -> Result<Vec<TaskDefinition>, TaskProviderError> {
        Ok(vec![task(
            self.id(),
            "fake-build",
            "Fake build",
            TaskKind::Build,
        )])
    }

    fn execution_plan(
        &self,
        project_root: &Path,
        task_id: &str,
    ) -> Result<TaskExecutionPlan, TaskProviderError> {
        match task_id {
            "fake-build" => Ok(plan(self.id(), task_id, "fake", ["build"], project_root)),
            _ => Err(TaskProviderError::TaskNotFound {
                provider_id: self.id(),
                task_id: task_id.to_owned(),
            }),
        }
    }
}

#[test]
fn fake_provider_exercises_provider_abstraction() {
    let project = TempProject::new("fake-provider");
    project.write(".fake-project", "");
    let mut registry = TaskProviderRegistry::new();
    registry.register(FakeProvider);

    let detections = registry.detect_project(&project.path);
    assert_eq!(detections.len(), 1);
    assert_eq!(
        detections[0].provider_id,
        TaskProviderId::Custom("fake".to_owned())
    );

    let tasks = registry
        .list_project_tasks(&project.path)
        .expect("list fake tasks");
    assert_eq!(tasks[0].id, "fake-build");

    let plan = FakeProvider
        .execution_plan(&project.path, "fake-build")
        .expect("fake execution plan");
    assert_eq!(plan.program, "fake");
    assert_eq!(plan.args, ["build"]);
}

#[test]
fn swift_package_provider_detects_manifest_and_lists_build_tasks() {
    let project = TempProject::new("swift-package");
    project.write("Package.swift", "// swift-tools-version: 6.0\n");
    let provider = SwiftPackageProvider;

    let detection = provider.detect(&project.path).expect("swift detection");
    assert_eq!(detection.provider_id, TaskProviderId::SwiftPackage);
    assert_eq!(detection.evidence, ["Package.swift"]);

    let tasks = provider.list_tasks(&project.path).expect("swift tasks");
    assert_eq!(
        tasks
            .iter()
            .map(|task| task.id.as_str())
            .collect::<Vec<_>>(),
        ["swift-build", "swift-test"]
    );

    let plan = provider
        .execution_plan(&project.path, "swift-test")
        .expect("swift test plan");
    assert_eq!(plan.program, "swift");
    assert_eq!(plan.args, ["test"]);
}

#[test]
fn web_provider_reads_package_json_scripts_with_package_manager_boundary() {
    let project = TempProject::new("web");
    project.write(
        "package.json",
        r#"{"scripts":{"test":"vitest","build":"vite build","dev":"vite"}}"#,
    );
    project.write("pnpm-lock.yaml", "");
    let provider = WebProvider;

    let detection = provider.detect(&project.path).expect("web detection");
    assert_eq!(detection.provider_id, TaskProviderId::Web);
    assert_eq!(detection.evidence, ["package.json", "pnpm-lock.yaml"]);

    let tasks = provider.list_tasks(&project.path).expect("web tasks");
    assert_eq!(
        tasks
            .iter()
            .map(|task| task.id.as_str())
            .collect::<Vec<_>>(),
        ["web-script:build", "web-script:dev", "web-script:test"]
    );

    let plan = provider
        .execution_plan(&project.path, "web-script:build")
        .expect("web build plan");
    assert_eq!(plan.program, "pnpm");
    assert_eq!(plan.args, ["run", "build"]);
}

#[test]
fn android_provider_detects_gradle_project_and_uses_wrapper_when_present() {
    let project = TempProject::new("android");
    project.write("settings.gradle.kts", "pluginManagement {}\n");
    project.write("gradlew", "");
    fs::create_dir_all(project.path.join("app/src/main")).expect("create android module dirs");
    project.write(
        "app/build.gradle.kts",
        "plugins { id(\"com.android.application\") }\n",
    );
    project.write("app/src/main/AndroidManifest.xml", "<manifest />\n");
    let provider = AndroidProvider;

    let detection = provider.detect(&project.path).expect("android detection");
    assert_eq!(detection.provider_id, TaskProviderId::Android);
    assert_eq!(detection.confidence, DetectionConfidence::High);

    let description = provider.describe_project_shape(&project.path);
    assert_eq!(description.settings_files.len(), 1);
    assert_eq!(description.module_build_files.len(), 1);
    assert_eq!(description.manifest_files.len(), 1);
    assert!(description.has_gradle_wrapper);

    let tasks = provider.list_tasks(&project.path).expect("android tasks");
    assert_eq!(
        tasks
            .iter()
            .map(|task| task.id.as_str())
            .collect::<Vec<_>>(),
        [
            "android-describe",
            "android-build",
            "android-run",
            "android-test"
        ]
    );

    let plan = provider
        .execution_plan(&project.path, "android-build")
        .expect("android build plan");
    assert_eq!(plan.program, "./gradlew");
    assert_eq!(plan.args, ["assembleDebug"]);

    let run_plan = provider
        .execution_plan(&project.path, "android-run")
        .expect("android run plan");
    assert_eq!(run_plan.program, "android");
    assert_eq!(run_plan.args, ["run", "--debug"]);
}

#[test]
fn android_provider_exposes_environment_and_device_placeholders() {
    let project = TempProject::new("android-env");
    project.write("gradlew", "");
    let bin = project.path.join("bin");
    fs::create_dir_all(&bin).expect("create bin");
    project.write("bin/android", "");
    let provider = AndroidProvider;

    let environment = provider.inspect_environment_from(
        &project.path,
        Some(PathBuf::from("/opt/android-sdk")),
        None,
        Some(bin.as_os_str()),
    );

    assert_eq!(
        environment.sdk_location,
        Some(PathBuf::from("/opt/android-sdk"))
    );
    assert_eq!(environment.android_cli_path, Some(bin.join("android")));
    assert_eq!(
        environment.gradle_wrapper_path,
        Some(project.path.join("gradlew"))
    );
    assert!(environment.notes.is_empty());

    let device_plan = provider.device_integration_plan();
    assert_eq!(
        device_plan.app_deployment,
        AndroidDeviceIntegrationStatus::Placeholder
    );
}

#[test]
fn registry_lists_tasks_only_for_detected_providers() {
    let project = TempProject::new("registry");
    project.write("Package.swift", "// swift-tools-version: 6.0\n");
    let registry = builtin_task_providers();

    let tasks = registry
        .list_project_tasks(&project.path)
        .expect("registry tasks");

    assert_eq!(
        tasks
            .iter()
            .map(|task| task.provider_id.clone())
            .collect::<Vec<_>>(),
        vec![TaskProviderId::SwiftPackage, TaskProviderId::SwiftPackage]
    );
}

#[test]
fn registry_builds_execution_plans_for_registered_providers() {
    let project = TempProject::new("registry-plan");
    project.write("Package.swift", "// swift-tools-version: 6.0\n");
    let registry = builtin_task_providers();

    let plan = registry
        .execution_plan(&TaskProviderId::SwiftPackage, &project.path, "swift-build")
        .expect("registry execution plan");

    assert_eq!(plan.program, "swift");
    assert_eq!(plan.args, ["build"]);
}

#[test]
fn generic_diagnostic_parser_extracts_file_locations() {
    let output = TaskOutput {
        stdout: "Sources/App.swift:12:4: error: cannot find value\n".to_owned(),
        stderr: "warning: build setting ignored\n".to_owned(),
        exit_code: Some(1),
    };

    let diagnostics = SwiftPackageProvider.parse_diagnostics(&output);
    assert_eq!(diagnostics.len(), 2);
    assert_eq!(diagnostics[0].severity, DiagnosticSeverity::Warning);
    assert_eq!(diagnostics[1].severity, DiagnosticSeverity::Error);
    assert_eq!(
        diagnostics[1].file,
        Some(PathBuf::from("Sources/App.swift"))
    );
    assert_eq!(diagnostics[1].line, Some(12));
    assert_eq!(diagnostics[1].column, Some(4));
}

#[test]
fn android_diagnostic_parser_handles_kotlin_style_locations() {
    let output = TaskOutput {
        stdout: String::new(),
        stderr: "e app/src/main/java/MainActivity.kt(12, 8): Unresolved reference\n".to_owned(),
        exit_code: Some(1),
    };

    let diagnostics = AndroidProvider.parse_diagnostics(&output);

    assert_eq!(diagnostics.len(), 1);
    assert_eq!(diagnostics[0].severity, DiagnosticSeverity::Error);
    assert_eq!(
        diagnostics[0].file,
        Some(PathBuf::from("app/src/main/java/MainActivity.kt"))
    );
    assert_eq!(diagnostics[0].line, Some(12));
    assert_eq!(diagnostics[0].column, Some(8));
}
