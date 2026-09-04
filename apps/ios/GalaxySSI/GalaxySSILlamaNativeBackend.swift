#if GALAXYSSI_NATIVE_LLAMA
import Foundation

final class GalaxySSILlamaNativeBackend: LocalModelInferenceBackend {
  static let shared = GalaxySSILlamaNativeBackend()

  var isAvailable: Bool {
    galaxyssi_llama_initialize() == 0
  }

  var backendName: String {
    guard galaxyssi_llama_initialize() == 0 else { return "Unavailable" }
    let value = galaxyssi_llama_backend_info()
    let name = value.map { String(cString: $0) } ?? ""
    return name.isEmpty ? "llama.cpp" : name
  }

  var exposesSme: Bool {
    galaxyssi_llama_os_exposes_sme() != 0
  }

  func loadModel(at modelURL: URL, contextTokens: Int, threads: Int) throws {
    guard galaxyssi_llama_initialize() == 0 else {
      throw LocalModelInferenceError.modelLoadFailed(lastError())
    }
    let result = modelURL.path.withCString { path in
      galaxyssi_llama_load_model(path, Int32(contextTokens), Int32(threads))
    }
    guard result == 0 else {
      throw LocalModelInferenceError.modelLoadFailed(lastError())
    }
  }

  func generate(
    systemPrompt: String,
    userPrompt: String,
    maximumTokens: Int,
    temperature: Double
  ) throws -> String {
    let pointer = systemPrompt.withCString { system in
      userPrompt.withCString { user in
        galaxyssi_llama_generate(system, user, Int32(maximumTokens), Float(temperature))
      }
    }
    guard let pointer else { throw LocalModelInferenceError.generationFailed(lastError()) }
    defer { galaxyssi_llama_free_string(pointer) }
    let response = String(cString: pointer)
    if response.isEmpty {
      let error = lastError()
      if !error.isEmpty { throw LocalModelInferenceError.generationFailed(error) }
    }
    return response
  }

  func unload() {
    galaxyssi_llama_unload()
  }

  private func lastError() -> String {
    galaxyssi_llama_last_error().map { String(cString: $0) } ?? ""
  }
}

@_silgen_name("galaxyssi_llama_initialize")
private func galaxyssi_llama_initialize() -> Int32

@_silgen_name("galaxyssi_llama_load_model")
private func galaxyssi_llama_load_model(
  _ modelPath: UnsafePointer<CChar>,
  _ contextTokens: Int32,
  _ threads: Int32
) -> Int32

@_silgen_name("galaxyssi_llama_generate")
private func galaxyssi_llama_generate(
  _ systemPrompt: UnsafePointer<CChar>,
  _ userPrompt: UnsafePointer<CChar>,
  _ maximumTokens: Int32,
  _ temperature: Float
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("galaxyssi_llama_free_string")
private func galaxyssi_llama_free_string(_ value: UnsafeMutablePointer<CChar>?)

@_silgen_name("galaxyssi_llama_unload")
private func galaxyssi_llama_unload()

@_silgen_name("galaxyssi_llama_backend_info")
private func galaxyssi_llama_backend_info() -> UnsafePointer<CChar>?

@_silgen_name("galaxyssi_llama_last_error")
private func galaxyssi_llama_last_error() -> UnsafePointer<CChar>?

@_silgen_name("galaxyssi_llama_os_exposes_sme")
private func galaxyssi_llama_os_exposes_sme() -> Int32
#endif
