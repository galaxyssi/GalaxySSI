package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasPhysiologyTest {
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
                    previous?.let { assertTrue(if (kind == HealthAtlasPhysiologyKind.RENAL_EXCRETION) y <= it + 1e-9 else y >= it - 1e-9) }
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
        assertNull(HealthAtlasPhysiologyKind.forItem("cell-type-ii-pneumocyte"))
        assertEquals(HealthAtlasPhysiologyKind.RENAL_EXCRETION, HealthAtlasPhysiologyKind.forItem("cell-proximal-tubular-cell"))
    }
}
