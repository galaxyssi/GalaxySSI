import XCTest
@testable import GalaxySSI

final class VoicePcmRingBufferTests: XCTestCase {
  func testRingRetainsNewestSamplesAcrossWrap() {
    let ring = PcmRingBuffer(capacitySamples: 6)
    ring.append([1, 2, 3, 4].map { Int16($0) }, count: 4)
    ring.append([5, 6, 7, 8].map { Int16($0) }, count: 4)

    XCTAssertEqual(ring.retainedStartSample(), 2)
    XCTAssertEqual(ring.snapshot(startSample: 0, endSampleExclusive: 8), [3, 4, 5, 6, 7, 8].map { Int16($0) })
  }

  func testSpeechSnapshotKeepsPreAndPostRoll() {
    let store = InMemorySpeechSegmentStore(sampleRateHz: 1_000, maxDurationMs: 2_000)
    for sequence in 0..<10 {
      let values = Array(repeating: Int16(sequence), count: 100)
      store.append(frame(sequence: Int64(sequence), samples: values))
      if sequence == 3 {
        store.markSpeechStart(sequence: 3)
      }
      if sequence == 7 {
        store.markSpeechEnd(sequence: 7)
      }
    }

    let snapshot = store.snapshot(segment: SegmentRange(preRollMs: 200, postRollMs: 100))

    XCTAssertTrue(snapshot.speechDetected)
    XCTAssertEqual(snapshot.samples.count, 700)
    XCTAssertEqual(snapshot.samples.first, 1)
    XCTAssertEqual(snapshot.samples.last, 7)
  }

  func testPartialSnapshotOnlyCopiesTheNewestRollingWindow() {
    let store = InMemorySpeechSegmentStore(sampleRateHz: 1_000, maxDurationMs: 20_000)
    for sequence in 0..<120 {
      let values = Array(repeating: Int16(sequence), count: 100)
      store.append(frame(sequence: Int64(sequence), samples: values))
      if sequence == 5 {
        store.markSpeechStart(sequence: 5)
      }
    }

    let partial = store.snapshotWindow(
      maxDurationMs: 4_000,
      segment: SegmentRange(preRollMs: 0, postRollMs: 0)
    )

    XCTAssertEqual(partial.samples.count, 4_000)
    XCTAssertEqual(partial.captureStartSample, 8_000)
    XCTAssertEqual(partial.captureEndSampleExclusive, 12_000)
    XCTAssertEqual(partial.samples.first, 80)
    XCTAssertEqual(partial.samples.last, 119)
  }

  private func frame(sequence: Int64, samples: [Int16]) -> AudioFrame {
    AudioFrame(sequence: sequence, captureTimeNanos: sequence, samples: samples)
  }
}
