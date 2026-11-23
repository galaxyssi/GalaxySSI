import SwiftUI

extension GalaxySSIHealthAtlas {
  struct RespirationPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let mechanisms: [Mechanism]
    let insertAfter: [String: String]
    let plate: Plate
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasRespiration", bundle: bundle)?.data else { return nil }
      guard data.count <= 256_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let revisions = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let additions = Set(entries.filter { base.entry($0.id) == nil }.map(\.id))
      let models = Set(mechanisms.map(\.id))
      guard schema == 1, entries.count <= 64, revisions.count == entries.count,
        !mechanisms.isEmpty, mechanisms.count <= 32, models.count == mechanisms.count,
        models.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        mechanisms.allSatisfy({ $0.kind == "cell" || $0.id == "gas-exchange" }),
        Set(insertAfter.keys) == additions, insertAfter.values.allSatisfy({ base.entry($0) != nil }),
        entries.allSatisfy({ entry in
          if let original = base.entry(entry.id) { return entry.kind == original.kind && entry.systems == original.systems }
          return entry.kind == .organ && entry.systems.contains("respiratory")
        }) else { throw Invalid.catalogue }
      let combined = base.entries.flatMap { entry in
        [revisions[entry.id] ?? entry] + entries.filter { insertAfter[$0.id] == entry.id }
      }
      let result = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: combined, mechanisms: base.mechanisms + mechanisms))
      guard plate.id == "alveolus", plate.asset == "HealthAtlasAlveolus", plate.owner == "alveoli",
        plate.entryIDs == ["alveoli", "respiratory-membrane", "pulmonary-capillaries"],
        plate.source == GalaxySSIHealthAtlasGasExchange.source, plate.aspectRatio == 1,
        UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
        Set(plate.markers.map(\.id)) == Set(plate.entryIDs), plate.markers.count == 3,
        plate.markers.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
        else { throw Invalid.catalogue }
      return result
    }
  }
}

/// Fixed textbook partial-pressure examples, never outputs of the ventilation model.
enum GalaxySSIHealthAtlasGasExchange {
  enum Gas: String, CaseIterable { case oxygen, carbon }
  struct Gradient {
    let gas: Gas
    let alveolar: Int
    let incomingBlood: Int
    var towardBlood: Bool { alveolar > incomingBlood }
    var difference: Int { abs(alveolar - incomingBlood) }
  }
  static let source = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-4-gas-exchange")!
  static let gradients = [Gradient(gas: .oxygen, alveolar: 104, incomingBlood: 40),
    Gradient(gas: .carbon, alveolar: 40, incomingBlood: 45)]
  static func supports(_ id: String) -> Bool { ["alveoli", "respiratory-membrane", "pulmonary-capillaries"].contains(id) }
  static func phase(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
  static func stage(_ value: Double) -> Int { min(3, Int(phase(value) * 4)) }
  static func position(_ gas: Gas, phase value: Double) -> Double { gas == .oxygen ? phase(value) : 1 - phase(value) }
  static func summary(_ gradient: Gradient, language: String) -> String {
    func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_gas_" + key, language) }
    return String(format: t("summary"), t(gradient.gas.rawValue), Int64(gradient.alveolar), Int64(gradient.incomingBlood),
      t(gradient.towardBlood ? "to_blood" : "to_air"))
  }
}

struct GalaxySSIHealthAtlasGasExchangeView: View {
  let phase: Double
  let language: String
  let stages: [String]
  let selected: (Int) -> Void
  let open: (String) -> Void
  @Environment(\.colorScheme) private var scheme
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
  var body: some View {
    VStack(spacing: 12) {
      Button { open("alveoli") } label: {
        Image("HealthAtlasAlveolus").resizable().scaledToFit().frame(height: 240)
      }.buttonStyle(.plain).accessibilityLabel(t("view_alveolus")).accessibilityIdentifier("atlas-gas-alveolus")
      Text(t("gas_example")).font(.caption).fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .top, spacing: 8) {
        structure("gas_alveolar", id: "alveoli")
        structure("respiratory_membrane_name", id: "respiratory-membrane")
        structure("gas_blood", id: "pulmonary-capillaries")
      }
      ForEach(GalaxySSIHealthAtlasGasExchange.gradients, id: \.gas) { gradient in
        VStack(spacing: 4) {
          Text(t("gas_" + gradient.gas.rawValue)).font(.headline)
          HStack(spacing: 8) {
            Text(number(gradient.alveolar)).frame(maxWidth: .infinity)
            arrow(gradient).frame(maxWidth: .infinity).frame(height: 40).accessibilityHidden(true)
            Text(number(gradient.incomingBlood)).frame(maxWidth: .infinity)
          }
        }.accessibilityElement(children: .ignore)
          .accessibilityLabel(GalaxySSIHealthAtlasGasExchange.summary(gradient, language: language))
      }
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        ForEach(0..<4) { index in
          Button { selected(index) } label: {
            Text(GalaxySSIHealthAtlasText.get(stages[index], language)).font(.caption).bold()
              .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 48)
              .foregroundColor(index == GalaxySSIHealthAtlasGasExchange.stage(phase) ? GalaxySSIHealthTheme.accent : .primary)
          }.buttonStyle(.plain)
            .accessibilityAddTraits(index == GalaxySSIHealthAtlasGasExchange.stage(phase) ? .isSelected : [])
            .accessibilityIdentifier("atlas-gas-stage-" + String(index))
        }
      }
    }
  }
  private func structure(_ key: String, id: String) -> some View {
    Button { open(id) } label: {
      Text(t(key)).font(.caption).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 48)
    }.buttonStyle(.plain).accessibilityIdentifier("atlas-gas-structure-" + id)
  }
  private func number(_ value: Int) -> String {
    let format = NumberFormatter(); format.locale = GalaxySSILocalization.interfaceLocale(language: language)
    return format.string(from: NSNumber(value: value)) ?? String(value)
  }
  private func arrow(_ gradient: GalaxySSIHealthAtlasGasExchange.Gradient) -> some View {
    let rich = gradient.towardBlood
    let color: Color = rich
      ? (scheme == .dark ? Color(red: 243.0 / 255, green: 152.0 / 255, blue: 160.0 / 255) : Color(red: 183.0 / 255, green: 70.0 / 255, blue: 80.0 / 255))
      : (scheme == .dark ? Color(red: 131.0 / 255, green: 190.0 / 255, blue: 235.0 / 255) : Color(red: 51.0 / 255, green: 111.0 / 255, blue: 164.0 / 255))
    return GeometryReader { geometry in
      let start: CGFloat = 10, end = max(10, geometry.size.width - 10), y = geometry.size.height / 2
      let tip = rich ? end : start, sign: CGFloat = rich ? 1 : -1
      ZStack {
        Path { p in p.move(to: CGPoint(x: start, y: y)); p.addLine(to: CGPoint(x: end, y: y)) }.stroke(color, lineWidth: 2)
        Path { p in
          p.move(to: CGPoint(x: tip, y: y)); p.addLine(to: CGPoint(x: tip - sign * 8, y: y - 5))
          p.addLine(to: CGPoint(x: tip - sign * 8, y: y + 5)); p.closeSubpath()
        }.fill(color)
        Circle().fill(color).frame(width: 8, height: 8)
          .position(x: start + (end - start) * GalaxySSIHealthAtlasGasExchange.position(gradient.gas, phase: phase), y: y)
      }
    }
  }
}
