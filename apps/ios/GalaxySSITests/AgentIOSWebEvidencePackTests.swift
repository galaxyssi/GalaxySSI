import XCTest
@testable import GalaxySSI

private func imagePresentationFixture() -> AgentMcpJSONObject {
  ["status": .string("completed"), "query": .string("Galaxy photos"),
   "results": .array([.object(["url": .string("https://source.test/page"), "title": .string("Galaxy"),
    "vertical": .string("image"), "excerpt": .string(String(repeating: "Original source summary. ", count: 30)),
    "images": .array([.object(["url": .string("https://images.test/original.jpg"),
      "thumbnail_url": .string("https://images.test/preview.jpg"), "width": .int(2000), "height": .int(1000),
      "title": .string("Galaxy photo")])])])])]
}

private final class ImagePresentationIntelligenceFixture: AgentIOSWebIntelligenceToolProviding {
  var implementationId = "fixture.image-presentation"
  var engineCatalogSize = 1
  var rankerId = "fixture"
  var inputs: [AgentMcpJSONObject] = []
  func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebIntelligenceOperation, input: AgentMcpJSONObject,
              invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    inputs.append(input)
    return .success(output: imagePresentationFixture())
  }
}

private struct ImagePresentationRawFixture: AgentIOSWebMediaToolProviding {
  var implementationId = "fixture.raw-image-presentation"
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject,
              invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    .success(output: imagePresentationFixture())
  }
}

final class AgentIOSWebEvidencePackTests: XCTestCase {
  func testImagePresentationUsesSecurePreviewAndRetainsSourceIdentity() throws {
    let output = imagePresentationFixture()
    let base = AgentIOSWebEvidencePack.build(query: "pictures", status: "completed", documents: [],
      results: output["results"]!.arrayValue!.compactMap(\.objectValue), receipts: [], generatedAtMillis: 1)
    let prepared = CloudImageSearchEvidence.prepare(output.merging(["evidence_pack": .object(base)]) { _, next in next })
    let pack = try XCTUnwrap(prepared["evidence_pack"]?.objectValue)
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    let image = try XCTUnwrap(item["images"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(image["url"], .string("https://images.test/preview.jpg"))
    XCTAssertEqual(image["original_url"], .string("https://images.test/original.jpg"))
    XCTAssertEqual(image["display_kind"], .string("search_preview"))
    XCTAssertNil(image["width"])
    XCTAssertNil(image["height"])
    XCTAssertEqual(pack["verification"]?.objectValue?["citation_manifest_sha256"], base["verification"]?.objectValue?["citation_manifest_sha256"])
    XCTAssertEqual(item["citation_id"], base["items"]?.arrayValue?.first?.objectValue?["citation_id"])
    XCTAssertLessThanOrEqual(item.string("excerpt").count, 240)
    XCTAssertEqual(item["media_evidence_level"], .string("discovered_url_not_visually_verified"))
    XCTAssertEqual(CloudImageSearchEvidence.prepare(prepared), prepared)
  }

  func testImagePresentationRejectsInsecurePreviewsAndCannotRepairInvalidSourceIdentity() throws {
    for preview in ["http://images.test/small.jpg", "file:///private/image.jpg", "https://user:secret@images.test/a.jpg",
      "https://images.test/" + String(repeating: "x", count: 4100)] {
      var result = imagePresentationFixture()["results"]!.arrayValue!.first!.objectValue!
      result["images"] = .array([.object(["url": .string("https://images.test/original.jpg"),
        "thumbnail_url": .string(preview), "width": .int(2000), "height": .int(1000)])])
      let base = AgentIOSWebEvidencePack.build(query: "images", status: "completed", documents: [], results: [result], receipts: [], generatedAtMillis: 1)
      let prepared = CloudImageSearchEvidence.prepare(["evidence_pack": .object(base)])
      let image = try XCTUnwrap(prepared["evidence_pack"]?.objectValue?["items"]?.arrayValue?.first?.objectValue?["images"]?.arrayValue?.first?.objectValue)
      XCTAssertEqual(image["url"], .string("https://images.test/original.jpg"))
      XCTAssertEqual(image["width"], .int(2000))
      XCTAssertNil(image["display_kind"])
    }
    var pack = AgentIOSWebEvidencePack.build(query: "images", status: "completed", documents: [],
      results: imagePresentationFixture()["results"]!.arrayValue!.compactMap(\.objectValue), receipts: [], generatedAtMillis: 1)
    var item = pack["items"]!.arrayValue!.first!.objectValue!
    item["citation_id"] = .string(String(repeating: "0", count: 24))
    pack["items"] = .array([.object(item)])
    let prepared = CloudImageSearchEvidence.prepare(["evidence_pack": .object(pack)])
    XCTAssertEqual(prepared["evidence_pack"]?.objectValue?["verification"]?.objectValue?["status"], .string("failed"))
  }

  func testBoundedImagePresentationKeepsWholeURLsAndVerifiableRemainingCandidates() throws {
    let results: [AgentMcpJSONObject] = (0..<12).map { index in
      ["url": .string("https://source\(index).test/" + String(repeating: "s", count: 1500)),
       "title": .string("Picture source"), "vertical": .string("image"), "excerpt": .string("Source discovery"),
       "images": .array((0..<4).map { image in .object([
        "url": .string("https://images.test/\(index)/\(image)/" + String(repeating: "o", count: 1800)),
        "thumbnail_url": .string("https://images.test/\(index)/\(image)/" + String(repeating: "p", count: 1000)),
        "title": .string("Picture"), "width": .int(2000), "height": .int(1000)]) })]
    }
    let output = AgentIOSWebEvidencePack.attach(to: ["operation": .string("search"), "status": .string("completed"),
      "results": .array(results.map(AgentMcpJSONValue.object))], generatedAtMillis: 1)
    let original = output["evidence_pack"]!.objectValue!
    let urls = Set(original["items"]!.arrayValue!.flatMap { $0.objectValue?["images"]?.arrayValue ?? [] }.compactMap { $0.objectValue?.string("url") })
    let encoded = CloudWebGrounding.boundedModelJson(output)
    XCTAssertLessThanOrEqual(encoded.count, 24_000)
    let root = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(encoded.utf8))
    let pack = try XCTUnwrap(root["evidence_pack"]?.objectValue)
    XCTAssertEqual(pack["presentation_partial"], .bool(true))
    XCTAssertGreaterThan(pack["presentation_omitted_images"]?.intValue ?? 0, 0)
    XCTAssertGreaterThan(pack["presentation_image_count"]?.intValue ?? 0, 0)
    XCTAssertEqual(pack["verification"]?.objectValue?["status"], .string("verified"))
    for value in pack["items"]?.arrayValue ?? [] {
      for image in value.objectValue?["images"]?.arrayValue ?? [] {
        XCTAssertTrue(urls.contains(image.objectValue?.string("url") ?? ""))
      }
    }
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    let image = try XCTUnwrap(item["images"]?.arrayValue?.first?.objectValue)
    let reply = "![photo](<\(image.string("url"))>) [source](<\(item.string("url"))>)"
    XCTAssertTrue(AgentIOSWebEvidenceVerification.validateAnswer(reply, packs: [pack]).valid)
    XCTAssertFalse(AgentIOSWebEvidenceVerification.validateAnswer("[false source](<\(image.string("url"))>)", packs: [pack]).valid)
  }

  func testImageAliasIsRegisteredOnceNormalizedAndCoveredByResearchBudget() {
    let names = CloudWebGrounding.openAITools().compactMap { $0["function"]?.objectValue?.string("name") }
    XCTAssertEqual(names.filter { $0 == "web_image_search" }.count, 1)
    let supervised = CloudSupervisedResearch.toolDefinitions().map { $0.string("name") }
    XCTAssertEqual(supervised.filter { $0 == "web_image_search" }.count, 1)
    XCTAssertEqual(Set(supervised).count, supervised.count)
    XCTAssertEqual(CloudWebGrounding.operation(forToolName: "web_image_search"), .search)
    XCTAssertTrue(CloudResearchRuntimeBudget.isRetrievalTool("web_image_search"))
    let normalized = CloudWebGrounding.normalizeArguments(name: " WEB_IMAGE_SEARCH ",
      arguments: ["query": .string("Galaxy photos"), "max_results": .int(1), "read_pages": .bool(true)])
    XCTAssertEqual(normalized["limit"], .int(6))
    XCTAssertEqual(normalized["verticals"], .array([.string("image")]))
    XCTAssertEqual(normalized["profile"], .string("fast"))
    XCTAssertEqual(normalized["engine_fanout"], .int(3))
    XCTAssertNil(normalized["read_pages"])
    XCTAssertEqual(CloudWebGrounding.normalizeArguments(name: "web_image_search", arguments: ["max_results": .int(Int64.max)])["limit"], .int(12))
  }

  func testCloudImageAliasReachesNativeRegistryAndReturnsPreparedPreviewEvidence() throws {
    let provider = ImagePresentationIntelligenceFixture()
    let encoded = CloudWebGrounding.executeTool(provider: provider, name: "web_image_search",
      arguments: ["query": .string("Galaxy photos"), "max_results": .int(2)],
      context: AgentNativeToolInvocationContext(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]))
    let root = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(encoded.utf8))
    let pack = try XCTUnwrap(root["evidence_pack"]?.objectValue)
    XCTAssertEqual(provider.inputs.count, 1)
    XCTAssertEqual(provider.inputs.first?["verticals"], .array([.string("image")]))
    XCTAssertEqual(pack["presentation"], .string("compact_image_candidates"))
    XCTAssertNotNil(pack["synthesis_contract"]?.objectValue?["image_response"])
    XCTAssertEqual(pack["items"]?.arrayValue?.first?.objectValue?["images"]?.arrayValue?.first?.objectValue?["url"], .string("https://images.test/preview.jpg"))
    XCTAssertEqual(pack["verification"]?.objectValue?["status"], .string("verified"))
  }

  func testRawNativeImageSearchAddsPreviewPackWithoutChangingOperation() throws {
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: ImagePresentationRawFixture()))
    let result = registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("Galaxy photos"), "verticals": .array([.string("image")])],
      context: AgentNativeToolInvocationContext(grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
        grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["operation"], .string(AgentIOSWebMediaOperation.webSearch.rawValue))
    let pack = try XCTUnwrap(result.output["evidence_pack"]?.objectValue)
    XCTAssertEqual(pack["presentation"], .string("compact_image_candidates"))
    XCTAssertEqual(pack["items"]?.arrayValue?.first?.objectValue?["images"]?.arrayValue?.first?.objectValue?["url"], .string("https://images.test/preview.jpg"))
  }

  func testImagesSurviveRetrievedBodyPreferenceAndAggregateOnlyTheirSourcePage() throws {
    let page = "https://source.test/article"
    let first: AgentMcpJSONObject = ["url": .string("https://images.test/first.jpg"),
      "thumbnail_url": .string("https://images.test/first-small.jpg"), "width": .int(640)]
    let second: AgentMcpJSONObject = ["url": .string("https://images.test/second.jpg"), "height": .int(480)]
    let pack = AgentIOSWebEvidencePack.build(query: "pictures", status: "completed",
      documents: [["url": .string(page), "content": .string("Retrieved source body")]],
      results: [["url": .string(page), "lead_image_url": first["url"]!, "images": .array([.object(first)])],
        ["url": .string(page), "images": .array([.object(first), .object(second),
          .object(["url": .string("file:///private/image.jpg")]),
          .object(["url": .string("https://user:pass@images.test/private.jpg")])])],
        ["url": .string("https://other.test/article"), "images": .array([.object(["url": .string("https://images.test/other.jpg")])])]],
      receipts: [], generatedAtMillis: 1)
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    let images = try XCTUnwrap(item["images"]?.arrayValue)
    XCTAssertEqual(item["source_kind"], .string("document"))
    XCTAssertEqual(item["media_evidence_level"], .string("discovered_url_not_visually_verified"))
    XCTAssertEqual(images.count, 2)
    XCTAssertEqual(images.first?.objectValue?["width"], .int(640))
    XCTAssertEqual(images.last?.objectValue?["url"], second["url"])
    XCTAssertEqual(item["lead_image_url"], first["url"])
    XCTAssertEqual(images.first?.objectValue?["source_url"], .string(page))
  }

  func testMediaURLsAreBoundedWebCandidatesNotLocalOrCredentialedLocations() {
    for value in ["file:///private/image.jpg", "data:image/png;base64,AAA", "https://user:pass@example.test/a.jpg",
                  "https://example.test/" + String(repeating: "a", count: 4100)] {
      XCTAssertNil(AgentIOSWebEvidencePack.mediaURL(value), value)
    }
    XCTAssertEqual(AgentIOSWebEvidencePack.mediaURL("https://images.test/a.jpg?token=opaque"),
      "https://images.test/a.jpg?token=opaque")
  }

  func testAttachingFetchCreatesCompactUnifiedEvidencePack() throws {
    let content = String(repeating: "Retrieved article evidence for unified model synthesis. ", count: 80)
    let hash = String(repeating: "a", count: 64)
    let attached = AgentIOSWebEvidencePack.attach(
      to: [
        "protocol": .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId),
        "operation": .string("fetch"),
        "status": .string("completed"),
        "url": .string("https://www.example.test/report?utm_source=test"),
        "title": .string("Unified report"),
        "text": .string(content),
        "content_type": .string("text/html"),
        "content_sha256": .string(hash),
        "source_receipts": .array([])
      ],
      generatedAtMillis: 123
    )

    let pack = try XCTUnwrap(attached["evidence_pack"]?.objectValue)
    let document = try XCTUnwrap(attached["documents"]?.arrayValue?.first?.objectValue)
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)

    XCTAssertEqual(pack["protocol"], .string(AgentIOSWebEvidencePack.protocolId))
    XCTAssertNil(attached["text"])
    XCTAssertNil(document["content"])
    XCTAssertEqual(item["source_kind"], .string("document"))
    XCTAssertEqual(item["evidence_level"], .string("retrieved_body"))
    XCTAssertEqual(item["url"], .string("https://example.test/report"))
    XCTAssertEqual(item["content_sha256"], .string(hash))
    XCTAssertTrue((item["excerpt"]?.stringValue ?? "").contains("Retrieved article evidence"))
  }

  func testRetrievedBodyWinsOverDuplicateDiscoveryResult() throws {
    let pack = AgentIOSWebEvidencePack.build(
      query: "report",
      status: "completed",
      documents: [[
        "url": .string("https://www.example.test/report?utm_source=search"),
        "title": .string("Retrieved report"),
        "content": .string(String(repeating: "Complete retrieved body with verified details. ", count: 40))
      ]],
      results: [[
        "url": .string("https://example.test/report"),
        "title": .string("Search result"),
        "excerpt": .string("Short discovery snippet")
      ]],
      receipts: [],
      generatedAtMillis: 123
    )

    let items = try XCTUnwrap(pack["items"]?.arrayValue)
    let item = try XCTUnwrap(items.first?.objectValue)
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(item["source_kind"], .string("document"))
    XCTAssertTrue((item["excerpt"]?.stringValue ?? "").hasPrefix("Complete retrieved body"))
  }

  func testCitationMatchesCrossPlatformFixture() throws {
    let pack = AgentIOSWebEvidencePack.build(
      query: "fixture",
      status: "completed",
      documents: [[
        "url": .string("https://www.example.com/a?utm_source=x&b=2&a=1"),
        "title": .string("Fixture"),
        "content": .string("Fixture evidence"),
        "content_sha256": .string(String(repeating: "a", count: 64))
      ]],
      results: [],
      receipts: [],
      generatedAtMillis: 1
    )

    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(item["url"], .string("https://example.com/a?a=1&b=2"))
    XCTAssertEqual(item["citation_id"], .string("2a6252e1a64266545ebcf887"))
  }

  func testModelAuthoredResearchPlanIsBoundedNormalizedAndDeduplicated() {
    let plan = AgentIOSWebResearchPlanCodec.decode(
      primaryQuery: "fallback",
      rawPlan: .array([
        .object([
          "query": .string("  Swift   concurrency updates  "),
          "purpose": .string(" Verify current behavior "),
          "verticals": .array([.string("DOCS"), .string("unsupported")]),
          "categories": .array([.string(" Apple Platforms "), .string("***")]),
          "engines": .array([.string("Engine-One"), .string("bad engine"), .string("engine-one")])
        ]),
        .string("swift concurrency updates")
      ]),
      allowedVerticals: ["general", "docs"]
    )

    XCTAssertEqual(plan.count, 1)
    XCTAssertEqual(plan[0].query, "Swift concurrency updates")
    XCTAssertEqual(plan[0].purpose, "Verify current behavior")
    XCTAssertEqual(plan[0].verticals, ["docs"])
    XCTAssertEqual(plan[0].categories, ["apple platforms"])
    XCTAssertEqual(plan[0].engines, ["engine-one"])
  }

  func testResearchResultsAreMergedFairlyAcrossQueries() {
    let merged = AgentIOSWebResearchPlanCodec.roundRobinResults([
      [
        ["url": .string("https://first.test/1")],
        ["url": .string("https://first.test/2")]
      ],
      [
        ["url": .string("https://second.test/1")],
        ["url": .string("https://first.test/1")],
        ["url": .string("https://second.test/2")]
      ]
    ])

    XCTAssertEqual(
      merged.compactMap { $0["url"]?.stringValue },
      [
        "https://first.test/1",
        "https://second.test/1",
        "https://first.test/2",
        "https://second.test/2"
      ]
    )
  }

  func testResearchEvidencePackCarriesCoverageAndUnresolvedQueries() throws {
    let attached = AgentIOSWebEvidencePack.attach(
      to: [
        "operation": .string("research"),
        "status": .string("partial"),
        "query": .string("compare options"),
        "research": .object([
          "query_plan": .array([
            .object(["query": .string("option A"), "purpose": .string("coverage A")])
          ]),
          "coverage": .array([
            .object([
              "query": .string("option A"),
              "status": .string("unresolved"),
              "candidate_count": .int(0)
            ])
          ]),
          "unresolved_queries": .array([.string("option A")])
        ])
      ],
      generatedAtMillis: 123
    )

    let context = try XCTUnwrap(
      attached["evidence_pack"]?.objectValue?["research_context"]?.objectValue
    )
    XCTAssertEqual(context["unresolved_queries"]?.arrayValue, [.string("option A")])
    XCTAssertEqual(
      context["coverage"]?.arrayValue?.first?.objectValue?["status"],
      .string("unresolved")
    )
  }
}
