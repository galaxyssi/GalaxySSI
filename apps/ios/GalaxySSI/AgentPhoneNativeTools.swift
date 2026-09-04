import Foundation

struct AgentNativeToolAvailabilityProvider {
  private let resolver: (AgentNativeToolInvocationContext?) -> AgentNativeToolAvailability

  init(_ resolver: @escaping (AgentNativeToolInvocationContext?) -> AgentNativeToolAvailability) {
    self.resolver = resolver
  }

  func current(_ context: AgentNativeToolInvocationContext? = nil) -> AgentNativeToolAvailability {
    resolver(context)
  }

  static func constant(_ availability: AgentNativeToolAvailability) -> AgentNativeToolAvailabilityProvider {
    AgentNativeToolAvailabilityProvider { _ in availability }
  }
}

struct AgentPhoneNativeToolDefinition: Codable, Equatable, Identifiable {
  var descriptor: AgentNativeToolDescriptor
  var executorId: String
  var provenanceMetadata: [String: String]
  var availabilityProvider: AgentNativeToolAvailabilityProvider

  var id: String { descriptor.id }

  init(
    descriptor: AgentNativeToolDescriptor,
    executorId: String,
    provenanceMetadata: [String: String] = [:],
    availabilityProvider: AgentNativeToolAvailabilityProvider? = nil
  ) {
    self.descriptor = descriptor
    self.executorId = executorId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.provenanceMetadata = provenanceMetadata
    self.availabilityProvider = availabilityProvider ?? .constant(descriptor.availability)
  }

  enum CodingKeys: String, CodingKey {
    case descriptor
    case executorId = "executor_id"
    case provenanceMetadata = "provenance_metadata"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let descriptor = try container.decode(AgentNativeToolDescriptor.self, forKey: .descriptor)
    self.init(
      descriptor: descriptor,
      executorId: try container.decodeIfPresent(String.self, forKey: .executorId) ?? "",
      provenanceMetadata: try container.decodeIfPresent([String: String].self, forKey: .provenanceMetadata) ?? [:]
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(descriptor, forKey: .descriptor)
    try container.encode(executorId, forKey: .executorId)
    try container.encode(provenanceMetadata, forKey: .provenanceMetadata)
  }

  static func == (lhs: AgentPhoneNativeToolDefinition, rhs: AgentPhoneNativeToolDefinition) -> Bool {
    lhs.descriptor == rhs.descriptor &&
      lhs.executorId == rhs.executorId &&
      lhs.provenanceMetadata == rhs.provenanceMetadata
  }
}
