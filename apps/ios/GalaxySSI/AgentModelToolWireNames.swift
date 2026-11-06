import Foundation

enum AgentModelToolWireNames {
  static let maximumLength = 64

  static func name(_ nativeID: String) -> String {
    let escaped = nativeID.replacingOccurrences(of: "_", with: "_u").replacingOccurrences(of: ".", with: "__")
    if escaped.utf8.count <= maximumLength { return escaped }
    // A short escaped name cannot contain "_h", so it cannot enter the hashed namespace.
    let digest = AgentModelToolProtocolJSON.sha256(AgentMcpJSONCodec.stringify(.string(nativeID)))
    return "gssi_h_" + String(digest.prefix(56))
  }

  static func description(_ descriptor: AgentNativeToolDescriptor) -> String {
    guard name(descriptor.id) != descriptor.id else { return descriptor.description }
    return "\(descriptor.description) Native tool ID: \(descriptor.id)."
  }
}
