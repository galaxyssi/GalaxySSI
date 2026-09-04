import CryptoKit
import Foundation

enum GalaxySSIError: LocalizedError {
  case invalidPairingQRCode(String)
  case invalidPayload(String)
  case missingCloudModel
  case missingAPIKey
  case notPaired
  case transportUnavailable
  case unsupportedResponse

  var errorDescription: String? {
    switch self {
    case .invalidPairingQRCode(let detail):
      return "Invalid GalaxySSI pairing QR: \(detail)"
    case .invalidPayload(let detail):
      return "Invalid GalaxySSI payload: \(detail)"
    case .missingCloudModel:
      return "No cloud model is selected for this contact."
    case .missingAPIKey:
      return "No API key is saved for this cloud model."
    case .notPaired:
      return "GalaxySSI Desktop is not paired yet."
    case .transportUnavailable:
      return "GalaxySSI Link transport is unavailable."
    case .unsupportedResponse:
      return "The model provider returned an unsupported response."
    }
  }
}

struct AgentManualTargetUnavailableError: LocalizedError, Equatable {
  let targetName: String

  init(targetName: String) {
    let clean = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.targetName = clean.isEmpty ? "selected target" : String(clean.prefix(120))
  }

  var errorDescription: String? {
    "The manually selected Agent target \"\(targetName)\" is currently unavailable. Choose another target or switch to Automatic."
  }
}
