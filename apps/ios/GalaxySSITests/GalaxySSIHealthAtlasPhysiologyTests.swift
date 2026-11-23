import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthAtlasPhysiologyTests: XCTestCase {
  typealias Model = GalaxySSIHealthAtlasPhysiology

  func testTwoCompartmentSolutionMatchesIndependentAndroidMatrixExponentialFixtures() throws {
    typealias Distribution = GalaxySSIHealthAtlasDistribution
    let fixtures: [(Distribution?, [Double])] = [
      (.init(outward: 30, returning: 15, elimination: 10, quarterHours: 16),
        [31.31146654418996, 46.72275917640283, 21.96577427940722]),
      (.init(outward: 300, returning: 100, elimination: 10, quarterHours: 8),
        [22.94872068963114, 70.48922199949571, 6.56205731087311]),
      (.init(outward: 1, returning: 300, elimination: 1, quarterHours: 192),
        [61.77014723483772, 0.20658681812629, 38.02326594703583]),
      (.init(outward: 300, returning: 0, elimination: 10, quarterHours: 16),
        [0.000411858870753571, 96.7737949752864, 3.22579316584287])
    ]
    for (candidate, expected) in fixtures {
      let model = try XCTUnwrap(candidate)
      for (actual, value) in zip(model.amounts.values, expected) { XCTAssertEqual(actual, value, accuracy: 1e-10) }
    }
    for a in [0, 1, 99, 300] {
      for b in [0, 1, 99, 300] {
        for e in [0, 1, 99, 300] {
          let model = try XCTUnwrap(Distribution(outward: a, returning: b, elimination: e))
          var previousLoss = 0.0
          for step in 0...192 {
            let value = try XCTUnwrap(model.at(Double(step) / 4))
            XCTAssertEqual(value.values.reduce(0, +), 100, accuracy: 1e-10)
            XCTAssertTrue(value.values.allSatisfy { $0.isFinite && (0...100).contains($0) })
            XCTAssertGreaterThanOrEqual(value.eliminated + 1e-10, previousLoss)
            previousLoss = value.eliminated
          }
        }
      }
    }
  }

  func testDrugModesRestoreBoundedInputsAndHandleRepeatedRoot() throws {
    typealias Distribution = GalaxySSIHealthAtlasDistribution
    let model = try XCTUnwrap(Distribution(outward: 0, returning: 10, elimination: 10))
    let amounts = try XCTUnwrap(model.at(4))
    XCTAssertEqual(amounts.central, 100 * exp(-0.4), accuracy: 1e-12)
    XCTAssertEqual(amounts.peripheral, 0)
    let state = GalaxySSIHealthAtlasDrugState(mode: .two, distribution: .standard)
    XCTAssertEqual(GalaxySSIHealthAtlasDrugState.restore(state.encoded), state)
    for invalid in [nil, [], [2, 30, 15, 10, 16], [1, 301, 15, 10, 16], [1, 30, 15, 10, -1]] as [[Int]?] {
      XCTAssertNil(GalaxySSIHealthAtlasDrugState.restore(invalid))
    }
    for invalid in [Double.nan, .infinity, -1, 49] { XCTAssertNil(model.at(invalid)) }
  }

  func testRenalTransfersConserveSoluteAndRejectInvalidInputs() throws {
    typealias Amounts = GalaxySSIHealthAtlasRenalAmounts
    let baseline = try XCTUnwrap(Amounts(filtered: 100, reabsorbedPercent: 90, secreted: 10))
    XCTAssertEqual(baseline.transfers, [100, 90, 10, 20])
    for filtered in [0.0, 100, 200] {
      for fraction in [0.0, 50, 100] {
        let values = try XCTUnwrap(Amounts(filtered: filtered, reabsorbedPercent: fraction, secreted: 30))
        XCTAssertEqual(values.filtered + values.secreted, values.reabsorbed + values.excreted, accuracy: 1e-9)
      }
    }
    XCTAssertNil(Amounts(filtered: .infinity, reabsorbedPercent: 90, secreted: 10))
    XCTAssertNil(Amounts(filtered: -1, reabsorbedPercent: 90, secreted: 10))
    XCTAssertNil(Amounts(filtered: 100, reabsorbedPercent: .nan, secreted: 10))
    XCTAssertNil(Amounts(filtered: 100, reabsorbedPercent: 101, secreted: 10))
    XCTAssertNil(Amounts(filtered: 100, reabsorbedPercent: 90, secreted: -1))
    XCTAssertNil(Amounts(filtered: .greatestFiniteMagnitude, reabsorbedPercent: 0, secreted: .greatestFiniteMagnitude))
    for id in ["proximal-tubule", "nephron-loop", "distal-tubule"] {
      XCTAssertEqual(Model.Kind.forEntry(id), .renal)
    }
    let model = Model(kind: .renal)
    XCTAssertEqual(model.renalAmounts, baseline)
    XCTAssertEqual(model.result, baseline.excreted)
    XCTAssertEqual(model.companionValue, baseline.reabsorbed)
    let prompt = GalaxySSIHealthAtlasPhysiologyText.context(model, language: "en")
    XCTAssertTrue(prompt.contains("Whole-nephron solute balance"))
    XCTAssertTrue(prompt.contains("Blood → tubular lumen"))
    XCTAssertTrue(prompt.contains("Tubular lumen → blood"))
    XCTAssertTrue(prompt.contains("Tubular lumen → urine"))
  }

  func testVentilationSeparatesAlveolarAndTotalFlow() throws {
    let model = Model(kind: .ventilation)
    XCTAssertEqual(model.result, 4.2, accuracy: 1e-9)
    XCTAssertEqual(model.companionValue, 6, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(2, to: 0)).result, 6, accuracy: 1e-9)
    let shallow = try XCTUnwrap(model.changing(0, to: 24)?.changing(1, to: 250))
    XCTAssertEqual(model.companionValue, shallow.companionValue, accuracy: 1e-9)
    XCTAssertEqual(shallow.result, 2.4, accuracy: 1e-9)
    XCTAssertLessThan(shallow.result, model.result)
    let noExchange = try XCTUnwrap(model.changing(1, to: 200)?.changing(2, to: 200))
    XCTAssertEqual(noExchange.result, 0, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 24)).result, 8.4, accuracy: 1e-9)
  }

  func testRenalMassConservationAndUnitsAcrossTheGrid() throws {
    for filtered in stride(from: 0, through: 200, by: 10) {
      for fraction in stride(from: 0, through: 100, by: 5) {
        for secreted in stride(from: 0, through: 100, by: 10) {
          let model = try XCTUnwrap(Model(kind: .renal, inputs: [filtered, fraction, secreted]))
          XCTAssertEqual(Double(filtered + secreted), model.result + model.companionValue, accuracy: 1e-9)
          XCTAssertGreaterThanOrEqual(model.result, 0)
          XCTAssertGreaterThanOrEqual(model.companionValue, 0)
        }
      }
    }
    let model = Model(kind: .renal)
    XCTAssertEqual(model.result, 20, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 100)).result, 10, accuracy: 1e-9)
    XCTAssertEqual(model.kind.unit, "mg/min")
  }

  func testPotassiumUsesNaturalLogKelvinAndMillivolts() throws {
    XCTAssertEqual(try XCTUnwrap(Model.potassiumPotential(outside: 4, inside: 140)), -95.0266, accuracy: 0.01)
    XCTAssertEqual(try XCTUnwrap(Model.potassiumPotential(outside: 140, inside: 140)), 0, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Model.potassiumPotential(outside: 10, inside: 1)), 61.5404, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(Model.potassiumPotential(outside: 140, inside: 4)),
      -(try XCTUnwrap(Model.potassiumPotential(outside: 4, inside: 140))), accuracy: 1e-9)
    let model = Model(kind: .potassium)
    XCTAssertEqual(model.input(0), 4)
    XCTAssertEqual(model.kind.inputs[0].scale, 10)
    XCTAssertGreaterThan(try XCTUnwrap(model.changing(0, to: 80)).result, model.result)
  }

  func testCurvesUseIdenticalEquationsAndRespectBoundsAndMonotonicity() throws {
    for kind in Model.Kind.allCases {
      var models = [Model(kind: kind)]
      for index in kind.inputs.indices {
        models = try models.flatMap { model in
          [try XCTUnwrap(model.changing(index, to: kind.inputs[index].range.lowerBound)),
           try XCTUnwrap(model.changing(index, to: kind.inputs[index].range.upperBound))]
        }
      }
      for model in models {
        XCTAssertEqual(try XCTUnwrap(model.resultAt(model.input(kind.axis))), model.result, accuracy: 1e-9)
        XCTAssertEqual(model.response.count, 121)
        var previous: Double?
        for point in model.response {
          XCTAssertTrue(point.y.isFinite)
          XCTAssertTrue(kind.bounds.contains(point.y))
          if let previous {
            if kind == .renal { XCTAssertLessThanOrEqual(point.y, previous + 1e-9) }
            else { XCTAssertGreaterThanOrEqual(point.y, previous - 1e-9) }
          }
          previous = point.y
        }
      }
    }
  }

  func testInvalidInputsAndRestorationAreRejectedRatherThanClamped() {
    for kind in Model.Kind.allCases {
      XCTAssertNil(Model(kind: kind, inputs: []))
      let model = Model(kind: kind)
      for index in model.inputs.indices {
        XCTAssertNil(model.changing(index, to: kind.inputs[index].range.lowerBound - 1))
        XCTAssertNil(model.changing(index, to: kind.inputs[index].range.upperBound + 1))
      }
      XCTAssertNil(model.changing(-1, to: 1))
      for invalid in [Double.nan, .infinity, -.infinity, model.axisRange.lowerBound - 1, model.axisRange.upperBound + 1] {
        XCTAssertNil(model.resultAt(invalid))
      }
    }
    for invalid in [Double.nan, .infinity, 0, -1] {
      XCTAssertNil(Model.potassiumPotential(outside: invalid, inside: 140))
      XCTAssertNil(Model.potassiumPotential(outside: 4, inside: invalid))
    }
    XCTAssertNil(Model.restore("kidneys", inputs: [100, 101, 10]))
    XCTAssertNil(Model.restore("brain", inputs: [0, 140]))
    XCTAssertNil(Model.restore("liver", inputs: [40, 140]))
  }

  func testCanonicalAssignmentMatchesAndroidAndDoesNotExpandToRelatedCells() {
    let ids = ["respiratory", "lungs", "alveoli", "urinary", "kidneys", "nephron", "renal-tubules", "collecting-ducts",
      "cell-proximal-tubular-cell", "cell-distal-tubular-cell", "cell-collecting-duct-principal-cell",
      "cell-collecting-duct-intercalated-cell", "nervous", "brain", "spinal-cord", "cell-neuron", "cell-olfactory-receptor-neuron",
      "proximal-tubule", "nephron-loop", "distal-tubule", "skeletal", "muscle", "biceps-brachii", "humerus", "radius", "ulna"]
    XCTAssertEqual(ids.count, 26)
    for id in ids { XCTAssertNotNil(Model.Kind.forEntry(id)) }
    for id in ["liver", "cell-hepatocyte", "renal-cortex", "renal-pelvis", "cell-type-ii-pneumocyte", "heart"] {
      XCTAssertNil(Model.Kind.forEntry(id))
    }
  }

  func testElbowFixturesBalanceForcesAndMomentsWithStrictUnitConversion() throws {
    let forces = try XCTUnwrap(GalaxySSIHealthAtlasElbow.forces(loadKg: 4, loadArmCm: 38, muscleArmMm: 40))
    XCTAssertEqual(forces.muscle, 470.4, accuracy: 1e-9)
    XCTAssertEqual(forces.jointDown, 406.7, accuracy: 1e-9)
    XCTAssertEqual(forces.torque, 18.816, accuracy: 1e-9)
    let model = Model(kind: .elbow)
    XCTAssertEqual(model.result, forces.muscle, accuracy: 1e-9)
    XCTAssertEqual(model.companionValue, forces.jointDown, accuracy: 1e-9)
    XCTAssertEqual(model.plotMaximum, 1100)
    for load in stride(from: 0, through: 100, by: 5) {
      for distance in stride(from: 20, through: 50, by: 3) {
        for arm in stride(from: 20, through: 60, by: 4) {
          let result = try XCTUnwrap(GalaxySSIHealthAtlasElbow.forces(loadKg: Double(load) / 10,
            loadArmCm: Double(distance), muscleArmMm: Double(arm)))
          XCTAssertEqual(result.muscle - result.jointDown - result.armWeight - result.loadWeight, 0, accuracy: 1e-9)
          XCTAssertEqual(result.muscle * result.muscleArmMetres,
            result.armWeight * 0.16 + result.loadWeight * result.loadArmMetres, accuracy: 1e-9)
          let changed = try XCTUnwrap(Model(kind: .elbow, inputs: [load, distance, arm]))
          XCTAssertTrue((0...changed.plotMaximum).contains(changed.result))
          XCTAssertLessThanOrEqual(changed.plotMaximum, 2700)
        }
      }
    }
    for invalid in [Double.nan, .infinity, -1, 11] {
      XCTAssertNil(GalaxySSIHealthAtlasElbow.forces(loadKg: invalid, loadArmCm: 38, muscleArmMm: 40))
    }
    XCTAssertNil(GalaxySSIHealthAtlasElbow.forces(loadKg: 4, loadArmCm: 19, muscleArmMm: 40))
    XCTAssertNil(GalaxySSIHealthAtlasElbow.forces(loadKg: 4, loadArmCm: 38, muscleArmMm: 61))
    XCTAssertNil(Model.restore("biceps-brachii", inputs: [40, 38, 0]))
    XCTAssertNil(Model.Kind.forEntry("triceps-brachii"))
    XCTAssertNil(Model.Kind.forEntry("cell-skeletal-muscle-fiber"))
  }

  func testLegacyVentilationMigrationAndIndependentEntryRestoration() throws {
    let migrated = try XCTUnwrap(Model.resolved("lungs", inputs: nil, legacyVentilation: [24, 600]))
    XCTAssertEqual(migrated.inputs, [24, 600, 150])
    let saved = try XCTUnwrap(Model.resolved("lungs", inputs: [10, 400, 100], legacyVentilation: [24, 600]))
    XCTAssertEqual(saved.inputs, [10, 400, 100])
    XCTAssertEqual(Model.resolved("lungs", inputs: nil, legacyVentilation: [.nan, 600])?.inputs, [12, 500, 150])
    XCTAssertEqual(Model.resolved("alveoli", inputs: nil, legacyVentilation: [24, 600])?.inputs, [12, 500, 150])
    XCTAssertEqual(Model.restore("brain", inputs: [80, 140])?.inputs, [80, 140])
    XCTAssertEqual(Model.restore("kidneys", inputs: [100, 50, 10])?.inputs, [100, 50, 10])
  }

  func testPublicContextIncludesSyntheticInputsOutputAssumptionsAndSource() {
    for kind in Model.Kind.allCases {
      let model = Model(kind: kind)
      let text = GalaxySSIHealthAtlasPhysiologyText.context(model, language: "en")
      XCTAssertTrue(text.contains("Not personal measurements"))
      XCTAssertTrue(text.contains(model.kind.source.absoluteString))
      XCTAssertTrue(text.contains(GalaxySSIHealthAtlasPhysiologyText.result(model, language: "en")))
      for index in model.inputs.indices {
        XCTAssertTrue(text.contains(GalaxySSIHealthAtlasPhysiologyText.input(model, index: index, language: "en")))
      }
      XCTAssertFalse(text.contains("measuredAt"))
      XCTAssertNotEqual(GalaxySSIHealthAtlasPhysiologyText.string("model_" + kind.rawValue, language: "en"),
        GalaxySSIHealthAtlasPhysiologyText.string("model_" + kind.rawValue, language: "zh-Hans"))
    }
  }
}
