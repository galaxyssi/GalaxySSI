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

  func testMaterialResponseModelsPreserveUnitsLimitsAndOwnerRouting() throws {
    let diffusion = Model(kind: .alveolarDiffusion)
    XCTAssertEqual(diffusion.inputs, [100, 100, 100])
    XCTAssertEqual(diffusion.result, 1)
    XCTAssertEqual(try XCTUnwrap(diffusion.changing(0, to: 0)).result, 0)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .alveolarDiffusion, inputs: [200, 200, 50])).result, 8)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .alveolarDiffusion, inputs: [100, 200, 50])).companionValue, 4)
    let cartilage = Model(kind: .cartilageCompression)
    XCTAssertEqual(cartilage.result, 2)
    XCTAssertEqual(cartilage.companionValue, 98)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .cartilageCompression, inputs: [64, 80])).result, 8)
    let bone = Model(kind: .boneBending)
    let inertia = Double.pi * pow(30.0, 4) * (1 - pow(0.6, 4)) / 64
    XCTAssertEqual(bone.companionValue, inertia, accuracy: 1e-9)
    XCTAssertEqual(bone.result, 500 * 6 * 30 / inertia, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(bone.changing(0, to: 0)).result, 0)
    for (kind, owners) in [
      (Model.Kind.alveolarDiffusion, ["respiratory-membrane", "pulmonary-capillaries", "tissue-alveolar-epithelium", "cell-type-i-pneumocyte"]),
      (.cartilageCompression, ["cartilage", "tissue-hyaline-cartilage", "cell-chondrocyte"]),
      (.boneBending, ["limb-bones", "femur", "tibia", "fibula"])
    ] {
      XCTAssertEqual(kind.axis, 0)
      XCTAssertTrue(kind.hasMaterialResponse)
      for owner in owners {
        XCTAssertEqual(Model.Kind.forEntry(owner), kind)
        XCTAssertEqual(Model.restore(owner, inputs: Model(kind: kind).inputs)?.kind, kind)
      }
      for language in ["en", "zh-Hans"] {
        let model = Model(kind: kind)
        XCTAssertFalse(GalaxySSIHealthAtlasPhysiologyText.context(model, language: language).contains("health_atlas_"))
        XCTAssertFalse(GalaxySSIHealthAtlasMaterialResponseView.description(kind, language: language).contains("health_atlas_"))
      }
    }
    XCTAssertEqual(Model.Kind.forEntry("lungs"), .ventilation)
    XCTAssertEqual(Model.Kind.forEntry("cell-type-ii-pneumocyte"), .alveolarSurface)
    XCTAssertEqual(Model.Kind.forEntry("humerus"), .elbow)
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
            if [Model.Kind.renal, .eye, .cushionContactPressure, .airwaySplit, .visualAngle, .hormoneSignal,
                .arterialContinuity, .glialCapacitance, .colonicWaterBalance, .endocrineDilution,
                .gastricLiquidEmptying, .boneRemodelingBalance, .cutaneousSebum,
                .externalEarResonance, .sweatDuctBalance, .oralMarkerDilution,
                .renalTubuleRetention, .mucusFilmThickness, .gametePathDistance,
                .vulvarFoldOverlap, .retinalLightAttenuation].contains(kind) { XCTAssertLessThanOrEqual(point.y, previous + 1e-9) }
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
      "proximal-tubule", "nephron-loop", "distal-tubule", "skeletal", "muscle", "biceps-brachii", "humerus", "radius", "ulna",
      "blood-vessels", "arteries", "veins", "coronary-vessels", "eye", "lens", "ear", "middle-ear",
      "cranial-nerves", "spinal-nerves", "peripheral-nerves", "ventricles", "left-ventricle", "right-ventricle", "cell-type-ii-pneumocyte",
      "pancreas", "pancreatic-duct", "cell-pancreatic-ductal-cell", "thyroid-gland", "cell-rod-photoreceptor", "sweat-glands", "lymphatic-vessels",
      "small-intestine", "jejunum"]
    XCTAssertEqual(ids.count, 50)
    for id in ids { XCTAssertNotNil(Model.Kind.forEntry(id)) }
    XCTAssertEqual(Model.Kind.forEntry("renal-cortex"), .renalTubuleRetention)
    XCTAssertEqual(Model.Kind.forEntry("cell-type-i-pneumocyte"), .alveolarDiffusion)
    XCTAssertEqual(Model.Kind.forEntry("cell-podocyte"), .glomerularFiltration)
  }

  func testTeachingModelsUseSourceDefaultsScaledUnitsAndLocalBindings() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let fixtures: [(Teaching, Double, Double)] = [
      (.capillaryExchange, 63.2120558829, 36.7879441171), (.valveFlux, 125, 12.5),
      (.glomerularFiltration, 30, 12), (.skinWaterBarrier, 1, 1), (.salivaryDelivery, 8, 40),
      (.tendonElongation, 0.1, 0.2), (.airwaySplit, 0.2, 0.1), (.peristalticTravel, 5, 50),
      (.cochlearFrequency, 1710.2665234, 50), (.diaphragmDisplacement, 216, 18),
      (.cardiacPhaseTime, 400, 800), (.visualAngle, 5.724810452, 2.862405226),
      (.serialAbsorption, 70, 30), (.hormoneSignal, 25, 75), (.immuneComposition, 50, 150),
      (.ductTransit, 4.8, 0.4), (.oviductCiliaryCycles, 7.5, 200), (.kneeMoment, 0.4, 0.04),
      (.arterialContinuity, 70 / (.pi * 1.44), .pi * 1.44), (.glialCapacitance, 1, 1),
      (.colonicWaterBalance, 100, 400), (.lymphParticleTransport, 6, 30), (.endocrineDilution, 1.5, 6),
      (.boneSection, 60 / (16 * .pi), 16 * .pi), (.retinalConvergence, 2, 6),
      (.muscleShortening, 0.25, 2.25), (.keratinGrowth, 4, 2),
      (.bladderExpansion, 58.74010519681994, 4 * .pi * pow(cbrt(600 / (4 * .pi)), 2)),
      (.vestibularTilt, 16.699244234, 1.044030651), (.airwayCiliaryClearance, 18, 30),
      (.gastricLiquidEmptying, 40.96, 59.04), (.bileStorage, 1, 6),
      (.thoracicCrossSection, 135 * .pi, 0.6), (.plateletFragmentCount, 12, 3),
      (.boneRemodelingBalance, 0, 100), (.cutaneousSebum, 5, 40),
      (.ureterDelivery, 6, 6), (.cornealRefraction, 28.665304049, 11.334695951),
      (.externalEarResonance, 428.75, 80), (.neuralRelayDelays, 4.5, 3), (.biliaryFlowTally, 10, 40),
      (.parathyroidSignalOccupancy, 50, 50), (.follicleSurface, 81 * .pi, 217 * .pi / 6),
      (.jointArticularArc, 19.634954085, 0.785398163), (.sweatDuctBalance, 35, 105),
      (.vocalCycles, 2.8, 1000.0 / 140), (.vertebralSeries, 1, 19), (.oralMarkerDilution, 1, 8),
      (.olfactorySurfaceRetention, 28, 52), (.circadianLightWindow, 450, 90), (.adiposeVolumeShare, 43.74, 72.9),
      (.thymicBranching, 28, 52), (.gastricPrecursorBalance, 4.2, 7.8), (.melaninDistribution, 3, 12),
      (.placentalMarker, 20, 60), (.renalTubuleRetention, 45, 55), (.merkelContact, 10 / .pi, 4 * .pi),
      (.toothEnamelSection, 43.75, 9 * .pi), (.mucosalSampling, 25, 75), (.mammaryDuctDelivery, 4.8, 3.2),
      (.rectalReservoir, 48, 72), (.stromalMatrix, 9, 6), (.mucusFilmThickness, 2, 12),
      (.pleuralSlide, 10, 0.1), (.retinalLightAttenuation, 36.7879441171, 63.2120558829),
      (.gametePathDistance, 10, 16), (.testisTubuleSection, 100.0 * 20 / 36, 16 * .pi),
      (.uterineLiningArea, 16 * .pi, 4 * .pi), (.vulvarFoldOverlap, 25, 37.5),
      (.capillarySupportSurface, 240 * .pi, 8 * .pi), (.marrowRenewal, 2, 14), (.ependymalBeatPhase, 1.5625, 0.5625)
    ]
    XCTAssertEqual(Teaching.allCases.count, 72)
    XCTAssertEqual(Teaching.allCases.flatMap(\.controls).count, 150)
    XCTAssertEqual(Set(Teaching.allCases.flatMap(\.entryIDs)).count, 216)
    for (teaching, expected, companion) in fixtures {
      let kind = try XCTUnwrap(Model.Kind(rawValue: teaching.rawValue)), model = Model(kind: kind)
      XCTAssertEqual(model.result, expected, accuracy: 1e-6)
      XCTAssertEqual(model.companionValue, companion, accuracy: 1e-6)
      XCTAssertEqual(kind.axis, teaching.axis); XCTAssertEqual(kind.unit, teaching.unit)
      XCTAssertEqual(kind.bounds, teaching.bounds); XCTAssertEqual(kind.sources, teaching.sources)
      let scaled = model.inputs.indices.map(model.input)
      XCTAssertEqual(try XCTUnwrap(teaching.evaluate(scaled)), model.result)
      XCTAssertEqual(try XCTUnwrap(teaching.companion(scaled)), model.companionValue)
      XCTAssertNil(teaching.evaluate([])); XCTAssertNil(teaching.companion([]))
      for invalid in [Double.nan, .infinity, -.infinity] {
        var values = scaled; values[0] = invalid
        XCTAssertNil(teaching.evaluate(values)); XCTAssertNil(teaching.companion(values))
      }
      for id in teaching.entryIDs {
        XCTAssertEqual(Model.Kind.forEntry(id), kind)
        XCTAssertEqual(Model.restore(id, inputs: model.inputs), model)
      }
      for locale in ["en", "zh-Hans"] {
        let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: locale)
        XCTAssertFalse(context.contains("health_atlas_"))
        XCTAssertTrue(context.contains(GalaxySSIHealthAtlasText.get(teaching.scope, locale)))
        XCTAssertTrue(context.contains(GalaxySSIHealthAtlasText.get(teaching.formula, locale)))
        for source in teaching.sources { XCTAssertTrue(context.contains(source.absoluteString)) }
        for index in model.inputs.indices {
          XCTAssertTrue(context.contains(GalaxySSIHealthAtlasPhysiologyText.input(model, index: index, language: locale)))
        }
      }
    }
    XCTAssertEqual(Model(kind: .tendonElongation).input(3), 750)
    XCTAssertEqual(Model(kind: .valveFlux).input(0), 2.5)
    XCTAssertEqual(Model(kind: .airwaySplit).input(0), 0.3)
    XCTAssertNil(Model.restore("inner-ear", inputs: [35, 20, 160]))
    XCTAssertEqual(Model.restore("inner-ear", inputs: [50])?.kind, .cochlearFrequency)
    XCTAssertNil(Model.restore("tendons", inputs: [40, 38]))
  }

  func testTeachingModelBoundaryFixturesPreservePressureAndFlowMeaning() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    for (inputs, pressure, flow) in [([40.0, 13, 28, 2.5], -1.0, 0.0),
      ([41.0, 13, 28, 2.5], 0.0, 0.0), ([41.5, 13, 28, 2.5], 0.5, 1.25)] {
      XCTAssertEqual(try XCTUnwrap(Teaching.glomerularFiltration.evaluate(inputs)), flow)
      XCTAssertEqual(try XCTUnwrap(Teaching.glomerularFiltration.companion(inputs)), pressure)
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.tendonElongation.evaluate([9, 70, 4.5, 800])), 0.175, accuracy: 1e-12)
    XCTAssertEqual(try XCTUnwrap(Teaching.tendonElongation.companion([9, 70, 4.5, 800])), 0.25, accuracy: 1e-12)
    XCTAssertEqual(try XCTUnwrap(Teaching.salivaryDelivery.evaluate([3.125, 4, 1])), 8.125)
    for x in [0.0, 0.25, 0.5, 1.0] {
      XCTAssertEqual(try XCTUnwrap(Teaching.cochlearFrequency.companion([x])), 100 * (1 - x))
    }
    for values in [[0.5, 1.0, 4.0], [0.5, 4.0, 1.0], [0.5, 2.0, 2.0]] {
      let selected = try XCTUnwrap(Teaching.airwaySplit.evaluate(values))
      let other = try XCTUnwrap(Teaching.airwaySplit.companion(values))
      XCTAssertEqual(selected + other, values[0], accuracy: 1e-12)
      XCTAssertEqual(selected * values[1], other * values[2], accuracy: 1e-12)
    }
    let capillary = Model(kind: .capillaryExchange)
    XCTAssertEqual(try XCTUnwrap(capillary.changing(0, to: 0)).companionValue, 100)
    XCTAssertNil(Model(kind: .capillaryExchange, inputs: [20, 0]))
    XCTAssertEqual(Model.Kind.forEntry("pulmonary-capillaries"), .alveolarDiffusion)
    XCTAssertEqual(Model.Kind.forEntry("veins"), .vessel)
  }

  func testSystemTeachingPairsPreserveSourceConservationAndUnitConversions() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let kinds: [Teaching] = [.diaphragmDisplacement, .cardiacPhaseTime, .visualAngle, .serialAbsorption,
      .hormoneSignal, .immuneComposition, .ductTransit, .oviductCiliaryCycles, .kneeMoment]
    for teaching in kinds {
      let controls = teaching.inputs
      for first in controls[0].range {
        for second in controls[1].range {
          let values = [Double(first) / controls[0].scale, Double(second) / controls[1].scale]
          let output = try XCTUnwrap(teaching.evaluate(values)), other = try XCTUnwrap(teaching.companion(values))
          XCTAssertTrue(teaching.bounds.contains(output))
          switch teaching {
          case .diaphragmDisplacement: XCTAssertEqual(output, other * values[0], accuracy: 1e-9)
          case .cardiacPhaseTime:
            XCTAssertEqual(other * values[0], 60_000, accuracy: 1e-9)
            XCTAssertEqual(output * 100 / other, values[1], accuracy: 1e-9)
          case .visualAngle: XCTAssertEqual(output, 2 * other, accuracy: 1e-9)
          case .serialAbsorption:
            XCTAssertEqual(output, values[0] + (100 - values[0]) * values[1] / 100, accuracy: 1e-9)
            XCTAssertEqual(output + other, 100, accuracy: 1e-9)
          case .hormoneSignal: XCTAssertEqual(output + other, 100, accuracy: 1e-9)
          case .immuneComposition:
            XCTAssertEqual(output + other, values[0], accuracy: 1e-9)
            XCTAssertEqual(output, output.rounded(), accuracy: 1e-9)
          case .ductTransit:
            XCTAssertEqual(output * values[1], values[0], accuracy: 1e-9)
            XCTAssertEqual(output, other * values[0], accuracy: 1e-9)
          case .oviductCiliaryCycles:
            XCTAssertEqual(output, values[0] * values[1], accuracy: 1e-9)
            XCTAssertEqual(other * values[0], 1000, accuracy: 1e-9)
          case .kneeMoment: XCTAssertEqual(output, values[0] * other, accuracy: 1e-9)
          default: XCTFail("Unexpected system teaching model")
          }
        }
      }
      for invalid in [0, 1] {
        var values = controls.map { Double($0.initial) / $0.scale }
        values[invalid] = Double(controls[invalid].range.upperBound + 1) / controls[invalid].scale
        XCTAssertNil(teaching.evaluate(values)); XCTAssertNil(teaching.companion(values))
      }
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.hormoneSignal.evaluate([2, 2])), 50)
    XCTAssertEqual(try XCTUnwrap(Teaching.hormoneSignal.evaluate([2, 1])), 70.71067811865476, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.visualAngle.evaluate([10, 50])),
      try XCTUnwrap(Teaching.visualAngle.evaluate([20, 100])), accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.oviductCiliaryCycles.evaluate([4, 0.3])), 1.2, accuracy: 1e-9)
    XCTAssertEqual(Model.Kind.forEntry("respiratory"), .ventilation)
    XCTAssertEqual(Model.Kind.forEntry("lungs"), .ventilation)
    XCTAssertEqual(Model.Kind.forEntry("cell-neutrophil"), .immuneComposition)
    XCTAssertEqual(Model.Kind.forEntry("cell-thyrotroph"), .hormoneSignal)
  }

  func testSystemTeachingVisibleUnitsAndDiaphragmDescriptionAreLocalized() {
    typealias Text = GalaxySSIHealthAtlasPhysiologyText
    for language in ["en", "zh-Hans"] {
      for (unit, suffix) in [("bpm", "heart_rate"), ("cells", "cells"), ("cycles", "cycles")] {
        XCTAssertEqual(Text.displayUnit(unit, language: language),
          GalaxySSIHealthAtlasText.get("health_atlas_teaching_unit_" + suffix, language))
      }
      for unit in ["DU/min", "LU", "LU/TU", "TU", "Hz", "cm", "%", ""] {
        XCTAssertEqual(Text.displayUnit(unit, language: language), unit)
      }
      let model = Model(kind: .immuneComposition)
      XCTAssertTrue(Text.result(model, language: language).hasSuffix(Text.displayUnit("cells", language: language)))
      XCTAssertTrue(Text.input(model, index: 0, language: language).hasSuffix(Text.displayUnit("cells", language: language)))
      XCTAssertEqual(GalaxySSIHealthAtlasMaterialResponseView.description(.diaphragmDisplacement, language: language),
        GalaxySSIHealthAtlasText.get("health_atlas_diaphragm_demo_diagram", language))
    }
    XCTAssertTrue(Model.Kind.diaphragmDisplacement.hasMaterialResponse)
  }

  func testOrganTeachingPairsPreserveConservationAndSyntheticDimensions() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let kinds: [Teaching] = [.arterialContinuity, .glialCapacitance, .colonicWaterBalance,
      .lymphParticleTransport, .endocrineDilution, .boneSection, .retinalConvergence, .muscleShortening, .keratinGrowth]
    for teaching in kinds {
      let controls = teaching.inputs
      for first in controls[0].range {
        for second in controls[1].range {
          let values = [Double(first) / controls[0].scale, Double(second) / controls[1].scale]
          let output = try XCTUnwrap(teaching.evaluate(values)), other = try XCTUnwrap(teaching.companion(values))
          XCTAssertTrue(teaching.bounds.contains(output))
          switch teaching {
          case .arterialContinuity:
            XCTAssertEqual(output * other, values[1], accuracy: 1e-9)
            XCTAssertEqual(other, .pi * pow(values[0] / 20, 2), accuracy: 1e-9)
          case .glialCapacitance:
            XCTAssertEqual(output, values[1] * other, accuracy: 1e-9)
            XCTAssertEqual(other, log1p(0.5) / log1p(values[0] * 0.5), accuracy: 1e-9)
          case .colonicWaterBalance: XCTAssertEqual(output + other, values[0], accuracy: 1e-9)
          case .lymphParticleTransport: XCTAssertEqual(other, output * 5, accuracy: 1e-9)
          case .endocrineDilution:
            XCTAssertEqual(output * values[1], other, accuracy: 1e-9)
            XCTAssertEqual(other, values[0])
          case .boneSection:
            XCTAssertEqual(output * other, values[0], accuracy: 1e-9)
            XCTAssertEqual(other, .pi * (25 - pow(5 - values[1], 2)), accuracy: 1e-9)
          case .retinalConvergence: XCTAssertEqual(output + other, values[0], accuracy: 1e-9)
          case .muscleShortening:
            XCTAssertEqual(output + other, values[0] * 2.5 / 1000, accuracy: 1e-9)
            XCTAssertGreaterThan(other, 0)
          case .keratinGrowth: XCTAssertEqual(output * other, values[0], accuracy: 1e-9)
          default: XCTFail("Unexpected organ teaching model")
          }
        }
      }
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.retinalConvergence.evaluate([8, 25.5])), 2.04, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.muscleShortening.evaluate([750, 0.32])), 0.24, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.muscleShortening.companion([750, 0.32])), 1.635, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.lymphParticleTransport.evaluate([5, 6])), 30)
    XCTAssertEqual(try XCTUnwrap(Teaching.lymphParticleTransport.companion([5, 6])), 150)
    XCTAssertEqual(Model.Kind.forEntry("arteries"), .vessel)
    XCTAssertEqual(Model.Kind.forEntry("aorta"), .arterialContinuity)
    XCTAssertTrue(Model.Kind.arterialContinuity.hasMaterialResponse)
    XCTAssertEqual(Model(kind: .arterialContinuity, inputs: [20, 0])?.result, 0)
    for language in ["en", "zh-Hans"] {
      XCTAssertEqual(GalaxySSIHealthAtlasMaterialResponseView.description(.arterialContinuity, language: language),
        GalaxySSIHealthAtlasText.get("health_atlas_arterial_continuity_diagram", language))
    }
  }

  func testRegionalTeachingPairsRetainSignedChangeAndWholeFragmentSteps() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let kinds: [Teaching] = [.bladderExpansion, .vestibularTilt, .airwayCiliaryClearance,
      .gastricLiquidEmptying, .bileStorage, .thoracicCrossSection, .plateletFragmentCount,
      .boneRemodelingBalance, .cutaneousSebum]
    for teaching in kinds {
      let controls = teaching.inputs
      for first in controls[0].range {
        for second in controls[1].range {
          let values = [Double(first) / controls[0].scale, Double(second) / controls[1].scale]
          let output = try XCTUnwrap(teaching.evaluate(values)), other = try XCTUnwrap(teaching.companion(values))
          XCTAssertTrue(teaching.bounds.contains(output))
          switch teaching {
          case .bladderExpansion:
            let startArea = 4 * Double.pi * pow(cbrt(3 * values[0] / (4 * Double.pi)), 2)
            XCTAssertEqual(output, 100 * (other / startArea - 1), accuracy: 1e-9)
          case .vestibularTilt:
            XCTAssertEqual(other * other, values[0] * values[0] + values[1] * values[1], accuracy: 1e-9)
          case .airwayCiliaryClearance: XCTAssertEqual(other, 100 * output / 60, accuracy: 1e-9)
          case .gastricLiquidEmptying: XCTAssertEqual(output + other, 100, accuracy: 1e-9)
          case .bileStorage: XCTAssertEqual(output * (12 - values[1]), other, accuracy: 1e-9)
          case .thoracicCrossSection:
            XCTAssertEqual(output, .pi * values[0] * values[1] / 4, accuracy: 1e-9)
            XCTAssertEqual(other * values[1], values[0], accuracy: 1e-9)
          case .plateletFragmentCount:
            XCTAssertEqual(output, output.rounded())
            XCTAssertEqual(output, values[0] * other)
          case .boneRemodelingBalance:
            XCTAssertEqual(output + values[0], values[1])
            XCTAssertEqual(other - 100, output)
          case .cutaneousSebum: XCTAssertEqual(output * values[1], other, accuracy: 1e-9)
          default: XCTFail("Unexpected regional teaching model")
          }
        }
      }
    }
    for (icons, result) in [(2.49, 6.0), (2.5, 9.0), (2.51, 9.0)] {
      XCTAssertEqual(try XCTUnwrap(Teaching.plateletFragmentCount.evaluate([icons, 3])), result)
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.gastricLiquidEmptying.evaluate([36, 0.5])), 80, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.boneRemodelingBalance.evaluate([10.5, 10])), -0.5)
    XCTAssertEqual(try XCTUnwrap(Teaching.boneRemodelingBalance.evaluate([9.5, 10])), 0.5)
    XCTAssertEqual(try XCTUnwrap(Teaching.airwayCiliaryClearance.evaluate([6.2, 1.5])), 9.3, accuracy: 1e-9)
    XCTAssertEqual(Model.Kind.forEntry("kidneys"), .renal)
    XCTAssertEqual(Model(kind: .bladderExpansion, inputs: [100, 0])?.result, 0)
    XCTAssertTrue(Model.Kind.airwayCiliaryClearance.hasMaterialResponse)
  }

  func testTransportTeachingPairsKeepOpticsGeometryAndVolumeAccounting() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let kinds: [Teaching] = [.ureterDelivery, .cornealRefraction, .externalEarResonance, .neuralRelayDelays,
      .biliaryFlowTally, .parathyroidSignalOccupancy, .follicleSurface, .jointArticularArc, .sweatDuctBalance]
    for teaching in kinds {
      let controls = teaching.inputs
      for first in controls[0].range {
        for second in controls[1].range {
          let values = [Double(first) / controls[0].scale, Double(second) / controls[1].scale]
          let output = try XCTUnwrap(teaching.evaluate(values)), other = try XCTUnwrap(teaching.companion(values))
          XCTAssertTrue(teaching.bounds.contains(output))
          switch teaching {
          case .ureterDelivery: XCTAssertEqual(output + other, 6 * values[1], accuracy: 1e-9)
          case .cornealRefraction:
            XCTAssertEqual(sin(values[0] * .pi / 180), values[1] * sin(output * .pi / 180), accuracy: 1e-9)
            XCTAssertEqual(output + other, values[0], accuracy: 1e-9)
          case .externalEarResonance: XCTAssertEqual(output * (other / 100), values[1], accuracy: 1e-9)
          case .neuralRelayDelays: XCTAssertEqual(output - other, values[1], accuracy: 1e-9)
          case .biliaryFlowTally: XCTAssertEqual(other, output * 4, accuracy: 1e-9)
          case .parathyroidSignalOccupancy: XCTAssertEqual(output + other, 100, accuracy: 1e-9)
          case .follicleSurface:
            let outer = values[0] / 2 + values[1]
            XCTAssertEqual(output, 4 * .pi * outer * outer, accuracy: 1e-9)
            XCTAssertGreaterThan(other, 0)
          case .jointArticularArc: XCTAssertEqual(output, values[1] * other, accuracy: 1e-9)
          case .sweatDuctBalance: XCTAssertEqual(output + other, values[0], accuracy: 1e-9)
          default: XCTFail("Unexpected transport teaching model")
          }
        }
      }
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.biliaryFlowTally.evaluate([2.625, 4])), 10.5)
    XCTAssertEqual(try XCTUnwrap(Teaching.follicleSurface.evaluate([14, 1])), 256 * .pi, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.follicleSurface.companion([14, 1])), 676 * .pi / 3, accuracy: 1e-9)
    for (count, expected) in [(2.49, 4.0), (2.5, 6.0), (2.51, 6.0)] {
      XCTAssertEqual(try XCTUnwrap(Teaching.ureterDelivery.evaluate([count, 2])), expected)
    }
    XCTAssertEqual(Model.Kind.forEntry("renal-pelvis"), .ureterDelivery)
    XCTAssertEqual(Model.Kind.forEntry("cell-hepatocyte"), .biliaryFlowTally)
    XCTAssertEqual(Model.Kind.forEntry("liver"), .biliaryFlowTally)
    XCTAssertEqual(Model.Kind.forEntry("kidneys"), .renal)
    XCTAssertEqual(Model.Kind.forEntry("bladder"), .bladderExpansion)
    XCTAssertTrue(Model.Kind.cornealRefraction.hasMaterialResponse)
  }

  func testSharedTeachingPlaybackPausesResumesReplaysAndResetsWithoutChangingInputs() throws {
    typealias Playback = GalaxySSIHealthAtlasTeachingPlaybackState
    let start = Date(timeIntervalSince1970: 0), model = Model(kind: .bladderExpansion)
    let selected = model.inputs
    var playback = Playback()
    XCTAssertEqual(playback.phase(at: start, duration: 1.8), 1)
    playback.start(at: start, duration: 1.8, allowed: true)
    XCTAssertTrue(playback.isPlaying)
    playback.pause(at: start.addingTimeInterval(0.45), duration: 1.8)
    XCTAssertFalse(playback.isPlaying); XCTAssertEqual(playback.offset, 0.25, accuracy: 1e-9)
    XCTAssertEqual(playback.phase(at: start.addingTimeInterval(2), duration: 1.8), 0.25, accuracy: 1e-9)
    playback.start(at: start.addingTimeInterval(2), duration: 1.8, allowed: true)
    XCTAssertEqual(playback.phase(at: start.addingTimeInterval(2.45), duration: 1.8), 0.5, accuracy: 1e-9)
    playback.pause(at: start.addingTimeInterval(4), duration: 1.8)
    XCTAssertEqual(playback.offset, 1)
    playback.start(at: start.addingTimeInterval(5), duration: 1.8, allowed: true)
    XCTAssertEqual(playback.phase(at: start.addingTimeInterval(5), duration: 1.8), 0)
    playback.showTarget(); XCTAssertEqual(playback.offset, 1); XCTAssertFalse(playback.isPlaying)
    for duration in [0, -1, Double.nan, .infinity] {
      playback.start(at: start, duration: duration, allowed: true); XCTAssertFalse(playback.isPlaying)
    }
    playback.start(at: start, duration: 1.8, allowed: false); XCTAssertFalse(playback.isPlaying)
    XCTAssertEqual(model.inputs, selected)
  }

  func testUreterFramesCommitOnlyCompletedTrips() throws {
    typealias Frame = GalaxySSIHealthAtlasUreterFrame
    XCTAssertEqual(try XCTUnwrap(Frame(selected: 0, phase: 0.5)).arrived, 0)
    XCTAssertNil(try XCTUnwrap(Frame(selected: 0, phase: 0.5)).inTransit)
    XCTAssertEqual(try XCTUnwrap(Frame(selected: 4, phase: 0)).arrived, 0)
    XCTAssertEqual(try XCTUnwrap(Frame(selected: 4, phase: 0.125)).inTransit, 0.5)
    XCTAssertEqual(try XCTUnwrap(Frame(selected: 4, phase: 0.25)).arrived, 1)
    XCTAssertEqual(try XCTUnwrap(Frame(selected: 4, phase: 0.25)).inTransit, 0)
    XCTAssertEqual(try XCTUnwrap(Frame(selected: 4, phase: 1)).arrived, 4)
    XCTAssertNil(try XCTUnwrap(Frame(selected: 4, phase: 1)).inTransit)
    for selected in 0...6 {
      for step in 0...120 {
        let phase = Double(step) / 120, frame = try XCTUnwrap(Frame(selected: selected, phase: phase))
        XCTAssertEqual(frame.arrived, Int(floor(Double(selected) * phase)))
        if let transit = frame.inTransit { XCTAssertTrue((0..<1).contains(transit)) }
      }
    }
    for phase in [-0.1, 1.1, Double.nan, .infinity] { XCTAssertNil(Frame(selected: 4, phase: phase)) }
    XCTAssertNil(Frame(selected: -1, phase: 0)); XCTAssertNil(Frame(selected: 7, phase: 1))
  }

  func testPhaseTeachingPairsPreserveCumulativePhaseAndVolumeBudgets() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let kinds: [Teaching] = [.vocalCycles, .vertebralSeries, .oralMarkerDilution, .olfactorySurfaceRetention,
      .circadianLightWindow, .adiposeVolumeShare, .thymicBranching, .gastricPrecursorBalance, .melaninDistribution]
    for teaching in kinds {
      let controls = teaching.inputs
      for first in controls[0].range {
        for second in controls[1].range {
          let values = [Double(first) / controls[0].scale, Double(second) / controls[1].scale]
          let output = try XCTUnwrap(teaching.evaluate(values)), other = try XCTUnwrap(teaching.companion(values))
          XCTAssertTrue(teaching.bounds.contains(output))
          switch teaching {
          case .vocalCycles: XCTAssertEqual(output * other, values[1], accuracy: 1e-9)
          case .vertebralSeries: XCTAssertEqual(output + other, 5 * values[0], accuracy: 1e-9)
          case .oralMarkerDilution: XCTAssertEqual(output * other, 8, accuracy: 1e-9)
          case .olfactorySurfaceRetention, .thymicBranching, .gastricPrecursorBalance:
            XCTAssertEqual(output + other, values[0], accuracy: 1e-9)
            if teaching == .thymicBranching { XCTAssertEqual(output, output.rounded(), accuracy: 1e-9) }
          case .circadianLightWindow:
            XCTAssertEqual(output, 360 * values[1] / values[0], accuracy: 1e-9)
            XCTAssertEqual(other, output.truncatingRemainder(dividingBy: 360), accuracy: 1e-9)
            XCTAssertTrue((0..<360).contains(other))
          case .adiposeVolumeShare: XCTAssertEqual(output, values[1] * other / 100, accuracy: 1e-9)
          case .melaninDistribution: XCTAssertEqual(output * values[1], other, accuracy: 1e-9)
          default: XCTFail("Unexpected phase teaching model")
          }
        }
      }
    }
    for elapsed in [0.0, 24, 48] {
      XCTAssertEqual(try XCTUnwrap(Teaching.circadianLightWindow.evaluate([24, elapsed])), elapsed * 15)
      XCTAssertEqual(try XCTUnwrap(Teaching.circadianLightWindow.companion([24, elapsed])), 0)
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.circadianLightWindow.evaluate([24, 24.5])), 367.5)
    XCTAssertEqual(try XCTUnwrap(Teaching.circadianLightWindow.companion([24, 24.5])), 7.5)
    XCTAssertEqual(try XCTUnwrap(Teaching.thymicBranching.evaluate([80, 42.75])), 34.2, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.adiposeVolumeShare.evaluate([0.98, 70])), 65.88344, accuracy: 1e-9)
    XCTAssertEqual(Model.Kind.forEntry("cell-adipocyte"), .adiposeVolumeShare)
    XCTAssertEqual(Model.Kind.forEntry("subcutaneous-tissue"), .cushionContactPressure)
  }

  func testVocalOpeningAndSeekShareOnePhaseWithoutChangingSelectedInputs() throws {
    typealias Opening = GalaxySSIHealthAtlasVocalCycle
    for cycles in [1.0, 2.8, 4.25, 7.2] {
      XCTAssertEqual(try XCTUnwrap(Opening.relativeOpening(cycles: cycles, phase: 0)), 0, accuracy: 1e-9)
      XCTAssertEqual(try XCTUnwrap(Opening.relativeOpening(cycles: cycles, phase: 0.5 / cycles)), 1, accuracy: 1e-9)
      XCTAssertEqual(try XCTUnwrap(Opening.relativeOpening(cycles: cycles, phase: 1 / cycles)), 0, accuracy: 1e-9)
      for step in 0...1000 {
        XCTAssertTrue((0...1).contains(try XCTUnwrap(Opening.relativeOpening(cycles: cycles, phase: Double(step) / 1000))))
      }
    }
    for invalid in [-0.1, 7.3, Double.nan, .infinity] { XCTAssertNil(Opening.relativeOpening(cycles: invalid, phase: 0.5)) }
    for invalid in [-0.1, 1.1, Double.nan, .infinity] { XCTAssertNil(Opening.relativeOpening(cycles: 2.8, phase: invalid)) }
    let date = Date(timeIntervalSince1970: 0), model = Model(kind: .vocalCycles), selected = model.inputs
    var playback = GalaxySSIHealthAtlasTeachingPlaybackState()
    playback.start(at: date, duration: 2.4, allowed: true)
    playback.seek(0.179); XCTAssertFalse(playback.isPlaying)
    XCTAssertEqual(playback.phase(at: date, duration: 2.4), 0.179)
    let opening = try XCTUnwrap(Opening.relativeOpening(cycles: model.result, phase: playback.offset))
    XCTAssertNotEqual(opening, try XCTUnwrap(Opening.relativeOpening(cycles: model.result, phase: 1)))
    playback.start(at: date, duration: 2.4, allowed: true)
    XCTAssertEqual(playback.phase(at: date.addingTimeInterval(0.24), duration: 2.4), 0.279, accuracy: 1e-9)
    playback.seek(-1); XCTAssertEqual(playback.offset, 0); XCTAssertFalse(playback.isPlaying)
    playback.seek(2); XCTAssertEqual(playback.offset, 1)
    playback.seek(0.5); playback.seek(.nan); XCTAssertEqual(playback.offset, 0.5)
    playback.showTarget(); XCTAssertEqual(playback.offset, 1)
    XCTAssertEqual(model.inputs, selected)
  }

  func testExchangeTeachingPairsPreserveAmountsAndSurfaceDimensions() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let kinds: [Teaching] = [.placentalMarker, .renalTubuleRetention, .merkelContact, .toothEnamelSection,
      .mucosalSampling, .mammaryDuctDelivery, .rectalReservoir, .stromalMatrix, .mucusFilmThickness]
    for teaching in kinds {
      let controls = teaching.inputs
      for first in controls[0].range {
        for second in controls[1].range {
          let values = [Double(first) / controls[0].scale, Double(second) / controls[1].scale]
          let output = try XCTUnwrap(teaching.evaluate(values)), other = try XCTUnwrap(teaching.companion(values))
          XCTAssertTrue(teaching.bounds.contains(output))
          switch teaching {
          case .placentalMarker, .mammaryDuctDelivery, .rectalReservoir:
            XCTAssertEqual(output + other, values[0], accuracy: 1e-9)
            if teaching == .placentalMarker { XCTAssertLessThanOrEqual(output, other) }
          case .renalTubuleRetention: XCTAssertEqual(output + other, 100, accuracy: 1e-9)
          case .merkelContact: XCTAssertEqual(output * other, values[0], accuracy: 1e-9)
          case .toothEnamelSection:
            let area = Double.pi * values[1] * values[1]
            XCTAssertEqual(other + area * output / 100, area, accuracy: 1e-9)
          case .mucosalSampling: XCTAssertEqual(output + other, 100, accuracy: 1e-9)
          case .stromalMatrix: XCTAssertEqual(output - other, values[0] / 2, accuracy: 1e-9)
          case .mucusFilmThickness: XCTAssertEqual(output * values[1], other, accuracy: 1e-9)
          default: XCTFail("Unexpected exchange teaching model")
          }
        }
      }
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.mucosalSampling.evaluate([3.5, 9])), 28)
    XCTAssertEqual(try XCTUnwrap(Teaching.merkelContact.evaluate([40.5, 2.3])), 40.5 / (.pi * 2.3 * 2.3), accuracy: 1e-12)
    XCTAssertEqual(Teaching.merkelContact.bounds.upperBound, 80 / .pi)
    XCTAssertEqual(Model.Kind.forEntry("cell-merkel-cell"), .merkelContact)
    XCTAssertEqual(Model.Kind.forEntry("kidneys"), .renal)
    XCTAssertEqual(Model.Kind.forEntry("capillaries"), .capillaryExchange)
  }

  func testSerialTubuleAmountsUseOnlyWhatEachPreviousSegmentLeaves() throws {
    typealias Amounts = GalaxySSIHealthAtlasTubuleRetentionAmounts
    let defaults = try XCTUnwrap(Amounts(segmentA: 40, segmentB: 25))
    XCTAssertEqual(defaults.starting, 100); XCTAssertEqual(defaults.afterA, 60)
    XCTAssertEqual(defaults.remaining, 45); XCTAssertEqual(defaults.reclaimedInA, 40)
    XCTAssertEqual(defaults.reclaimedInB, 15); XCTAssertEqual(defaults.totalReclaimed, 55)
    for a in [0.0, 40, 40.5, 80] {
      for b in [0.0, 25, 25.5, 80] {
        let amounts = try XCTUnwrap(Amounts(segmentA: a, segmentB: b))
        XCTAssertEqual(amounts.starting, amounts.reclaimedInA + amounts.reclaimedInB + amounts.remaining, accuracy: 1e-9)
        XCTAssertEqual(amounts.reclaimedInB, amounts.afterA * b / 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(GalaxySSIHealthAtlasTeachingModel.renalTubuleRetention.evaluate([a, b])), amounts.remaining)
      }
    }
    for invalid in [-1, 81, Double.nan, .infinity] {
      XCTAssertNil(Amounts(segmentA: invalid, segmentB: 25)); XCTAssertNil(Amounts(segmentA: 40, segmentB: invalid))
    }
  }

  func testPlacentalPlaybackConservesMarkerWithoutMixingItsTwoSides() throws {
    typealias Amounts = GalaxySSIHealthAtlasPlacentalAmounts
    for (phase, maternal, fetal) in [(0.0, 80.0, 0.0), (0.5, 70.0, 10.0), (1.0, 60.0, 20.0)] {
      let amounts = try XCTUnwrap(Amounts(total: 80, finalTransfer: 20, phase: phase))
      XCTAssertEqual(amounts.maternal, maternal); XCTAssertEqual(amounts.fetal, fetal)
    }
    for total in stride(from: 40.0, through: 120, by: 10) {
      for percent in stride(from: 0.0, through: 100, by: 10) {
        let transfer = try XCTUnwrap(GalaxySSIHealthAtlasTeachingModel.placentalMarker.evaluate([total, percent]))
        for step in 0...100 {
          let amounts = try XCTUnwrap(Amounts(total: total, finalTransfer: transfer, phase: Double(step) / 100))
          XCTAssertEqual(amounts.maternal + amounts.fetal, total, accuracy: 1e-9)
          XCTAssertGreaterThanOrEqual(amounts.fetal, 0); XCTAssertLessThanOrEqual(amounts.fetal, transfer)
          XCTAssertGreaterThanOrEqual(amounts.maternal, amounts.fetal)
        }
      }
    }
    XCTAssertEqual(try XCTUnwrap(Amounts(total: 80, finalTransfer: 0, phase: 0.5)).maternal, 80)
    for bad in [-1, 41, Double.nan, .infinity] { XCTAssertNil(Amounts(total: 80, finalTransfer: bad, phase: 0.5)) }
    for bad in [-0.1, 1.1, Double.nan, .infinity] { XCTAssertNil(Amounts(total: 80, finalTransfer: 20, phase: bad)) }
    for bad in [0, 121, Double.nan, .infinity] { XCTAssertNil(Amounts(total: bad, finalTransfer: 0, phase: 0.5)) }
    XCTAssertEqual(Model(kind: .placentalMarker, inputs: [80, 0])?.result, 0)
  }

  func testPleuralTeachingPairsKeepGeometryAttenuationAndDiscreteTallyMeaning() throws {
    typealias Teaching = GalaxySSIHealthAtlasTeachingModel
    let kinds: [Teaching] = [.pleuralSlide, .retinalLightAttenuation, .gametePathDistance, .testisTubuleSection,
      .uterineLiningArea, .vulvarFoldOverlap, .capillarySupportSurface, .marrowRenewal, .ependymalBeatPhase]
    for teaching in kinds {
      let controls = teaching.inputs
      for first in controls[0].range {
        for second in controls[1].range {
          let values = [Double(first) / controls[0].scale, Double(second) / controls[1].scale]
          let output = try XCTUnwrap(teaching.evaluate(values)), other = try XCTUnwrap(teaching.companion(values))
          XCTAssertTrue(teaching.bounds.contains(output))
          switch teaching {
          case .pleuralSlide:
            XCTAssertEqual(output * values[1], values[0], accuracy: 1e-9)
            XCTAssertEqual(other, 0.01 * output, accuracy: 1e-9)
          case .retinalLightAttenuation: XCTAssertEqual(output + other, 100, accuracy: 1e-9)
          case .gametePathDistance:
            XCTAssertEqual(output + values[0] + values[1], 16); XCTAssertEqual(other, 16)
            XCTAssertGreaterThanOrEqual(output, 2)
          case .testisTubuleSection:
            let area = Double.pi * values[0] * values[0]
            XCTAssertEqual(other + area * output / 100, area, accuracy: 1e-9)
          case .uterineLiningArea, .capillarySupportSurface:
            XCTAssertEqual(output, other * values[1], accuracy: 1e-9)
          case .vulvarFoldOverlap:
            XCTAssertEqual(output, min(100, max(0, 2 * (other - 25))), accuracy: 1e-9)
          case .marrowRenewal:
            XCTAssertEqual(output, output.rounded()); XCTAssertEqual(other, 12 + output)
          case .ependymalBeatPhase:
            XCTAssertEqual(other, output.truncatingRemainder(dividingBy: 1))
            XCTAssertTrue((0..<1).contains(other))
          default: XCTFail("Unexpected pleural teaching model")
          }
        }
      }
    }
    XCTAssertEqual(try XCTUnwrap(Teaching.gametePathDistance.evaluate([4.5, 2])), 9.5)
    XCTAssertEqual(try XCTUnwrap(Teaching.marrowRenewal.evaluate([4.49, 3])), 1)
    XCTAssertEqual(try XCTUnwrap(Teaching.marrowRenewal.evaluate([4.5, 3])), 2)
    XCTAssertEqual(try XCTUnwrap(Teaching.marrowRenewal.evaluate([0, 12])), -12)
    XCTAssertEqual(try XCTUnwrap(Teaching.marrowRenewal.companion([12, 0])), 24)
    XCTAssertEqual(try XCTUnwrap(Teaching.retinalLightAttenuation.evaluate([1, 4])), 1.8315638889, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Teaching.retinalLightAttenuation.evaluate([0.5, 0])), 100)
    for rate in [0.5, 1.0, 1.25, 2.0] {
      XCTAssertEqual(try XCTUnwrap(Teaching.ependymalBeatPhase.evaluate([rate, 0])), 0)
    }
    for (offset, unwrapped, wrapped) in [(0.75, 0.75, 0.75), (1.0, 1.0, 0.0), (1.25, 1.25, 0.25)] {
      XCTAssertEqual(try XCTUnwrap(Teaching.ependymalBeatPhase.evaluate([1, offset])), unwrapped)
      XCTAssertEqual(try XCTUnwrap(Teaching.ependymalBeatPhase.companion([1, offset])), wrapped)
    }
    XCTAssertEqual(Model.Kind.forEntry("cell-mesangial-cell"), .capillarySupportSurface)
    XCTAssertEqual(Model.Kind.forEntry("lungs"), .ventilation)
  }

  func testPleuralTracersUseLinearRelativeVelocityAndPauseWithoutChangingInputs() throws {
    typealias Slide = GalaxySSIHealthAtlasPleuralSlide
    XCTAssertEqual(try XCTUnwrap(Slide.relativeVelocity(surfaceSpeed: 18, fractionFromReference: 0)), 0)
    XCTAssertEqual(try XCTUnwrap(Slide.relativeVelocity(surfaceSpeed: 18, fractionFromReference: 0.5)), 9)
    XCTAssertEqual(try XCTUnwrap(Slide.relativeVelocity(surfaceSpeed: 18, fractionFromReference: 1)), 18)
    for speed in 0...24 {
      for row in 0...5 {
        let fraction = Double(row) / 5
        XCTAssertEqual(try XCTUnwrap(Slide.offset(surfaceSpeed: Double(speed), fractionFromReference: fraction, phase: 0)), 0)
        XCTAssertEqual(try XCTUnwrap(Slide.offset(surfaceSpeed: Double(speed), fractionFromReference: fraction, phase: 1)),
          Double(speed) * fraction * 5, accuracy: 1e-9)
      }
    }
    for invalid in [-1, 25, Double.nan, .infinity] { XCTAssertNil(Slide.relativeVelocity(surfaceSpeed: invalid, fractionFromReference: 0.5)) }
    for invalid in [-0.1, 1.1, Double.nan, .infinity] {
      XCTAssertNil(Slide.relativeVelocity(surfaceSpeed: 18, fractionFromReference: invalid))
      XCTAssertNil(Slide.offset(surfaceSpeed: 18, fractionFromReference: 0.5, phase: invalid))
    }
    let model = Model(kind: .pleuralSlide), selected = model.inputs, date = Date(timeIntervalSince1970: 0)
    var playback = GalaxySSIHealthAtlasTeachingPlaybackState()
    playback.start(at: date, duration: 2.3, allowed: true)
    playback.pause(at: date.addingTimeInterval(1.15), duration: 2.3)
    XCTAssertEqual(playback.offset, 0.5, accuracy: 1e-9); XCTAssertFalse(playback.isPlaying)
    XCTAssertEqual(model.inputs, selected)
    XCTAssertEqual(Model(kind: .pleuralSlide, inputs: [0, 8])?.result, 0)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 16)).result, 5)
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
    XCTAssertEqual(Model.Kind.forEntry("triceps-brachii"), .muscleShortening)
    XCTAssertNil(Model.Kind.forEntry("cell-skeletal-muscle-fiber"))
  }

  func testVesselIndependentSIConversionsAndProfileConservation() throws {
    typealias Flow = GalaxySSIHealthAtlasVesselFlow
    let baseline = try XCTUnwrap(Flow())
    XCTAssertEqual(baseline.flowMlPerMinute, 0.017950485959955423, accuracy: 1e-12)
    XCTAssertEqual(baseline.resistanceMmHgMinutesPerMl, 557.0879820361606, accuracy: 1e-9)
    XCTAssertEqual(baseline.meanSpeedMmPerSecond, 9.523028571428572, accuracy: 1e-10)
    XCTAssertEqual(baseline.centreSpeedMmPerSecond, 19.046057142857144, accuracy: 1e-10)
    XCTAssertEqual(baseline.wallShearPascals, 1.333224, accuracy: 1e-10)
    let maximum = try XCTUnwrap(Flow(pressureMmHg: 20, radiusMm: 0.2, lengthMm: 20, viscosityMilliPascalSeconds: 2))
    XCTAssertEqual(maximum.flowMlPerMinute, 2.5130680343937595, accuracy: 1e-10)
    let minimum = try XCTUnwrap(Flow(pressureMmHg: 1, radiusMm: 0.05, lengthMm: 100, viscosityMilliPascalSeconds: 6))
    XCTAssertEqual(minimum.flowMlPerMinute, 0.00003272224003116874, accuracy: 1e-14)
    XCTAssertEqual(try XCTUnwrap(Flow(radiusMm: 0.2)).flowMlPerMinute, baseline.flowMlPerMinute * 16, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Flow(pressureMmHg: 20)).flowMlPerMinute, baseline.flowMlPerMinute * 2, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Flow(lengthMm: 100)).flowMlPerMinute, baseline.flowMlPerMinute / 2, accuracy: 1e-10)
    let viscous = try XCTUnwrap(Flow(viscosityMilliPascalSeconds: 5))
    XCTAssertEqual(viscous.flowMlPerMinute, baseline.flowMlPerMinute * 3.5 / 5, accuracy: 1e-10)
    XCTAssertEqual(viscous.wallShearPascals, baseline.wallShearPascals, accuracy: 1e-10)
    var volume = 0.0
    for index in 0..<10000 {
      let inner = Double(index) / 10000, outer = Double(index + 1) / 10000
      let relative = (inner + outer) / 2
      let speed = try XCTUnwrap(baseline.speedMmPerSecond(relativeRadius: relative))
      XCTAssertEqual(baseline.speedMmPerSecond(relativeRadius: -relative), speed)
      volume += Double.pi * pow(baseline.radiusMm, 2) * (outer * outer - inner * inner) * speed
    }
    XCTAssertEqual(volume * 0.06, baseline.flowMlPerMinute, accuracy: 1e-9)
    XCTAssertEqual(baseline.speedMmPerSecond(relativeRadius: 1), 0)
    XCTAssertEqual(baseline.speedMmPerSecond(relativeRadius: -1), 0)
    XCTAssertEqual(baseline.speedMmPerSecond(relativeRadius: 0), baseline.centreSpeedMmPerSecond)
  }

  func testMiddleEarSeparatesPressureFromDbAndConservesVolumeVelocityProduct() throws {
    typealias Ear = GalaxySSIHealthAtlasMiddleEar
    let baseline = try XCTUnwrap(Ear())
    XCTAssertEqual(baseline.areaRatio, 17.1875, accuracy: 1e-10)
    XCTAssertEqual(baseline.pressureRatio, 22.34375, accuracy: 1e-10)
    XCTAssertEqual(baseline.pressureGainDb, 26.983121269623492, accuracy: 1e-10)
    XCTAssertEqual(baseline.volumeVelocityRatio, 0.044755244755244755, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Ear(membraneAreaMm2: 35, footplateAreaMm2: 5, leverRatio: 1)).pressureRatio, 7, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Ear(membraneAreaMm2: 75, footplateAreaMm2: 2, leverRatio: 1.6)).pressureGainDb, 35.56302500767287, accuracy: 1e-10)
    for input in [35, 55, 75] {
      for output in [20, 32, 50] {
        for lever in [100, 130, 160] {
          let model = try XCTUnwrap(Model(kind: .middleEar, inputs: [input, output, lever]))
          let ear = try XCTUnwrap(model.middleEar)
          XCTAssertEqual(ear.pressureRatio * ear.volumeVelocityRatio, 1, accuracy: 1e-12)
          XCTAssertEqual(model.result, ear.pressureRatio); XCTAssertEqual(model.companionValue, ear.pressureGainDb)
          XCTAssertEqual(try XCTUnwrap(model.resultAt(model.input(model.kind.axis))), model.result, accuracy: 1e-12)
          XCTAssertTrue((7...60).contains(model.result))
        }
      }
    }
    for bad in [Double.nan, .infinity, 34, 76] { XCTAssertNil(Ear(membraneAreaMm2: bad)) }
    for bad in [Double.nan, -.infinity, 0, 1.9, 5.1] { XCTAssertNil(Ear(footplateAreaMm2: bad)) }
    for bad in [Double.nan, .infinity, 0.99, 1.61] { XCTAssertNil(Ear(leverRatio: bad)) }
    for id in ["ear", "middle-ear"] {
      XCTAssertEqual(Model.Kind.forEntry(id), .middleEar)
      XCTAssertEqual(Model.restore(id, inputs: [35, 20, 160])?.inputs, [35, 20, 160])
      XCTAssertNil(Model.restore(id, inputs: [35, 0, 160]))
      XCTAssertNil(Model.restore(id, inputs: [35, 20]))
    }
    XCTAssertEqual(Model.Kind.forEntry("external-ear"), .externalEarResonance)
    XCTAssertEqual(Model.Kind.forEntry("vestibular-apparatus"), .vestibularTilt)
    for id in ["inner-ear", "cochlea", "cell-inner-ear-hair-cell"] {
      XCTAssertEqual(Model.Kind.forEntry(id), .cochlearFrequency)
      XCTAssertNil(Model.restore(id, inputs: [35, 20, 160]))
      XCTAssertEqual(Model.restore(id, inputs: [50])?.inputs, [50])
    }
    for language in ["en", "zh-Hans"] {
      let model = Model(kind: .middleEar)
      let text = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      for line in GalaxySSIHealthAtlasPhysiologyText.middleEarContext(baseline, language: language) { XCTAssertTrue(text.contains(line)) }
      XCTAssertTrue(text.contains(Ear.source.absoluteString)); XCTAssertTrue(text.contains(Ear.measurementSource.absoluteString))
      XCTAssertFalse(text.contains("health_atlas_middle_ear_"))
    }
  }

  func testEyeThinLensFixturesSignedOffsetAndRayIntersection() throws {
    typealias Eye = GalaxySSIHealthAtlasEyeOptics
    let baseline = try XCTUnwrap(Eye())
    XCTAssertEqual(baseline.imageDistanceMm, 17.001020061203672, accuracy: 1e-10)
    XCTAssertEqual(baseline.focusSide, .at_plane)
    XCTAssertEqual(try XCTUnwrap(Eye(distanceMetres: 0.25, powerDiopters: 55)).offsetMm, 2.6078431372549034, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Eye(distanceMetres: 6, powerDiopters: 65)).offsetMm, -1.5758354755784065, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Eye(distanceMetres: 0.5, powerDiopters: 60)).offsetMm, 0.24137931034482563, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Eye(distanceMetres: 0.25)).targetPowerDiopters, 62.8235294117647, accuracy: 1e-10)
    for distance in 25...600 {
      let eye = try XCTUnwrap(Eye(distanceMetres: Double(distance) / 100))
      let aligned = try XCTUnwrap(Eye(distanceMetres: eye.distanceMetres, powerDiopters: Double(eye.targetPowerSteps) / 100))
      XCTAssertLessThan(abs(aligned.offsetMm), 0.002)
      XCTAssertEqual(aligned.focusSide, .at_plane)
      XCTAssertEqual(try XCTUnwrap(Eye(distanceMetres: eye.distanceMetres, powerDiopters: 55)).focusSide, .behind)
      XCTAssertEqual(try XCTUnwrap(Eye(distanceMetres: eye.distanceMetres, powerDiopters: 65)).focusSide, .in_front)
      for height in [-1.0, 1.0] {
        XCTAssertEqual(try XCTUnwrap(eye.rayHeight(axialMm: -1000 * eye.distanceMetres, heightAtLensMm: height)), 0, accuracy: 1e-12)
        XCTAssertEqual(eye.rayHeight(axialMm: 0, heightAtLensMm: height), height)
        XCTAssertEqual(try XCTUnwrap(eye.rayHeight(axialMm: eye.imageDistanceMm, heightAtLensMm: height)), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(eye.rayHeight(axialMm: 2 * eye.imageDistanceMm, heightAtLensMm: height)), -height, accuracy: 1e-12)
      }
    }
    XCTAssertNil(baseline.rayHeight(axialMm: .nan, heightAtLensMm: 1))
    XCTAssertNil(baseline.rayHeight(axialMm: 1, heightAtLensMm: .infinity))
    XCTAssertEqual(GalaxySSIHealthAtlasPhysiologyText.resultNumber(baseline.offsetMm, kind: .eye, language: "en"), "0")
  }

  func testEyeInputsRestoreOnlyForEyeAndLensAndPublicContextStaysScoped() throws {
    typealias Eye = GalaxySSIHealthAtlasEyeOptics
    for invalid in [Double.nan, .infinity, 0.24, 6.01] { XCTAssertNil(Eye(distanceMetres: invalid)) }
    for invalid in [Double.nan, -.infinity, 54.99, 65.01] { XCTAssertNil(Eye(powerDiopters: invalid)) }
    for id in ["eye", "lens"] {
      XCTAssertEqual(Model.Kind.forEntry(id), .eye)
      XCTAssertEqual(Model.restore(id, inputs: [25, 6500])?.inputs, [25, 6500])
      XCTAssertNil(Model.restore(id, inputs: [25, 6501]))
      XCTAssertNil(Model.restore(id, inputs: [25]))
    }
    for id in ["ear", "cornea", "retina", "cell-rod-photoreceptor", "sensory"] {
      XCTAssertNil(Model.restore(id, inputs: [25, 6500]))
    }
    for language in ["en", "zh-Hans"] {
      let model = Model(kind: .eye)
      let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      for line in GalaxySSIHealthAtlasPhysiologyText.eyeContext(try XCTUnwrap(model.eyeOptics), language: language) {
        XCTAssertTrue(context.contains(line))
      }
      XCTAssertTrue(context.contains(Eye.source.absoluteString))
      XCTAssertFalse(context.contains("health_atlas_eye_"))
    }
  }

  func testVesselZeroPressureBoundsRestorationAndLocalizedPrecision() throws {
    typealias Flow = GalaxySSIHealthAtlasVesselFlow
    let zero = try XCTUnwrap(Flow(pressureMmHg: 0))
    XCTAssertEqual(zero.flowMlPerMinute, 0)
    XCTAssertEqual(zero.meanSpeedMmPerSecond, 0)
    XCTAssertEqual(zero.wallShearPascals, 0)
    XCTAssertEqual(zero.resistanceMmHgMinutesPerMl, try XCTUnwrap(Flow()).resistanceMmHgMinutesPerMl)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .vessel).changing(0, to: 0)).plotMaximum, 0.01)
    for p in [0, 1, 10, 20] {
      for r in [50, 101, 200] {
        for l in [20, 50, 100] {
          for m in [20, 35, 60] {
            let model = try XCTUnwrap(Model(kind: .vessel, inputs: [p, r, l, m]))
            XCTAssertEqual(model.result * model.companionValue, Double(p), accuracy: 1e-9)
            XCTAssertTrue((0...model.plotMaximum).contains(model.result))
            XCTAssertLessThanOrEqual(model.plotMaximum, 3)
            for point in model.response { XCTAssertTrue((0...model.plotMaximum).contains(point.y)) }
          }
        }
      }
    }
    for invalid in [Double.nan, .infinity, -.infinity, -1, 21] { XCTAssertNil(Flow(pressureMmHg: invalid)) }
    for invalid in [Double.nan, .infinity, 0, 0.049, 0.201] { XCTAssertNil(Flow(radiusMm: invalid)) }
    for invalid in [Double.nan, .infinity, 0, 19, 101] { XCTAssertNil(Flow(lengthMm: invalid)) }
    for invalid in [Double.nan, .infinity, 0, 1.9, 6.1] { XCTAssertNil(Flow(viscosityMilliPascalSeconds: invalid)) }
    for invalid in [Double.nan, .infinity, -1.01, 1.01] { XCTAssertNil(zero.speedMmPerSecond(relativeRadius: invalid)) }
    for id in ["blood-vessels", "arteries", "veins", "coronary-vessels"] {
      XCTAssertEqual(Model.Kind.forEntry(id), .vessel)
      XCTAssertEqual(Model.restore(id, inputs: [10, 101, 50, 35])?.inputs, [10, 101, 50, 35])
      XCTAssertNil(Model.restore(id, inputs: [10, 100, 50]))
      XCTAssertNil(Model.restore(id, inputs: [10, 49, 50, 35]))
    }
    for id in ["heart", "cardiovascular", "capillaries", "cell-vascular-endothelium"] {
      XCTAssertNotEqual(Model.Kind.forEntry(id), .vessel)
    }
    XCTAssertNil(Model(kind: .potassium).vesselFlow)
    typealias Text = GalaxySSIHealthAtlasPhysiologyText
    XCTAssertEqual(Text.inputNumber(0.051, key: "vessel_radius", language: "en"), "0.051")
    XCTAssertEqual(Text.resultNumber(0.00003272224003116874, kind: .vessel, language: "en"), "0.000033")
    for language in ["en", "zh-Hans"] {
      let model = Model(kind: .vessel)
      let context = Text.context(model, language: language)
      for line in Text.vesselContext(try XCTUnwrap(model.vesselFlow), language: language) { XCTAssertTrue(context.contains(line)) }
      for source in Flow.sources { XCTAssertTrue(context.contains(source.absoluteString)) }
      XCTAssertFalse(context.contains("health_atlas_vessel_"))
    }
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

  func testNerveTransitConvertsCentimetresSecondsAndMillisecondsWithBoundedInputs() throws {
    let model = Model(kind: .nerveTransit)
    XCTAssertEqual(model.result, 12, accuracy: 1e-9)
    XCTAssertEqual(model.companionValue, 2, accuracy: 1e-9)
    XCTAssertEqual(model.plotMaximum, 30)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 120)).plotMaximum, 20)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 120)).result, 24, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 100)).result, 6, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .nerveTransit, inputs: [150, 1])).result, 1500, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .nerveTransit, inputs: [10, 120])).result, 10.0 / 12, accuracy: 1e-9)
    for id in ["cranial-nerves", "spinal-nerves", "peripheral-nerves"] {
      let stored = try XCTUnwrap(Model.restore(id, inputs: [75, 30]))
      XCTAssertEqual(stored.kind, .nerveTransit)
      XCTAssertEqual(stored.result, 25, accuracy: 1e-9)
      XCTAssertNil(Model.restore(id, inputs: [75, 0]))
      XCTAssertNil(Model.restore(id, inputs: [9, 30]))
      XCTAssertNil(Model.restore(id, inputs: [75, 121]))
    }
    XCTAssertEqual(Model.Kind.forEntry("spinal-cord"), .potassium)
    XCTAssertEqual(Model.Kind.forEntry("ganglia"), .neuralRelayDelays)
    XCTAssertEqual(Model.Kind.forEntry("ovaries"), .follicleSurface)
    for distance in [10, 60, 150] {
      for speed in [1, 50, 120] {
        let value = try XCTUnwrap(Model(kind: .nerveTransit, inputs: [distance, speed]))
        XCTAssertEqual(value.resultAt(Double(distance)), value.result)
        XCTAssertEqual(value.result, 10 * Double(distance) / Double(speed), accuracy: 1e-9)
        XCTAssertTrue((0...value.plotMaximum).contains(value.result))
      }
    }
  }

  func testEjectionUsesSyntheticEjectedAndResidualVolumesWithoutInferringNormality() throws {
    let model = Model(kind: .ejection)
    XCTAssertEqual(model.companionValue, 130)
    XCTAssertEqual(model.result, 100.0 * 70 / 130, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 60)).result, 50, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 0)).result, 0)
    XCTAssertLessThan(try XCTUnwrap(model.changing(1, to: 100)).result, model.result)
    XCTAssertGreaterThan(try XCTUnwrap(model.changing(0, to: 100)).result, model.result)
    for id in ["ventricles", "right-ventricle", "left-ventricle"] {
      let restored = try XCTUnwrap(Model.restore(id, inputs: [90, 60]))
      XCTAssertEqual(restored.result, 60, accuracy: 1e-9)
      XCTAssertEqual(restored.resultAt(90), restored.result)
      XCTAssertNil(Model.restore(id, inputs: [90, 0]))
      XCTAssertNil(Model.restore(id, inputs: [181, 60]))
      XCTAssertNil(Model.restore(id, inputs: [90]))
    }
    for id in ["aorta", "mitral-valve", "heart-valves"] {
      XCTAssertNil(Model.restore(id, inputs: [90, 60]))
    }
    for id in ["left-atrium", "right-atrium", "tissue-cardiac-muscle"] {
      XCTAssertEqual(Model.restore(id, inputs: [90, 60])?.kind, .cardiacPhaseTime)
    }
    for stroke in [0, 1, 70, 180] {
      for residual in [5, 60, 180] {
        let value = try XCTUnwrap(Model(kind: .ejection, inputs: [stroke, residual]))
        XCTAssertEqual(value.companionValue, Double(stroke + residual))
        XCTAssertEqual(value.result, 100 * Double(stroke) / Double(stroke + residual), accuracy: 1e-9)
        XCTAssertTrue((0...100).contains(value.result))
      }
    }
    for language in ["en", "zh-Hans"] {
      let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      XCTAssertTrue(context.contains(GalaxySSIHealthAtlasHeartSection.ejectionSource.absoluteString))
      XCTAssertFalse(context.contains("health_atlas_ejection_"))
    }
  }

  func testBicarbonateMixConservesSoluteWithNoAddedFlowAndAtBounds() throws {
    let model = Model(kind: .bicarbonateMix)
    XCTAssertEqual(model.result, 50, accuracy: 1e-9)
    XCTAssertEqual(model.companionValue, 100, accuracy: 1e-9)
    XCTAssertEqual(model.input(0), 1); XCTAssertEqual(model.kind.axis, 1)
    XCTAssertEqual(model.kind.unit, "mmol/L")
    XCTAssertEqual(try XCTUnwrap(Model(kind: .bicarbonateMix, inputs: [0, 120])).result, 20, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .bicarbonateMix, inputs: [40, 120])).result, 100, accuracy: 1e-9)
    for flow in 0...40 {
      for concentration in stride(from: 20, through: 120, by: 5) {
        let value = try XCTUnwrap(Model(kind: .bicarbonateMix, inputs: [flow, concentration]))
        XCTAssertEqual(value.result * (1 + Double(flow) / 10), value.companionValue, accuracy: 1e-8)
        XCTAssertGreaterThanOrEqual(value.result, 20 - 1e-9)
        XCTAssertLessThanOrEqual(value.result, Double(concentration) + 1e-9)
      }
    }
    for id in ["pancreas", "pancreatic-duct", "cell-pancreatic-ductal-cell"] {
      XCTAssertEqual(Model.restore(id, inputs: [10, 80]), model)
      XCTAssertNil(Model.restore(id, inputs: [-1, 80]))
    }
    for id in ["pancreatic-islets", "cell-pancreatic-acinar-cell", "cell-pancreatic-beta-cell", "cell-cholangiocyte"] {
      XCTAssertNotEqual(Model.Kind.forEntry(id), .bicarbonateMix)
    }
    for language in ["en", "zh-Hans"] {
      let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      XCTAssertTrue(context.contains(GalaxySSIHealthAtlasText.get("health_atlas_digestive_bicarb_scope", language)))
      XCTAssertTrue(context.contains(model.kind.source.absoluteString))
      XCTAssertFalse(context.contains("health_atlas_"))
    }
  }

  func testAlveolarSurfaceUsesSingleInterfaceSIUnitsAndStrictOwnership() throws {
    let model = try XCTUnwrap(Model.restore("cell-type-ii-pneumocyte", inputs: [15, 100]))
    XCTAssertEqual(model.kind, .alveolarSurface)
    XCTAssertEqual(model.kind.axis, 0); XCTAssertEqual(model.kind.unit, "Pa")
    XCTAssertEqual(model.result, 300, accuracy: 1e-9)
    XCTAssertEqual(model.companionValue, 150, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 200)).result, model.companionValue, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 30)).result, 600, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .alveolarSurface, inputs: [5, 200])).result, 50, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .alveolarSurface, inputs: [35, 50])).result, 1400, accuracy: 1e-9)
    XCTAssertNil(Model.restore("cell-type-ii-pneumocyte", inputs: [15, 0]))
    for id in ["cell-type-i-pneumocyte", "cell-podocyte", "cell-club-cell", "lungs", "alveoli"] {
      XCTAssertNotEqual(Model.Kind.forEntry(id), .alveolarSurface)
    }
    for tension in [5, 15, 35] {
      for radius in [50, 100, 200] {
        let value = try XCTUnwrap(Model(kind: .alveolarSurface, inputs: [tension, radius]))
        XCTAssertEqual(value.result, 2 * (Double(tension) / 1000) / (Double(radius) / 1_000_000), accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(value.plotMaximum, try XCTUnwrap(value.response.map(\.y).max()))
      }
    }
    for language in ["en", "zh-Hans"] {
      let text = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      XCTAssertFalse(text.contains("health_atlas_"))
      XCTAssertTrue(text.contains("https://pubmed.ncbi.nlm.nih.gov/20724566/"))
      XCTAssertTrue(text.contains(GalaxySSIHealthAtlasText.get("health_atlas_alveolar_surface_scope", language)))
    }
  }

  func testThyroidFeedbackIsDimensionlessAndDoesNotExpandToOtherEndocrineEntries() throws {
    let model = Model(kind: .thyroidFeedback)
    XCTAssertEqual(model.inputs, [80, 100])
    XCTAssertEqual(model.result, 40, accuracy: 1e-9)
    XCTAssertEqual(model.companionValue, 40, accuracy: 1e-9)
    XCTAssertEqual(model.kind.axis, 0)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 0)).result, 80, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 300)).result, 20, accuracy: 1e-9)
    XCTAssertEqual(Model.restore("thyroid-gland", inputs: [80, 100]), model)
    for id in ["pituitary-gland", "parathyroid-glands", "adrenal-glands", "cell-thyrotroph", "cell-thyroid-follicular-cell"] {
      XCTAssertNotEqual(Model.Kind.forEntry(id), .thyroidFeedback)
    }
    XCTAssertNil(model.changing(0, to: 19)); XCTAssertNil(model.changing(1, to: 301))
    for drive in stride(from: 20, through: 100, by: 5) {
      var previous = Double(drive)
      for gain in stride(from: 0, through: 300, by: 10) {
        let value = try XCTUnwrap(Model(kind: .thyroidFeedback, inputs: [drive, gain]))
        XCTAssertEqual(value.result * (1 + Double(gain) / 100), Double(drive), accuracy: 1e-9)
        XCTAssertEqual(value.result + value.companionValue, Double(drive), accuracy: 1e-9)
        XCTAssertLessThanOrEqual(value.result, previous + 1e-9); previous = value.result
      }
    }
    for language in ["en", "zh-Hans"] {
      let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      XCTAssertTrue(context.contains(GalaxySSIHealthAtlasText.get("health_atlas_endocrine_feedback_scope", language)))
      XCTAssertTrue(context.contains(model.kind.source.absoluteString))
      XCTAssertFalse(context.contains("health_atlas_")); XCTAssertFalse(context.contains("measuredAt"))
    }
  }

  func testPhotonAbsorptionUsesStablePoissonComplementAndOnlyOneUnitlessInput() throws {
    let model = try XCTUnwrap(Model.restore("cell-rod-photoreceptor", inputs: [100]))
    XCTAssertEqual(model.kind, .photonCapture); XCTAssertEqual(model.kind.inputs.count, 1)
    XCTAssertTrue(model.kind.inputs[0].unit.isEmpty)
    XCTAssertEqual(model.kind.sources.count, 2)
    XCTAssertEqual(model.result, 63.21205588, accuracy: 1e-8)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 0)).result, 0, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 500)).result, 99.3262053, accuracy: 1e-7)
    for count in 0...500 {
      let value = try XCTUnwrap(model.changing(0, to: count))
      XCTAssertEqual(value.result + value.companionValue, 100, accuracy: 1e-9)
      XCTAssertEqual(value.input(0), Double(count) / 100, accuracy: 1e-12)
    }
    XCTAssertNil(model.changing(0, to: 501)); XCTAssertNil(Model.restore("cell-rod-photoreceptor", inputs: [100, 100]))
    for id in ["retina", "cell-cone-photoreceptor", "cell-retinal-bipolar-cell", "cell-retinal-aii-amacrine-cell"] {
      XCTAssertNotEqual(Model.Kind.forEntry(id), .photonCapture)
    }
    for language in ["en", "zh-Hans"] {
      let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      XCTAssertTrue(context.contains(GalaxySSIHealthAtlasText.get("health_atlas_sensory_photon_scope", language)))
      for source in model.kind.sources { XCTAssertTrue(context.contains(source.absoluteString)) }
      XCTAssertFalse(context.contains("health_atlas_"))
      XCTAssertFalse(GalaxySSIHealthAtlasPhysiologyText.input(model, index: 0, language: language).hasSuffix(" "))
    }
  }

  func testOnlyEvaporatedSweatContributesExampleLatentHeat() throws {
    let model = try XCTUnwrap(Model.restore("sweat-glands", inputs: [60, 50]))
    XCTAssertEqual(model.kind, .sweatEvaporation); XCTAssertEqual(model.kind.unit, "W")
    XCTAssertEqual(model.kind.axis, 0)
    XCTAssertEqual(model.companionValue, 3, accuracy: 1e-9)
    XCTAssertEqual(model.result, 121.3, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 0)).result, 0, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 0)).result, 0, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(model.changing(1, to: 100)).result, 242.6, accuracy: 1e-9)
    for mass in stride(from: 0, through: 200, by: 5) {
      for fraction in stride(from: 0, through: 100, by: 5) {
        let value = try XCTUnwrap(Model(kind: .sweatEvaporation, inputs: [mass, fraction]))
        XCTAssertEqual(value.result * 60, value.companionValue * 2426, accuracy: 1e-8)
        XCTAssertLessThanOrEqual(value.companionValue, value.input(0))
        XCTAssertTrue(value.kind.bounds.contains(value.result))
      }
    }
    for id in ["hair-follicles", "skin-organ", "cell-sweat-gland-secretory-cell", "cell-sebocyte"] {
      XCTAssertNotEqual(Model.Kind.forEntry(id), .sweatEvaporation)
    }
    for language in ["en", "zh-Hans"] {
      let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: language)
      XCTAssertTrue(context.contains(GalaxySSIHealthAtlasText.get("health_atlas_context_evap_scope", language)))
      XCTAssertTrue(context.contains(model.kind.source.absoluteString)); XCTAssertFalse(context.contains("health_atlas_"))
    }
  }

  func testVillusAreaUsesGeometryRatherThanAbsorptionAndKeepsRadiusPrecision() throws {
    let model = Model(kind: .villusArea)
    XCTAssertEqual(model.result, 1 + 12 * 2 * Double.pi * 0.045 * 0.6, accuracy: 1e-12)
    XCTAssertEqual(model.companionValue, model.result - 1, accuracy: 1e-12)
    XCTAssertEqual(try XCTUnwrap(model.changing(0, to: 0)).result, 1)
    let maximum = try XCTUnwrap(Model(kind: .villusArea, inputs: [24, 70, 120]))
    XCTAssertEqual(maximum.result, 1 + 24 * 2 * Double.pi * 0.07 * 1.2, accuracy: 1e-12)
    XCTAssertTrue(maximum.result < 14)
    XCTAssertEqual(Model.Kind.forEntry("small-intestine"), .villusArea)
    XCTAssertEqual(Model.Kind.forEntry("jejunum"), .villusArea)
    for id in ["duodenum", "ileum", "cell-enterocyte", "lymphatic-vessels"] {
      XCTAssertNotEqual(Model.Kind.forEntry(id), .villusArea)
    }
    XCTAssertNil(Model(kind: .villusArea, inputs: [25, 45, 60]))
    XCTAssertNil(Model(kind: .villusArea, inputs: [12, 0, 60]))
    XCTAssertEqual(Model.restore("jejunum", inputs: [24, 70, 120]), maximum)
    XCTAssertNil(Model.restore("ileum", inputs: [24, 70, 120]))
    for language in ["en", "zh-Hans"] {
      let radius = GalaxySSIHealthAtlasPhysiologyText.inputNumber(0.045, key: "gut_section_area_radius", language: language)
      XCTAssertEqual(radius, "0.045")
      XCTAssertFalse(GalaxySSIHealthAtlasPhysiologyText.string("model_villusArea_scope", language: language).contains("health_atlas_"))
      XCTAssertFalse(GalaxySSIHealthAtlasPhysiologyText.companion(model, language: language).contains("health_atlas_"))
    }
  }

  func testLymphValveSeparatesForwardFlowFromSignedNoValveComparison() throws {
    let baseline = Model(kind: .lymphValve)
    XCTAssertEqual(baseline.result, 0.5, accuracy: 1e-12)
    XCTAssertEqual(baseline.companionValue, 0.5, accuracy: 1e-12)
    let reverse = try XCTUnwrap(baseline.changing(0, to: -20))
    XCTAssertEqual(reverse.result, 0)
    XCTAssertEqual(reverse.companionValue, -0.5, accuracy: 1e-12)
    XCTAssertEqual(try XCTUnwrap(baseline.changing(0, to: 0)).result, 0)
    XCTAssertEqual(try XCTUnwrap(Model(kind: .lymphValve, inputs: [40, 20])).result, 2)
    XCTAssertNil(Model(kind: .lymphValve, inputs: [20, 0]))
    XCTAssertEqual(Model.Kind.forEntry("lymphatic-vessels"), .lymphValve)
    for id in ["thoracic-duct", "lymph-nodes", "cell-lymphatic-endothelial-cell"] {
      XCTAssertEqual(Model.Kind.forEntry(id), .lymphParticleTransport)
    }
    XCTAssertEqual(Model.restore("lymphatic-vessels", inputs: [-20, 40]), reverse)
    XCTAssertNil(Model.restore("thoracic-duct", inputs: [-20, 40]))
    for language in ["en", "zh-Hans"] {
      for model in [baseline, reverse, try XCTUnwrap(baseline.changing(0, to: 0))] {
        XCTAssertFalse(GalaxySSIHealthAtlasPhysiologyText.companion(model, language: language).contains("health_atlas_"))
        XCTAssertFalse(GalaxySSIHealthAtlasPhysiologyText.string("model_lymphValve_scope", language: language).contains("health_atlas_"))
      }
    }
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
