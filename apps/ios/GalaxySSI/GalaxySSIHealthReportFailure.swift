import Foundation

enum GalaxySSIHealthReportFailure: String, Codable {
  case notSent, notAccepted, replyTimeout, remoteFailure, replyFormat, noSupportedRows, invalidRows
  case privacy, sourceChanged, image, storage

  static func classify(_ error: Error, fallback: Self = .storage) -> Self {
    if let problem = error as? GalaxySSIHealthReportDelivery.Problem {
      switch problem {
      case .notSent: return .notSent
      case .notAccepted: return .notAccepted
      case .replyTimeout: return .replyTimeout
      case .remoteFailure: return .remoteFailure
      }
    }
    if let problem = error as? GalaxySSIHealthReportVision.ReplyProblem {
      switch problem {
      case .format: return .replyFormat
      case .noSupportedRows: return .noSupportedRows
      case .invalidRows: return .invalidRows
      }
    }
    if error is AgentDataDisclosureBlockedError { return .privacy }
    if let failure = error as? GalaxySSIHealthRecords.Failure {
      switch failure {
      case .permission: return .privacy
      case .stale: return .sourceChanged
      default: break
      }
    }
    if let failure = error as? MqttRouteError, case .identityChanged = failure { return .sourceChanged }
    if let failure = error as? GalaxySSIError, case .transportUnavailable = failure { return .notSent }
    return fallback
  }

  func title(_ language: String) -> String {
    let fallback: String
    switch self {
    case .notSent: fallback = "The image was not sent. Check the paired Desktop connection and continue."
    case .notAccepted: fallback = "Desktop did not accept this recognition task. Continue to try this file again."
    case .replyTimeout: fallback = "No recognition result arrived in time. The task was not automatically resubmitted."
    case .remoteFailure: fallback = "Desktop could not complete recognition. Continue to retry this file."
    case .replyFormat: fallback = "The model reply was not a valid report result."
    case .noSupportedRows: fallback = "No supported measurement rows were found."
    case .invalidRows: fallback = "None of the returned measurement rows could be validated."
    case .privacy: fallback = "Health processing or destination authorization is unavailable."
    case .sourceChanged: fallback = "The image, account, permissions or destination changed. Review the file again."
    case .image: fallback = "The image could not be prepared within the 100 KB limit."
    case .storage: fallback = "The local import could not be saved. Existing measurements were not overwritten."
    }
    return GalaxySSIHealthReportVision.text("failure_" + rawValue, fallback, language)
  }
}
