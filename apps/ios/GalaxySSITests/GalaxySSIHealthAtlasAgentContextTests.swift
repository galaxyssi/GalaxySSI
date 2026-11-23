import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthAtlasAgentContextTests: XCTestCase {
  typealias Context = GalaxySSIHealthAtlasAgentContext
  private let locale = Locale(identifier: "en_US_POSIX")
  private func anatomy(_ id: String = "heart") -> Context.Anatomy {
    .init(id: id, name: id, description: "Public anatomy", mechanism: "Public mechanism",
      stages: ["Stage one", "Stage two", "Stage three", "Stage four"],
      source: URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/1-introduction")!)
  }
  private func text(_ key: String) -> String {
    ["ask_whole_context": "Public whole-body teaching only", "ask_context": "%1$@. %2$@. %3$@. %4$@. Not personal health data.",
     "teaching_note": "Synthetic inputs only", "stage": "Stage %1$lld / %2$lld: %3$@", "heart_rate": "Heart rate",
     "stroke_volume": "Stroke volume", "cardiac_output": "Cardiac output", "cardiac_formula": "Fixed stroke volume, not a patient model",
     "physiology": "Physiology", "drugs": "Drug pathways", "aging": "Aging research", "aging_evidence": "Research not personal age",
     "elimination_assumptions": "Single-compartment teaching assumptions",
     "elimination_summary": "Half-life %1$lld h; after %2$lld h: %3$@%%"] [key] ?? key
  }
  func testCirculationRoutesBoundsAndPublicContextScope() throws {
    typealias Circuit = GalaxySSIHealthAtlasCirculation
    XCTAssertEqual(Circuit.legs.map(\.oxygenRich), [false, false, true, true])
    XCTAssertEqual(Circuit.stage(.nan), 0)
    XCTAssertEqual(Circuit.stage(-1), 0)
    XCTAssertEqual(Circuit.stage(1), 3)
    XCTAssertEqual(Circuit.fraction(1), 1)
    XCTAssertEqual(Circuit.stage(0.5), 2)
    for id in ["heart", "cardio", "atria", "ventricles", "heart-valves", "coronary-vessels",
      "blood-vessels", "arteries", "veins", "capillaries", "blood"] { XCTAssertTrue(Circuit.supports(id)) }
    for id in ["lungs", "brain", "cell-erythrocyte"] { XCTAssertFalse(Circuit.supports(id)) }
    let simulation = try XCTUnwrap(Context.Simulation(entryID: "heart", phase: 0.5, first: 70, second: 70))
    for screen in [Context.Screen.simulation, .physiology] {
      let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: screen,
        simulation: simulation, locale: locale, text: text))
      XCTAssertTrue(prompt.contains("circuit_scope")); XCTAssertTrue(prompt.contains("circuit_path"))
      XCTAssertTrue(prompt.contains(Circuit.source.absoluteString))
    }
    for screen in [Context.Screen.structure, .function, .drugs, .aging] {
      let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: screen,
        simulation: simulation, locale: locale, text: text))
      XCTAssertFalse(prompt.contains("circuit_scope"))
    }
  }

  func testCardiacPreviewContainsTheCurrentStageInputsResultAndAssumptions() throws {
    let simulation = try XCTUnwrap(Context.Simulation(entryID: "heart", phase: 0.76, first: 80, second: 70))
    let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: .simulation, simulation: simulation, locale: locale, text: text))
    XCTAssertTrue(prompt.contains("Stage 4 / 4: Stage four"))
    XCTAssertTrue(prompt.contains("Heart rate: 80 bpm"))
    XCTAssertTrue(prompt.contains("Stroke volume: 70 mL"))
    XCTAssertTrue(prompt.contains("Cardiac output: 5.6 L/min"))
    XCTAssertTrue(prompt.contains("not a patient model"))
    XCTAssertTrue(prompt.contains("openstax.org"))
    XCTAssertFalse(prompt.contains("Single-compartment"))
  }
  func testInactiveResearchAndForeignModelsNeverEnterThePublicQuestion() throws {
    let simulation = try XCTUnwrap(Context.Simulation(entryID: "heart", phase: 0.5, first: 80, second: 70))
    let quantitative = Context.Quantitative(entryID: "heart", context: "ACTIVE_QUANTITATIVE_CONTEXT")
    for screen in [Context.Screen.structure, .function, .drugs, .aging] {
      let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: screen, simulation: simulation,
        quantitative: quantitative, locale: locale, text: text))
      XCTAssertFalse(prompt.contains("ACTIVE_QUANTITATIVE_CONTEXT"))
      XCTAssertFalse(prompt.contains("80 bpm"))
      XCTAssertFalse(prompt.contains("Stage 3 / 4"))
      if screen != .drugs { XCTAssertFalse(prompt.contains("Single-compartment")) }
    }
    let foreign = Context.Quantitative(entryID: "kidneys", context: "FOREIGN_MODEL")
    let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: .physiology,
      quantitative: foreign, locale: locale, text: text))
    XCTAssertFalse(prompt.contains("FOREIGN_MODEL"))
    let active = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: .physiology,
      simulation: simulation, quantitative: quantitative, locale: locale, text: text))
    XCTAssertTrue(active.contains("ACTIVE_QUANTITATIVE_CONTEXT"))
    XCTAssertTrue(active.contains("Stage 3 / 4: Stage three"))
  }
  func testIllustrationStaysWithSelectedPublicAnatomy() throws {
    let source = URL(string: "https://openstax.org/books/anatomy/plate")!
    let plate = try XCTUnwrap(Context.Illustration(entryID: "heart", caption: "SELECTED_PLATE", source: source))
    let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: .structure,
      illustration: plate, locale: locale, text: text))
    XCTAssertTrue(prompt.contains("SELECTED_PLATE"))
    XCTAssertTrue(prompt.contains("art_note"))
    XCTAssertTrue(prompt.contains(source.absoluteString))
    let foreign = Context.prompt(anatomy: anatomy("lungs"), screen: .function, illustration: plate, locale: locale, text: text)
    XCTAssertFalse(foreign?.contains("SELECTED_PLATE") ?? true)
    XCTAssertNil(Context.prompt(anatomy: anatomy(), screen: .values, illustration: plate, locale: locale, text: text))
    XCTAssertEqual(Context.prompt(anatomy: nil, screen: .structure, illustration: plate, locale: locale, text: text),
      "Public whole-body teaching only")
    XCTAssertNil(Context.Illustration(entryID: "heart", caption: " ", source: source))
    XCTAssertNil(Context.Illustration(entryID: "heart", caption: "Plate", source: URL(string: "http://openstax.org/books")))
    XCTAssertNil(Context.Illustration(entryID: "heart", caption: "Plate", source: URL(string: "https://user@openstax.org/books")))
  }

  func testPersonalValuesHasNoPublicFallbackIncludingAnEmptyMetric() {
    XCTAssertNil(Context.prompt(anatomy: anatomy(), screen: .values, locale: locale, text: text))
    XCTAssertNil(Context.prompt(anatomy: nil, screen: .values, locale: locale, text: text))
    XCTAssertEqual(Context.prompt(anatomy: nil, screen: .structure, locale: locale, text: text), "Public whole-body teaching only")
  }
  func testGasExamplesOnlyEnterMatchingActivePhysiologyContext() throws {
    let simulation = try XCTUnwrap(Context.Simulation(entryID: "alveoli", phase: 0.5, first: 12, second: 500))
    for screen in [Context.Screen.simulation, .physiology] {
      let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy("alveoli"), screen: screen,
        simulation: simulation, locale: locale, text: text))
      XCTAssertTrue(prompt.contains("gas_scope"))
      XCTAssertTrue(prompt.contains(GalaxySSIHealthAtlasGasExchange.source.absoluteString))
    }
    for screen in [Context.Screen.structure, .function, .drugs, .aging] {
      let prompt = try XCTUnwrap(Context.prompt(anatomy: anatomy("alveoli"), screen: screen,
        simulation: simulation, locale: locale, text: text))
      XCTAssertFalse(prompt.contains("gas_scope"))
    }
    let foreign = try XCTUnwrap(Context.prompt(anatomy: anatomy("lungs"), screen: .physiology,
      simulation: simulation, locale: locale, text: text))
    XCTAssertFalse(foreign.contains("gas_scope"))
    XCTAssertNil(Context.prompt(anatomy: anatomy("alveoli"), screen: .values,
      simulation: simulation, locale: locale, text: text))
  }

  func testDrugAndAgingContextUseOnlyTheirCurrentSourcesAndParameters() throws {
    let drug = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: .drugs,
      elimination: Context.Elimination(halfLife: 4, elapsed: 8), locale: locale, text: text))
    XCTAssertTrue(drug.contains("after 8 h: 25%"))
    XCTAssertTrue(drug.contains("Single-compartment"))
    XCTAssertTrue(drug.contains("pharmacologyeducation.org"))
    XCTAssertFalse(drug.contains("pubmed.ncbi.nlm.nih.gov"))
    let aging = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: .aging,
      elimination: Context.Elimination(halfLife: 4, elapsed: 8), locale: locale, text: text))
    XCTAssertTrue(aging.contains("pubmed.ncbi.nlm.nih.gov/36599349"))
    XCTAssertTrue(aging.contains("not personal age"))
    XCTAssertFalse(aging.contains("25%"))
    XCTAssertFalse(aging.contains("pharmacologyeducation.org"))
  }
  func testInvalidSyntheticDescriptorsAreRejectedAndSnapshotsDoNotChange() throws {
    for phase in [Double.nan, .infinity, -1, 1.1] {
      XCTAssertNil(Context.Simulation(entryID: "heart", phase: phase, first: 80, second: 70))
    }
    XCTAssertNil(Context.Simulation(entryID: "heart", phase: 0, first: 80.5, second: 70))
    XCTAssertNil(Context.Simulation(entryID: "heart", phase: 0, first: 20, second: 70))
    XCTAssertNil(Context.Elimination(halfLife: 0, elapsed: 8))
    XCTAssertNil(Context.Elimination(halfLife: .nan, elapsed: 8))
    XCTAssertNil(Context.Elimination(halfLife: 4, elapsed: 49))
    XCTAssertNil(Context.Elimination(halfLife: 3.5, elapsed: 8))
    var simulation = try XCTUnwrap(Context.Simulation(entryID: "heart", phase: 0, first: 70, second: 70))
    let frozen = try XCTUnwrap(Context.prompt(anatomy: anatomy(), screen: .simulation, simulation: simulation, locale: locale, text: text))
    simulation = try XCTUnwrap(Context.Simulation(entryID: "heart", phase: 1, first: 80, second: 80))
    XCTAssertTrue(frozen.contains("Stage 1 / 4"))
    XCTAssertFalse(frozen.contains("80 bpm"))
    XCTAssertEqual(simulation.stage, 3)
  }

  private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
  private func identity(metric: GalaxySSIHealthMetric = .bloodPressure, component: GalaxySSIHealthTrend.Component = .value,
                        unit: String = "mmHg", source: GalaxySSIHealthTrend.Source = .all, device: UUID? = nil,
                        origin: GalaxySSIHealthTrend.HealthOrigin = .all, aggregation: GalaxySSIHealthTrend.Aggregation = .latest,
                        days: Int = 7, selection: String = "heart:bp:week", timeZone: TimeZone? = nil,
                        through: Date = Date(timeIntervalSince1970: 1_735_689_600)) -> GalaxySSIHealthAtlasTrendAction.Identity {
    let spec = GalaxySSIHealthTrendAnalysis.Spec(metric: metric, component: component, unit: unit, source: source, device: device,
      origin: origin, aggregation: aggregation, through: through, days: days, calendar: calendar)
    return .init(spec: spec, environmentCalendar: calendar, timeZone: timeZone ?? calendar.timeZone, selection: selection)
  }
  func testAChangedScopeImmediatelyDisablesTheCapturedPersonalAction() {
    let captured = identity()
    let changed = [identity(metric: .glucose), identity(component: .diastolic), identity(unit: "kPa"), identity(source: .manual),
      identity(device: UUID()), identity(origin: .application("test.example")), identity(aggregation: .mean), identity(days: 30),
      identity(selection: "heart:bp:month"), identity(timeZone: TimeZone(secondsFromGMT: 28_800)!),
      identity(through: Date(timeIntervalSince1970: 1_735_693_200))]
    for current in changed {
      XCTAssertNotEqual(captured, current)
      XCTAssertFalse(GalaxySSIHealthAtlasTrendAction.ready(captured: captured, current: current, foreground: true,
        protectedData: true, permitted: true, changed: false, hasChartData: true))
    }
  }
  func testBackgroundRevocationLoadingAndEmptyChartsCannotUsePersonalAnalysis() {
    let scope = identity()
    func ready(captured: GalaxySSIHealthAtlasTrendAction.Identity? = nil, active: Bool = true,
               protected: Bool = true, permitted: Bool = true, changed: Bool = false, data: Bool = true) -> Bool {
      GalaxySSIHealthAtlasTrendAction.ready(captured: captured, current: scope, foreground: active,
        protectedData: protected, permitted: permitted, changed: changed, hasChartData: data)
    }
    XCTAssertTrue(ready(captured: scope))
    XCTAssertFalse(ready())
    XCTAssertFalse(ready(captured: scope, active: false))
    XCTAssertFalse(ready(captured: scope, protected: false))
    XCTAssertFalse(ready(captured: scope, permitted: false))
    XCTAssertFalse(ready(captured: scope, changed: true))
    XCTAssertFalse(ready(captured: scope, data: false))
  }
}
