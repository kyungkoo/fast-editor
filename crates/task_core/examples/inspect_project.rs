use std::env;
use std::path::PathBuf;

use task_core::{builtin_task_providers, AndroidProvider, TaskProviderId};

fn main() {
    let project_root = env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| env::current_dir().expect("read current directory"));
    let registry = builtin_task_providers();

    println!("project: {}", project_root.display());

    let detections = registry.detect_project(&project_root);
    if detections.is_empty() {
        println!("detections: none");
        return;
    }

    println!("detections:");
    for detection in &detections {
        println!(
            "- {:?} ({:?}) evidence={:?}",
            detection.provider_id, detection.confidence, detection.evidence
        );
    }

    println!("tasks:");
    match registry.list_project_tasks(&project_root) {
        Ok(tasks) => {
            for task in tasks {
                println!("- {:?} {} [{}]", task.provider_id, task.id, task.label);
            }
        }
        Err(error) => println!("error: {error}"),
    }

    if detections
        .iter()
        .any(|detection| detection.provider_id == TaskProviderId::Android)
    {
        let provider = AndroidProvider;
        let environment = provider.inspect_environment(&project_root);
        let description = provider.describe_project_shape(&project_root);
        let device_plan = provider.device_integration_plan();

        println!("android environment:");
        println!("- sdk_location={:?}", environment.sdk_location);
        println!("- android_cli_path={:?}", environment.android_cli_path);
        println!(
            "- gradle_wrapper_path={:?}",
            environment.gradle_wrapper_path
        );
        println!("- notes={:?}", environment.notes);

        println!("android project:");
        println!("- settings_files={:?}", description.settings_files);
        println!("- root_build_files={:?}", description.root_build_files);
        println!("- module_build_files={:?}", description.module_build_files);
        println!("- manifest_files={:?}", description.manifest_files);
        println!("- has_gradle_wrapper={}", description.has_gradle_wrapper);

        println!("android device plan:");
        println!("- device_listing={:?}", device_plan.device_listing);
        println!("- emulator_listing={:?}", device_plan.emulator_listing);
        println!("- app_deployment={:?}", device_plan.app_deployment);
    }
}
