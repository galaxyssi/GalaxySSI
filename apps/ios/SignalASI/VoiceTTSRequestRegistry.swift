import Foundation

struct VoiceTTSRequest {
  var utteranceId: String
  var traceId: String
  var onFinished: () -> Void
}

final class VoiceTTSRequestRegistry {
  private var active: VoiceTTSRequest?
  private let lock = NSLock()

  func begin(_ request: VoiceTTSRequest) {
    locked {
      active = request
    }
  }

  func finish(_ utteranceId: String?) -> VoiceTTSRequest? {
    locked {
      guard let current = active,
            matches(current, utteranceId: utteranceId) else {
        return nil
      }
      active = nil
      return current
    }
  }

  func discard(_ utteranceId: String?) -> Bool {
    locked {
      guard let current = active,
            matches(current, utteranceId: utteranceId) else {
        return false
      }
      active = nil
      return true
    }
  }

  func isActive(_ utteranceId: String?) -> Bool {
    locked {
      guard let current = active else { return false }
      return matches(current, utteranceId: utteranceId)
    }
  }

  func clear() {
    locked {
      active = nil
    }
  }

  private func matches(_ request: VoiceTTSRequest, utteranceId: String?) -> Bool {
    guard let utteranceId,
          !utteranceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    return request.utteranceId == utteranceId
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
