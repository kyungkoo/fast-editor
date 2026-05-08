import Foundation
import Testing
@testable import FastEditorModels

struct ProjectTaskSummaryTests {
    @Test func decodesAndroidTaskSummaryPayload() throws {
        let payload = """
        {
          "detections": [
            {
              "provider_id": "android",
              "confidence": "high",
              "project_root": "/tmp/android",
              "evidence": ["settings.gradle.kts", "gradlew"]
            }
          ],
          "tasks": [
            {
              "provider_id": "android",
              "id": "android-build",
              "label": "assembleDebug",
              "kind": "build",
              "detail": null
            }
          ],
          "android": {
            "environment": {
              "sdk_location": "/opt/android-sdk",
              "android_home": "/opt/android-sdk",
              "android_sdk_root": null,
              "android_cli_path": "/usr/local/bin/android",
              "gradle_wrapper_path": "/tmp/android/gradlew",
              "notes": []
            },
            "project": {
              "project_root": "/tmp/android",
              "settings_files": ["/tmp/android/settings.gradle.kts"],
              "root_build_files": [],
              "module_build_files": ["/tmp/android/app/build.gradle.kts"],
              "manifest_files": ["/tmp/android/app/src/main/AndroidManifest.xml"],
              "has_gradle_wrapper": true
            }
          }
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(ProjectTaskSummary.self, from: payload)

        #expect(summary.detections[0].providerID == .android)
        #expect(summary.detections[0].confidence == .high)
        #expect(summary.tasks[0].kind == .build)
        #expect(summary.android?.environment.sdkLocation == "/opt/android-sdk")
        #expect(summary.android?.project.hasGradleWrapper == true)
    }

    @Test func decodesTaskExecutionPlanPayload() throws {
        let payload = """
        {
          "provider_id": "swift_package",
          "task_id": "swift-test",
          "program": "swift",
          "args": ["test"],
          "cwd": "/tmp/project",
          "environment": []
        }
        """.data(using: .utf8)!

        let plan = try JSONDecoder().decode(TaskExecutionPlan.self, from: payload)

        #expect(plan.providerID == .swiftPackage)
        #expect(plan.taskID == "swift-test")
        #expect(plan.program == "swift")
        #expect(plan.args == ["test"])
        #expect(plan.commandDisplay == "swift test")
    }

    @Test func decodesTaskDiagnosticPayload() throws {
        let payload = """
        [
          {
            "severity": "error",
            "message": "cannot find value",
            "file": "Sources/App.swift",
            "line": 12,
            "column": 4
          }
        ]
        """.data(using: .utf8)!

        let diagnostics = try JSONDecoder().decode([TaskDiagnostic].self, from: payload)

        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].locationDisplay == "Sources/App.swift:12:4")
        #expect(diagnostics[0].message == "cannot find value")
        #expect(diagnostics[0].targetLineIndex == 11)
        #expect(diagnostics[0].targetColumnIndex == 3)
        #expect(diagnostics[0].resolvedFileURL(workspaceURL: URL(fileURLWithPath: "/tmp/project"))?.path == "/tmp/project/Sources/App.swift")
    }
}
