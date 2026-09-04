import Foundation
import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentRuntimeProjectWorkspacePersistsAcrossIsolatedRequests() throws {
    let fixture = try runtimeProjectFixture("runtime-project-persist")
    let project = fixture.projects.appendingPathComponent("workspace-one", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("first".utf8).write(to: project.appendingPathComponent("README.md"))

    let first = try fixture.manager.prepare(runtimeProjectRequest("run-one", source: "print('one')"))
    XCTAssertEqual(try String(contentsOf: first.directory.appendingPathComponent("README.md")), "first")
    try Data("generated".utf8).write(to: first.directory.appendingPathComponent("result.txt"))
    try Data("private runtime output".utf8).write(to: first.directory.appendingPathComponent(".galaxyssi-stdout"))
    let sync = try fixture.manager.syncProject(first, byteLimit: 8 * runtimeProjectMiB)

    XCTAssertGreaterThanOrEqual(sync.fileCount, 3)
    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("result.txt")), "generated")
    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("main.py")), "print('one')")
    XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("request.json").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent(".galaxyssi-stdout").path))

    let second = try fixture.manager.prepare(runtimeProjectRequest("run-two", source: "print('two')"))
    XCTAssertEqual(try String(contentsOf: second.directory.appendingPathComponent("result.txt")), "generated")
    XCTAssertEqual(try String(contentsOf: second.directory.appendingPathComponent("README.md")), "first")
    XCTAssertEqual(try String(contentsOf: second.sourceFile), "print('two')")
    XCTAssertGreaterThan(second.importedProjectBytes, 0)
  }

  func testAgentRuntimeProjectWorkspaceRejectsSnapshotsOverQuota() throws {
    let fixture = try runtimeProjectFixture("runtime-project-quota")
    let prepared = try fixture.manager.prepare(runtimeProjectRequest("run-quota", source: "print('quota')"))
    try Data(repeating: 0x5a, count: 32 * 1024)
      .write(to: prepared.directory.appendingPathComponent("large.bin"))

    XCTAssertThrowsError(try fixture.manager.syncProject(prepared, byteLimit: 8 * 1024)) { error in
      XCTAssertEqual((error as? AgentRuntimeProjectWorkspaceError)?.code, .limitExceeded)
    }
  }

  func testAgentRuntimeProjectWorkspacePackagesProjectArtifacts() throws {
    let fixture = try runtimeProjectFixture("runtime-project-artifacts")
    let request = runtimeProjectRequest(
      "run-project",
      source: "print('project')",
      artifactPaths: ["src", "README.md"]
    )
    let prepared = try fixture.manager.prepare(request)
    try FileManager.default.createDirectory(
      at: prepared.directory.appendingPathComponent("src/lib", isDirectory: true),
      withIntermediateDirectories: true
    )
    try Data("print('hello')".utf8).write(to: prepared.directory.appendingPathComponent("src/main.py"))
    try Data("VALUE = 7".utf8).write(to: prepared.directory.appendingPathComponent("src/lib/value.py"))
    try Data("# Sample".utf8).write(to: prepared.directory.appendingPathComponent("README.md"))
    _ = try fixture.manager.syncProject(prepared, byteLimit: 8 * runtimeProjectMiB)

    let artifact = try fixture.manager.collectArtifacts(prepared: prepared, request: request).singleValue()
    let archiveData = try Data(contentsOf: artifact.hostURL)
    let publicValue = artifact.publicValue()

    XCTAssertEqual(artifact.artifactKind, "project_archive")
    XCTAssertEqual(artifact.fileCount, 3)
    XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.hostURL.path))
    XCTAssertTrue(archiveData.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
    XCTAssertTrue(String(decoding: archiveData, as: UTF8.self).contains("src/lib/value.py"))
    XCTAssertNil(publicValue["host_path"])
    XCTAssertEqual(publicValue["artifact_kind"], .string("project_archive"))
  }

  func testAgentRuntimeProjectWorkspaceCheckpointRollbackAndIsolation() throws {
    let fixture = try runtimeProjectFixture("runtime-project-rollback", nowMillis: { 7_000 })
    let project = fixture.projects.appendingPathComponent("workspace-one", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("stable".utf8).write(to: project.appendingPathComponent("README.md"))
    let checkpoint = try fixture.manager.checkpoint(
      workspaceId: "workspace-one",
      checkpointId: "before-change",
      byteLimit: 8 * runtimeProjectMiB
    )

    let prepared = try fixture.manager.prepare(runtimeProjectRequest("run-change", source: "print('change')"))
    try Data("changed".utf8).write(to: prepared.directory.appendingPathComponent("README.md"))
    try Data("candidate".utf8).write(to: prepared.directory.appendingPathComponent("generated.txt"))
    _ = try fixture.manager.syncProject(prepared, byteLimit: 8 * runtimeProjectMiB)
    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("README.md")), "changed")

    let restored = try fixture.manager.rollback(
      workspaceId: "workspace-one",
      checkpointId: checkpoint.checkpointId,
      byteLimit: 8 * runtimeProjectMiB
    )

    XCTAssertEqual(restored.fileCount, 1)
    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("README.md")), "stable")
    XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("generated.txt").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("main.py").path))
    let status = try fixture.manager.workspaceStatus("workspace-one")
    XCTAssertEqual(status.checkpoints.map(\.checkpointId), ["before-change"])
    XCTAssertFalse(String(describing: status.publicValue()).contains(fixture.root.path))

    XCTAssertThrowsError(
      try fixture.manager.rollback(
        workspaceId: "workspace-two",
        checkpointId: checkpoint.checkpointId,
        byteLimit: 8 * runtimeProjectMiB
      )
    )
  }

  func testAgentRuntimeProjectWorkspaceCommitCreatesRecoveryCheckpoint() throws {
    let fixture = try runtimeProjectFixture("runtime-project-commit")
    let project = fixture.projects.appendingPathComponent("workspace-one", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("stable".utf8).write(to: project.appendingPathComponent("value.txt"))
    let prepared = try fixture.manager.prepare(runtimeProjectRequest("run-commit", source: "print('candidate')"))
    try Data("candidate".utf8).write(to: prepared.directory.appendingPathComponent("value.txt"))
    try Data("created".utf8).write(to: prepared.directory.appendingPathComponent("new.txt"))

    let commit = try fixture.manager.commitProject(
      prepared: prepared,
      byteLimit: 8 * runtimeProjectMiB,
      checkpointId: "pre-run-commit"
    )

    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("value.txt")), "candidate")
    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("new.txt")), "created")
    XCTAssertEqual(commit.checkpoint.checkpointId, "pre-run-commit")
    XCTAssertEqual(commit.checkpoint.fileCount, 1)
    XCTAssertGreaterThanOrEqual(commit.project.fileCount, 3)
    XCTAssertEqual(commit.publicValue()["workspace_disposition"], .string("committed"))

    _ = try fixture.manager.rollback(
      workspaceId: "workspace-one",
      checkpointId: commit.checkpoint.checkpointId,
      byteLimit: 8 * runtimeProjectMiB
    )
    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("value.txt")), "stable")
    XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("new.txt").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("main.py").path))
  }

  func testAgentRuntimeProjectWorkspaceModelsUseAndroidWireNames() throws {
    let request = runtimeProjectRequest("run-wire", source: "print('wire')")
    let encodedRequest = String(data: try JSONEncoder().encode(request), encoding: .utf8) ?? ""
    let status = AgentRuntimeProjectStatus(
      workspaceId: "workspace-one",
      fileCount: 2,
      totalBytes: 12,
      checkpoints: [
        AgentRuntimeProjectCheckpoint(
          workspaceId: "workspace-one",
          checkpointId: "checkpoint-1",
          fileCount: 1,
          totalBytes: 6,
          createdAtMillis: 9
        )
      ]
    )
    let encodedStatus = String(data: try JSONEncoder().encode(status), encoding: .utf8) ?? ""

    XCTAssertTrue(encodedRequest.contains(#""timeout_ms":1000"#))
    XCTAssertTrue(encodedRequest.contains(#""workspace_id":"workspace-one""#))
    XCTAssertTrue(encodedRequest.contains(#""request_id":"run-wire""#))
    XCTAssertTrue(encodedRequest.contains(#""resource_limits":{"#))
    XCTAssertTrue(encodedStatus.contains(#""workspace_file_count":2"#))
    XCTAssertTrue(encodedStatus.contains(#""checkpoint_id":"checkpoint-1""#))
    XCTAssertEqual(try JSONDecoder().decode(AgentRuntimeProjectStatus.self, from: Data(encodedStatus.utf8)), status)
  }

  private func runtimeProjectFixture(
    _ label: String,
    nowMillis: @escaping () -> Int64 = { 1_000 }
  ) throws -> (
    root: URL,
    runtime: URL,
    projects: URL,
    manager: AgentRuntimeProjectWorkspaceManager
  ) {
    let root = try temporaryDirectory(label)
    let runtime = root.appendingPathComponent("runtime", isDirectory: true)
    let projects = root.appendingPathComponent("projects", isDirectory: true)
    let manager = AgentRuntimeProjectWorkspaceManager(
      runtimeRoot: runtime,
      projectRoot: projects,
      nowMillis: nowMillis
    )
    return (root, runtime, projects, manager)
  }

  private func runtimeProjectRequest(
    _ requestId: String,
    source: String,
    artifactPaths: [String] = ["result.txt"]
  ) -> AgentRuntimeProjectExecutionRequest {
    AgentRuntimeProjectExecutionRequest(
      language: .python,
      source: source,
      timeoutMillis: 1_000,
      networkEnabled: false,
      artifactPaths: artifactPaths,
      workspaceId: "workspace-one",
      requestId: requestId,
      resourceLimits: AgentRuntimeProjectResourceLimits(
        wallClockMillis: 1_000,
        cpuMillis: 750,
        memoryBytes: 64 * 1024 * 1024,
        diskBytes: 8 * runtimeProjectMiB,
        maxProcesses: 8,
        maxOutputBytes: 64 * 1024,
        maxArtifactBytes: 4 * runtimeProjectMiB
      )
    )
  }
}

private let runtimeProjectMiB: Int64 = 1024 * 1024

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) throws -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return try XCTUnwrap(first, file: file, line: line)
  }
}
