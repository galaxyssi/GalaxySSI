import Foundation

protocol VoiceWhisperBenchmarkRunning {
  func run(
    profile: VoiceWhisperModelProfile,
    audio: VoiceWhisperBenchmarkAudio,
    force: Bool,
    onProgress: @escaping (VoiceWhisperBenchmarkProgress) -> Void
  ) async throws -> VoiceWhisperBenchmarkRecord
}

extension VoiceWhisperBenchmarkRunner: VoiceWhisperBenchmarkRunning {}

enum VoiceWhisperBenchmarkRunCoordinatorError: LocalizedError, Equatable {
  case busy(profileId: String)

  var errorDescription: String? {
    switch self {
    case .busy(let profileId):
      return "Another Whisper benchmark is already running for \(profileId)."
    }
  }
}

final class VoiceWhisperBenchmarkRunCoordinator {
  private let manager: VoiceWhisperBenchmarkManager
  private let audioLoader: () throws -> VoiceWhisperBenchmarkAudio
  private let runnerFactory: () -> VoiceWhisperBenchmarkRunning
  private let lock = NSLock()
  private var runningProfiles = Set<String>()
  private var activeTask: Task<VoiceWhisperBenchmarkRecord, Error>?

  init(
    manager: VoiceWhisperBenchmarkManager,
    audioLoader: @escaping () throws -> VoiceWhisperBenchmarkAudio = {
      try VoiceWhisperBenchmarkAudioLoader.loadBundled()
    },
    runnerFactory: @escaping () -> VoiceWhisperBenchmarkRunning
  ) {
    self.manager = manager
    self.audioLoader = audioLoader
    self.runnerFactory = runnerFactory
  }

  func isRunning(profileId: String) -> Bool {
    locked {
      runningProfiles.contains(profileId.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  func cancelForInteractiveVoice() {
    locked {
      activeTask?.cancel()
    }
  }

  func benchmark(
    profile: VoiceWhisperModelProfile,
    force: Bool = false,
    onProgress: @escaping (VoiceWhisperBenchmarkProgress) -> Void = { _ in }
  ) async throws -> VoiceWhisperBenchmarkRecord {
    try begin(profileId: profile.id)
    defer {
      finish(profileId: profile.id)
    }

    let audio = try audioLoader()
    let task = Task { [runnerFactory] in
      try await runnerFactory().run(
        profile: profile,
        audio: audio,
        force: force,
        onProgress: onProgress
      )
    }
    setActiveTask(task)

    let record = try await task.value
    try manager.save(record, profile: profile)
    return record
  }

  private func begin(profileId: String) throws {
    let cleanProfileId = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
    try locked {
      if let running = runningProfiles.first {
        throw VoiceWhisperBenchmarkRunCoordinatorError.busy(profileId: running)
      }
      runningProfiles.insert(cleanProfileId)
    }
  }

  private func setActiveTask(_ task: Task<VoiceWhisperBenchmarkRecord, Error>) {
    locked {
      activeTask = task
    }
  }

  private func finish(profileId: String) {
    let cleanProfileId = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
    locked {
      runningProfiles.remove(cleanProfileId)
      activeTask = nil
    }
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
