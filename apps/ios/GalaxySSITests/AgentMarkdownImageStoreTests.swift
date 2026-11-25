import XCTest
@testable import GalaxySSI

final class AgentMarkdownImageStoreTests: XCTestCase {
  private let url = URL(string: "https://images.example.org/a.png")!
  private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

  func testPublicURLRejectsUnsafeInputsAndCanonicalizesFragments() throws {
    for value in ["http://example.org/a.png", "https://user:secret@example.org/a.png",
                  "https://127.0.0.1/a.png", "https://192.168.1.1/a.png", "https://localhost/a.png"] {
      XCTAssertThrowsError(try AgentMarkdownImageStore.publicURL(URL(string: value)!))
    }
    XCTAssertEqual(try AgentMarkdownImageStore.publicURL(URL(string: url.absoluteString + "#one")!), url)
  }

  func testSharedFetchCancellationReleasesOnlyItsWaiter() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fetch = ControlledMarkdownImageFetch()
    let store = makeStore(root, fetch)
    let first = Task { try await store.image(url) }
    let second = Task { try await store.image(url) }
    try await wait { await store.activity().waiters == 2 }
    first.cancel()
    do { _ = try await first.value; XCTFail("Cancelled waiter returned bytes") }
    catch { XCTAssertTrue(error is CancellationError) }
    let remaining = await store.activity()
    XCTAssertEqual(remaining.waiters, 1)
    let calls = await fetch.calls
    XCTAssertEqual(calls, 1)
    await fetch.finish(url, data: png)
    let result = try await second.value
    XCTAssertEqual(result, png)
  }

  func testEncryptedCacheHitAndCorruptionRefetch() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fetch = ControlledMarkdownImageFetch()
    let store = makeStore(root, fetch)
    let first = Task { try await store.image(url) }
    try await wait { await fetch.calls == 1 }
    await fetch.finish(url, data: png)
    let firstData = try await first.value
    XCTAssertEqual(firstData, png)
    let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root,
      includingPropertiesForKeys: nil).first)
    XCTAssertEqual(file.pathExtension, "saenc")
    XCTAssertNotEqual(try Data(contentsOf: file), png)
    let hit = try await store.image(URL(string: url.absoluteString + "#two")!)
    XCTAssertEqual(hit, png)
    let beforeCorruption = await fetch.calls
    XCTAssertEqual(beforeCorruption, 1)
    try Data("corrupt".utf8).write(to: file)
    let replacement = Task { try await store.image(url) }
    try await wait { await fetch.calls == 2 }
    await fetch.finish(url, data: png)
    let replacementData = try await replacement.value
    XCTAssertEqual(replacementData, png)
  }

  func testClearInvalidatesLateProducerBeforeNewRequest() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fetch = ControlledMarkdownImageFetch()
    let store = makeStore(root, fetch)
    let first = Task { try await store.image(url) }
    try await wait { await fetch.calls == 1 }
    await store.clear()
    do { _ = try await first.value; XCTFail("Cleared waiter returned bytes") }
    catch { XCTAssertTrue(error is CancellationError) }
    // This fake deliberately completes despite cancellation, like a late delegate callback.
    await fetch.finish(url, data: png)
    let second = Task { try await store.image(url) }
    try await wait { await fetch.calls == 2 }
    await fetch.finish(url, data: png)
    let data = try await second.value
    XCTAssertEqual(data, png)
    let idle = await store.activity()
    XCTAssertEqual(idle.resources, 0)
  }

  func testCacheWriteFailureDoesNotDiscardValidDownloadedImage() async throws {
    let root = temporaryRoot()
    try Data("not a directory".utf8).write(to: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let fetch = ControlledMarkdownImageFetch()
    let store = makeStore(root, fetch)
    let task = Task { try await store.image(url) }
    try await wait { await fetch.calls == 1 }
    await fetch.finish(url, data: png)
    let data = try await task.value
    XCTAssertEqual(data, png)
    XCTAssertEqual(try Data(contentsOf: root), Data("not a directory".utf8))
  }

  @MainActor
  func testLoaderIgnoresLateOldURLAndClearsIdentityOnCancel() async throws {
    let fetch = ControlledMarkdownImageFetch()
    let next = URL(string: "https://images.example.org/b.png")!
    let loader = GalaxySSIAsyncAnimatedImageLoader(fetch: { url, _ in try await fetch.fetch(url) })
    let first = Task { await loader.load(url: url, publicWebImage: true) }
    try await wait { await fetch.calls == 1 }
    let second = Task { await loader.load(url: next, publicWebImage: true) }
    try await wait { await fetch.calls == 2 }
    await fetch.finish(next, data: Data([2]))
    await second.value
    await fetch.finish(url, data: Data([1]))
    await first.value
    XCTAssertEqual(loader.state, .loaded(Data([2])))
    XCTAssertTrue(loader.represents(url: next, publicWebImage: true))
    XCTAssertFalse(loader.represents(url: next, publicWebImage: false))
    loader.cancel()
    XCTAssertEqual(loader.state, .loading)
    XCTAssertFalse(loader.represents(url: next, publicWebImage: true))
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private func makeStore(_ root: URL, _ fetch: ControlledMarkdownImageFetch) -> AgentMarkdownImageStore {
    AgentMarkdownImageStore(root: root, transport: fetch,
      cipher: GalaxySSIAttachmentAtRestCipher(secrets: InMemorySecretStore(), keyAccount: "fixture.markdown"))
  }

  private func wait(_ ready: () async -> Bool) async throws {
    for _ in 0..<200 {
      if await ready() { return }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    throw URLError(.timedOut)
  }
}

private actor ControlledMarkdownImageFetch: AgentMarkdownImageFetching {
  private struct Pending { var url: URL; var continuation: CheckedContinuation<Data, Error> }
  private var pending: [UUID: Pending] = [:]
  private(set) var calls = 0

  func fetch(_ url: URL) async throws -> Data {
    calls += 1
    let id = UUID()
    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = Pending(url: url, continuation: continuation)
      Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        expire(id)
      }
    }
  }

  func finish(_ url: URL, data: Data) {
    guard let id = pending.first(where: { $0.value.url == url })?.key,
      let value = pending.removeValue(forKey: id) else { return }
    value.continuation.resume(returning: data)
  }

  private func expire(_ id: UUID) {
    pending.removeValue(forKey: id)?.continuation.resume(throwing: URLError(.timedOut))
  }
}
