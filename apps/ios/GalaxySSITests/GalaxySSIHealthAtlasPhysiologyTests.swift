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
            if kind == .renal || kind == .eye { XCTAssertLessThanOrEqual(point.y, previous + 1e-9) }
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
      "pancreas", "pancreatic-duct", "cell-pancreatic-ductal-cell", "thyroid-gland", "cell-rod-photoreceptor", "sweat-glands"]
    XCTAssertEqual(ids.count, 47)
    for id in ids { XCTAssertNotNil(Model.Kind.forEntry(id)) }
    for id in ["liver", "cell-hepatocyte", "renal-cortex", "renal-pelvis", "cell-type-i-pneumocyte", "cell-podocyte", "heart"] {
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
    for id in ["external-ear", "inner-ear", "cochlea", "vestibular-apparatus", "cell-inner-ear-hair-cell"] {
      XCTAssertNil(Model.Kind.forEntry(id))
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
    XCTAssertNil(Model.Kind.forEntry("ganglia")); XCTAssertNil(Model.Kind.forEntry("ovaries"))
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
    for id in ["left-atrium", "right-atrium", "aorta", "mitral-valve", "heart-valves", "tissue-cardiac-muscle"] {
      XCTAssertNil(Model.restore(id, inputs: [90, 60]))
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
