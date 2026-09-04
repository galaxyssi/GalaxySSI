import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testModelSelectedRoutingUsesExplicitOfficialDocumentationSource() {
    let selection = AgentIOSWebIntelligenceQueryRouting.select(
      query: "Android app process lifecycle and WorkManager official documentation",
      requestedVerticals: [.docs],
      requestedEngineIds: ["android_developers"]
    )

    XCTAssertEqual(selection.inferredVerticals, [])
    XCTAssertEqual(selection.selected.first?.id, "android_developers")
    XCTAssertEqual(selection.strategy, "model_selected_topics")
  }

  func testUnscopedRoutingDoesNotGuessSourcesFromQueryText() {
    let selection = AgentIOSWebIntelligenceQueryRouting.select(
      query: "Android official documentation",
      requestedVerticals: [],
      requestedEngineIds: []
    )

    XCTAssertTrue(selection.inferredVerticals.isEmpty)
    XCTAssertTrue(selection.selected.isEmpty)
    XCTAssertEqual(selection.strategy, "broad_unscoped")
  }

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
              "query": input["query"] ?? .string("GalaxySSI"),
              "results": .array([.object(["title": .string("GalaxySSI"), "url": .string("https://galaxyssi.example")])]),
              "result_count": .int(1)
            ]) { current, _ in current }
          )
        case .webOpen, .browserRender:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "text": .string("GalaxySSI page"),
              "html_sha256": .string(sha),
              "render_mode": .string(operation == .browserRender ? "isolated_static_dom" : "bounded_http")
            ]) { current, _ in current }
          )
        case .browserSessionCreate, .browserSessionNavigate:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "browser_id": .string("browser-session-0001"),
              "current_url": .string("https://galaxyssi.example"),
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
            "requested_url": .string("https://galaxyssi.example"),
            "final_url": .string("https://galaxyssi.example"),
            "redirect_chain": .array([]),
            "dns_resolution": .array([
              .object([
                "host": .string("galaxyssi.example"),
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
      input: ["query": .string("GalaxySSI"), "max_results": .int(1)],
      context: networkContext
    )
    let session = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.browserSessionCreate,
      input: ["url": .string("https://galaxyssi.example")],
      context: sessionContext
    )
    let invalidURL = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webFetch,
      input: ["url": .string("http://galaxyssi.example")],
      context: networkContext
    )
    let missingDownloadKey = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webDownload,
      input: [
        "url": .string("https://galaxyssi.example/file.txt"),
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
        "url": .string("https://galaxyssi.example/file.txt"),
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
      input: ["url": .string("https://galaxyssi.example")],
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

  func testAgentIOSURLSessionWebMediaProviderExecutesBoundedHTTPSTools() throws {
    final class FakeURLSessionWebTransport: AgentIOSURLSessionWebTransporting {
      var requests: [AgentIOSURLSessionWebRequest] = []
      var responses: [AgentIOSURLSessionWebResponse]

      init(responses: [AgentIOSURLSessionWebResponse]) {
        self.responses = responses
      }

      func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
        requests.append(request)
        guard !responses.isEmpty else {
          throw AgentIOSURLSessionWebError.transportFailed("missing fake response")
        }
        return responses.removeFirst()
      }
    }

    func response(
      statusCode: Int,
      url: String,
      headers: [String: String],
      body: Data = Data()
    ) -> AgentIOSURLSessionWebResponse {
      AgentIOSURLSessionWebResponse(
        statusCode: statusCode,
        finalURL: URL(string: url)!,
        headers: headers,
        body: body,
        retrievedAtEpochMillis: 1_100
      )
    }

    let textBody = Data("hello".utf8)
    let jsonBody = Data("{\"ok\":true}".utf8)
    let htmlBody = Data("<html><body><h1>Hello&nbsp;ASI</h1><script>secret()</script><p>Done</p></body></html>".utf8)
    let searchBody = Data("""
      <html><body>
      <li class='b_algo'><h2><a href='https://docs.galaxyssi.example'>GalaxySSI Docs</a></h2></li>
      <a class='result__a' href='/l/?uddg=https%3A%2F%2Fblog.galaxyssi.example'>GalaxySSI Blog</a>
      </body></html>
      """.utf8)
    let transport = FakeURLSessionWebTransport(responses: [
      response(
        statusCode: 200,
        url: "https://cn.bing.com/search?q=GalaxySSI&count=2",
        headers: ["content-type": "text/html; charset=utf-8"],
        body: searchBody
      ),
      response(
        statusCode: 302,
        url: "https://galaxyssi.example/start",
        headers: ["location": "/final"]
      ),
      response(
        statusCode: 200,
        url: "https://galaxyssi.example/final",
        headers: [
          "content-type": "text/plain; charset=utf-8",
          "content-length": "5",
          "etag": "abc"
        ],
        body: textBody
      ),
      response(
        statusCode: 200,
        url: "https://galaxyssi.example/info",
        headers: [
          "content-type": "text/html; charset=utf-8",
          "content-length": "12"
        ]
      ),
      response(
        statusCode: 200,
        url: "https://galaxyssi.example/api",
        headers: [
          "content-type": "application/json; charset=utf-8",
          "content-length": "11"
        ],
        body: jsonBody
      ),
      response(
        statusCode: 200,
        url: "https://galaxyssi.example/page",
        headers: ["content-type": "text/html; charset=utf-8"],
        body: htmlBody
      )
    ])
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, nowMillis: { 1_000 })
    let definitions = AgentIOSWebMediaNativeToolCatalog.definitions()
    let defaultFetch = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebMediaNativeToolCatalog.webFetch })
    let defaultSearch = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebMediaNativeToolCatalog.webSearch })
    XCTAssertEqual(defaultFetch.descriptor.availability.status, .available)
    XCTAssertEqual(defaultFetch.provenanceMetadata["network_policy"], "public_https_urlsession_revalidated_v1")
    XCTAssertEqual(defaultFetch.provenanceMetadata["redirect_policy"], "manual_revalidate_each_hop")
    XCTAssertEqual(defaultSearch.descriptor.availability.status, .available)

    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]
    )
    let hooks = AgentNativeToolInvocationHooks(nowMillis: { 1_000 })

    let search = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("GalaxySSI"), "max_results": .int(2)],
      context: context,
      hooks: hooks
    )
    let fetched = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webFetch,
      input: ["url": .string("https://galaxyssi.example/start"), "max_bytes": .int(1_024)],
      context: context,
      hooks: hooks
    )
    let head = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webHead,
      input: ["url": .string("https://galaxyssi.example/info")],
      context: context,
      hooks: hooks
    )
    let httpGet = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.httpRequest,
      input: [
        "url": .string("https://galaxyssi.example/api"),
        "method": .string("GET")
      ],
      context: context,
      hooks: hooks
    )
    let opened = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webOpen,
      input: ["url": .string("https://galaxyssi.example/page")],
      context: context,
      hooks: hooks
    )

    XCTAssertTrue(search.isSuccess)
    XCTAssertEqual(search.output["query"], .string("GalaxySSI"))
    XCTAssertEqual(search.output["result_count"], .int(2))
    XCTAssertEqual(search.metadata["provider"], .string("bing"))
    XCTAssertEqual(search.metadata["fallback_count"], .int(0))
    let searchResults = try XCTUnwrap(search.output["results"]?.arrayValue)
    XCTAssertEqual(searchResults.first?.objectValue?["url"], .string("https://docs.galaxyssi.example"))
    XCTAssertEqual(searchResults.last?.objectValue?["url"], .string("https://blog.galaxyssi.example"))

    XCTAssertTrue(fetched.isSuccess)
    XCTAssertEqual(fetched.output["method"], .string("get"))
    XCTAssertEqual(fetched.output["status_code"], .int(200))
    XCTAssertEqual(fetched.output["content_type"], .string("text/plain"))
    XCTAssertEqual(fetched.output["text"], .string("hello"))
    XCTAssertEqual(fetched.output["charset"], .string("UTF-8"))
    XCTAssertEqual(fetched.output["size_bytes"], .int(5))
    XCTAssertEqual(fetched.output["sha256"], .string(GalaxySSIAttachmentPayloadBuilder.sha256(textBody)))
    XCTAssertEqual(fetched.metadata["network_policy"], .string("public_https_urlsession_revalidated_v1"))
    let source = try XCTUnwrap(fetched.output["source"]?.objectValue)
    let redirects = try XCTUnwrap(source["redirect_chain"]?.arrayValue)
    XCTAssertEqual(redirects.count, 1)
    XCTAssertEqual(redirects.first?.objectValue?["to_url"], .string("https://galaxyssi.example/final"))
    XCTAssertEqual(source["dns_resolution"], .array([]))

    XCTAssertTrue(head.isSuccess)
    XCTAssertEqual(head.output["method"], .string("head"))
    XCTAssertNil(head.output["text"])

    XCTAssertTrue(httpGet.isSuccess)
    XCTAssertEqual(httpGet.output["text"], .string("{\"ok\":true}"))
    XCTAssertEqual(httpGet.metadata["method"], .string("GET"))

    XCTAssertTrue(opened.isSuccess)
    let openedText = try XCTUnwrap(opened.output["text"]?.stringValue)
    XCTAssertTrue(openedText.contains("Hello ASI"))
    XCTAssertFalse(openedText.contains("secret"))
    XCTAssertEqual(opened.output["render_mode"], .string("bounded_http"))
    XCTAssertEqual(opened.metadata["javascript"], .bool(false))
    XCTAssertEqual(
      transport.requests.map(\.method),
      [.get, .get, .get, .head, .get, .get]
    )
    XCTAssertTrue(transport.requests[0].url.absoluteString.hasPrefix("https://cn.bing.com/search?"))
    XCTAssertEqual(transport.requests[2].url.absoluteString, "https://galaxyssi.example/final")
  }

  func testAgentIOSURLSessionWebMediaProviderRejectsNonTextResponses() throws {
    final class FakeURLSessionWebTransport: AgentIOSURLSessionWebTransporting {
      func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
        AgentIOSURLSessionWebResponse(
          statusCode: 200,
          finalURL: request.url,
          headers: ["content-type": "image/png", "content-length": "4"],
          body: Data([0, 1, 2, 3]),
          retrievedAtEpochMillis: 1_100
        )
      }
    }

    let provider = AgentIOSURLSessionWebMediaToolProvider(
      transport: FakeURLSessionWebTransport(),
      nowMillis: { 1_000 }
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    let result = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webFetch,
      input: ["url": .string("https://galaxyssi.example/image.png")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
        grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]
      ),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, "unsupported_content_type")
    XCTAssertEqual(result.error?.details["content_type"], .string("image/png"))
  }

  func testAgentIOSURLSessionWebMediaProviderDownloadsToFileURLDestination() throws {
    final class FakeURLSessionWebTransport: AgentIOSURLSessionWebTransporting {
      var requests: [AgentIOSURLSessionWebRequest] = []
      let body: Data

      init(body: Data) {
        self.body = body
      }

      func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
        requests.append(request)
        return AgentIOSURLSessionWebResponse(
          statusCode: 200,
          finalURL: request.url,
          headers: [
            "content-type": "application/pdf",
            "content-length": String(body.count)
          ],
          body: body,
          retrievedAtEpochMillis: 1_100
        )
      }
    }

    let body = Data("%PDF-1.7 GalaxySSI".utf8)
    let transport = FakeURLSessionWebTransport(body: body)
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, nowMillis: { 1_000 })
    let definitions = AgentIOSWebMediaNativeToolCatalog.definitions(provider: provider)
    let downloadDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebMediaNativeToolCatalog.webDownload })
    XCTAssertEqual(downloadDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(downloadDefinition.provenanceMetadata["destination_scope"], "file_url_user_authorized")
    XCTAssertEqual(downloadDefinition.provenanceMetadata["writer_implementation"], "galaxyssi.ios.file_url_download_writer")

    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let destination = directory.appendingPathComponent("galaxyssi-web-download-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: destination) }
    let context = AgentNativeToolInvocationContext(
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
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )

    let result = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webDownload,
      input: [
        "url": .string("https://galaxyssi.example/file.pdf"),
        "destination_content_uri": .string(destination.absoluteString)
      ],
      context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )
    let unsupported = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.fileDownload,
      input: [
        "url": .string("https://galaxyssi.example/file.pdf"),
        "destination_content_uri": .string("content://downloads/file.pdf")
      ],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "download-2",
        grantedPermissions: [
          AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
          AgentIOSWebMediaNativeToolCatalog.contentUriPermission
        ],
        grantedConsents: [
          AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
          AgentIOSWebMediaNativeToolCatalog.webDownloadConsent,
          AgentIOSWebMediaNativeToolCatalog.contentUriWriteConsent
        ]
      ),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["destination_content_uri"], .string(destination.absoluteString))
    XCTAssertEqual(result.output["size_bytes"], .int(Int64(body.count)))
    XCTAssertEqual(result.output["sha256"], .string(GalaxySSIAttachmentPayloadBuilder.sha256(body)))
    XCTAssertEqual(result.metadata["writer_implementation"], .string("galaxyssi.ios.file_url_download_writer"))
    XCTAssertEqual(result.metadata["auto_execute"], .bool(false))
    let writtenBody = try XCTUnwrap(FileManager.default.contents(atPath: destination.path))
    XCTAssertEqual(writtenBody, body)
    XCTAssertEqual(unsupported.status, .failed)
    XCTAssertEqual(unsupported.error?.code, "unsupported_destination_content_uri")
    XCTAssertEqual(transport.requests.count, 1)
  }

  func testAgentIOSURLSessionWebMediaProviderRecognizesOCRContent() throws {
    final class FakeContentReader: AgentIOSWebMediaContentReading {
      var implementationId = "fake.file_reader"
      var capturedContentURI = ""
      var capturedMaxBytes: Int64 = 0

      func read(contentURI: String, maxBytes: Int64) throws -> AgentIOSWebMediaContent {
        capturedContentURI = contentURI
        capturedMaxBytes = maxBytes
        return AgentIOSWebMediaContent(
          contentURI: contentURI,
          contentType: "image/png",
          displayName: "capture.png",
          data: Data("fake-image".utf8)
        )
      }
    }

    final class FakeOCRRecognizer: AgentIOSWebMediaOCRRecognizing {
      var implementationId = "fake.vision_ocr"
      var availability: AgentNativeToolAvailability = .available
      var capturedRequest: AgentIOSWebMediaOCRRequest?
      var capturedContentType = ""

      func recognize(
        content: AgentIOSWebMediaContent,
        request: AgentIOSWebMediaOCRRequest
      ) throws -> AgentIOSWebMediaOCRResult {
        capturedContentType = content.contentType
        capturedRequest = request
        return AgentIOSWebMediaOCRResult(
          text: "Invoice Total",
          lines: [
            AgentIOSWebMediaOCRLine(
              text: "Invoice Total",
              left: 10,
              top: 20,
              right: 210,
              bottom: 58,
              languageTag: "en",
              blockIndex: 0,
              lineIndex: 0
            )
          ],
          blocks: [
            AgentIOSWebMediaOCRBlock(
              text: "Invoice Total",
              left: 10,
              top: 20,
              right: 210,
              bottom: 58,
              lineCount: 1
            )
          ],
          width: 640,
          height: 480,
          languageTags: ["en"],
          layoutMode: "vision_text_observations",
          qualityScore: 0.92,
          warnings: []
        )
      }
    }

    let reader = FakeContentReader()
    let recognizer = FakeOCRRecognizer()
    let provider = AgentIOSURLSessionWebMediaToolProvider(
      ocrProcessor: AgentIOSWebMediaOCRPipeline(
        contentReader: reader,
        recognizer: recognizer,
        nowMillis: { 1_200 }
      ),
      nowMillis: { 1_000 }
    )
    let definitions = AgentIOSWebMediaNativeToolCatalog.definitions(provider: provider)
    let ocrDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebMediaNativeToolCatalog.ocrRecognizeContent })
    XCTAssertEqual(ocrDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(ocrDefinition.provenanceMetadata["implementation"], "fake.vision_ocr")
    XCTAssertEqual(ocrDefinition.provenanceMetadata["content_reader_implementation"], "fake.file_reader")
    XCTAssertEqual(ocrDefinition.provenanceMetadata["recognition"], "vision_bounded_ocr")

    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.contentUriReadConsent]
    )
    let result = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.ocrRecognizeContent,
      input: [
        "content_uri": .string("file:///selected/capture.png"),
        "source_kind": .string("screenshot")
      ],
      context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["text"], .string("Invoice Total"))
    XCTAssertEqual(result.output["content_uri"], .string("file:///selected/capture.png"))
    XCTAssertEqual(result.output["source_kind"], .string("screenshot"))
    XCTAssertEqual(result.output["script_hint"], .string("auto"))
    XCTAssertEqual(result.output["observed_at_epoch_ms"], .int(1_200))
    XCTAssertEqual(result.output["width"], .int(640))
    XCTAssertEqual(result.output["height"], .int(480))
    XCTAssertEqual(result.output["layout_mode"], .string("sparse"))
    let quality = try XCTUnwrap(doubleValue(result.output["quality_score"]))
    XCTAssertGreaterThan(quality, 0.80)
    XCTAssertLessThan(quality, 0.90)
    XCTAssertEqual(result.output["warnings"]?.arrayValue, [.string("low_resolution")])
    let lines = try XCTUnwrap(result.output["lines"]?.arrayValue)
    XCTAssertEqual(lines.first?.objectValue?["text"], .string("Invoice Total"))
    let blocks = try XCTUnwrap(result.output["blocks"]?.arrayValue)
    XCTAssertEqual(blocks.first?.objectValue?["line_count"], .int(1))
    XCTAssertEqual(result.metadata["ocr_implementation"], .string("fake.vision_ocr"))
    XCTAssertEqual(result.metadata["content_reader_implementation"], .string("fake.file_reader"))
    XCTAssertEqual(reader.capturedContentURI, "file:///selected/capture.png")
    XCTAssertEqual(reader.capturedMaxBytes, AgentIOSWebMediaNativeToolCatalog.maxOcrSourceBytes)
    XCTAssertEqual(recognizer.capturedContentType, "image/png")
    XCTAssertEqual(recognizer.capturedRequest?.scriptHint, "auto")
  }

  func testAgentIOSURLSessionWebMediaProviderRejectsUnsupportedOCRContentURI() throws {
    final class FakeOCRRecognizer: AgentIOSWebMediaOCRRecognizing {
      var implementationId = "fake.vision_ocr"
      var availability: AgentNativeToolAvailability = .available

      func recognize(
        content: AgentIOSWebMediaContent,
        request: AgentIOSWebMediaOCRRequest
      ) throws -> AgentIOSWebMediaOCRResult {
        throw AgentIOSWebMediaOCRError.ocrEmptyResult
      }
    }

    let provider = AgentIOSURLSessionWebMediaToolProvider(
      ocrProcessor: AgentIOSWebMediaOCRPipeline(
        contentReader: AgentIOSFileWebMediaContentReader(),
        recognizer: FakeOCRRecognizer(),
        nowMillis: { 1_200 }
      ),
      nowMillis: { 1_000 }
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    let result = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.ocrRecognizeContent,
      input: [
        "content_uri": .string("content://captures/1"),
        "source_kind": .string("image")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.contentUriPermission],
        grantedConsents: [AgentIOSWebMediaNativeToolCatalog.contentUriReadConsent]
      ),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, "unsupported_content_uri")
  }

  func testAgentIOSURLSessionWebMediaProviderManagesBrowserSessions() throws {
    final class FakeURLSessionWebTransport: AgentIOSURLSessionWebTransporting {
      var requests: [AgentIOSURLSessionWebRequest] = []
      var responses: [AgentIOSURLSessionWebResponse]

      init(responses: [AgentIOSURLSessionWebResponse]) {
        self.responses = responses
      }

      func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
        requests.append(request)
        guard !responses.isEmpty else {
          throw AgentIOSURLSessionWebError.transportFailed("missing fake response")
        }
        return responses.removeFirst()
      }
    }

    func response(url: String, body: String) -> AgentIOSURLSessionWebResponse {
      AgentIOSURLSessionWebResponse(
        statusCode: 200,
        finalURL: URL(string: url)!,
        headers: ["content-type": "text/html; charset=utf-8"],
        body: Data(body.utf8),
        retrievedAtEpochMillis: 1_100
      )
    }

    let transport = FakeURLSessionWebTransport(responses: [
      response(url: "https://galaxyssi.example/first", body: "<h1>First</h1><script>hidden()</script>"),
      response(url: "https://galaxyssi.example/second", body: "<h1>Second</h1>")
    ])
    let provider = AgentIOSURLSessionWebMediaToolProvider(
      transport: transport,
      browserSessions: AgentIOSURLSessionBrowserSessionStore(),
      nowMillis: { 1_000 }
    )
    let definitions = AgentIOSWebMediaNativeToolCatalog.definitions(provider: provider)
    let createDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebMediaNativeToolCatalog.browserSessionCreate })
    XCTAssertEqual(createDefinition.descriptor.availability.status, .available)

    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      sessionId: "ios-session",
      conversationId: "conversation-1",
      callerId: "agent-a",
      grantedPermissions: [
        AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
        AgentIOSWebMediaNativeToolCatalog.browserSessionPermission
      ],
      grantedConsents: [
        AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
        AgentIOSWebMediaNativeToolCatalog.browserSessionConsent
      ]
    )
    let hooks = AgentNativeToolInvocationHooks(nowMillis: { 1_000 })

    let created = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.browserSessionCreate,
      input: ["url": .string("https://galaxyssi.example/first")],
      context: context,
      hooks: hooks
    )
    let browserId = try XCTUnwrap(created.output["browser_id"]?.stringValue)
    let navigated = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.browserSessionNavigate,
      input: [
        "browser_id": .string(browserId),
        "url": .string("https://galaxyssi.example/second")
      ],
      context: context,
      hooks: hooks
    )
    let closed = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.browserSessionClose,
      input: ["browser_id": .string(browserId)],
      context: context,
      hooks: hooks
    )
    let afterClose = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.browserSessionNavigate,
      input: [
        "browser_id": .string(browserId),
        "url": .string("https://galaxyssi.example/third")
      ],
      context: context,
      hooks: hooks
    )

    XCTAssertTrue(created.isSuccess)
    XCTAssertTrue(browserId.hasPrefix("browser_session-"))
    XCTAssertEqual(created.output["current_url"], .string("https://galaxyssi.example/first"))
    XCTAssertEqual(created.output["history_count"], .int(1))
    XCTAssertEqual(created.output["text"]?.stringValue?.contains("First"), true)
    XCTAssertEqual(created.output["text"]?.stringValue?.contains("hidden"), false)
    XCTAssertEqual(created.metadata["tool_handle_contract"], .string("galaxyssi.tool-handle/1.0"))
    XCTAssertEqual(created.metadata["network_policy"], .string("public_https_urlsession_revalidated_v1"))

    XCTAssertTrue(navigated.isSuccess)
    XCTAssertEqual(navigated.output["current_url"], .string("https://galaxyssi.example/second"))
    XCTAssertEqual(navigated.output["history_count"], .int(2))
    XCTAssertEqual(navigated.output["text"]?.stringValue?.contains("Second"), true)

    XCTAssertTrue(closed.isSuccess)
    XCTAssertEqual(closed.output["browser_id"], .string(browserId))
    XCTAssertEqual(closed.output["closed"], .bool(true))
    XCTAssertEqual(afterClose.status, .failed)
    XCTAssertEqual(afterClose.error?.code, "tool_handle_not_found")
    XCTAssertEqual(transport.requests.count, 2)
  }

  private func doubleValue(_ value: AgentMcpJSONValue?) -> Double? {
    guard case .double(let double) = value else {
      return nil
    }
    return double
  }
}
