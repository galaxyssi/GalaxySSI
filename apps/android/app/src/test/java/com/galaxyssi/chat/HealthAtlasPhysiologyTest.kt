package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasPhysiologyTest {
    @Test fun idealPelvicSupportsBalanceForceAndMoment() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("pelvis", intArrayOf(500, 0)))
        assertEquals(HealthAtlasPhysiologyKind.PELVIC_SUPPORT, model.kind)
        assertEquals(250.0, model.result, 1e-9)
        for (load in 0..800 step 20) for (position in -100..100 step 5) {
            val setting = model.withInput(0, load).withInput(1, position)
            assertEquals(load.toDouble(), setting.result + setting.companionValue, 1e-9)
            assertEquals(load * position / 100.0, setting.result - setting.companionValue, 1e-9)
            assertEquals(setting.result, setting.withInput(1, -position).companionValue, 1e-9)
            assertTrue(setting.result in 0.0..setting.plotMaximum)
        }
        assertEquals(0.0, model.withInput(1, -100).result, 0.0)
        assertEquals(500.0, model.withInput(1, 100).result, 0.0)
        assertNull(HealthAtlasPhysiology.restore("pelvis", intArrayOf(500, 101)))
        assertEquals(HealthAtlasPhysiologyKind.BONE_BENDING, HealthAtlasPhysiologyKind.forItem("femur"))
    }

    @Test fun contactPressureDependsOnForceAndAreaWithAStableSameForceReference() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("subcutaneous-tissue", intArrayOf(40, 40)))
        assertEquals(HealthAtlasPhysiologyKind.CUSHION_CONTACT_PRESSURE, model.kind)
        assertEquals(10.0, model.result, 1e-9)
        assertEquals(20.0, model.withInput(1, 20).result, 1e-9)
        assertEquals(5.0, model.withInput(1, 80).result, 1e-9)
        assertEquals(10.0, model.withInput(1, 80).companionValue, 1e-9)
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(80.0, model.withInput(0, 80).withInput(1, 10).result, 1e-9)
        assertNull(HealthAtlasPhysiology.restore("subcutaneous-tissue", intArrayOf(40, 0)))
        assertNull(HealthAtlasPhysiologyKind.forItem("cell-adipocyte"))
    }

    @Test fun idealCalfPumpConservesForwardAndReturningVolume() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("soleus", intArrayOf(12, 12, 0)))
        assertEquals(HealthAtlasPhysiologyKind.CALF_PUMP, model.kind)
        assertEquals(144.0, model.result, 1e-9)
        assertEquals(12.0, model.companionValue, 1e-9)
        for (returnPercent in 0..100) {
            val example = model.withInput(2, returnPercent)
            val returned = example.input(0) * example.input(1) * returnPercent / 100.0
            assertEquals(144.0, example.result + returned, 1e-9)
            assertEquals(example.result, example.companionValue * example.input(1), 1e-9)
        }
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(0.0, model.withInput(1, 0).result, 0.0)
        assertEquals(0.0, model.withInput(2, 100).result, 0.0)
        assertNull(HealthAtlasPhysiology.restore("gastrocnemius", intArrayOf(12, 12, 101)))
        assertEquals(HealthAtlasPhysiologyKind.VESSEL_FLOW, HealthAtlasPhysiologyKind.forItem("veins"))
    }

    @Test fun bendingSeparatesMomentFromTubeGeometryAndUsesConsistentUnits() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("limb-bones", intArrayOf(6, 20, 60)))
        val inertia = Math.PI * (20.0 * 20 * 20 * 20 - 12.0 * 12 * 12 * 12) / 64
        assertEquals(HealthAtlasPhysiologyKind.BONE_BENDING, model.kind)
        assertEquals(inertia, model.companionValue, 1e-9)
        assertEquals(6000.0 * 10.0 / inertia, model.result, 1e-9)
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(model.result * 2, model.withInput(0, 12).result, 1e-9)
        val wider = model.withInput(1, 40)
        assertEquals(model.companionValue * 16, wider.companionValue, 1e-8)
        assertEquals(model.result / 8, wider.result, 1e-9)
        assertTrue(model.withInput(2, 80).result > model.result)
        assertNull(HealthAtlasPhysiology.restore("tibia", intArrayOf(6, 20, 100)))
        assertEquals(HealthAtlasPhysiologyKind.ELBOW_BALANCE, HealthAtlasPhysiologyKind.forItem("radius"))
    }

    @Test fun simplifiedOxygenTransferSeparatesGeometryAndPressureDifference() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("respiratory-membrane", intArrayOf(100, 100, 100)))
        assertEquals(HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION, model.kind)
        assertEquals(1.0, model.result, 0.0)
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(2.0, model.withInput(0, 200).result, 0.0)
        assertEquals(2.0, model.withInput(1, 200).result, 0.0)
        assertEquals(.5, model.withInput(2, 200).result, 0.0)
        val thicker = model.withInput(1, 200).withInput(2, 200)
        assertEquals(model.result, thicker.result, 0.0)
        assertEquals(1.0, thicker.companionValue, 0.0)
        assertNull(HealthAtlasPhysiology.restore("respiratory-membrane", intArrayOf(100, 100, 0)))
        assertEquals(HealthAtlasPhysiologyKind.VENTILATION, HealthAtlasPhysiologyKind.forItem("alveoli"))
        assertEquals(HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE, HealthAtlasPhysiologyKind.forItem("cell-type-ii-pneumocyte"))
    }

    @Test fun cartilageCompressionUsesConsistentStressUnitsAndKeepsTheBaseline() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("cartilage", intArrayOf(32, 160)))
        assertEquals(HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION, model.kind)
        assertEquals(2.0, model.result, 0.0)
        assertEquals(98.0, model.companionValue, 0.0)
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(4.0, model.withInput(0, 64).result, 0.0)
        assertEquals(4.0, model.withInput(1, 80).result, 0.0)
        assertEquals(100.0, model.withInput(0, 0).companionValue, 0.0)
        assertNull(HealthAtlasPhysiology.restore("cartilage", intArrayOf(32, 0)))
        assertNull(HealthAtlasPhysiology.restore("ligaments", intArrayOf(32, 160)))
    }

    @Test fun ventilationSeparatesTotalFlowFromDeadSpace() {
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VENTILATION)
        assertEquals(4.2, model.result, 1e-9)
        assertEquals(6.0, model.companionValue, 1e-9)
        assertEquals(6.0, model.withInput(2, 0).result, 1e-9)
        assertEquals(0.0, model.withInput(1, 200).withInput(2, 200).result, 1e-9)
        assertEquals(8.4, model.withInput(0, 24).result, 1e-9)
        assertEquals(9.0, model.withInput(1, 900).result, 1e-9)
    }
    @Test fun deeperAndSlowerBreathingDifferAtTheSameMinuteVolume() {
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VENTILATION)
        val shallow = model.withInput(0, 24).withInput(1, 250)
        assertEquals(model.companionValue, shallow.companionValue, 1e-9)
        assertEquals(2.4, shallow.result, 1e-9)
        assertTrue(shallow.result < model.result)
    }
    @Test fun renalRatesConserveMassAndDoNotBecomeUrineVolumes() {
        for (filtered in 0..200 step 10) for (fraction in 0..100 step 5) for (secreted in 0..100 step 10) {
            val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.RENAL_EXCRETION, listOf(filtered, fraction, secreted))
            assertEquals(filtered + secreted.toDouble(), model.result + model.companionValue, 1e-9)
            assertTrue(model.result >= 0 && model.companionValue >= 0)
        }
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.RENAL_EXCRETION)
        assertEquals(20.0, model.result, 1e-9)
        assertEquals(10.0, model.withInput(1, 100).result, 1e-9)
        assertEquals("mg/min", model.kind.unit)
    }
    @Test fun potassiumUsesNaturalLogKelvinAndMillivolts() {
        assertEquals(-95.0266, HealthAtlasPhysiology.potassiumPotential(4.0, 140.0), .01)
        assertEquals(0.0, HealthAtlasPhysiology.potassiumPotential(140.0, 140.0), 1e-9)
        assertEquals(61.5404, HealthAtlasPhysiology.potassiumPotential(10.0, 1.0), .001)
        assertEquals(-HealthAtlasPhysiology.potassiumPotential(4.0, 140.0),
            HealthAtlasPhysiology.potassiumPotential(140.0, 4.0), 1e-9)
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.POTASSIUM)
        assertEquals(4.0, model.input(0), 0.0)
        assertEquals(model.result, HealthAtlasPhysiology.potassiumPotential(4.0, 140.0), 0.0)
        assertTrue(model.withInput(0, 80).result > model.result)
    }
    @Test fun everyCurvePointUsesTheSameEquationAndStaysInsideItsAxis() {
        for (kind in HealthAtlasPhysiologyKind.entries) {
            var models = listOf(HealthAtlasPhysiology(kind))
            for (index in kind.inputs.indices) models = models.flatMap { model ->
                listOf(model.withInput(index, kind.inputs[index].range.first), model.withInput(index, kind.inputs[index].range.last))
            }
            for (model in models) {
                assertEquals(model.result, model.resultAt(model.input(kind.axis)), 1e-9)
                var previous: Double? = null
                for (step in 0..120) {
                    val x = model.axisRange.start + (model.axisRange.endInclusive - model.axisRange.start) * step / 120
                    val y = model.resultAt(x)
                    assertTrue("$kind: $y", y.isFinite() && y in kind.minimum..kind.maximum)
                    previous?.let { value ->
                        assertTrue("$kind at $x", when (kind) {
                            HealthAtlasPhysiologyKind.RENAL_EXCRETION, HealthAtlasPhysiologyKind.EYE_FOCUS,
                            HealthAtlasPhysiologyKind.CUSHION_CONTACT_PRESSURE -> y <= value + 1e-9
                            else -> y >= value - 1e-9
                        })
                    }
                    previous = y
                }
            }
        }
    }
    @Test fun invalidSavedStatesAndNonfiniteInputsAreRejected() {
        for (kind in HealthAtlasPhysiologyKind.entries) {
            assertTrue(runCatching { HealthAtlasPhysiology(kind, emptyList()) }.isFailure)
            val model = HealthAtlasPhysiology(kind)
            for ((index, spec) in kind.inputs.withIndex()) for (value in listOf(spec.range.first - 1, spec.range.last + 1))
                assertTrue(runCatching { model.withInput(index, value) }.isFailure)
            for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, model.axisRange.start - 1, model.axisRange.endInclusive + 1))
                assertTrue(runCatching { model.resultAt(value) }.isFailure)
        }
        for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, -1.0)) {
            assertTrue(runCatching { HealthAtlasPhysiology.potassiumPotential(value, 140.0) }.isFailure)
            assertTrue(runCatching { HealthAtlasPhysiology.potassiumPotential(4.0, value) }.isFailure)
        }
        assertNull(HealthAtlasPhysiology.restore("kidneys", intArrayOf(100, 101, 10)))
        assertNull(HealthAtlasPhysiology.restore("brain", intArrayOf(0, 140)))
        assertNull(HealthAtlasPhysiology.restore("liver", intArrayOf(40, 140)))
        assertEquals(4.2, requireNotNull(HealthAtlasPhysiology.restore("lungs", intArrayOf(12, 500, 150))).result, 1e-9)
    }
    @Test fun unrelatedEntitiesDoNotInheritAQuantitativeModel() {
        assertNull(HealthAtlasPhysiologyKind.forItem("cell-hepatocyte"))
        assertNull(HealthAtlasPhysiologyKind.forItem("renal-pelvis"))
        assertNull(HealthAtlasPhysiologyKind.forItem("cell-club-cell"))
        assertNull(HealthAtlasPhysiologyKind.forItem("cell-podocyte"))
        assertEquals(HealthAtlasPhysiologyKind.RENAL_EXCRETION, HealthAtlasPhysiologyKind.forItem("cell-proximal-tubular-cell"))
    }
    @Test fun singleSphericalInterfaceUsesSIAndHalvesPressureWhenRadiusDoubles() {
        val id = "cell-type-ii-pneumocyte"
        val model = requireNotNull(HealthAtlasPhysiology.restore(id, intArrayOf(15, 100)))
        assertEquals(HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE, model.kind)
        assertEquals("Pa", model.kind.unit)
        assertEquals(300.0, model.result, 1e-9)
        assertEquals(150.0, model.companionValue, 1e-9)
        assertEquals(model.companionValue, model.withInput(1, 200).result, 1e-9)
        assertEquals(600.0, model.withInput(0, 30).result, 1e-9)
        assertEquals(50.0, model.withInput(0, 5).withInput(1, 200).result, 1e-9)
        assertEquals(1400.0, model.withInput(0, 35).withInput(1, 50).result, 1e-9)
        assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(15, 0)))
        assertNull(HealthAtlasPhysiology.restore("cell-type-i-pneumocyte", intArrayOf(15, 100)))
    }
    @Test fun bicarbonateMixConservesSoluteWithAndWithoutAddedFlow() {
        val kind = HealthAtlasPhysiologyKind.BICARBONATE_MIX
        val model = HealthAtlasPhysiology(kind)
        assertEquals(50.0, model.result, 1e-9)
        assertEquals(100.0, model.companionValue, 1e-9)
        assertEquals(20.0, model.withInput(0, 0).withInput(1, 120).result, 1e-9)
        assertEquals(100.0, model.withInput(0, 40).withInput(1, 120).result, 1e-9)
        for (flow in kind.inputs[0].range) for (concentration in kind.inputs[1].range step 5) {
            val mixed = model.withInput(0, flow).withInput(1, concentration)
            assertEquals(20.0 + flow / 10.0 * concentration, mixed.result * (1 + flow / 10.0), 1e-8)
            assertTrue(mixed.result >= 20.0 - 1e-9 && mixed.result <= concentration + 1e-9)
        }
        assertNull(HealthAtlasPhysiology.restore("pancreatic-islets", intArrayOf(10, 80)))
        assertNull(HealthAtlasPhysiology.restore("cell-pancreatic-acinar-cell", intArrayOf(10, 80)))
        assertNull(HealthAtlasPhysiology.restore("pancreatic-duct", intArrayOf(-1, 80)))
    }
    @Test fun thyroidFeedbackBalancesTheSyntheticSignalWithoutUsingPersonalResults() {
        val id = "thyroid-gland"
        val model = requireNotNull(HealthAtlasPhysiology.restore(id, intArrayOf(80, 100)))
        assertEquals(40.0, model.result, 1e-9)
        assertEquals(80.0, model.withInput(1, 0).result, 1e-9)
        assertEquals(20.0, model.withInput(1, 300).result, 1e-9)
        for (gain in 0..300 step 7) {
            val current = model.withInput(1, gain)
            assertEquals(current.result * current.input(1), current.companionValue, 1e-9)
            assertEquals(current.input(0), current.result + current.companionValue, 1e-9)
        }
        assertNull(HealthAtlasPhysiology.restore("parathyroid-glands", intArrayOf(80, 100)))
        assertNull(HealthAtlasPhysiology.restore("cell-thyrotroph", intArrayOf(80, 100)))
        assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(80, 301)))
    }
    @Test fun idealPoissonAbsorptionComplementsTheZeroEventProbability() {
        val id = "cell-rod-photoreceptor"
        val model = requireNotNull(HealthAtlasPhysiology.restore(id, intArrayOf(100)))
        assertEquals(63.21205588, model.result, 1e-8)
        assertEquals(0.0, model.withInput(0, 0).result, 1e-9)
        assertEquals(99.3262053, model.withInput(0, 500).result, 1e-7)
        for (count in 0..500) {
            val example = model.withInput(0, count)
            assertEquals(100.0, example.result + example.companionValue, 1e-9)
        }
        assertNull(HealthAtlasPhysiology.restore("retina", intArrayOf(100)))
        assertNull(HealthAtlasPhysiology.restore("cell-cone-photoreceptor", intArrayOf(100)))
        assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(501)))
    }
    @Test fun onlyTheEvaporatedFractionContributesLatentHeat() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("sweat-glands", intArrayOf(60, 50)))
        assertEquals("W", model.kind.unit)
        assertEquals(3.0, model.companionValue, 1e-9)
        assertEquals(121.3, model.result, 1e-9)
        assertEquals(0.0, model.withInput(0, 0).result, 1e-9)
        assertEquals(0.0, model.withInput(1, 0).result, 1e-9)
        assertEquals(242.6, model.withInput(1, 100).result, 1e-9)
        assertNull(HealthAtlasPhysiology.restore("hair-follicles", intArrayOf(60, 50)))
        assertNull(HealthAtlasPhysiology.restore("cell-sweat-gland-secretory-cell", intArrayOf(60, 50)))
    }
    @Test fun idealLymphValveDistinguishesForwardFlowFromAnAdverseGradient() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("lymphatic-vessels", intArrayOf(20, 40)))
        assertEquals(0.5, model.result, 1e-9)
        assertEquals(0.25, model.withInput(1, 80).result, 1e-9)
        assertEquals(0.0, model.withInput(0, 0).result, 1e-9)
        val reverse = model.withInput(0, -20)
        assertEquals(0.0, reverse.result, 1e-9)
        assertEquals(-0.5, reverse.companionValue, 1e-9)
        assertEquals(2.0, model.withInput(0, 40).withInput(1, 20).result, 1e-9)
        assertNull(HealthAtlasPhysiology.restore("lymphatic-vessels", intArrayOf(20, 0)))
        assertNull(HealthAtlasPhysiology.restore("lymph-nodes", intArrayOf(20, 40)))
        assertNull(HealthAtlasPhysiology.restore("thoracic-duct", intArrayOf(20, 40)))
    }
    @Test fun villusSurfaceCountsSideAreaButNeverDoubleCountsTheTubeFootprint() {
        val model = requireNotNull(HealthAtlasPhysiology.restore("jejunum", intArrayOf(12, 45, 60)))
        assertEquals(1.0 + 12 * 2 * Math.PI * .045 * .6, model.result, 1e-9)
        assertEquals(model.result - 1.0, model.companionValue, 1e-9)
        assertEquals(1.0, model.withInput(0, 0).result, 1e-9)
        assertEquals(0.0, model.withInput(0, 0).companionValue, 1e-9)
        val maximum = model.withInput(0, 24).withInput(1, 70).withInput(2, 120)
        assertEquals(1.0 + 24 * 2 * Math.PI * .070 * 1.2, maximum.result, 1e-9)
        assertTrue(maximum.input(1) * 2 < 1.0 / 5.0)
        assertNotNull(HealthAtlasPhysiology.restore("small-intestine", intArrayOf(12, 45, 60)))
        assertNull(HealthAtlasPhysiology.restore("colon", intArrayOf(12, 45, 60)))
        assertNull(HealthAtlasPhysiology.restore("cell-enterocyte", intArrayOf(12, 45, 60)))
    }
}
