import Foundation

/// Public catalogue/synthetic state only. Values has no public-prompt fallback.
enum GalaxySSIHealthAtlasAgentContext {
  enum Screen: CaseIterable {
    case structure, function, values, simulation, physiology, drugs, aging
    var includesPhysiology: Bool { self == .simulation || self == .physiology }
  }
  struct Anatomy {
    let id: String
    let name: String
    let description: String
    let mechanism: String
    let stages: [String]
    let source: URL
  }
  struct Simulation {
    let entryID: String
    let phase: Double
    let first: Double
    let second: Double
    var stage: Int { min(3, Int(phase * 4)) }
    init?(entryID: String, phase: Double, first: Double, second: Double) {
      guard phase.isFinite, (0...1).contains(phase), first.isFinite, second.isFinite,
        !["heart", "cardio"].contains(entryID) || ((40...160).contains(first) && (30...120).contains(second) &&
          first.rounded() == first && second.rounded() == second) else { return nil }
      self.entryID = entryID; self.phase = phase; self.first = first; self.second = second
    }
  }
  struct Illustration {
    let entryID: String
    let caption: String
    let source: URL?
    init?(entryID: String, caption: String, source: URL?) {
      guard !entryID.isEmpty, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        source == nil || (source?.scheme == "https" && source?.host == "openstax.org" &&
          source?.user == nil && source?.password == nil) else { return nil }
      self.entryID = entryID; self.caption = caption; self.source = source
    }
  }
  struct Quantitative {
    let entryID: String
    let context: String
  }
  struct Elimination {
    let halfLife: Double
    let elapsed: Double
    init?(halfLife: Double, elapsed: Double) {
      guard halfLife.isFinite, elapsed.isFinite, (1...24).contains(halfLife), (0...48).contains(elapsed),
        halfLife.rounded() == halfLife, elapsed.rounded() == elapsed else { return nil }
      self.halfLife = halfLife; self.elapsed = elapsed
    }
    var percent: Double { 100 * pow(0.5, elapsed / halfLife) }
  }

  static func prompt(anatomy: Anatomy?, screen: Screen, simulation: Simulation? = nil, quantitative: Quantitative? = nil,
                     elimination: Elimination? = nil, illustration: Illustration? = nil,
                     locale: Locale, text t: (String) -> String) -> String? {
    guard screen != .values else { return nil }
    guard let anatomy else { return t("ask_whole_context") }
    guard anatomy.stages.count == 4 else { return nil }
    func number(_ value: Double) -> String {
      let format = NumberFormatter(); format.locale = locale; format.numberStyle = .decimal; format.maximumFractionDigits = 2
      return format.string(from: NSNumber(value: value)) ?? String(value)
    }
    var lines = [String(format: t("ask_context"), anatomy.name, anatomy.description, anatomy.mechanism, anatomy.source.absoluteString)]
    if let illustration, illustration.entryID == anatomy.id {
      lines += [illustration.caption, t("art_note")]
      if let source = illustration.source { lines.append(source.absoluteString) }
    }
    if screen.includesPhysiology {
      if let simulation, simulation.entryID == anatomy.id {
        lines.append(t("teaching_note"))
        if GalaxySSIHealthAtlasCirculation.supports(anatomy.id) {
          lines += [t("circuit_scope"), t("circuit_path"), GalaxySSIHealthAtlasCirculation.source.absoluteString]
        }
        lines.append(String(format: t("stage"), Int64(simulation.stage + 1), Int64(4), anatomy.stages[simulation.stage]))
        if ["heart", "cardio"].contains(anatomy.id) {
          lines.append(t("heart_rate") + ": " + number(simulation.first) + " bpm")
          lines.append(t("stroke_volume") + ": " + number(simulation.second) + " mL")
          lines.append(t("cardiac_output") + ": " + number(simulation.first * simulation.second / 1000) + " L/min")
          lines.append(t("cardiac_formula"))
        }
      }
      if let quantitative, quantitative.entryID == anatomy.id, !quantitative.context.isEmpty { lines.append(quantitative.context) }
      if let simulation, simulation.entryID == anatomy.id, GalaxySSIHealthAtlasGasExchange.supports(anatomy.id) {
        lines.append(t("gas_scope"))
        lines += GalaxySSIHealthAtlasGasExchange.gradients.map {
          String(format: t("gas_summary"), t("gas_" + $0.gas.rawValue), Int64($0.alveolar), Int64($0.incomingBlood),
            t($0.towardBlood ? "gas_to_blood" : "gas_to_air"))
        }
        lines.append(GalaxySSIHealthAtlasGasExchange.source.absoluteString)
      }
    }
    switch screen {
    case .physiology:
      lines += [t("physiology"), t("teaching_note"), anatomy.source.absoluteString]
    case .drugs:
      let values = elimination ?? Elimination(halfLife: 4, elapsed: 8)!
      lines += [t("drugs"), t("elimination_assumptions"),
        String(format: t("elimination_summary"), Int64(values.halfLife), Int64(values.elapsed), number(values.percent)),
        "https://openstax.org/books/pharmacology/pages/2-2-pharmacokinetics-and-pharmacodynamics",
        "https://pharmacologyeducation.org/clinical-pharmacokinetics/"]
    case .aging:
      lines += [t("aging"), t("aging_evidence"), "https://pubmed.ncbi.nlm.nih.gov/36599349/", anatomy.source.absoluteString]
    default: break
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
