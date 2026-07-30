import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentIOSWebMediaNativeToolCatalogAndExecutorMirrorsAndroidDefaultTools() throws {
    final class FakeWebMediaProvider: AgentIOSWebMediaToolProviding {
      var implementationId = "fake.ios.web_media"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSWebMediaOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSWebMediaOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        let sha = String(repeating: "a", count: 64)
        switch operation {
        case .webSearch:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "query": input["query"] ?? .string("SignalASI"),
              "results": .array([.object(["title": .string("SignalASI"), "url": .string("https://signalasi.example")])]),
              "result_count": .int(1)
            ]) { current, _ in current }
          )
        case .webOpen, .browserRender:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "text": .string("SignalASI page"),
              "html_sha256": .string(sha),
              "render_mode": .string(operation == .browserRender ? "isolated_static_dom" : "bounded_http")
            ]) { current, _ in current }
          )
        case .browserSessionCreate, .browserSessionNavigate:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "browser_id": .string("browser-session-0001"),
              "current_url": .string("https://signalasi.example"),
              "history_count": .int(operation == .browserSessionNavigate ? 2 : 1),
              "expires_at_epoch_ms": .int(5_000),
              "text": .string("session page"),
              "html_sha256": .string(sha)
            ]) { current, _ in current }
          )
        case .browserSessionClose:
          return AgentNativeToolExecutionResult.success(
            output: [
              "browser_id": input["browser_id"] ?? .string("browser-session-0001"),
              "closed": .bool(true),
              "expires_at_epoch_ms": .int(0)
            ]
          )
        case .httpRequest:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: input["method"]?.stringValue?.lowercased() == "head" ? "head" : "get")
              .merging(["text": .string("ok")]) { current, _ in current }
          )
        case .fileDownload, .webDownload:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "destination_content_uri": input["destination_content_uri"] ?? .string("content://downloads/item"),
              "size_bytes": .int(128),
              "sha256": .string(sha)
            ]) { current, _ in current },
            metadata: ["writer_implementation": .string("fake.content.writer")]
          )
        case .webHead:
          return AgentNativeToolExecutionResult.success(output: commonWeb(method: "head"))
        case .webFetch:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "text": .string("hello"),
              "charset": .string("UTF-8"),
              "size_bytes": .int(5),
              "sha256": .string(sha)
            ]) { current, _ in current }
          )
        case .ocrRecognizeContent:
          return AgentNativeToolExecutionResult.success(
            output: [
              "text": .string("invoice total"),
              "lines": .array([
                .object([
                  "text": .string("invoice total"),
                  "left": .int(0),
                  "top": .int(0),
                  "right": .int(200),
                  "bottom": .int(40),
                  "language_tag": .string("en"),
                  "block_index": .int(0),
                  "line_index": .int(0)
                ])
              ]),
              "blocks": .array([
                .object([
                  "text": .string("invoice total"),
                  "left": .int(0),
                  "top": .int(0),
                  "right": .int(200),
                  "bottom": .int(40),
                  "line_count": .int(1)
                ])
              ]),
              "content_uri": input["content_uri"] ?? .string("content://captures/1"),
              "source_kind": input["source_kind"] ?? .string("image"),
              "script_hint": input["script_hint"] ?? .string("auto"),
              "observed_at_epoch_ms": .int(1_000)
            ]
          )
        case .contentExtract:
          return AgentNativeToolExecutionResult.failure(code: "unexpected_provider_call", message: "content.extract should run locally")
        }
      }

      private func commonWeb(method: String) -> AgentMcpJSONObject {
        [
          "method": .string(method),
          "status_code": .int(200),
          "content_type": .string("text/html; charset=utf-8"),
          "content_length_bytes": .int(128),
          "requested_at_epoch_ms": .int(1_000),
          "retrieved_at_epoch_ms": .int(1_100),
          "response_headers": .object(["content-type": .string("text/html; charset=utf-8")]),
          "source": .object([
            "requested_url": .string("https://signalasi.example"),
            "final_url": .string("https://signalasi.example"),
            "redirect_chain": .array([]),
            "dns_resolution": .array([
              .object([
                "host": .string("signalasi.example"),
                "addresses": .array([.string("203.0.113.10")])
              ])
            ])
          ])
        ]
      }
    }

    let provider = FakeWebMediaProvider()
    let definitions = AgentIOSWebMediaNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    let networkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]
    )
    let sessionContext = AgentNativeToolInvocationContext(
      grantedPermissions: [
        AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
        AgentIOSWebMediaNativeToolCatalog.browserSessionPermission
      ],
      grantedConsents: [
        AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
        AgentIOSWebMediaNativeToolCatalog.browserSessionConsent
      ]
    )
    let downloadContext = AgentNativeToolInvocationContext(
      idempotencyKey: "download-1",
      grantedPermissions: [
        AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
        AgentIOSWebMediaNativeToolCatalog.contentUriPermission
      ],
      grantedConsents: [
        AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
        AgentIOSWebMediaNativeToolCatalog.webDownloadConsent,
        AgentIOSWebMediaNativeToolCatalog.contentUriWriteConsent
      ]
    )
    let ocrContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.contentUriReadConsent]
    )
    let extractContext = AgentNativeToolInvocationContext(
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.localContentExtractConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSWebMediaNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSWebMediaNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSWebMediaNativeToolCatalog.toolIds.isDisjoint(with: AgentIOSMediaNativeToolCatalog.toolIds))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebMediaNativeToolCatalog.webSearch))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebMediaNativeToolCatalog.webFetch))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebMediaNativeToolCatalog.ocrRecognizeContent))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSWebMediaNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertFalse(definition.descriptor.capabilities.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios_phone")
      XCTAssertEqual(definition.provenanceMetadata["result_policy"], "bounded-v1")
    }

    let webDownload = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebMediaNativeToolCatalog.webDownload })
    XCTAssertEqual(webDownload.descriptor.risk, .medium)
    XCTAssertEqual(webDownload.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertTrue(webDownload.descriptor.requiredConsents.contains { $0.id == AgentIOSWebMediaNativeToolCatalog.webDownloadConsent })
    XCTAssertEqual(webDownload.provenanceMetadata["destination_scope"], "user_authorized_content_uri")

    let extracted = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.contentExtract,
      input: ["content": .string("<p>Hello&nbsp;ASI</p><script>secret()</script>")],
      context: extractContext
    )
    let search = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("SignalASI"), "max_results": .int(1)],
      context: networkContext
    )
    let session = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.browserSessionCreate,
      input: ["url": .string("https://signalasi.example")],
      context: sessionContext
    )
    let invalidURL = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webFetch,
      input: ["url": .string("http://signalasi.example")],
      context: networkContext
    )
    let missingDownloadKey = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webDownload,
      input: [
        "url": .string("https://signalasi.example/file.txt"),
        "destination_content_uri": .string("content://downloads/file.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
          AgentIOSWebMediaNativeToolCatalog.contentUriPermission
        ],
        grantedConsents: [
          AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
          AgentIOSWebMediaNativeToolCatalog.webDownloadConsent,
          AgentIOSWebMediaNativeToolCatalog.contentUriWriteConsent
        ]
      )
    )
    let download = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.fileDownload,
      input: [
        "url": .string("https://signalasi.example/file.txt"),
        "destination_content_uri": .string("content://downloads/file.txt")
      ],
      context: downloadContext
    )
    let ocr = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.ocrRecognizeContent,
      input: [
        "content_uri": .string("file://selected/capture.png"),
        "source_kind": .string("image")
      ],
      context: ocrContext
    )
    let unavailableProvider = FakeWebMediaProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Web provider missing"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webFetch,
      input: ["url": .string("https://signalasi.example")],
      context: networkContext
    )

    XCTAssertTrue(extracted.isSuccess)
    XCTAssertEqual(extracted.output["text"], .string("Hello ASI"))
    XCTAssertEqual(extracted.metadata["script_execution"], .bool(false))
    XCTAssertFalse(provider.invokedOperations.contains(.contentExtract))
    XCTAssertTrue(search.isSuccess)
    XCTAssertEqual(search.output["operation"], .string("web.search"))
    XCTAssertEqual(search.metadata["network_policy"], .string("public_https_pinned_dns_v1"))
    XCTAssertTrue(session.isSuccess)
    XCTAssertEqual(session.output["browser_id"], .string("browser-session-0001"))
    XCTAssertEqual(invalidURL.status, .failed)
    XCTAssertEqual(invalidURL.error?.code, "invalid_url")
    XCTAssertEqual(missingDownloadKey.status, .rejected)
    XCTAssertEqual(missingDownloadKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(download.isSuccess)
    XCTAssertEqual(download.metadata["auto_execute"], .bool(false))
    XCTAssertTrue(ocr.isSuccess)
    XCTAssertEqual(ocr.output["script_hint"], .string("auto"))
    XCTAssertEqual(provider.invokedOperations, [.webSearch, .browserSessionCreate, .fileDownload, .ocrRecognizeContent])
    XCTAssertEqual(provider.capturedInputs.last?["script_hint"], .string("auto"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSMediaNativeToolCatalogAndExecutorBoundsMetadataPlaybackAndTranscode() throws {
    final class FakeMediaProvider: AgentIOSMediaNativeToolProviding {
      var implementationId = "fake.ios.media"
      var currentAvailability: AgentNativeToolAvailability = .available
      var metadataUri = ""
      var playbackUri = ""
      var playbackContentType = ""
      var transcodeRequest: AgentIOSMediaTranscodeRequest?
      var transcodeCalls = 0

      func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func inspectMetadata(
        contentUri: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        metadataUri = contentUri
        return AgentNativeToolExecutionResult.success(
          output: [
            "content_uri": .string(contentUri),
            "content_type": .string("video/mp4"),
            "display_name": .string("clip.mp4"),
            "size_bytes": .int(4_096),
            "duration_ms": .int(4_000),
            "width": .int(1_920),
            "height": .int(1_080),
            "rotation_degrees": .int(0),
            "has_audio": .bool(true),
            "has_video": .bool(true),
            "observed_at_epoch_ms": .int(1_000),
            "source": .object(["content_uri": .string(contentUri)])
          ]
        )
      }

      func handoffPlayback(
        contentUri: String,
        contentType: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        playbackUri = contentUri
        playbackContentType = contentType
        return AgentNativeToolExecutionResult.success(
          output: [
            "launched": .bool(true),
            "action": .string("ios.media.open"),
            "handler_package": .string("com.apple.avplayer"),
            "completed": .bool(false),
            "handed_off_at_epoch_ms": .int(1_000),
            "source": .object(["content_uri": .string(contentUri)])
          ]
        )
      }

      func transcode(
        request: AgentIOSMediaTranscodeRequest,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        transcodeCalls += 1
        transcodeRequest = request
        let sha = String(repeating: "a", count: 64)
        return AgentNativeToolExecutionResult.success(
          output: [
            "source_path": .string(request.sourcePath.isEmpty ? "selected/input.mov" : request.sourcePath),
            "destination_path": .string(request.destinationPath.isEmpty ? "outputs/clip.mp4" : request.destinationPath),
            "target_format": .string(request.targetFormat),
            "mime_type": .string("video/mp4"),
            "size_bytes": .int(8_192),
            "sha256": .string(sha),
            "execution_duration_ms": .int(250),
            "artifacts": .array([
              .object([
                "relative_path": .string("outputs/clip.mp4"),
                "size_bytes": .int(8_192),
                "sha256": .string(sha),
                "artifact_kind": .string("media")
              ])
            ]),
            "execution_receipt": .object(["runtime": .string("ffmpeg")]),
            "network_enabled": .bool(false),
            "completed_at_epoch_ms": .int(1_000)
          ]
        )
      }
    }

    let provider = FakeMediaProvider()
    let definitions = AgentIOSMediaNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: provider, nowMillis: { 2_000 })
    )
    let contentContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [AgentIOSMediaNativeToolCatalog.contentUriReadConsent]
    )
    let playbackContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [
        AgentIOSMediaNativeToolCatalog.contentUriReadConsent,
        AgentIOSMediaNativeToolCatalog.mediaPlaybackConsent
      ]
    )
    let transcodeContext = AgentNativeToolInvocationContext(
      invocationId: "media-transcode-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
      grantedPermissions: [
        AgentIOSMediaNativeToolCatalog.workspaceMediaPermission,
        AgentIOSMediaNativeToolCatalog.mediaRuntimePermission
      ],
      grantedConsents: [
        AgentIOSMediaNativeToolCatalog.contentUriReadConsent,
        AgentIOSMediaNativeToolCatalog.contentUriWriteConsent,
        AgentIOSMediaNativeToolCatalog.mediaTranscodeConsent
      ],
      attributes: ["workspace_id": "workspace-1"]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSMediaNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSMediaNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSMediaNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios_phone")
    }

    let metadata = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaMetadata,
      input: ["content_uri": .string("content://media/item-7")],
      context: contentContext
    )
    let deniedPlayback = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaPlaybackHandoff,
      input: ["content_uri": .string("content://media/item-7")],
      context: contentContext
    )
    let playback = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaPlaybackHandoff,
      input: [
        "content_uri": .string("content://media/item-7"),
        "content_type": .string("video/mp4")
      ],
      context: playbackContext
    )
    let transcode = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("inputs/turn/clip.mov"),
        "destination_path": .string("outputs/clip.mp4"),
        "target_format": .string("mp4"),
        "preset": .string("compact"),
        "timeout_ms": .int(30_000)
      ],
      context: transcodeContext
    )
    let duplicateSource = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "content_uri": .string("content://media/item-7"),
        "source_path": .string("inputs/turn/clip.mov"),
        "target_format": .string("mp4")
      ],
      context: transcodeContext
    )
    let unavailableProvider = FakeMediaProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install signed FFmpeg runtime"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("inputs/turn/clip.mov"),
        "target_format": .string("mp4")
      ],
      context: transcodeContext
    )

    XCTAssertTrue(metadata.isSuccess)
    XCTAssertEqual(metadata.output["duration_ms"], .int(4_000))
    XCTAssertEqual(metadata.output["has_video"], .bool(true))
    XCTAssertEqual(provider.metadataUri, "content://media/item-7")
    XCTAssertEqual(deniedPlayback.status, .rejected)
    XCTAssertEqual(deniedPlayback.error?.code, "missing_consents")
    XCTAssertTrue(playback.isSuccess)
    XCTAssertEqual(playback.output["launched"], .bool(true))
    XCTAssertEqual(playback.output["completed"], .bool(false))
    XCTAssertEqual(provider.playbackUri, "content://media/item-7")
    XCTAssertEqual(provider.playbackContentType, "video/mp4")
    XCTAssertTrue(transcode.isSuccess)
    XCTAssertEqual(provider.transcodeRequest?.workspaceId, "workspace-1")
    XCTAssertEqual(provider.transcodeRequest?.sourcePath, "inputs/turn/clip.mov")
    XCTAssertEqual(provider.transcodeRequest?.targetFormat, "mp4")
    XCTAssertEqual(provider.transcodeRequest?.preset, "compact")
    XCTAssertEqual(transcode.output["mime_type"], .string("video/mp4"))
    XCTAssertEqual(transcode.output["network_enabled"], .bool(false))
    XCTAssertEqual(duplicateSource.status, .failed)
    XCTAssertEqual(duplicateSource.error?.code, "invalid_transcode_source")
    XCTAssertEqual(provider.transcodeCalls, 1)
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertEqual(unavailableProvider.transcodeCalls, 0)
  }

  func testAgentIOSSelfEvolutionNativeToolCatalogAndExecutorMirrorsAndroidWireProtocol() throws {
    final class FakeSelfEvolutionProvider: AgentIOSSelfEvolutionToolProviding {
      var implementationId = "fake.ios.self_evolution"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSSelfEvolutionOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSSelfEvolutionOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .status:
          return AgentNativeToolExecutionResult.success(
            output: [
              "execution_target": .string("ios"),
              "runtime_ready": .bool(true),
              "runtime_reason": .string("ready"),
              "task_count": .int(1),
              "active_tasks": .int(0),
              "health": .object(["total_tasks": .int(1), "active_tasks": .int(0)])
            ],
            message: "iOS-local self-evolution inspected"
          )
        case .tasksList:
          return AgentNativeToolExecutionResult.success(
            output: [
              "tasks": .array([.object(taskValue(status: "proposed"))]),
              "health": .object(["total_tasks": .int(1)])
            ],
            message: "iOS-local evolution tasks listed"
          )
        case .tasksCreate:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "proposed")),
              "candidate_workspace_id": .string(""),
              "candidate_source_root": .string("")
            ],
            message: "Evolution task created"
          )
        case .candidatePrepare:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "running")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("source")
            ],
            message: "Evolution candidate prepared"
          )
        case .candidatePatch:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "waiting_approval")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("source"),
              "unified_diff": .string("diff --git a/secret b/secret")
            ],
            message: "Evolution candidate validated",
            metadata: ["unified_diff": .string("diff --git a/secret b/secret")]
          )
        case .candidateRollback:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "rolled_back")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("")
            ],
            message: "Evolution candidate rolled back"
          )
        }
      }

      private func taskValue(status: String) -> AgentMcpJSONObject {
        [
          "protocol": .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId),
          "task_id": .string("evolve-ios-1"),
          "problem": .string("Mirror Android self-evolution tools on iOS"),
          "reproduction_steps": .array([.string("Open iOS agent tool catalog")]),
          "scope": .array([.string("apps/ios")]),
          "acceptance": .array([.string("Android wire-compatible tool ids are registered")]),
          "risk_level": .string("medium"),
          "max_attempts": .int(3),
          "status": .string(status),
          "execution_target": .string("ios"),
          "base_commit": .string("base"),
          "candidate_commit": .string(status == "waiting_approval" ? "candidate" : ""),
          "candidate_branch": .string(status == "waiting_approval" ? "evolution/evolve-ios-1-a1" : ""),
          "approval_hash": .string(status == "waiting_approval" ? "approval" : ""),
          "attempts": .array([]),
          "last_error_code": .string(""),
          "last_error": .string(""),
          "created_at_millis": .int(1_000),
          "updated_at_millis": .int(2_000)
        ]
      }
    }

    let provider = FakeSelfEvolutionProvider()
    let definitions = AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.selfEvolutionExecutableDefinitions(provider: provider, nowMillis: { 44_000 })
    )
    let readContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSelfEvolutionNativeToolCatalog.storePermission]
    )
    let candidateContext = AgentNativeToolInvocationContext(
      invocationId: "evolution-patch-1",
      idempotencyKey: "patch-key-1",
      grantedPermissions: [
        AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
        AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
        AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
      ],
      grantedConsents: [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent]
    )

    XCTAssertEqual(Set(AgentIOSSelfEvolutionNativeToolCatalog.orderedToolIds), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSSelfEvolutionNativeToolCatalog.toolIds.contains("signalasi.evolution.candidate.patch"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSSelfEvolutionNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("evolution.self"))
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentSelfEvolutionNativeTools")
      XCTAssertEqual(definition.provenanceMetadata["production_mutation"], "disabled")
    }
    let prepareDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare })
    let patchDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch })
    let createDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.tasksCreate })
    XCTAssertEqual(createDescriptor.descriptor.risk, .low)
    XCTAssertEqual(createDescriptor.descriptor.requiredConsents.first?.required, false)
    XCTAssertEqual(prepareDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent])
    XCTAssertEqual(patchDescriptor.descriptor.risk, .high)
    XCTAssertEqual(patchDescriptor.descriptor.timeoutMillis, 30 * 60_000)
    XCTAssertEqual(patchDescriptor.descriptor.idempotency, .idempotencyKeyRequired)

    let status = registry.invoke(AgentIOSSelfEvolutionNativeToolCatalog.status, input: [:], context: readContext)
    let list = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.tasksList,
      input: ["limit": .int(2)],
      context: readContext
    )
    let create = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.tasksCreate,
      input: [
        "problem": .string("Mirror Android self-evolution tools on iOS"),
        "scope": .array([.string("apps/ios")]),
        "acceptance": .array([.string("Tool ids match Android")])
      ],
      context: readContext
    )
    let deniedPrepare = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare,
      input: ["task_id": .string("evolve-ios-1")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
        ]
      )
    )
    let missingPatchKey = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/a b/a")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
        ],
        grantedConsents: [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent]
      )
    )
    let prepare = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare,
      input: ["task_id": .string("evolve-ios-1")],
      context: candidateContext
    )
    let patch = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/apps/ios/a b/apps/ios/a")
      ],
      context: candidateContext
    )
    let rollback = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidateRollback,
      input: ["task_id": .string("evolve-ios-1")],
      context: candidateContext
    )
    let unavailableProvider = FakeSelfEvolutionProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install signed self-evolution runtime"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.selfEvolutionExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/a b/a")
      ],
      context: candidateContext
    )

    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["protocol"], .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId))
    XCTAssertEqual(status.output["runtime_ready"], .bool(true))
    XCTAssertTrue(list.isSuccess)
    XCTAssertEqual(provider.capturedInputs[1]["limit"], .int(2))
    XCTAssertTrue(create.isSuccess)
    XCTAssertEqual(create.output["status"], .string("proposed"))
    XCTAssertEqual(deniedPrepare.status, .rejected)
    XCTAssertEqual(deniedPrepare.error?.code, "missing_consents")
    XCTAssertEqual(missingPatchKey.status, .rejected)
    XCTAssertEqual(missingPatchKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(prepare.isSuccess)
    XCTAssertEqual(prepare.output["candidate_source_root"], .string("source"))
    XCTAssertTrue(patch.isSuccess)
    XCTAssertEqual(patch.output["status"], .string("waiting_approval"))
    XCTAssertNil(patch.output["unified_diff"])
    XCTAssertNil(patch.metadata["unified_diff"])
    XCTAssertEqual(patch.metadata["patch_content_retained"], .bool(false))
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["status"], .string("rolled_back"))
    XCTAssertEqual(provider.invokedOperations, [.status, .tasksList, .tasksCreate, .candidatePrepare, .candidatePatch, .candidateRollback])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentDesktopControlAuthorizationParsesAndroidRecords() throws {
    let authorization = try XCTUnwrap(AgentDesktopControlAuthorization.parse([
      "authorization_id": .string("dca_test"),
      "app_instance_id": .string("phone_route_01"),
      "app_name": .string("SignalASI"),
      "app_platform": .string("ios"),
      "phone_name": .string("iPhone"),
      "app_identity_fingerprint": .string("AA:BB:CC"),
      "grant_source": .string("pairing_qr"),
      "access_profile": .string("full_desktop_executor"),
      "access_scopes": .array([.string("desktop.execute"), .string("desktop.observe")]),
      "granted_at": .int(1_000),
      "last_used_at": .int(2_000),
      "status": .string("active"),
      "allowed_tools": .array([
        .string(AgentDesktopControlAction.screenshot),
        .string(AgentDesktopControlAction.clickXY)
      ]),
      "desktop_session_id": .string("session_01"),
      "desktop_session_expires_at": .int(3_000)
    ]))
    let revoked = try XCTUnwrap(AgentDesktopControlAuthorization.parse([
      "authorization_id": .string("dca_revoked"),
      "app_instance_id": .string("phone_route_02"),
      "app_name": .string("SignalASI"),
      "app_platform": .string("ios"),
      "status": .string("revoked"),
      "revoked_at": .int(4_000),
      "revoke_reason": .string("revoked_by_phone")
    ]))

    XCTAssertEqual(authorization.authorizationId, "dca_test")
    XCTAssertEqual(authorization.appInstanceId, "phone_route_01")
    XCTAssertEqual(authorization.appName, "SignalASI")
    XCTAssertEqual(authorization.appPlatform, "ios")
    XCTAssertEqual(authorization.phoneFingerprint, "AA:BB:CC")
    XCTAssertEqual(authorization.accessProfile, "full_desktop_executor")
    XCTAssertEqual(authorization.accessScopes, ["desktop.execute", "desktop.observe"])
    XCTAssertEqual(authorization.allowedTools, [AgentDesktopControlAction.screenshot, AgentDesktopControlAction.clickXY])
    XCTAssertEqual(authorization.desktopSessionId, "session_01")
    XCTAssertEqual(revoked.status, "revoked")
    XCTAssertEqual(revoked.revokedAt, 4_000)
    XCTAssertEqual(revoked.desktopSessionId, "")
    XCTAssertNil(AgentDesktopControlAuthorization.parse(["status": .string("active")]))
    XCTAssertNotNil(AgentDesktopControlAuthorization.parse(["status": .string("pending")]))
  }

  func testAgentDesktopSurfaceCatalogParsesDisplaysWindowsAndIndependentSelection() throws {
    let catalog = try XCTUnwrap(AgentDesktopSurfaceCatalog.parse([
      "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
      "displays": .array([
        .object([
          "display_id": .string("display:primary"),
          "name": .string("Display 1"),
          "primary": .bool(true),
          "bounds": .object([
            "left": .int(0),
            "top": .int(0),
            "width": .int(1_920),
            "height": .int(1_080)
          ])
        ]),
        .object([
          "display_id": .string("display:left"),
          "name": .string("Display 2"),
          "bounds": .object([
            "left": .int(-1_280),
            "top": .int(40),
            "width": .int(1_280),
            "height": .int(1_024)
          ])
        ])
      ]),
      "windows": .array([
        .object([
          "window_id": .string("window:browser"),
          "title": .string("Browser"),
          "display_id": .string("display:left"),
          "foreground": .bool(true),
          "minimized": .bool(false),
          "bounds": .object([
            "left": .int(-1_200),
            "top": .int(100),
            "width": .int(1_000),
            "height": .int(760)
          ])
        ]),
        .object([
          "window_id": .string("window:orphan"),
          "title": .string("Orphan"),
          "display_id": .string("display:missing")
        ])
      ]),
      "selection": .object([
        "selected_display_id": .string("display:left"),
        "selected_window_id": .string("window:browser"),
        "target_kind": .string("window")
      ]),
      "target": .object([
        "title": .string("Browser"),
        "bounds": .object([
          "left": .int(-1_200),
          "top": .int(100),
          "width": .int(1_000),
          "height": .int(760)
        ])
      ])
    ]))
    let nested = try XCTUnwrap(AgentDesktopSurfaceCatalog.parseOutput([
      "surface_catalog": .object([
        "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
        "displays": .array([
          .object([
            "display_id": .string("display:primary"),
            "name": .string("Display 1"),
            "bounds": .object(["width": .int(1), "height": .int(1)])
          ])
        ])
      ])
    ]))

    func request(toolId: String, input: AgentMcpJSONObject) -> AgentMcpJSONObject {
      [
        "type": .string("desktop_executor_request"),
        "task_id": .string("desktop-control-action"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string("session-1"),
        "tool_id": .string(toolId),
        "input": .object(input),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ]
    }
    let displaySelect = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.surfaceSelect, input: ["display_id": .string("display:left")]),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "signalasi:phone"
    )
    let windowSelect = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.surfaceSelect, input: ["window_id": .string("window:browser")]),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "signalasi:phone"
    )
    let windowActivate = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.windowActivate, input: ["window_id": .string("window:browser")]),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "signalasi:phone"
    )

    XCTAssertEqual(catalog.displays.count, 2)
    XCTAssertEqual(catalog.windows.count, 1)
    XCTAssertEqual(catalog.selection.displayId, "display:left")
    XCTAssertEqual(catalog.selection.windowId, "window:browser")
    XCTAssertEqual(catalog.selection.targetKind, "window")
    XCTAssertEqual(catalog.targetTitle, "Browser")
    XCTAssertEqual(catalog.targetBounds.left, -1_200)
    XCTAssertTrue(catalog.displays.first?.primary == true)
    XCTAssertTrue(catalog.windows.first?.foreground == true)
    XCTAssertEqual(nested.displays.count, 1)
    XCTAssertNil(AgentDesktopSurfaceCatalog.parse([:]))
    XCTAssertNil(AgentDesktopSurfaceCatalog.parse([
      "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
      "displays": .array([])
    ]))
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.surfaceList))
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.surfaceSelect))
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.windowActivate))
    XCTAssertNotEqual(displaySelect.inputSha256, windowSelect.inputSha256)
    XCTAssertNotEqual(windowSelect.requestSha256, windowActivate.requestSha256)
  }

  func testAgentDesktopRemoteControlSnapshotCombinesAndroidState() throws {
    let screenshotBytes = Data([0xff, 0xd8, 0xff, 0xd9])
    let snapshot = try XCTUnwrap(AgentDesktopRemoteControlSnapshot.parse([
      "desktop_id": .string("desktop-1"),
      "desktop_name": .string("Workstation"),
      "desktop_fingerprint": .string("desktop-fingerprint"),
      "server_route_id": .string("server-route-1"),
      "full_desktop_executor": .bool(true),
      "enabled": .bool(true),
      "require_unlocked": .bool(true),
      "authorizations": .array([
        .object([
          "status": .string("pending")
        ]),
        .object([
          "authorization_id": .string("auth-active"),
          "status": .string("active"),
          "desktop_session_id": .string("session-1"),
          "desktop_session_expires_at": .int(1_800_000_030_000)
        ])
      ]),
      "recent_audit": .array([
        .object([
          "event_type": .string("desktop_control_action"),
          "tool_id": .string(AgentDesktopControlAction.screenshot),
          "status": .string("succeeded"),
          "summary": .string("Captured screen"),
          "created_at": .int(1_800_000_000_100)
        ])
      ]),
      "recent_receipts": .array([
        .object([
          "receipt_id": .string("receipt-1"),
          "tool_id": .string(AgentDesktopControlAction.screenshot),
          "status": .string("succeeded"),
          "summary": .string("Captured screen")
        ])
      ]),
      "active_runs": .array([
        .object([
          "task_id": .string("task-1"),
          "conversation_id": .string("conversation-1"),
          "turn_id": .string("turn-1"),
          "agent_id": .string("agent-1"),
          "status": .string("running"),
          "prompt": .string("Review desktop"),
          "current_step": .string("observing"),
          "updated_at": .int(1_800_000_000_200),
          "execution_view": .object([
            "pausable": .bool(true),
            "takeover_available": .bool(true)
          ])
        ])
      ]),
      "last_action_status": .string("succeeded"),
      "last_action_summary": .string("Captured screen"),
      "last_action_at": .int(1_800_000_000_300),
      "screenshot": .object([
        "image_mime": .string("image/jpeg"),
        "image_base64": .string(screenshotBytes.base64EncodedString()),
        "bytes": .int(Int64(screenshotBytes.count)),
        "width": .int(640),
        "height": .int(360),
        "original_width": .int(1_920),
        "original_height": .int(1_080)
      ]),
      "perception": .object([
        "contract_version": .string(AgentDesktopPerceptionSnapshot.contractVersion),
        "capture_id": .string("capture-1"),
        "captured_at": .int(1_800_000_000_400),
        "untrusted_evidence": .bool(true),
        "available_layers": .array([.string("screenshot"), .string("ui_tree")]),
        "ui_tree": .object([
          "status": .string("ok"),
          "element_count": .int(0),
          "elements": .array([])
        ])
      ]),
      "surface_catalog": .object([
        "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
        "displays": .array([
          .object([
            "display_id": .string("display:primary"),
            "name": .string("Display 1"),
            "primary": .bool(true),
            "bounds": .object(["width": .int(1_920), "height": .int(1_080)])
          ])
        ]),
        "selection": .object([
          "selected_display_id": .string("display:primary"),
          "target_kind": .string("display")
        ]),
        "target": .object([
          "title": .string("Display 1"),
          "bounds": .object(["width": .int(1_920), "height": .int(1_080)])
        ])
      ]),
      "stream_fps": .int(3),
      "stream_active": .bool(true)
    ]))
    let pending = try XCTUnwrap(AgentDesktopRemoteControlSnapshot.parse([
      "full_desktop_executor": .bool(true),
      "current_authorization": .object([
        "status": .string("pending")
      ]),
      "stream_fps": .int(4)
    ]))

    XCTAssertEqual(snapshot.desktopId, "desktop-1")
    XCTAssertEqual(snapshot.desktopName, "Workstation")
    XCTAssertEqual(snapshot.currentAuthorization?.authorizationId, "auth-active")
    XCTAssertEqual(snapshot.authorizations.count, 2)
    XCTAssertTrue(snapshot.authorized)
    XCTAssertFalse(snapshot.pending)
    XCTAssertTrue(snapshot.requireUnlocked)
    XCTAssertEqual(snapshot.recentAudit.first?.summary, "Captured screen")
    XCTAssertEqual(snapshot.recentReceipts.first?.receiptId, "receipt-1")
    XCTAssertEqual(snapshot.activeRuns.first?.taskId, "task-1")
    XCTAssertEqual(snapshot.screenshot?.capturedAt, 1_800_000_000_300)
    XCTAssertEqual(snapshot.perception?.captureId, "capture-1")
    XCTAssertEqual(snapshot.surfaceCatalog?.selection.displayId, "display:primary")
    XCTAssertEqual(snapshot.streamFps, 3)
    XCTAssertTrue(snapshot.streamActive)
    XCTAssertEqual(pending.desktopName, "SignalASI Desktop")
    XCTAssertTrue(pending.pending)
    XCTAssertFalse(pending.authorized)
    XCTAssertEqual(pending.streamFps, 0)
    XCTAssertNil(AgentDesktopRemoteControlSnapshot.parse(nil))
  }

  func testAgentDesktopControlRequestFactoryBuildsAndroidExecutorPayloads() throws {
    let now: Int64 = 1_800_000_000_000
    let routing = AgentDesktopControlRequestRoutingContext(
      clientRouteId: "client-route-1",
      controllerFingerprint: "Controller-Fingerprint",
      controllerSignalName: "signalasi:phone"
    )
    func snapshot(status: String = "active", expiresAt: Int64 = now + 60_000) throws -> AgentDesktopRemoteControlSnapshot {
      try XCTUnwrap(AgentDesktopRemoteControlSnapshot.parse([
        "desktop_id": .string("desktop-1"),
        "current_authorization": .object([
          "authorization_id": .string("auth-1"),
          "status": .string(status),
          "desktop_session_id": .string("session-1"),
          "desktop_session_expires_at": .int(expiresAt)
        ])
      ]))
    }

    let active = try snapshot()
    let screenshot = try XCTUnwrap(AgentDesktopControlRequestFactory.screenshot(
      snapshot: active,
      routing: routing,
      actionId: "action-screenshot",
      nowMillis: now
    ))
    let perception = try XCTUnwrap(AgentDesktopControlRequestFactory.perception(
      snapshot: active,
      routing: routing,
      actionId: "action-perceive",
      nowMillis: now
    ))
    let stream = try XCTUnwrap(AgentDesktopControlRequestFactory.screenshotStreamFrame(
      snapshot: active,
      routing: routing,
      fps: 2,
      actionId: "action-stream",
      nowMillis: now
    ))
    let displaySelect = try XCTUnwrap(AgentDesktopControlRequestFactory.selectDisplay(
      snapshot: active,
      routing: routing,
      displayId: "display:primary",
      actionId: "action-display",
      nowMillis: now
    ))
    let windowActivate = try XCTUnwrap(AgentDesktopControlRequestFactory.activateWindow(
      snapshot: active,
      routing: routing,
      windowId: "window:browser",
      actionId: "action-window",
      nowMillis: now
    ))
    let click = try XCTUnwrap(AgentDesktopControlRequestFactory.click(
      snapshot: active,
      routing: routing,
      x: 12,
      y: 34,
      coordinateWidth: 640,
      coordinateHeight: 360,
      actionId: "action-click",
      nowMillis: now
    ))
    let takeover = try XCTUnwrap(AgentDesktopControlRequestFactory.takeOverTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      leaseSeconds: 9_000,
      actionId: "action-takeover",
      nowMillis: now
    ))

    XCTAssertEqual(AgentDesktopControlRequestFactory.actionTTLMillis, 30_000)
    XCTAssertEqual(screenshot.payload["type"], .string("desktop_executor_request"))
    XCTAssertEqual(screenshot.payload["task_id"], .string("desktop-control-action-screenshot"))
    XCTAssertEqual(screenshot.payload["action_id"], .string("action-screenshot"))
    XCTAssertEqual(screenshot.payload["authorization_id"], .string("auth-1"))
    XCTAssertEqual(screenshot.payload["desktop_session_id"], .string("session-1"))
    XCTAssertEqual(screenshot.payload["tool_id"], .string(AgentDesktopControlAction.screenshot))
    XCTAssertEqual(screenshot.payload["input"], .object([:]))
    XCTAssertEqual(screenshot.payload["sent_at"], .int(now))
    XCTAssertEqual(screenshot.payload["expires_at"], .int(now + 30_000))
    XCTAssertEqual(screenshot.pendingRequest.desktopId, "desktop-1")
    XCTAssertEqual(screenshot.pendingRequest.toolId, AgentDesktopControlAction.screenshot)
    XCTAssertEqual(screenshot.pendingRequest.expiresAt, now + 30_000)
    XCTAssertTrue(screenshot.durable)
    XCTAssertTrue(screenshot.updatesRuntimeStatus)

    XCTAssertFalse(perception.durable)
    XCTAssertEqual(perception.input["include_screenshot"], .bool(true))
    XCTAssertEqual(perception.input["include_ocr"], .bool(true))
    XCTAssertEqual(perception.input["include_ui_tree"], .bool(true))
    XCTAssertEqual(perception.input["max_elements"], .int(80))
    XCTAssertEqual(perception.input["max_depth"], .int(8))
    XCTAssertEqual(perception.input["max_ocr_chars"], .int(12_000))
    XCTAssertFalse(stream.durable)
    XCTAssertFalse(stream.updatesRuntimeStatus)
    XCTAssertTrue(stream.pendingRequest.streamFrame)
    XCTAssertEqual(stream.input["stream_fps"], .int(2))
    XCTAssertFalse(displaySelect.durable)
    XCTAssertTrue(displaySelect.resetsSurfaceState)
    XCTAssertEqual(displaySelect.input["display_id"], .string("display:primary"))
    XCTAssertTrue(windowActivate.durable)
    XCTAssertTrue(windowActivate.resetsSurfaceState)
    XCTAssertEqual(windowActivate.input["window_id"], .string("window:browser"))
    XCTAssertEqual(click.input["button"], .string("left"))
    XCTAssertEqual(click.input["coordinate_width"], .int(640))
    XCTAssertEqual(click.input["coordinate_height"], .int(360))
    XCTAssertEqual(takeover.input["task_id"], .string("task-1"))
    XCTAssertEqual(takeover.input["lease_seconds"], .int(3_600))
    XCTAssertNotEqual(screenshot.pendingRequest.requestSha256, perception.pendingRequest.requestSha256)

    XCTAssertEqual(AgentDesktopControlRequestFactory.hotkey(
      snapshot: active,
      routing: routing,
      keys: ["ctrl", "tab"],
      actionId: "action-hotkey",
      nowMillis: now
    )?.input["keys"], .array([.string("ctrl"), .string("tab")]))
    XCTAssertEqual(AgentDesktopControlRequestFactory.windowSwitch(
      snapshot: active,
      routing: routing,
      previous: true,
      actionId: "action-window-switch",
      nowMillis: now
    )?.input["direction"], .string("previous"))
    XCTAssertEqual(AgentDesktopControlRequestFactory.selectFile(
      snapshot: active,
      routing: routing,
      path: "C:\\Users\\agent\\Desktop\\report.txt",
      actionId: "action-file",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.fileSelect)
    XCTAssertEqual(AgentDesktopControlRequestFactory.pauseTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      actionId: "action-pause",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.taskPause)
    XCTAssertEqual(AgentDesktopControlRequestFactory.continueTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      actionId: "action-continue",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.taskContinue)
    XCTAssertEqual(AgentDesktopControlRequestFactory.releaseTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      actionId: "action-release",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.taskRelease)
    XCTAssertNil(AgentDesktopControlRequestFactory.screenshotStreamFrame(
      snapshot: active,
      routing: routing,
      fps: 4,
      actionId: "action-bad-stream",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.typeText(
      snapshot: active,
      routing: routing,
      text: " ",
      actionId: "action-empty-type",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.typeText(
      snapshot: active,
      routing: routing,
      text: String(repeating: "x", count: 4_097),
      actionId: "action-long-type",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.hotkey(
      snapshot: active,
      routing: routing,
      keys: ["a", "b", "c", "d", "e"],
      actionId: "action-many-keys",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.scroll(
      snapshot: active,
      routing: routing,
      delta: 2_401,
      actionId: "action-scroll",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.selectDisplay(
      snapshot: active,
      routing: routing,
      displayId: "",
      actionId: "action-empty-display",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.screenshot(
      snapshot: try snapshot(status: "pending"),
      routing: routing,
      actionId: "action-pending",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.screenshot(
      snapshot: try snapshot(expiresAt: now),
      routing: routing,
      actionId: "action-expired",
      nowMillis: now
    ))
  }

  func testAgentDesktopControlReceiptProtocolVerifiesSignedScreenshotEvidence() throws {
    let signerId = "desktop_test"
    let desktopSessionId = "sth_desktops_00000000000000000000000000000000"
    let signatureKeyId = AgentDesktopControlReceiptProtocol.digest(Data("desktop-key".utf8))
    let controllerFingerprint = AgentDesktopControlReceiptProtocol.digest(Data("phone-key".utf8))
    let secret = Data("receipt-secret".utf8)

    func request(input: AgentMcpJSONObject = [:]) -> AgentMcpJSONObject {
      [
        "type": .string("desktop_executor_request"),
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "tool_id": .string(AgentDesktopControlAction.screenshot),
        "input": .object(input),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ]
    }

    func signedDigest(_ payload: Data) -> String {
      var data = secret
      data.append(payload)
      return AgentDesktopControlReceiptProtocol.digest(data)
    }

    func makeReceipt(
      for request: AgentMcpJSONObject,
      pending: AgentDesktopControlPendingRequest,
      screenshotBytes: Data = Data([0xff, 0xd8, 0xff, 0xd9]),
      declaredBytes: Int? = nil
    ) -> AgentMcpJSONObject {
      let evidenceSha256 = AgentDesktopControlReceiptProtocol.digest(screenshotBytes)
      let summary = "Executed desktop screenshot"
      let screenshot: AgentMcpJSONObject = [
        "image_mime": .string("image/jpeg"),
        "image_base64": .string(screenshotBytes.base64EncodedString()),
        "bytes": .int(Int64(declaredBytes ?? screenshotBytes.count)),
        "width": .int(480),
        "height": .int(270),
        "original_width": .int(1_920),
        "original_height": .int(1_080),
        "captured_at": .int(1_800_000_001_000)
      ]
      var screenshotMetadata = screenshot
      screenshotMetadata.removeValue(forKey: "image_base64")
      screenshotMetadata["image_sha256"] = .string(evidenceSha256)
      let outputSha256 = AgentDesktopControlReceiptProtocol.digest([
        "status": .string("succeeded"),
        "summary": .string(summary),
        "error": .null,
        "output": .object(["screenshot": .object(screenshotMetadata)]),
        "post_screenshot": .null
      ])
      let completedAt: Int64 = 1_800_000_001_000
      let receiptId = AgentDesktopControlReceiptProtocol.digest([
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "request_sha256": .string(pending.requestSha256),
        "output_sha256": .string(outputSha256),
        "evidence_sha256": .string(evidenceSha256),
        "completed_at": .int(completedAt)
      ])
      var receipt: AgentMcpJSONObject = [
        "type": .string("desktop_action_receipt"),
        "receipt_version": .int(Int64(AgentDesktopControlReceiptProtocol.receiptVersion)),
        "receipt_id": .string(receiptId),
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "tool_id": .string(request["tool_id"]?.stringValue ?? ""),
        "status": .string("succeeded"),
        "summary": .string(summary),
        "error_code": .string(""),
        "error_retryable": .bool(false),
        "request_sha256": .string(pending.requestSha256),
        "input_sha256": .string(pending.inputSha256),
        "output_sha256": .string(outputSha256),
        "evidence_sha256": .string(evidenceSha256),
        "controller_app_instance_id": .string("signalasi:phone"),
        "controller_name": .string("Test iPhone"),
        "controller_platform": .string("ios"),
        "controller_fingerprint": .string(controllerFingerprint),
        "started_at": .int(1_800_000_000_500),
        "completed_at": .int(completedAt),
        "duration_ms": .int(500),
        "signer_id": .string(signerId),
        "signature_key_id": .string(signatureKeyId),
        "output": .object(["screenshot": .object(screenshot)]),
        "post_screenshot": .null
      ]
      let signedFields: AgentMcpJSONObject = [
        "receipt_version": .int(Int64(AgentDesktopControlReceiptProtocol.receiptVersion)),
        "receipt_id": .string(receiptId),
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "tool_id": .string(request["tool_id"]?.stringValue ?? ""),
        "status": .string("succeeded"),
        "summary": .string(summary),
        "error_code": .string(""),
        "error_retryable": .bool(false),
        "request_sha256": .string(pending.requestSha256),
        "input_sha256": .string(pending.inputSha256),
        "output_sha256": .string(outputSha256),
        "evidence_sha256": .string(evidenceSha256),
        "controller_app_instance_id": .string("signalasi:phone"),
        "controller_name": .string("Test iPhone"),
        "controller_platform": .string("ios"),
        "controller_fingerprint": .string(controllerFingerprint),
        "started_at": .int(1_800_000_000_500),
        "completed_at": .int(completedAt),
        "duration_ms": .int(500),
        "signer_id": .string(signerId),
        "signature_key_id": .string(signatureKeyId)
      ]
      receipt["signature"] = .string(signedDigest(Data(AgentMcpJSONCodec.stringify(signedFields).utf8)))
      return receipt
    }

    let baseRequest = request()
    let pending = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: baseRequest,
      clientRouteId: "client-route-1",
      controllerFingerprint: controllerFingerprint.uppercased(),
      controllerSignalName: "signalasi:phone"
    )
    let receipt = makeReceipt(for: baseRequest, pending: pending)
    let context = AgentDesktopControlReceiptVerificationContext(
      expectedSignerId: signerId,
      expectedSignatureKeyId: signatureKeyId,
      expectedControllerFingerprint: controllerFingerprint,
      pendingRequest: pending
    )
    let verifier: AgentDesktopControlReceiptSignatureVerifier = { _, _, payload, signature in
      signature == signedDigest(payload)
    }

    XCTAssertEqual(AgentDesktopControlReceiptProtocol.contractVersion, "signalasi.desktop-control/1.5")
    XCTAssertEqual(AgentDesktopControlReceiptProtocol.receiptVersion, 4)
    XCTAssertEqual(pending.toolId, AgentDesktopControlAction.screenshot)
    XCTAssertEqual(pending.requestSha256.count, 64)
    XCTAssertEqual(pending.inputSha256.count, 64)
    XCTAssertTrue(AgentDesktopControlReceiptProtocol.verify(payload: receipt, context: context, verifier: verifier))
    let parsed = try XCTUnwrap(AgentDesktopControlReceipt.parse(receipt))
    XCTAssertEqual(parsed.controllerAppInstanceId, "signalasi:phone")
    XCTAssertEqual(parsed.controllerName, "Test iPhone")
    XCTAssertEqual(parsed.controllerPlatform, "ios")
    XCTAssertEqual(parsed.controllerFingerprint, controllerFingerprint)
    XCTAssertEqual(parsed.startedAt, 1_800_000_000_500)
    XCTAssertEqual(parsed.durationMillis, 500)
    XCTAssertEqual(parsed.inputSha256, pending.inputSha256)

    var wrongController = context
    wrongController.expectedControllerFingerprint = AgentDesktopControlReceiptProtocol.digest(Data("other-phone".utf8))
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: receipt, context: wrongController, verifier: verifier))

    var tamperedSummary = receipt
    tamperedSummary["summary"] = .string("tampered")
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: tamperedSummary, context: context, verifier: verifier))

    var badTiming = receipt
    badTiming["started_at"] = .int(1_800_000_002_000)
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: badTiming, context: context, verifier: verifier))

    var badScreenshot = receipt
    if var output = badScreenshot["output"]?.objectValue,
       var screenshot = output["screenshot"]?.objectValue {
      screenshot["image_base64"] = .string(Data("tampered".utf8).base64EncodedString())
      output["screenshot"] = .object(screenshot)
      badScreenshot["output"] = .object(output)
    }
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: badScreenshot, context: context, verifier: verifier))
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(
      payload: makeReceipt(
        for: baseRequest,
        pending: pending,
        screenshotBytes: Data(repeating: 0x5a, count: AgentDesktopScreenshotStreamPolicy.screenshotByteLimit + 1)
      ),
      context: context,
      verifier: verifier
    ))
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(
      payload: makeReceipt(for: baseRequest, pending: pending, screenshotBytes: Data([1, 2, 3, 4]), declaredBytes: 5),
      context: context,
      verifier: verifier
    ))
  }

  func testAgentDesktopControlPoliciesAndPerceptionSnapshotMirrorAndroid() throws {
    func frame(_ capturedAt: Int64) -> AgentDesktopControlScreenshot {
      AgentDesktopControlScreenshot(
        jpegBytes: Data([1]),
        width: 1,
        height: 1,
        originalWidth: 1,
        originalHeight: 1,
        capturedAt: capturedAt
      )
    }

    XCTAssertNil(AgentDesktopScreenshotStreamPolicy.normalizeFps(0))
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.normalizeFps(1), 1)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.normalizeFps(2), 2)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.normalizeFps(3), 3)
    XCTAssertNil(AgentDesktopScreenshotStreamPolicy.normalizeFps(4))
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.intervalMillis(1), 1_000)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.intervalMillis(2), 500)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.intervalMillis(3), 333)
    XCTAssertTrue(shouldApplyDesktopScreenshot(current: nil, candidate: frame(2_000)))
    XCTAssertTrue(shouldApplyDesktopScreenshot(current: frame(2_000), candidate: frame(2_000)))
    XCTAssertFalse(shouldApplyDesktopScreenshot(current: frame(2_000), candidate: frame(1_999)))

    let gate = AgentDesktopScreenshotRequestGate()
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-1", expiresAt: 2_000, now: 1_000))
    XCTAssertFalse(gate.claim(desktopId: "desktop-1", actionId: "action-2", expiresAt: 2_500, now: 1_500))
    gate.release(desktopId: "desktop-1", actionId: "wrong-action")
    XCTAssertFalse(gate.claim(desktopId: "desktop-1", actionId: "action-3", expiresAt: 2_500, now: 1_600))
    gate.release(desktopId: "desktop-1", actionId: "action-1")
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-4", expiresAt: 2_500, now: 1_700))
    XCTAssertTrue(gate.claim(desktopId: "desktop-2", actionId: "action-5", expiresAt: 2_500, now: 1_700))
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-6", expiresAt: 3_500, now: 2_501))
    gate.clear(desktopId: "desktop-1")
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-7", expiresAt: 4_000, now: 3_000))

    let snapshot = try XCTUnwrap(AgentDesktopPerceptionSnapshot.parse([
      "contract_version": .string(AgentDesktopPerceptionSnapshot.contractVersion),
      "capture_id": .string("capture-1"),
      "captured_at": .int(1_800_000_001_000),
      "duration_ms": .int(237),
      "untrusted_evidence": .bool(true),
      "preferred_grounding": .string("ui_tree"),
      "available_layers": .array([.string("ui_tree"), .string("ocr"), .string("screenshot")]),
      "active_window": .object([
        "title": .string("SignalASI"),
        "process_id": .int(42)
      ]),
      "screenshot_layer": .object(["status": .string("available")]),
      "ui_tree": .object([
        "status": .string("available"),
        "element_count": .int(1),
        "truncated": .bool(false),
        "elements": .array([
          .object([
            "id": .string("42.1"),
            "parent_id": .string(""),
            "depth": .int(99),
            "name": .string("Send"),
            "control_type": .string("Button"),
            "enabled": .bool(true),
            "focused": .bool(false),
            "offscreen": .bool(false),
            "password": .bool(false),
            "bounds": .object([
              "left": .int(10),
              "top": .int(20),
              "width": .int(80),
              "height": .int(40)
            ]),
            "actions": .array([.string("invoke"), .string("")])
          ])
        ])
      ]),
      "ocr": .object([
        "status": .string("available"),
        "text": .string("Send a message"),
        "character_count": .int(14),
        "line_count": .int(1),
        "truncated": .bool(false)
      ])
    ]))

    XCTAssertEqual(snapshot.captureId, "capture-1")
    XCTAssertEqual(snapshot.activeWindowTitle, "SignalASI")
    XCTAssertEqual(snapshot.availableLayers, ["ui_tree", "ocr", "screenshot"])
    XCTAssertEqual(snapshot.uiElementCount, 1)
    XCTAssertEqual(snapshot.uiElements.count, 1)
    XCTAssertEqual(snapshot.uiElements.first?.name, "Send")
    XCTAssertEqual(snapshot.uiElements.first?.depth, 12)
    XCTAssertEqual(snapshot.uiElements.first?.actions, ["invoke"])
    XCTAssertEqual(snapshot.ocrText, "Send a message")
    XCTAssertNil(AgentDesktopPerceptionSnapshot.parse([
      "contract_version": .string(AgentDesktopPerceptionSnapshot.contractVersion),
      "capture_id": .string("capture-1"),
      "captured_at": .int(1_800_000_001_000),
      "untrusted_evidence": .bool(false)
    ]))
  }

  func testAgentDesktopRunSummariesAndTaskControlDigestsMirrorAndroid() throws {
    let runs = AgentDesktopRunSummary.parseSummaries(.array([
      .object([
        "task_id": .string("task-running"),
        "conversation_id": .string("conversation-1"),
        "turn_id": .string("turn-1"),
        "agent_id": .string("codex"),
        "status": .string("running"),
        "prompt": .string("Build the project"),
        "current_step": .string("Running tests"),
        "updated_at": .int(1_800_000_000_000),
        "execution_view": .object([
          "pausable": .bool(true),
          "resumable": .bool(false),
          "takeover_available": .bool(false),
          "takeover_active": .bool(false)
        ])
      ]),
      .object([
        "task_id": .string("task-takeover"),
        "task_status": .string("takeover"),
        "execution_view": .object([
          "pausable": .bool(false),
          "resumable": .bool(true),
          "takeover_available": .bool(false),
          "takeover_active": .bool(true),
          "takeover": .object(["controller_name": .string("iPhone")])
        ])
      ]),
      .object(["status": .string("running")])
    ]))

    func request(toolId: String, targetTaskId: String) -> AgentMcpJSONObject {
      [
        "type": .string("desktop_executor_request"),
        "task_id": .string("desktop-control-action"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string("session-1"),
        "tool_id": .string(toolId),
        "input": .object(["task_id": .string(targetTaskId)]),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ]
    }

    let pause = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.taskPause, targetTaskId: "task-1"),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "signalasi:phone"
    )
    let anotherTask = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.taskPause, targetTaskId: "task-2"),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "signalasi:phone"
    )
    let continueRequest = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.taskContinue, targetTaskId: "task-1"),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "signalasi:phone"
    )
    let liveFrame = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: [
        "type": .string("desktop_executor_request"),
        "task_id": .string("desktop-control-action"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string("session-1"),
        "tool_id": .string(AgentDesktopControlAction.screenshot),
        "input": .object(["stream_frame": .bool(true), "stream_fps": .int(3)]),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ],
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "signalasi:phone"
    )

    XCTAssertEqual(runs.count, 2)
    XCTAssertEqual(runs[0].status, "running")
    XCTAssertEqual(runs[0].currentStep, "Running tests")
    XCTAssertTrue(runs[0].pausable)
    XCTAssertFalse(runs[0].resumable)
    XCTAssertEqual(runs[1].status, "takeover")
    XCTAssertTrue(runs[1].resumable)
    XCTAssertTrue(runs[1].takeoverActive)
    XCTAssertEqual(runs[1].takeoverController, "iPhone")
    XCTAssertEqual(AgentDesktopControlReceiptProtocol.contractVersion, "signalasi.desktop-control/1.5")
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.taskTakeover))
    XCTAssertEqual(pause.toolId, AgentDesktopControlAction.taskPause)
    XCTAssertNotEqual(pause.inputSha256, anotherTask.inputSha256)
    XCTAssertNotEqual(pause.requestSha256, continueRequest.requestSha256)
    XCTAssertTrue(liveFrame.streamFrame)
    XCTAssertNotEqual(liveFrame.inputSha256, pause.inputSha256)
  }

  func testAgentIOSDesktopRemoteNativeToolCatalogAndExecutorForwardsVerifiedDesktopCalls() throws {
    final class FakeDesktopRemoteProvider: AgentIOSDesktopRemoteToolProviding {
      var implementationId = "fake.ios.desktop_remote"
      var transportId = "signalasi-link-v1"
      var currentAvailability: AgentNativeToolAvailability = .available
      var verificationStatus = "passed"
      var invokedKinds: [AgentIOSDesktopRemoteToolKind] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(kind: AgentIOSDesktopRemoteToolKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        kind: AgentIOSDesktopRemoteToolKind,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedKinds.append(kind)
        capturedInputs.append(input)
        return AgentNativeToolExecutionResult.success(
          output: output(kind: kind, input: input),
          message: "Desktop \(kind.rawValue) completed",
          metadata: [
            "desktop_id": .string(input["desktop_id"]?.stringValue ?? "desktop-1"),
            "remote_verification_status": .string(verificationStatus),
            "remote_verification_evidence": .object([
              "tool_id": .string(invocation.descriptor.id),
              "observed": .bool(true)
            ])
          ]
        )
      }

      private func output(kind: AgentIOSDesktopRemoteToolKind, input: AgentMcpJSONObject) -> AgentMcpJSONObject {
        switch kind {
        case .systemStatus:
          return ["os": .string("Windows"), "memory_used_bytes": .int(1_024)]
        case .processList:
          return ["processes": .array([.object(["pid": .int(7), "name": .string("SignalASI.exe")])])]
        case .fileReadText:
          return [
            "path": input["path"] ?? .string("notes/readme.txt"),
            "text": .string("desktop text"),
            "size_bytes": .int(12)
          ]
        case .terminalRun:
          return [
            "argv": input["argv"] ?? .array([]),
            "exit_code": .int(0),
            "stdout": .string("ok"),
            "stderr": .string("")
          ]
        case .fileList, .fileWriteText, .fileSha256, .archiveCreate, .officeInspect, .officeConvert:
          return ["kind": .string(kind.rawValue)]
        }
      }
    }

    let provider = FakeDesktopRemoteProvider()
    let definitions = AgentIOSDesktopRemoteNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.desktopRemoteExecutableDefinitions(provider: provider)
    )
    let linkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSDesktopRemoteNativeToolCatalog.linkPermission]
    )
    let workspaceContext = AgentNativeToolInvocationContext(
      invocationId: "desktop-terminal-1",
      idempotencyKey: "desktop-key-1",
      grantedPermissions: [
        AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
        AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
      ],
      grantedConsents: [AgentIOSDesktopRemoteNativeToolCatalog.executeConsent],
      attributes: ["workspace_id": "desktop-workspace-1"]
    )

    XCTAssertEqual(Set(AgentIOSDesktopRemoteNativeToolCatalog.orderedToolIds), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map { $0.descriptor.version }), [AgentIOSDesktopRemoteNativeToolCatalog.version])
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSDesktopRemoteNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .desktop)
      XCTAssertFalse(definition.descriptor.capabilities.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["transport"], "signalasi-link-v1")
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentDesktopRemoteNativeTools")
    }
    let terminalDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.terminalRun })
    let writeDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.fileWriteText })
    let readDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.fileReadText })
    XCTAssertEqual(terminalDescriptor.descriptor.risk, .high)
    XCTAssertEqual(terminalDescriptor.descriptor.timeoutMillis, 185_000)
    XCTAssertEqual(terminalDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSDesktopRemoteNativeToolCatalog.executeConsent])
    XCTAssertEqual(terminalDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(writeDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(readDescriptor.descriptor.requiredConsents.first?.required, false)
    XCTAssertTrue(AgentIOSDesktopRemoteNativeToolCatalog.alwaysConfirmToolIds.contains(AgentIOSDesktopRemoteNativeToolCatalog.terminalRun))

    let missingWorkspace = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileReadText,
      input: [
        "desktop_id": .string("desktop-1"),
        "path": .string("notes/readme.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ]
      )
    )
    let read = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileReadText,
      input: [
        "desktop_id": .string("desktop-1"),
        "path": .string("notes/readme.txt")
      ],
      context: workspaceContext
    )
    let deniedTerminal = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.terminalRun,
      input: ["argv": .array([.string("python"), .string("--version")])],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "desktop-key-2",
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ],
        attributes: ["workspace_id": "desktop-workspace-1"]
      )
    )
    let missingWriteKey = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileWriteText,
      input: [
        "path": .string("notes/readme.txt"),
        "content": .string("updated"),
        "mode": .string("overwrite")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ],
        attributes: ["workspace_id": "desktop-workspace-1"]
      )
    )
    let terminal = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.terminalRun,
      input: ["argv": .array([.string("python"), .string("--version")])],
      context: workspaceContext
    )
    provider.verificationStatus = "failed"
    let verificationFailed = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.processList,
      input: ["query": .string("SignalASI")],
      context: linkContext
    )
    let unavailableProvider = FakeDesktopRemoteProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Waiting for Desktop manifest"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.desktopRemoteExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.systemStatus,
      input: [:],
      context: linkContext
    )

    XCTAssertEqual(missingWorkspace.status, .failed)
    XCTAssertEqual(missingWorkspace.error?.code, "desktop_workspace_unavailable")
    XCTAssertTrue(read.isSuccess)
    XCTAssertEqual(read.output["desktop_id"], .string("desktop-1"))
    XCTAssertEqual(read.output["workspace_id"], .string("desktop-workspace-1"))
    XCTAssertEqual(read.output["remote_artifacts"], .array([]))
    XCTAssertEqual(read.verification?.status, .passed)
    XCTAssertEqual(deniedTerminal.status, .rejected)
    XCTAssertEqual(deniedTerminal.error?.code, "missing_consents")
    XCTAssertEqual(missingWriteKey.status, .rejected)
    XCTAssertEqual(missingWriteKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(terminal.isSuccess)
    XCTAssertEqual(terminal.output["remote_forwarded"], .bool(true))
    XCTAssertEqual(terminal.metadata["transport"], .string("signalasi-link-v1"))
    XCTAssertEqual(verificationFailed.status, .verificationFailed)
    XCTAssertEqual(verificationFailed.error?.code, "verification_failed")
    XCTAssertEqual(provider.invokedKinds, [.fileReadText, .terminalRun, .processList])
    XCTAssertEqual(provider.capturedInputs.first?["path"], .string("notes/readme.txt"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedKinds.isEmpty)
  }

  func testAgentMcpNativeToolsExposeAndroidWireIdsAndProviderBackedExecution() throws {
    final class FakeMcpNativeProvider: AgentIOSMcpNativeToolProviding {
      var implementationId = "fake.ios.mcp"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSMcpNativeToolOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSMcpNativeToolOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .listConnections:
          return AgentNativeToolExecutionResult.success(
            output: [
              "connections": .array([
                .object([
                  "id": .string("github"),
                  "name": .string("GitHub"),
                  "state": .string("connected"),
                  "auth_state": .string("authenticated"),
                  "enabled": .bool(true),
                  "permission_mode": .string("ask_for_changes"),
                  "tools": .array([.string("github.repositories")])
                ])
              ])
            ],
            message: "MCP connections listed"
          )
        case .listTools:
          return AgentNativeToolExecutionResult.success(
            output: [
              "connection_id": input["connection_id"] ?? .string("github"),
              "tools": .array([
                .object([
                  "name": .string("github.repositories"),
                  "title": .string("List repositories"),
                  "description": .string("Lists repositories"),
                  "security": .object(["risk": .string("low")])
                ])
              ])
            ],
            message: "MCP tools discovered"
          )
        case .callTool:
          return AgentNativeToolExecutionResult.success(
            output: [
              "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
              "structured_content": .object(["ok": .bool(true)])
            ],
            message: "MCP tool called",
            metadata: ["mcp_audit_id": .string("audit-1")]
          )
        }
      }
    }

    let provider = FakeMcpNativeProvider()
    let definitions = AgentMcpNativeTools.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentMcpNativeTools.toolIds)
    XCTAssertEqual(registry.ids(), AgentMcpNativeTools.toolIds)
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.connections.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.tools.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.tool.call"))
    XCTAssertFalse(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.call_tool"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentMcpNativeTools.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("mcp"))
      XCTAssertEqual(definition.descriptor.requiredPermissions.map(\.id), [AgentMcpNativeTools.mcpHostPermission])
      XCTAssertEqual(definition.descriptor.requiredConsents.first?.required, false)
      XCTAssertEqual(definition.provenanceMetadata["protocol"], "mcp")
      XCTAssertEqual(definition.provenanceMetadata["host"], "ios")
    }
    let callDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentMcpNativeTools.callTool })
    XCTAssertEqual(callDescriptor.descriptor.risk, .medium)
    XCTAssertEqual(callDescriptor.descriptor.timeoutMillis, 60_000)
    XCTAssertEqual(callDescriptor.descriptor.idempotency, .nonIdempotent)

    let connections = registry.invoke(AgentMcpNativeTools.listConnections, input: [:], context: context)
    let tools = registry.invoke(
      AgentMcpNativeTools.listTools,
      input: ["connection_id": .string("github")],
      context: context
    )
    let denied = registry.invoke(
      AgentMcpNativeTools.callTool,
      input: [
        "connection_id": .string("github"),
        "tool_name": .string("github.repositories"),
        "arguments": .object([:])
      ],
      context: AgentNativeToolInvocationContext()
    )
    let call = registry.invoke(
      AgentMcpNativeTools.callTool,
      input: [
        "connection_id": .string("github"),
        "tool_name": .string("github.repositories"),
        "arguments": .object(["limit": .int(1)])
      ],
      context: context
    )
    let unavailableProvider = FakeMcpNativeProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "No authenticated MCP connection is ready"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(AgentMcpNativeTools.listConnections, input: [:], context: context)

    XCTAssertTrue(connections.isSuccess)
    if case .array(let listedConnections)? = connections.output["connections"] {
      XCTAssertEqual(listedConnections.count, 1)
    } else {
      XCTFail("Expected MCP connections array")
    }
    XCTAssertTrue(tools.isSuccess)
    XCTAssertEqual(provider.capturedInputs[1]["connection_id"], .string("github"))
    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_permissions")
    XCTAssertTrue(call.isSuccess)
    XCTAssertEqual(call.output["connection_id"], .string("github"))
    XCTAssertEqual(call.output["tool_name"], .string("github.repositories"))
    XCTAssertEqual(call.metadata["protocol"], .string("mcp"))
    XCTAssertEqual(call.metadata["mcp_audit_id"], .string("audit-1"))
    XCTAssertEqual(provider.invokedOperations, [.listConnections, .listTools, .callTool])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSOnDeviceRuntimeNativeToolCatalogAndExecutorMirrorsAndroidRuntimeTools() throws {
    final class FakeRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding {
      var implementationId = "fake.ios.runtime"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSOnDeviceRuntimeToolOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSOnDeviceRuntimeToolOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .status:
          return AgentNativeToolExecutionResult.success(
            output: [
              "backend": .string("ios_local"),
              "backend_ready": .bool(true),
              "reason": .string("ready"),
              "packs": .array([packValue("linux-base", state: "ready")]),
              "languages": .array([
                .object(["id": .string("python"), "ready": .bool(true)])
              ])
            ],
            message: "On-device runtime inspected"
          )
        case .workspaceStatus:
          return AgentNativeToolExecutionResult.success(
            output: [
              "workspace_file_count": .int(3),
              "workspace_bytes": .int(1_024),
              "checkpoints": .array([.object(["checkpoint_id": .string("cp-1")])])
            ],
            message: "On-device project workspace inspected"
          )
        case .workspaceRollback:
          return AgentNativeToolExecutionResult.success(
            output: [
              "checkpoint_id": input["checkpoint_id"] ?? .string("cp-1"),
              "workspace_file_count": .int(2),
              "workspace_bytes": .int(512),
              "workspace_disposition": .string("rolled_back")
            ],
            message: "On-device project checkpoint restored"
          )
        case .listPacks:
          return AgentNativeToolExecutionResult.success(
            output: ["packs": .array([packValue("linux-base", state: "ready"), packValue("python-uv", state: "ready")])],
            message: "On-device runtime packs listed"
          )
        case .installPack:
          return AgentNativeToolExecutionResult.success(
            output: [
              "requested_pack": input["pack_id"] ?? .string("python-uv"),
              "installed": .array([
                .object(["pack_id": .string("python-uv"), "version": .string("1.0.0"), "state": .string("ready")])
              ])
            ],
            message: "Trusted runtime pack is ready"
          )
        case .execute:
          return AgentNativeToolExecutionResult.success(
            output: [
              "exit_code": .int(0),
              "stdout": .string("ok"),
              "stderr": .string(""),
              "duration_ms": .int(25),
              "workspace_file_count": .int(4),
              "workspace_bytes": .int(2_048),
              "checkpoint_id": .string("cp-2"),
              "execution_receipt": .object(["request_id": .string(invocation.context.invocationId)])
            ],
            message: "On-device runtime completed"
          )
        }
      }

      private func packValue(_ id: String, state: String) -> AgentMcpJSONValue {
        .object([
          "id": .string(id),
          "state": .string(state),
          "reason": .string(""),
          "version": .string("1.0.0"),
          "architecture": .string("arm64"),
          "capabilities": .array([.string("shell.execute")]),
          "installed_size_bytes": .int(2_048),
          "license": .string("Apache-2.0")
        ])
      }
    }

    let provider = FakeRuntimeProvider()
    let definitions = AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: provider)
    )
    let runtimeContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission]
    )
    let workspaceContext = AgentNativeToolInvocationContext(
      invocationId: "runtime-execute-1",
      grantedPermissions: [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.workspacePermission
      ],
      attributes: ["workspace_id": "runtime-workspace-1"]
    )
    let packContext = AgentNativeToolInvocationContext(
      grantedPermissions: [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.packInstallPermission
      ]
    )

    XCTAssertEqual(Set(AgentIOSOnDeviceRuntimeNativeToolCatalog.orderedToolIds), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds.contains("signalasi.runtime.workspace.status"))
    XCTAssertTrue(AgentIOSOnDeviceRuntimeNativeToolCatalog.requiredPacks.contains("python-uv"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("runtime.ios_local"))
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertEqual(definition.descriptor.requiredConsents.first?.required, false)
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentOnDeviceRuntimeTools")
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios")
    }
    let installDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack })
    let executeDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute })
    let statusDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.status })
    XCTAssertEqual(statusDescriptor.descriptor.risk, .low)
    XCTAssertEqual(installDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.packManagerExecutorId)
    XCTAssertEqual(installDescriptor.descriptor.timeoutMillis, 30 * 60_000)
    XCTAssertEqual(executeDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId)
    XCTAssertEqual(executeDescriptor.descriptor.risk, .medium)
    XCTAssertEqual(executeDescriptor.descriptor.timeoutMillis, 30 * 60_000)

    let status = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.status, input: [:], context: runtimeContext)
    let packs = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks, input: [:], context: runtimeContext)
    let workspace = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceStatus, input: [:], context: workspaceContext)
    let deniedInstall = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack,
      input: ["pack_id": .string("python-uv")],
      context: runtimeContext
    )
    let install = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack,
      input: ["pack_id": .string("python-uv")],
      context: packContext
    )
    let rollback = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceRollback,
      input: ["checkpoint_id": .string("cp-1")],
      context: workspaceContext
    )
    let invalidExecute = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("swift"),
        "source": .string("print(\"no\")")
      ],
      context: workspaceContext
    )
    let execute = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("python"),
        "source": .string("print('ok')"),
        "timeout_ms": .int(1_000),
        "artifact_paths": .array([.string("out/result.txt")])
      ],
      context: workspaceContext
    )
    let unavailableProvider = FakeRuntimeProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install runtime backend"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("python"),
        "source": .string("print('ok')")
      ],
      context: workspaceContext
    )

    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["backend"], .string("ios_local"))
    XCTAssertTrue(packs.isSuccess)
    if case .array(let packValues)? = packs.output["packs"] {
      XCTAssertEqual(packValues.count, 2)
    } else {
      XCTFail("Expected runtime packs array")
    }
    XCTAssertTrue(workspace.isSuccess)
    XCTAssertEqual(workspace.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(deniedInstall.status, .rejected)
    XCTAssertEqual(deniedInstall.error?.code, "missing_permissions")
    XCTAssertTrue(install.isSuccess)
    XCTAssertEqual(install.output["requested_pack"], .string("python-uv"))
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["workspace_disposition"], .string("rolled_back"))
    XCTAssertEqual(invalidExecute.status, .rejected)
    XCTAssertEqual(invalidExecute.error?.code, "invalid_input")
    XCTAssertTrue(execute.isSuccess)
    XCTAssertEqual(execute.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(execute.output["workspace_disposition"], .string("preserved"))
    XCTAssertEqual(execute.output["artifacts"], .array([]))
    XCTAssertEqual(execute.metadata["network_default"], .string("disabled"))
    XCTAssertEqual(provider.invokedOperations, [.status, .listPacks, .workspaceStatus, .installPack, .workspaceRollback, .execute])
    XCTAssertEqual(provider.capturedInputs.last?["language"], .string("python"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentPhoneNativeToolCatalogRegistersStableDefaultIds() {
    var expected: Set<String> = [
      "signalasi.workspace.initialize",
      "signalasi.workspace.directory.create",
      "signalasi.workspace.directory.list",
      "signalasi.workspace.file.stat",
      "signalasi.workspace.file.read.text",
      "signalasi.workspace.file.read.bytes",
      "signalasi.workspace.file.write.text",
      "signalasi.workspace.file.create.text",
      "signalasi.workspace.file.append.text",
      "signalasi.workspace.file.write.bytes",
      "signalasi.workspace.file.create.bytes",
      "signalasi.workspace.file.append.bytes",
      "signalasi.workspace.entry.move",
      "signalasi.workspace.entry.copy",
      "signalasi.workspace.entry.delete",
      "signalasi.workspace.file.search.text",
      "signalasi.workspace.file.patch.exact",
      "signalasi.workspace.file.diff.summary",
      "signalasi.workspace.file.sha256",
      "signalasi.workspace.zip.create",
      "signalasi.workspace.zip.list",
      "signalasi.workspace.zip.extract",
      "signalasi.agent_action.read.screen",
      "signalasi.agent_action.tap",
      "signalasi.agent_action.type.text",
      "signalasi.agent_action.swipe",
      "signalasi.agent_action.long.press",
      "signalasi.agent_action.delete.text",
      "signalasi.agent_action.paste.text",
      "signalasi.agent_action.copy.screen.text",
      "signalasi.agent_action.back",
      "signalasi.agent_action.home",
      "signalasi.agent_action.recents",
      "signalasi.agent_action.lock.screen",
      "signalasi.agent_action.open.app",
      "signalasi.agent_action.open.url",
      "signalasi.agent_action.set.alarm",
      "signalasi.agent_action.reply.notification"
    ]
    expected.formUnion(AgentIOSSystemNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSHardwareNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSNotificationNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSMediaNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    expected.formUnion(AgentMcpNativeTools.toolIds)
    expected.formUnion(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    let descriptors = AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: readyPhoneCapabilityStatuses())

    XCTAssertEqual(expected, AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertEqual(expected, Set(descriptors.map(\.id)))
    XCTAssertEqual(expected.count, descriptors.count)
  }

  func testAgentPhoneNativeToolCatalogDescriptorsCarryPolicyAndProvenance() {
    let definitions = AgentPhoneNativeToolCatalog.definitions(capabilityStatuses: readyPhoneCapabilityStatuses())

    XCTAssertEqual(definitions.count, AgentPhoneNativeToolCatalog.toolIds.count)
    definitions.forEach { definition in
      let descriptor = definition.descriptor
      XCTAssertFalse(descriptor.inputSchema.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.outputSchema.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.capabilities.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.requiredPermissions.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.requiredConsents.isEmpty, descriptor.id)
      XCTAssertTrue((Int64(1)...Int64(30 * 60_000)).contains(descriptor.timeoutMillis), descriptor.id)
      XCTAssertFalse(definition.executorId.isEmpty, descriptor.id)
      XCTAssertFalse(definition.provenanceMetadata.isEmpty, descriptor.id)
    }
  }

  func testAgentPhoneNativeToolCatalogMapsCapabilityAvailabilityToActions() throws {
    let declared = AgentPhoneNativeToolCatalog.descriptors()
    let readScreen = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.readScreen) }
    )
    let openURL = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.openURL) }
    )
    let reply = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.replyNotification) }
    )

    XCTAssertEqual(readScreen.availability.status, .unavailable)
    XCTAssertTrue(readScreen.capabilities.contains("phone.accessibility.ui.tree"))
    XCTAssertEqual(openURL.availability.status, .available)
    XCTAssertEqual(reply.availability.status, .available)
    XCTAssertTrue(reply.availability.reason.contains("SignalASI-owned notification"))
  }

  func testAgentPhoneNativeToolCatalogDefaultIdsIncludeExpansionGroups() {
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.isSuperset(of: AgentPhoneNativeToolCatalog.toolIds))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.media.playback.handoff"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.web.intelligence.search"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.hardware.location.foreground.read"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.status))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.execute))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.listConnections))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.callTool))
    XCTAssertFalse(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.mcp.call_tool"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSSystemNativeToolCatalog.smsSend))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSHardwareNativeToolCatalog.storageStatus))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSHomeAssistantNativeToolCatalog.connectionStatus))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSNotificationNativeToolCatalog.notificationsList))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebIntelligenceNativeToolCatalog.search))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSMediaNativeToolCatalog.mediaMetadata))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSSelfEvolutionNativeToolCatalog.status))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSDesktopRemoteNativeToolCatalog.systemStatus))
  }

  func testAgentPhoneNativeToolCatalogModelsUseAndroidWireNames() throws {
    let definition = try XCTUnwrap(
      AgentPhoneNativeToolCatalog.definitions().first { $0.id == AgentPhoneNativeToolCatalog.workspaceReadText }
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as? [String: Any]
    )
    let descriptor = try XCTUnwrap(object["descriptor"] as? [String: Any])

    XCTAssertEqual(object["executor_id"] as? String, AgentPhoneNativeToolCatalog.fileExecutorId)
    XCTAssertNotNil(object["provenance_metadata"])
    XCTAssertEqual(descriptor["id"] as? String, AgentPhoneNativeToolCatalog.workspaceReadText)
    XCTAssertNotNil(descriptor["input_schema"] as? [String: Any])
    XCTAssertNotNil(descriptor["output_schema"] as? [String: Any])
    XCTAssertNil(object["executorId"])
    XCTAssertNil(descriptor["inputSchema"])
  }

  func testAgentNativeToolRegistryRegistersStableIdsAndCatalogJson() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.echo",
      availability: AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Contacts permission is disabled",
        checkedAtEpochMillis: 123
      ),
      capabilities: ["phone.local", "contacts.read"],
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "ios.permission.contacts", title: "Contacts")
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(id: "contacts.lookup", title: "Look up contact")
      ]
    )
    let definition = AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: "test.executor",
      provenanceMetadata: ["implementation": "fake"]
    )
    let registry = try AgentNativeToolRegistry(definitions: [definition])

    XCTAssertEqual(registry.ids(), Set(["signalasi.test.echo"]))
    XCTAssertEqual(registry.lookup("signalasi.test.echo"), definition)
    XCTAssertThrowsError(try registry.register(AgentPhoneNativeToolDefinition(
      descriptor: try nativeToolDescriptor("signalasi.test.echo"),
      executorId: "duplicate.executor"
    )))

    let json = registry.catalogJson()
    XCTAssertTrue(json.contains("\"contract_version\":\"signalasi.phone-native-tools/1.0\""))
    XCTAssertTrue(json.contains("\"id\":\"signalasi.test.echo\""))
    XCTAssertTrue(json.contains("\"input_schema\""))
    XCTAssertTrue(json.contains("\"output_schema\""))
    XCTAssertTrue(json.contains("\"required_permissions\""))
    XCTAssertTrue(json.contains("\"required_consents\""))
    XCTAssertTrue(json.contains("\"timeout_ms\""))
    XCTAssertTrue(json.contains("\"checked_at_epoch_ms\":123"))
    XCTAssertTrue((json.range(of: "contacts.read")?.lowerBound ?? json.endIndex) < (json.range(of: "phone.local")?.lowerBound ?? json.startIndex))
  }

  func testAgentNativeToolRegistryValidatesJsonSchemaTypesRequiredAndAdditionalProperties() throws {
    let schema: AgentMcpJSONObject = [
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string"), "minLength": .int(2)]),
        "count": .object(["type": .string("integer"), "minimum": .int(1)]),
        "mode": .object(["type": .string("string"), "enum": .array([.string("fast"), .string("safe")])]),
        "tags": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "maxItems": .int(2)
        ])
      ]),
      "required": .array([.string("name"), .string("count")]),
      "additionalProperties": .bool(false)
    ]
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(
        descriptor: try nativeToolDescriptor("signalasi.test.schema", inputSchema: schema),
        executorId: "test.executor"
      )
    ])

    let invalid = registry.validateInput("signalasi.test.schema", input: [
      "count": .string("one"),
      "mode": .string("slow"),
      "tags": .array([.string("a"), .string("b"), .string("c")]),
      "extra": .bool(true)
    ])
    let codes = Set(invalid.issues.map(\.code))

    XCTAssertFalse(invalid.isValid)
    XCTAssertTrue(codes.contains("required"))
    XCTAssertTrue(codes.contains("type_mismatch"))
    XCTAssertTrue(codes.contains("not_in_enum"))
    XCTAssertTrue(codes.contains("max_items"))
    XCTAssertTrue(codes.contains("additional_property"))
    XCTAssertTrue(registry.validateInput("signalasi.test.schema", input: [
      "name": .string("ok"),
      "count": .int(1),
      "mode": .string("safe")
    ]).isValid)
    XCTAssertEqual(registry.validateInput("signalasi.missing", input: [:]).issues.first?.code, "unknown_tool")
  }

  func testAgentNativeToolRegistryAuthorizesAvailabilityPermissionsAndConsents() throws {
    let permission = AgentNativePermissionRequirement(id: "ios.permission.camera", title: "Camera")
    let consent = AgentNativeConsentRequirement(id: "camera.capture", title: "Capture camera")
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.camera",
      requiredPermissions: [permission],
      requiredConsents: [consent],
      inputSchema: AgentNativeToolDescriptor.objectSchema()
    )
    let setup = try nativeToolDescriptor(
      "signalasi.test.setup",
      availability: AgentNativeToolAvailability(status: .requiresSetup, reason: "Needs configuration")
    )
    let blocked = try nativeToolDescriptor("signalasi.test.blocked", risk: .blocked)
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: setup, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: blocked, executorId: "test.executor")
    ])

    let missingPermission = registry.authorize("signalasi.test.camera", input: [:])
    let missingConsent = registry.authorize(
      "signalasi.test.camera",
      input: [:],
      context: AgentNativeToolInvocationContext(grantedPermissions: ["ios.permission.camera"])
    )
    let ready = registry.authorize(
      "signalasi.test.camera",
      input: [:],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: ["ios.permission.camera"],
        grantedConsents: ["camera.capture"]
      )
    )

    XCTAssertEqual(missingPermission.code, "missing_permissions")
    XCTAssertEqual(missingPermission.missingPermissions.map(\.id), ["ios.permission.camera"])
    XCTAssertEqual(missingConsent.code, "missing_consents")
    XCTAssertEqual(missingConsent.missingConsents.map(\.id), ["camera.capture"])
    XCTAssertTrue(ready.allowed)
    XCTAssertEqual(ready.code, "ok")
    XCTAssertEqual(registry.authorize("signalasi.test.setup").code, "tool_unavailable")
    XCTAssertEqual(registry.authorize("signalasi.test.blocked").code, "tool_blocked")
    XCTAssertEqual(registry.authorize("signalasi.missing").code, "unknown_tool")
  }

  func testAgentNativeToolRegistryProtectsIdempotencyKeys() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.idempotent",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let missingKey = registry.authorize("signalasi.test.idempotent", input: ["value": .int(1)])
    let first = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let replay = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )
    let conflict = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(2)],
      context: AgentNativeToolInvocationContext(invocationId: "third", idempotencyKey: "request-1")
    )

    XCTAssertEqual(missingKey.code, "missing_idempotency_key")
    XCTAssertEqual(first.code, .accepted)
    XCTAssertEqual(replay.code, .replay)
    XCTAssertTrue(replay.replayed)
    XCTAssertEqual(replay.originalInvocationId, "first")
    XCTAssertEqual(conflict.code, .conflict)
  }

  func testAgentNativeToolRegistryAcceptsPhoneCatalogDescriptors() throws {
    let registry = try AgentNativeToolRegistry(definitions: AgentPhoneNativeToolCatalog.definitions(
      capabilityStatuses: readyPhoneCapabilityStatuses()
    ))
    let workspaceDecision = registry.authorize(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("default"),
        "path": .string("notes/today.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )
    let openURL = registry.validateInput(
      AgentNativeToolAgentActionAdapter.defaultToolId(.openURL),
      input: [
        "target": .string("Safari"),
        "url": .string("https://signalasi.com")
      ]
    )

    XCTAssertEqual(registry.ids(), AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertTrue(workspaceDecision.allowed)
    XCTAssertTrue(openURL.isValid)
  }

  func testAgentNativeToolRegistryModelsUseAndroidWireNames() throws {
    let context = AgentNativeToolInvocationContext(
      invocationId: "invoke-1",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "key",
      grantedPermissions: ["permission.b", "permission.a"],
      grantedConsents: ["consent.a"]
    )
    let contextObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any]
    )
    let decision = AgentNativeToolAuthorizationDecision(
      toolId: "signalasi.test.tool",
      allowed: false,
      code: "missing_permissions",
      message: "Missing",
      availability: .available,
      risk: .medium,
      missingPermissions: [AgentNativePermissionRequirement(id: "permission.a")],
      missingConsents: [],
      validationIssues: []
    )
    let decisionObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(decision)) as? [String: Any]
    )

    XCTAssertEqual(contextObject["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(contextObject["session_id"] as? String, "session")
    XCTAssertEqual(contextObject["idempotency_key"] as? String, "key")
    XCTAssertEqual(contextObject["granted_permissions"] as? [String], ["permission.a", "permission.b"])
    XCTAssertNil(contextObject["invocationId"])
    XCTAssertEqual(decisionObject["tool_id"] as? String, "signalasi.test.tool")
    XCTAssertNotNil(decisionObject["missing_permissions"])
    XCTAssertNotNil(decisionObject["validation_issues"])
    XCTAssertNil(decisionObject["missingPermissions"])
  }

  func testAgentNativeToolAgentActionAdapterCreatesNativeCallsWithLegacyContext() {
    let action = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .medium,
      status: .proposed,
      description: "Tap Wi-Fi",
      parameters: ["bounds": "[0,0][10,10]"],
      requiresConfirmation: true
    )

    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(action)

    XCTAssertEqual(call.toolId, AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    XCTAssertEqual(call.input["target"], .string("Wi-Fi"))
    XCTAssertEqual(call.input["description"], .string("Tap Wi-Fi"))
    XCTAssertEqual(call.input["requires_confirmation"], .bool(true))
    XCTAssertEqual(call.input["parameters"]?.objectValue?["bounds"], .string("[0,0][10,10]"))
    XCTAssertEqual(call.context.invocationId, "legacy-9")
    XCTAssertEqual(call.context.attributes[AgentNativeToolRegistry.legacyActionIdAttribute], "legacy-9")
  }

  func testAgentNativeToolAgentActionAdapterRehydratesLegacyActions() throws {
    let descriptor = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.tap),
      risk: .medium,
      requiredConsents: [
        AgentNativeConsentRequirement(id: "tap.once", title: "Tap once")
      ]
    )
    let call = AgentNativeToolCall(
      toolId: descriptor.id,
      input: [
        "target": .string("Wi-Fi"),
        "description": .string("Tap Wi-Fi"),
        "parameters": .object(["bounds": .string("[0,0][10,10]")])
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "invoke-9",
        attributes: [AgentNativeToolRegistry.legacyActionIdAttribute: "legacy-9"]
      )
    )

    let action = AgentNativeToolAgentActionAdapter.toAgentAction(
      call: call,
      descriptor: descriptor,
      kind: .tap
    )

    XCTAssertEqual(action.id, "legacy-9")
    XCTAssertEqual(action.kind, .tap)
    XCTAssertEqual(action.target, "Wi-Fi")
    XCTAssertEqual(action.risk, .medium)
    XCTAssertEqual(action.status, .running)
    XCTAssertEqual(action.parameters["bounds"], "[0,0][10,10]")
    XCTAssertTrue(action.requiresConfirmation)
  }

  func testAgentNativeToolAgentActionAdapterMapsResultsAndMetadata() throws {
    let descriptor = try nativeToolDescriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(
        descriptor: descriptor,
        executorId: "legacy.agent_action",
        provenanceMetadata: ["adapter": "AgentActionExecutor"]
      )
    ])
    let action = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap Wi-Fi"
    )
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(action)
    let nativeResult = registry.makeResult(
      call.toolId,
      input: call.input,
      context: call.context,
      status: .succeeded,
      output: ["action_id": .string(action.id), "success": .bool(true)],
      message: "Tapped",
      startedAtEpochMillis: 1_000,
      finishedAtEpochMillis: 1_007
    )
    let roundTripped = AgentNativeToolAgentActionAdapter.toAgentActionResult(nativeResult, actionId: action.id)
    let failedExecution = AgentNativeToolAgentActionAdapter.fromAgentActionResult(AgentActionResult(
      actionId: action.id,
      success: false,
      message: "Missed target",
      metadata: ["screen": "Settings"]
    ))

    XCTAssertTrue(roundTripped.success)
    XCTAssertEqual(roundTripped.message, "Tapped")
    XCTAssertEqual(roundTripped.metadata["native_tool_id"], descriptor.id)
    XCTAssertEqual(roundTripped.metadata["native_tool_version"], "1.0.0")
    XCTAssertEqual(roundTripped.metadata["native_receipt_id"], "legacy-9")
    XCTAssertEqual(roundTripped.metadata["native_status"], "succeeded")
    XCTAssertFalse(failedExecution.isSuccess)
    XCTAssertEqual(failedExecution.error?.code, "agent_action_failed")
    XCTAssertEqual(failedExecution.output["metadata"]?.objectValue?["screen"], .string("Settings"))
  }

  func testAgentNativeToolResultModelsUseAndroidWireNames() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.result",
      requiredPermissions: [AgentNativePermissionRequirement(id: "ios.permission.camera")]
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let context = AgentNativeToolInvocationContext(
      invocationId: "invoke-1",
      idempotencyKey: "key-1",
      attributes: [AgentNativeToolRegistry.legacyActionIdAttribute: "legacy-1"]
    )
    let result = registry.makeResult(
      descriptor.id,
      input: [:],
      context: context,
      status: .rejected,
      message: "Missing permission",
      error: AgentNativeToolError(code: "missing_permissions", message: "Missing permission"),
      verification: AgentNativeToolVerification(status: .skipped),
      startedAtEpochMillis: 1_000,
      finishedAtEpochMillis: 1_010
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
    let provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
    let callData = try JSONEncoder().encode(AgentNativeToolAgentActionAdapter.fromAgentAction(AgentAction(
      id: "legacy-1",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap"
    )))
    let callObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: callData) as? [String: Any]
    )

    XCTAssertEqual(receipt["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(receipt["idempotency_key"] as? String, "key-1")
    XCTAssertEqual(receipt["started_at_epoch_ms"] as? Int, 1_000)
    XCTAssertEqual(receipt["finished_at_epoch_ms"] as? Int, 1_010)
    XCTAssertEqual(receipt["duration_ms"] as? Int, 10)
    XCTAssertNotNil(receipt["input_sha256"])
    XCTAssertEqual(provenance["tool_id"] as? String, descriptor.id)
    XCTAssertEqual(provenance["executor_id"] as? String, "test.executor")
    XCTAssertEqual(provenance["legacy_agent_action_id"] as? String, "legacy-1")
    XCTAssertEqual(callObject["tool_id"] as? String, AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    XCTAssertNil(receipt["startedAtEpochMillis"])
    XCTAssertNil(provenance["legacyAgentActionId"])
    XCTAssertNil(callObject["toolId"])
  }

  func testAgentNativeToolRegistryBuildsPreflightRejectionResults() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.preflight",
      requiredPermissions: [AgentNativePermissionRequirement(id: "ios.permission.camera")]
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])

    let result = try XCTUnwrap(registry.preflightRejectionResult(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "invoke-preflight")
    ))
    let passed = registry.preflightRejectionResult(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(
        invocationId: "invoke-ready",
        grantedPermissions: ["ios.permission.camera"]
      )
    )

    XCTAssertEqual(result.status, .rejected)
    XCTAssertEqual(result.error?.code, "missing_permissions")
    XCTAssertEqual(result.receipt.invocationId, "invoke-preflight")
    XCTAssertEqual(result.provenance.toolId, descriptor.id)
    XCTAssertNil(passed)
  }

  func testAgentNativeToolRegistryInvokeReturnsReceiptProgressAndVerification() throws {
    var now: Int64 = 1_000
    var started = 0
    var progress: [AgentNativeToolProgressUpdate] = []
    var finished = 0
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.invoke",
      outputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ]
    )
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "test.executor",
          provenanceMetadata: ["implementation": "fake"]
        ),
        executor: { invocation in
          try invocation.reportProgress(
            stage: "working",
            message: "Preparing output",
            percent: 40,
            sequence: 3
          )
          now += 7
          return .success(
            output: ["value": .string("done")],
            message: "Completed",
            metadata: ["native_call": .string("local")]
          )
        },
        verifier: { _, execution in
          AgentNativeToolVerification(
            status: .passed,
            evidence: ["observed": execution.output["value"] ?? .null]
          )
        }
      ))

    let result = registry.invoke(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "invoke-7", requestedAtEpochMillis: now),
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        onStarted: { _ in started += 1 },
        onProgress: { _, update in progress.append(update) },
        onFinished: { _ in finished += 1 }
      )
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.status, .succeeded)
    XCTAssertEqual(result.output["value"], .string("done"))
    XCTAssertEqual(result.message, "Completed")
    XCTAssertEqual(result.receipt.durationMillis, 7)
    XCTAssertEqual(result.receipt.inputSha256.count, 64)
    XCTAssertEqual(result.receipt.outputSha256.count, 64)
    XCTAssertEqual(result.verification?.status, .passed)
    XCTAssertEqual(result.provenance.executorId, "test.executor")
    XCTAssertEqual(result.provenance.toolVersion, "1.0.0")
    XCTAssertEqual(started, 1)
    XCTAssertEqual(progress.first?.stage, "working")
    XCTAssertEqual(progress.first?.percent, 40)
    XCTAssertEqual(progress.first?.sequence, 3)
    XCTAssertEqual(finished, 1)
    XCTAssertTrue(result.toJson().contains("\"invocation_id\":\"invoke-7\""))
  }

  func testAgentNativeToolRegistryInvokeRejectsInvalidOutputAndFailedVerification() throws {
    let invalidOutput = try nativeToolDescriptor(
      "signalasi.test.invalid-output",
      outputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ]
    )
    let verificationFailed = try nativeToolDescriptor("signalasi.test.verification")
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: invalidOutput, executorId: "test.executor"),
        executor: { _ in .success(output: ["value": .int(1)], message: "Invalid") }
      ))
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: verificationFailed, executorId: "test.executor"),
        executor: { _ in .success(message: "Executed") },
        verifier: { _, _ in AgentNativeToolVerification(status: .failed, message: "Screen did not change") }
      ))

    let invalid = registry.invoke(invalidOutput.id, input: [:])
    let failed = registry.invoke(verificationFailed.id, input: [:])

    XCTAssertEqual(invalid.status, .failed)
    XCTAssertEqual(invalid.error?.code, "invalid_output")
    XCTAssertEqual(failed.status, .verificationFailed)
    XCTAssertEqual(failed.error?.code, "verification_failed")
    XCTAssertEqual(failed.verification?.message, "Screen did not change")
  }

  func testAgentNativeToolRegistryInvokeHandlesCancellationTimeoutAndMissingExecutor() throws {
    var now: Int64 = 10
    var cancelledHooks = 0
    var timeoutHooks = 0
    var executions = 0
    let cancelledDescriptor = try nativeToolDescriptor("signalasi.test.cancelled")
    let timedDescriptor = try nativeToolDescriptor("signalasi.test.timeout", timeoutMillis: 5)
    let descriptorOnly = try nativeToolDescriptor("signalasi.test.descriptor-only")
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptorOnly, executorId: "test.executor")
    ])
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: cancelledDescriptor, executorId: "test.executor"),
        executor: { _ in
          executions += 1
          return .success()
        }
      ))
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: timedDescriptor, executorId: "test.executor"),
        executor: { invocation in
          now += 5
          try invocation.checkpoint()
          return .success()
        }
      ))

    let cancelled = registry.invoke(
      cancelledDescriptor.id,
      input: [:],
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        cancellationRequested: { true },
        onCancelled: { _ in cancelledHooks += 1 }
      )
    )
    let timedOut = registry.invoke(
      timedDescriptor.id,
      input: [:],
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        onTimeout: { _ in timeoutHooks += 1 }
      )
    )
    let missingExecutor = registry.invoke(descriptorOnly.id, input: [:])

    XCTAssertEqual(cancelled.status, .cancelled)
    XCTAssertEqual(cancelled.error?.code, "cancelled")
    XCTAssertEqual(executions, 0)
    XCTAssertEqual(cancelledHooks, 1)
    XCTAssertEqual(timedOut.status, .timedOut)
    XCTAssertEqual(timedOut.error?.code, "timeout")
    XCTAssertEqual(timeoutHooks, 1)
    XCTAssertEqual(missingExecutor.status, .unavailable)
    XCTAssertEqual(missingExecutor.error?.code, "missing_executor")
  }

  func testAgentNativeToolRegistryInvokeReplaysSuccessfulKeyedResults() throws {
    var executions = 0
    let replayStore = InMemoryAgentNativeToolReplayStore()
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.replay",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )

    func registry() throws -> AgentNativeToolRegistry {
      try AgentNativeToolRegistry(replayStore: replayStore)
        .registerExecutable(AgentNativeToolExecutableDefinition(
          definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
          executor: { _ in
            executions += 1
            return .success(output: ["execution": .int(Int64(executions))])
          }
        ))
    }

    let missingKey = try registry().invoke(descriptor.id, input: ["value": .int(1)])
    let first = try registry().invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let replay = try registry().invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )
    let conflict = try registry().invoke(
      descriptor.id,
      input: ["value": .int(2)],
      context: AgentNativeToolInvocationContext(invocationId: "third", idempotencyKey: "request-1")
    )

    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(first.output, replay.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.originalInvocationId, "first")
    XCTAssertEqual(replay.receipt.invocationId, "second")
    XCTAssertEqual(conflict.status, .rejected)
    XCTAssertEqual(conflict.error?.code, "idempotency_key_conflict")
  }

  func testAgentActionNativeToolExecutorRunsLegacyExecutorThroughRegistry() throws {
    var capturedAction: AgentAction?
    var capturedScreen: AgentScreenContext?
    let descriptor = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.tap),
      risk: .medium
    )
    let delegate = TestAgentActionExecutor { action, screen in
      capturedAction = action
      capturedScreen = screen
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Tapped",
        metadata: ["screen": screen.pageTitle]
      )
    }
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentActionNativeToolExecutor.executableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "legacy.agent_action",
          provenanceMetadata: ["adapter": "AgentActionExecutor"]
        ),
        delegate: delegate,
        kind: .tap,
        screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Settings") }
      ))
    let legacy = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .medium,
      status: .proposed,
      description: "Tap Wi-Fi",
      parameters: ["bounds": "[0,0][10,10]"]
    )
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(legacy, toolId: descriptor.id)

    let nativeResult = registry.invoke(call.toolId, input: call.input, context: call.context)
    let roundTripped = AgentNativeToolAgentActionAdapter.toAgentActionResult(nativeResult, actionId: legacy.id)

    XCTAssertTrue(nativeResult.toJson(), nativeResult.isSuccess)
    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertEqual(capturedAction?.id, "legacy-9")
    XCTAssertEqual(capturedAction?.kind, .tap)
    XCTAssertEqual(capturedAction?.target, "Wi-Fi")
    XCTAssertEqual(capturedAction?.parameters["bounds"], "[0,0][10,10]")
    XCTAssertTrue(capturedAction?.requiresConfirmation == true)
    XCTAssertEqual(capturedScreen?.pageTitle, "Settings")
    XCTAssertEqual(nativeResult.provenance.legacyAgentActionId, "legacy-9")
    XCTAssertEqual(nativeResult.provenance.executorId, "legacy.agent_action")
    XCTAssertTrue(roundTripped.success)
    XCTAssertEqual(roundTripped.metadata["native_tool_id"], descriptor.id)
    XCTAssertEqual(roundTripped.metadata["native_receipt_id"], "legacy-9")
  }

  func testAgentPhoneNativeToolCatalogBuildsExecutableActionDefinitions() throws {
    var captured: [AgentAction] = []
    let delegate = TestAgentActionExecutor { action, _ in
      captured.append(action)
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Executed \(action.kind.rawValue)"
      )
    }
    let executables = AgentPhoneNativeToolCatalog.actionExecutableDefinitions(
      delegate: delegate,
      screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Browser") },
      capabilityStatuses: readyPhoneCapabilityStatuses()
    )
    let openURL = try XCTUnwrap(
      executables.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.openURL) }
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(executables)
    let context = AgentNativeToolInvocationContext(
      invocationId: "open-url",
      grantedPermissions: Set(openURL.descriptor.requiredPermissions.filter { $0.required }.map(\.id)),
      grantedConsents: Set(openURL.descriptor.requiredConsents.filter { $0.required }.map(\.id))
    )

    let result = registry.invoke(
      openURL.id,
      input: [
        "target": .string("Safari"),
        "url": .string("https://signalasi.com"),
        "parameters": .object(["url": .string("https://signalasi.com")])
      ],
      context: context
    )

    XCTAssertEqual(Set(executables.map(\.id)), Set(AgentPhoneNativeToolCatalog.supportedActionKinds.map {
      AgentNativeToolAgentActionAdapter.defaultToolId($0)
    }))
    XCTAssertEqual(registry.ids(), Set(executables.map(\.id)))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(captured.first?.kind, .openURL)
    XCTAssertEqual(captured.first?.target, "Safari")
    XCTAssertEqual(captured.first?.parameters["url"], "https://signalasi.com")
    XCTAssertEqual(result.provenance.executorId, AgentPhoneNativeToolCatalog.actionExecutorId)
  }

  func testAgentActionNativeToolExecutorMapsLegacyFailuresToNativeFailures() throws {
    let descriptor = try nativeToolDescriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: false, message: "Missed target")
    }
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentActionNativeToolExecutor.executableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "legacy.agent_action"),
        delegate: delegate,
        kind: .tap,
        screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Settings") }
      ))
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(AgentAction(
      id: "legacy-failed",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap Wi-Fi"
    ))

    let result = registry.invoke(call.toolId, input: call.input, context: call.context)

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, "agent_action_failed")
    XCTAssertEqual(result.output["action_id"], .string("legacy-failed"))
  }

}
