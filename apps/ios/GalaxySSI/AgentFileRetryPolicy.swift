import CoreFoundation
import Foundation

enum AgentFileRetryPolicy {
  static let codes: Set<String> = ["blob_expired", "blob_not_found", "ciphertext_hash_mismatch", "chunk_authentication_failed"]
  static func generation(_ payload: [String: Any]) -> Int? {
    guard let value = payload["file_retry_generation"] else { return 0 }
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      !["f", "d"].contains(String(cString: number.objCType)), (0...3).contains(number.intValue),
      number.int64Value == Int64(number.intValue) else { return nil }
    return number.intValue
  }
  static func recoverable(_ payload: [String: Any], file: AgentPreparedOutboundAttachment) -> Bool {
    payload["supports_file_retry"] as? Bool == true && codes.contains(payload.string("error_code")) &&
      file.scope.attachmentRequestId == nil && file.fileRetryGeneration < 3 &&
      generation(payload) == file.fileRetryGeneration &&
      AgentAttachmentDeliveryFailureContract.matches(receipt: payload, attachment: file)
  }
}
