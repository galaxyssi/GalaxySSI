import XCTest
@testable import GalaxySSI

final class AgentSkillLifecycleTests: XCTestCase {
  func testAgentSkillRuntimeInstallsExpandsAndRecordsUse() throws {
    var now: Int64 = 1_000
    let store = InMemoryAgentSkillStore()
    let runtime = AgentSkillRuntime(store: store, availableNativeToolIds: ["test.echo"], clock: { now })
    let manifest = AgentSkillManifest(
      id: "daily_news",
      name: "Daily news",
      version: "1.0.0",
      summary: "Find current news",
      instructions: "Search current public news.",
      nativeTools: ["test.echo"],
      resources: [AgentSkillResource(id: "prompt", path: "prompts/news.txt", mimeType: "text/plain")],
      parameters: .objectSchema(
        properties: [
          "request": .string(minLength: 1, maxLength: 8_000),
          "count": .integer(minimum: 1, maximum: 10)
        ],
        required: ["request", "count"]
      ),
      steps: [
        AgentSkillStep(
          id: "search",
          toolId: "test.echo",
          input: [
            "query": .string("{{parameters.request}}"),
            "count": .string("{{parameters.count}}"),
            "resource": .string("{{resources.prompt}}")
          ]
        )
      ],
      autoInvoke: true,
      triggerExamples: ["Find today's technology news"]
    )

    let installed = try runtime.install(manifest)
    let expansion = try runtime.expand(
      id: installed.id,
      version: installed.version,
      parameters: ["request": .string("Find AI news"), "count": .int(3)]
    )
    now = 2_000
    let used = try runtime.recordUse(id: installed.id, version: installed.version)
    let snapshot = store.serializedSnapshot()
    let restored = InMemoryAgentSkillStore(initialSkills: AgentSkillStoreCodec.decode(snapshot)).list()

    XCTAssertEqual(expansion.steps.singleValue().input["query"], .string("Find AI news"))
    XCTAssertEqual(expansion.steps.singleValue().input["count"], .int(3))
    XCTAssertEqual(expansion.steps.singleValue().input["resource"], .string("prompts/news.txt"))
    XCTAssertEqual(used.useCount, 1)
    XCTAssertEqual(used.lastUsedAtMillis, 2_000)
    XCTAssertEqual(restored.singleValue().manifest.steps.singleValue().toolId, "test.echo")
    XCTAssertTrue(snapshot.contains(#""installations":["#))
    XCTAssertTrue(snapshot.contains(#""installed_at":1000"#))
    XCTAssertTrue(snapshot.contains(#""last_used_at":2000"#))
    XCTAssertTrue(AgentSkillManifestCodec.encode(manifest).contains(#""trigger_examples":["Find today's technology news"]"#))
    XCTAssertTrue(runtime.validate(AgentSkillManifestCodec.encode(manifest)).isValid)
    XCTAssertEqual(try runtime.install(AgentSkillManifestCodec.encode(manifest)).id, installed.id)
  }

  func testAgentSkillMatcherHonorsNegativeExamplesAndExplicitTargets() throws {
    let runtime = AgentSkillRuntime(availableNativeToolIds: ["web.search"], clock: { 1_000 })
    let installed = try runtime.install(
      AgentSkillManifest(
        id: "daily-news",
        name: "Daily news",
        version: "1.0.0",
        summary: "Find current news",
        instructions: "Search current public news.",
        nativeTools: ["web.search"],
        steps: [AgentSkillStep(id: "search", toolId: "web.search")],
        autoInvoke: true,
        triggerExamples: ["Find today's technology news"],
        negativeExamples: ["Open my saved news file"]
      )
    )
    let matcher = AgentSkillMatcher(runtime)

    XCTAssertEqual(matcher.match("Find today's technology news")?.installation.id, installed.id)
    XCTAssertNil(matcher.match("Open my saved news file"))
    XCTAssertNil(matcher.match("Turn on the flashlight"))
    XCTAssertEqual(matcher.match("@daily-news find AI news")?.parameters["request"], .string("find AI news"))
    XCTAssertEqual(matcher.match("@Daily news find security news")?.installation.id, installed.id)
  }

  func testAgentSkillRequestTransformerReusesSingleCharacterParameterizedTask() {
    let argumentMarker = "\u{5B57}"
    let firstArgument = "\u{7532}"
    let secondArgument = "\u{4E59}"
    let savedRequest = "use provider lookup \(firstArgument)\(argumentMarker) mode alpha with detailed output"
    let currentRequest = "lookup \(secondArgument)\(argumentMarker) mode alpha"

    XCTAssertEqual(
      AgentSkillRequestTransformer.transform(savedRequest: savedRequest, currentRequest: currentRequest),
      savedRequest.replacingOccurrences(of: firstArgument, with: secondArgument)
    )
  }

  func testAgentConversationSkillCompilerBuildsLatestReusableWorkflow() throws {
    let descriptor = nativeDescriptor("test.echo")
    let runtime = AgentSkillRuntime(availableNativeToolIds: [descriptor.id], clock: { 1_000 })
    let first = completedRun("run-1", request: "Do the first item", value: "first")
    let latest = completedRun("run-2", request: "Do the second item", value: "second")

    let manifest = try AgentConversationSkillCompiler(runtime, availableTools: { [descriptor] })
      .compile([first, latest])
    let installed = try runtime.install(manifest)
    let next = try AgentConversationSkillCompiler(runtime, availableTools: { [descriptor] })
      .compile([latest])

    XCTAssertEqual(manifest.steps.count, 1)
    XCTAssertEqual(manifest.steps.singleValue().toolId, "test.echo")
    XCTAssertEqual(manifest.steps.singleValue().input["value"], .string("second"))
    XCTAssertEqual(manifest.nativeTools, ["test.echo"])
    XCTAssertEqual(manifest.tests.singleValue().expectedToolIds, ["test.echo"])
    XCTAssertEqual(installed.version, "1.0.0")
    XCTAssertEqual(next.version, "1.1.0")
  }

  func testAgentConversationSkillCompilerFallsBackToOrchestrationTool() throws {
    let runtime = AgentSkillRuntime(
      availableNativeToolIds: [AgentConversationSkillCompiler.agentOrchestrationToolId],
      clock: { 1_000 }
    )
    let run = AgentRecordedRun(
      runId: "run-1",
      conversationId: "conversation",
      taskThreadId: "thread",
      originalRequest: "\u{4f60}\u{5b57}\u{7b14}\u{987a}\u{7b14}\u{753b}",
      status: .completed
    )

    let manifest = try AgentConversationSkillCompiler(runtime, availableTools: { [] }).compile([run])

    XCTAssertEqual(manifest.nativeTools, [AgentConversationSkillCompiler.agentOrchestrationToolId])
    XCTAssertEqual(manifest.steps.singleValue().toolId, AgentConversationSkillCompiler.agentOrchestrationToolId)
    XCTAssertEqual(manifest.steps.singleValue().input["request"], .string("{{parameters.request}}"))
  }

  func testAgentSkillRuntimeRejectsUnsafeResourcesAndMalformedTemplates() {
    let runtime = AgentSkillRuntime(availableNativeToolIds: ["test.echo"])
    let unsafe = AgentSkillManifest(
      id: "unsafe",
      name: "Unsafe",
      version: "1.0.0",
      summary: "Unsafe path",
      instructions: "Reject unsafe paths.",
      nativeTools: ["test.echo"],
      resources: [AgentSkillResource(id: "prompt", path: "../secret.txt")],
      steps: [AgentSkillStep(id: "run", toolId: "test.echo")]
    )
    let malformed = AgentSkillManifest(
      id: "bad-template",
      name: "Bad template",
      version: "1.0.0",
      summary: "Bad template",
      instructions: "Reject bad templates.",
      nativeTools: ["test.echo"],
      steps: [AgentSkillStep(id: "run", toolId: "test.echo", input: ["value": .string("{{parameters.missing")])]
    )
    let unknown = AgentSkillManifest(
      id: "unknown-template",
      name: "Unknown template",
      version: "1.0.0",
      summary: "Unknown template",
      instructions: "Reject unknown parameters.",
      nativeTools: ["test.echo"],
      steps: [AgentSkillStep(id: "run", toolId: "test.echo", input: ["value": .string("{{parameters.missing}}")])]
    )

    XCTAssertTrue(runtime.validate(unsafe).issues.contains { $0.code == "path_traversal" })
    XCTAssertTrue(runtime.validate(malformed).issues.contains { $0.code == "invalid_template" })
    XCTAssertTrue(runtime.validate(unknown).issues.contains { $0.code == "unknown_parameter" })
    XCTAssertTrue(runtime.validate(String(repeating: "x", count: AgentSkillLimits.maxManifestBytes + 1)).issues.contains { $0.code == "oversized_manifest" })
  }

  func testAgentSkillLifecycleModelsUseAndroidWireNames() throws {
    let decodedManifest = try JSONDecoder().decode(
      AgentSkillManifest.self,
      from: Data(
        #"""
        {
          "id": "wire_skill",
          "title": "Wire Skill",
          "version": "1.0.0",
          "description": "Android field names",
          "instructions": "Use the saved workflow",
          "native_tools": ["test.echo"],
          "parameters": {
            "type": "object",
            "properties": {"request": {"type": "string", "max_length": 32}},
            "additional_properties": false,
            "required": ["request"]
          },
          "steps": [{"id": "step_1", "tool_id": "test.echo", "input": {"query": "{{parameters.request}}"}}],
          "auto_invoke": true,
          "trigger_examples": ["Find today's news"]
        }
        """#.utf8
      )
    )
    let decodedRun = try JSONDecoder().decode(
      AgentRecordedRun.self,
      from: Data(
        #"""
        {
          "run_id": "run",
          "conversation_id": "conversation",
          "task_thread_id": "thread",
          "original_request": "Find news",
          "tool_calls": [{"id": "call", "tool": "test.echo", "status": "SUCCEEDED", "arguments": {"value": "ok"}}],
          "active_skill_id": "wire_skill",
          "revision_number": 2,
          "status": "COMPLETED",
          "created_at": 1000,
          "completed_at": 2000
        }
        """#.utf8
      )
    )
    let encodedManifest = AgentSkillManifestCodec.encode(decodedManifest)
    let encodedRun = String(decoding: try JSONEncoder().encode(decodedRun), as: UTF8.self)

    XCTAssertEqual(decodedManifest.name, "Wire Skill")
    XCTAssertEqual(decodedManifest.summary, "Android field names")
    XCTAssertEqual(decodedManifest.parameters.properties["request"]?.maxLength, 32)
    XCTAssertEqual(decodedManifest.steps.singleValue().toolId, "test.echo")
    XCTAssertEqual(decodedRun.toolCalls.singleValue().status, .succeeded)
    XCTAssertEqual(decodedRun.revisionNumber, 2)
    XCTAssertEqual(decodedRun.createdAtMillis, 1_000)
    XCTAssertTrue(encodedManifest.contains(#""auto_invoke":true"#))
    XCTAssertTrue(encodedManifest.contains(#""additional_properties":false"#))
    XCTAssertTrue(encodedManifest.contains(#""max_length":32"#))
    XCTAssertTrue(encodedManifest.contains(#""tool_id":"test.echo""#))
    XCTAssertTrue(encodedRun.contains(#""tool_calls":["#))
    XCTAssertTrue(encodedRun.contains(#""arguments":{"value":"ok"}"#))
    XCTAssertTrue(encodedRun.contains(#""active_skill_id":"wire_skill""#))
  }

  private func completedRun(_ id: String, request: String, value: String) -> AgentRecordedRun {
    AgentRecordedRun(
      runId: id,
      conversationId: "conversation",
      taskThreadId: "thread",
      originalRequest: request,
      toolCalls: [
        AgentToolCallRecord(
          id: "call-\(id)",
          toolName: "test.echo",
          status: .succeeded,
          arguments: ["value": .string(value)]
        )
      ],
      status: .completed
    )
  }

  private func nativeDescriptor(_ id: String) -> AgentNativeToolDescriptor {
    AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: "Echo",
      description: "Echoes a bounded value.",
      location: .application,
      risk: .low,
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "test.echo", required: true)
      ]
    )
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
