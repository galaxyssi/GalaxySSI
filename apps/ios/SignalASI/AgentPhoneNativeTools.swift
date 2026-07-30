import Foundation

struct AgentPhoneNativeToolDefinition: Codable, Equatable, Identifiable {
  var descriptor: AgentNativeToolDescriptor
  var executorId: String
  var provenanceMetadata: [String: String]

  var id: String { descriptor.id }

  init(
    descriptor: AgentNativeToolDescriptor,
    executorId: String,
    provenanceMetadata: [String: String] = [:]
  ) {
    self.descriptor = descriptor
    self.executorId = executorId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.provenanceMetadata = provenanceMetadata
  }

  enum CodingKeys: String, CodingKey {
    case descriptor
    case executorId = "executor_id"
    case provenanceMetadata = "provenance_metadata"
  }
}
