import Foundation

enum VoiceWhisperBenchmarkSystemProbe {
  static func snapshot(
    device: LocalModelDeviceSnapshot = LocalModelDeviceSnapshotDetector.capture()
  ) -> VoiceWhisperBenchmarkSystemSnapshot {
    VoiceWhisperBenchmarkSystemSnapshot(
      availableMemoryBytes: device.availableMemoryBytes,
      systemLowMemory: device.systemLowMemory,
      pssBytes: 0,
      rssBytes: 0,
      nativeAllocatedBytes: 0,
      cpuTimeMillis: 0,
      energyCounterNwh: nil,
      batteryTemperatureCelsius: device.batteryTemperatureCelsius,
      thermalStatus: device.thermalStatus ?? 0
    )
  }

  static func highPerformanceCoreCount(processInfo: ProcessInfo = .processInfo) -> Int {
    min(max(processInfo.activeProcessorCount, 1), 16)
  }
}

enum VoiceWhisperBenchmarkDefaultFactory {
  static func makeCoordinator(
    modelsDirectory: URL = VoiceWhisperModelCatalog.defaultModelsDirectory(),
    modelManager: VoiceWhisperModelManager? = nil,
    benchmarkManager: VoiceWhisperBenchmarkManager? = nil,
    native: VoiceWhisperNativeAPI = GalaxySSIWhisperNativeBridge(),
    bundle: Bundle = .main,
    plan: VoiceWhisperBenchmarkPlan = VoiceWhisperBenchmarkPlan(),
    audioLoader: (() throws -> VoiceWhisperBenchmarkAudio)? = nil,
    snapshot: @escaping () -> VoiceWhisperBenchmarkSystemSnapshot = {
      VoiceWhisperBenchmarkSystemProbe.snapshot()
    },
    highPerformanceCoreCount: @escaping () -> Int = {
      VoiceWhisperBenchmarkSystemProbe.highPerformanceCoreCount()
    },
    runnerOverride: ((VoiceWhisperBenchmarkManager) -> VoiceWhisperBenchmarkRunning)? = nil
  ) -> VoiceWhisperBenchmarkRunCoordinator {
    let normalizedDirectory = modelsDirectory.standardizedFileURL
    let resolvedModelManager = modelManager ?? VoiceWhisperModelManager(modelsDirectory: normalizedDirectory)
    let resolvedBenchmarkManager = benchmarkManager ?? VoiceWhisperBenchmarkManager(modelsDirectory: normalizedDirectory)
    return VoiceWhisperBenchmarkRunCoordinator(
      manager: resolvedBenchmarkManager,
      audioLoader: {
        if let audioLoader {
          return try audioLoader()
        }
        return try VoiceWhisperBenchmarkAudioLoader.loadBundled(bundle: bundle)
      },
      runnerFactory: {
        if let runnerOverride {
          return runnerOverride(resolvedBenchmarkManager)
        }
        return VoiceWhisperBenchmarkRunner(
          runtimeFactory: {
            DefaultVoiceLocalWhisperRuntime(modelManager: resolvedModelManager, native: native)
          },
          keyFactory: { profile, audioVersion in
            resolvedBenchmarkManager.key(profile: profile, benchmarkAudioVersion: audioVersion)
          },
          snapshot: snapshot,
          highPerformanceCoreCount: highPerformanceCoreCount,
          verifyModel: { profile in
            _ = try resolvedModelManager.ensureVerifiedFile(for: profile)
          },
          store: resolvedBenchmarkManager.recordStore,
          plan: plan
        )
      }
    )
  }
}
