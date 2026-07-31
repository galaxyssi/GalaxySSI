import Foundation

final class PcmRingBuffer {
  private let lock = NSLock()
  private var samples: [Int16]
  private var totalWritten: Int64 = 0

  init(capacitySamples: Int) {
    samples = Array(repeating: 0, count: max(1, capacitySamples))
  }

  var capacity: Int {
    locked { samples.count }
  }

  @discardableResult
  func append(_ source: [Int16], count: Int? = nil) -> Range<Int64> {
    locked {
      let safeCount = min(max(0, count ?? source.count), source.count)
      let start = totalWritten
      let sourceStart = max(0, safeCount - samples.count)
      var absolute = totalWritten + Int64(sourceStart)
      var sourceOffset = sourceStart
      while sourceOffset < safeCount {
        samples[Int(absolute % Int64(samples.count))] = source[sourceOffset]
        sourceOffset += 1
        absolute += 1
      }
      totalWritten += Int64(safeCount)
      return start..<totalWritten
    }
  }

  func retainedStartSample() -> Int64 {
    locked { max(0, totalWritten - Int64(samples.count)) }
  }

  func endSampleExclusive() -> Int64 {
    locked { totalWritten }
  }

  func clear() {
    locked {
      samples = Array(repeating: 0, count: samples.count)
      totalWritten = 0
    }
  }

  func snapshot(startSample: Int64, endSampleExclusive: Int64) -> [Int16] {
    locked {
      let retainedStart = max(0, totalWritten - Int64(samples.count))
      let start = min(max(startSample, retainedStart), totalWritten)
      let end = min(max(endSampleExclusive, start), totalWritten)
      let count = Int(end - start)
      guard count > 0 else { return [] }
      var output = Array(repeating: Int16(0), count: count)
      var absolute = start
      var outputOffset = 0
      while outputOffset < count {
        output[outputOffset] = samples[Int(absolute % Int64(samples.count))]
        absolute += 1
        outputOffset += 1
      }
      return output
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}

struct SegmentRange: Equatable {
  var preRollMs: Int
  var postRollMs: Int
  var includeAllWhenSpeechMissing: Bool

  init(
    preRollMs: Int = 300,
    postRollMs: Int = 200,
    includeAllWhenSpeechMissing: Bool = true
  ) {
    self.preRollMs = max(0, preRollMs)
    self.postRollMs = max(0, postRollMs)
    self.includeAllWhenSpeechMissing = includeAllWhenSpeechMissing
  }
}

protocol SpeechSegmentStore {
  func append(_ frame: AudioFrame)
  func markSpeechStart(sequence: Int64)
  func markSpeechEnd(sequence: Int64)
  func snapshot(segment: SegmentRange) -> PcmSnapshot
  func trimBefore(sequence: Int64)
  func clear()
}

final class InMemorySpeechSegmentStore: SpeechSegmentStore {
  private let lock = NSLock()
  private let sampleRateHz: Int
  private let ring: PcmRingBuffer
  private var sequenceOffsets: [Int64: Range<Int64>] = [:]
  private var sequenceOrder: [Int64] = []
  private var speechStartSample: Int64?
  private var speechEndSampleExclusive: Int64?

  init(sampleRateHz: Int, maxDurationMs: Int64) {
    self.sampleRateHz = max(1, sampleRateHz)
    let capacity = max(
      self.sampleRateHz,
      Int(Int64(self.sampleRateHz) * max(1, maxDurationMs) / 1_000)
    )
    self.ring = PcmRingBuffer(capacitySamples: capacity)
  }

  func append(_ frame: AudioFrame) {
    locked {
      let range = ring.append(frame.samples, count: frame.validSamples)
      if sequenceOffsets[frame.sequence] == nil {
        sequenceOrder.append(frame.sequence)
      }
      sequenceOffsets[frame.sequence] = range
      trimSequenceIndex()
    }
  }

  func markSpeechStart(sequence: Int64) {
    locked {
      guard let range = sequenceOffsets[sequence] else { return }
      if speechStartSample == nil {
        speechStartSample = range.lowerBound
      }
      speechEndSampleExclusive = nil
    }
  }

  func markSpeechEnd(sequence: Int64) {
    locked {
      guard let range = sequenceOffsets[sequence] else { return }
      speechEndSampleExclusive = max(range.lowerBound, speechStartSample ?? range.lowerBound)
    }
  }

  func snapshot(segment: SegmentRange = SegmentRange()) -> PcmSnapshot {
    locked {
      let retainedStart = ring.retainedStartSample()
      let retainedEnd = ring.endSampleExclusive()
      let start = speechStartSample.map {
        max(retainedStart, $0 - Int64(segment.preRollMs) * Int64(sampleRateHz) / 1_000)
      } ?? (segment.includeAllWhenSpeechMissing ? retainedStart : retainedEnd)
      let end = speechEndSampleExclusive.map {
        min(retainedEnd, $0 + Int64(segment.postRollMs) * Int64(sampleRateHz) / 1_000)
      } ?? retainedEnd
      return PcmSnapshot(
        samples: ring.snapshot(startSample: start, endSampleExclusive: end),
        sampleRateHz: sampleRateHz,
        speechDetected: speechStartSample != nil,
        speechStartSample: speechStartSample,
        speechEndSampleExclusive: speechEndSampleExclusive,
        captureStartSample: start,
        captureEndSampleExclusive: end
      )
    }
  }

  func trimBefore(sequence: Int64) {
    locked {
      guard let trimSample = sequenceOffsets[sequence]?.lowerBound else { return }
      sequenceOrder.removeAll { key in
        guard let range = sequenceOffsets[key] else { return true }
        if range.upperBound <= trimSample {
          sequenceOffsets.removeValue(forKey: key)
          return true
        }
        return false
      }
      if let start = speechStartSample, start < trimSample {
        speechStartSample = trimSample
      }
    }
  }

  func clear() {
    locked {
      sequenceOffsets.removeAll()
      sequenceOrder.removeAll()
      speechStartSample = nil
      speechEndSampleExclusive = nil
      ring.clear()
    }
  }

  private func trimSequenceIndex() {
    while sequenceOrder.count > 4_096 {
      let expired = sequenceOrder.removeFirst()
      sequenceOffsets.removeValue(forKey: expired)
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
