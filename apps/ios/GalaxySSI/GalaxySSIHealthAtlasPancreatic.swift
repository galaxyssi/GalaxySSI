import Foundation

enum GalaxySSIHealthAtlasPancreatic {
  static let source = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-9-the-endocrine-pancreas")!
  static let isletCells = ["cell-pancreatic-beta-cell", "cell-pancreatic-alpha-cell", "cell-pancreatic-delta-cell", "cell-pancreatic-pp-cell"]
  static func supports(_ id: String) -> Bool { ["pancreas", "pancreatic-islets"].contains(id) }
  static func isletCell(stage: Int) -> String? { isletCells.indices.contains(stage) ? isletCells[stage] : nil }
  enum Route: String, CaseIterable, Identifiable {
    case duct, blood
    var id: String { rawValue }
    var target: String { self == .duct ? "pancreatic-duct" : "pancreatic-islets" }
    var asset: String { self == .duct ? "HealthAtlasDigestivePancreaticAcinar" : "HealthAtlasDigestiveIslet" }
    var title: String { self == .duct ? "digestive_routes_exocrine" : "digestive_routes_endo" }
    var chain: String { self == .duct ? "digestive_routes_exocrine_chain" : "digestive_routes_endo_chain" }
    func active(stage: Int) -> Bool? {
      guard (0..<4).contains(stage) else { return nil }
      return self == .duct ? stage <= 2 : stage == 0 || stage == 3
    }
  }
  static func context(_ id: String, text t: (String) -> String) -> [String] {
    if id == "pancreas" {
      return [t("digestive_routes_scope"), t("digestive_routes_exocrine_chain"), t("digestive_routes_endo_chain"), source.absoluteString]
    }
    return id == "pancreatic-islets" ? [t("digestive_islets_scope")] : []
  }
}
