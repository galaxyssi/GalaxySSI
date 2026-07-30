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

}
