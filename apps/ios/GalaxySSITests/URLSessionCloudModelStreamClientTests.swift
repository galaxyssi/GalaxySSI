import Network
import XCTest
@testable import GalaxySSI

final class URLSessionCloudModelStreamClientTests: XCTestCase {
  func testTrialHTTPRejectsAmbiguousAndTruncatedFraming() throws {
    func parse(_ text: String) throws -> CloudTrialHTTPTransport.Response? {
      var parser = CloudTrialHTTPTransport.Parser()
      return try parser.append(Data(text.utf8), complete: true)
    }
    XCTAssertThrowsError(try parse("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nab"))
    XCTAssertThrowsError(try parse("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"))
    XCTAssertThrowsError(try parse("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab"))
    XCTAssertThrowsError(try parse("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 2\r\n\r\nab"))
    var split = CloudTrialHTTPTransport.Parser()
    XCTAssertNil(try split.append(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\na".utf8), complete: false))
    XCTAssertNil(try split.append(Data("b\r\n1\r\nc\r\n0\r\n".utf8), complete: false))
    XCTAssertEqual(try split.append(Data("\r\n".utf8), complete: false)?.body, Data("abc".utf8))
  }

  func testTrialHTTPWireRejectsForeignPlaintextAndTransportOverrides() throws {
    var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9000/v1/models?case=exact")))
    request.httpMethod = "POST"
    request.httpBody = Data("{\"model\":\"fixture\"}".utf8)
    let wire = try CloudTrialHTTPTransport.WireRequest(request)
    XCTAssertTrue(wire.bytes.starts(with: Data("POST /v1/models?case=exact HTTP/1.1\r\n".utf8)))
    XCTAssertEqual(wire.sha256, try CloudTrialHTTPTransport.WireRequest(request).sha256)
    request.setValue("chunked", forHTTPHeaderField: "Transfer-Encoding")
    XCTAssertThrowsError(try CloudTrialHTTPTransport.WireRequest(request))
    request.setValue(nil, forHTTPHeaderField: "Transfer-Encoding")
    request.url = URL(string: "http://127.0.0.1.example.invalid/v1")
    XCTAssertThrowsError(try CloudTrialHTTPTransport.WireRequest(request))
  }

  func testTrialHTTPNeverRepeatsPostAfterRedirectAuthenticationOrDisconnect() async throws {
    for status in [307, 401, 0] {
      let queue = DispatchQueue(label: "test.trial-loopback")
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
      let listener = try NWListener(using: parameters)
      defer { listener.cancel() }
      let received = WireCounter()
      listener.newConnectionHandler = { peer in
        peer.start(queue: queue)
        let count = received.expectedCount()
        guard count > 0 else { peer.cancel(); return }
        peer.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, _ in
          if let data { received.record(data) }
          if status == 0 { peer.cancel(); return }
          let header = status == 307 ? "Location: /second" : "WWW-Authenticate: Basic realm=\"test\""
          let reply = Data("HTTP/1.1 \(status) Fixture\r\n\(header)\r\nContent-Length: 0\r\n\r\n".utf8)
          peer.send(content: reply, completion: .contentProcessed { _ in peer.cancel() })
        }
      }
      let ready = expectation(description: "Loopback listener ready")
      listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
      listener.start(queue: queue)
      await fulfillment(of: [ready], timeout: 3)
      let port = try XCTUnwrap(listener.port)
      var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port.rawValue)/fixture")))
      request.httpMethod = "POST"
      request.httpBody = Data("{\"model\":\"fixture\"}".utf8)
      let wire = try CloudTrialHTTPTransport.WireRequest(request)
      received.expect(wire.bytes.count)
      do {
        let response = try await CloudTrialHTTPTransport.send(request, expectedSHA256: wire.sha256,
          connectMillis: 2_000, readMillis: 2_000)
        XCTAssertNotEqual(status, 0)
        XCTAssertEqual(response.status, status)
      } catch {
        if status != 0 { throw error }
      }
      try await Task.sleep(nanoseconds: 150_000_000)
      XCTAssertEqual(received.values(), [wire.bytes])
    }
  }

  private final class WireCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var requests: [Data] = []
    func expect(_ value: Int) {
      lock.lock(); defer { lock.unlock() }
      count = value
    }
    func expectedCount() -> Int {
      lock.lock(); defer { lock.unlock() }
      return count
    }
    func record(_ bytes: Data) {
      lock.lock(); defer { lock.unlock() }
      requests.append(bytes)
    }
    func values() -> [Data] {
      lock.lock(); defer { lock.unlock() }
      return requests
    }
  }

  func testMobileStreamingConfigurationAvoidsSharedCacheAndKeepsActiveTimeouts() {
    let configuration = URLSessionCloudModelStreamClient.mobileStreamingConfiguration()
    XCTAssertTrue(configuration.waitsForConnectivity)
    XCTAssertEqual(configuration.timeoutIntervalForRequest, 300)
    XCTAssertEqual(configuration.timeoutIntervalForResource, 900)
    XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 8)
    XCTAssertNil(configuration.urlCache)
    XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
  }

  func testSSEFrameAccumulatorCombinesEventAndMultilineData() {
    let accumulator = ModelStreamFrameAccumulator(transport: .sse)
    var frames: [ModelStreamFrame] = []

    frames += accumulator.accept(line: ": heartbeat")
    frames += accumulator.accept(line: "event: response.output_text.delta")
    frames += accumulator.accept(line: #"data: {"delta":"hel"}"#)
    frames += accumulator.accept(line: #"data: {"delta":"lo"}"#)
    frames += accumulator.accept(line: "")

    XCTAssertEqual(
      frames,
      [
        ModelStreamFrame(
          eventName: "response.output_text.delta",
          data: #"{"delta":"hel"}"# + "\n" + #"{"delta":"lo"}"#
        )
      ]
    )
  }

  func testSSEFrameAccumulatorFlushesTrailingDataWithoutBlankLine() {
    let accumulator = ModelStreamFrameAccumulator(transport: .sse)

    _ = accumulator.accept(line: #"data: {"choices":[]}"#)

    XCTAssertEqual(
      accumulator.finish(),
      ModelStreamFrame(eventName: nil, data: #"{"choices":[]}"#)
    )
  }

  func testSSEFrameAccumulatorAcceptsBareJsonLines() {
    let accumulator = ModelStreamFrameAccumulator(transport: .sse)

    _ = accumulator.accept(line: #"{"choices":[{"delta":{}}]}"#)
    let frames = accumulator.accept(line: "")

    XCTAssertEqual(
      frames,
      [ModelStreamFrame(eventName: nil, data: #"{"choices":[{"delta":{}}]}"#)]
    )
  }

  func testJsonLineAccumulatorIgnoresBlankLinesAndTrimsPayload() {
    let accumulator = ModelStreamFrameAccumulator(transport: .jsonLines)

    XCTAssertEqual(accumulator.accept(line: "   "), [])
    XCTAssertEqual(
      accumulator.accept(line: #"  {"text":"hi"}  "#),
      [ModelStreamFrame(eventName: nil, data: #"{"text":"hi"}"#)]
    )
  }

  func testEmissionStateSequencesIncrease() {
    let state = ModelStreamEmissionState()

    XCTAssertEqual(state.nextSequence(), 1)
    XCTAssertEqual(state.nextSequence(), 2)
  }
}
