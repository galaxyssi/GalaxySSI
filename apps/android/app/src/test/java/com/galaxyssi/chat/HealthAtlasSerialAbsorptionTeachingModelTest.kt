package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasSerialAbsorptionTeachingModelTest {
    private val spec = HealthAtlasSerialAbsorptionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultsAbsorbFortyThenHalfOfTheRemainingSixty() {
        assertEquals(setOf("gut", "digestive", "duodenum", "ileum", "cell-enterocyte"), spec.entryIds)
        assertEquals(listOf("serial-absorption-stage-a", "serial-absorption-stage-b"), controls.map { it.key })
        assertEquals(1, spec.axis)
        assertEquals("%", spec.unit)
        assertEquals(listOf("%", "%"), spec.inputs.map { it.unit })

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(40.0, 50.0), defaults)
        assertEquals(70.0, spec.evaluate(defaults), epsilon)
        assertEquals(30.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun eachStageOnlyAbsorbsFromItsIncomingAmount() {
        val cases = listOf(
            listOf(0.0, 0.0) to 0.0,
            listOf(40.0, 0.0) to 40.0,
            listOf(0.0, 50.0) to 50.0,
            listOf(20.0, 50.0) to 60.0,
            listOf(60.0, 50.0) to 80.0,
            listOf(40.0, 100.0) to 100.0,
            listOf(100.0, 50.0) to 100.0,
        )
        for ((values, absorbed) in cases) {
            assertEquals(absorbed, spec.evaluate(values), epsilon)
            assertEquals(100.0 - absorbed, spec.companionValue(values), epsilon)
        }
    }

    @Test fun everySliderCombinationConservesTheStartingAmountAndFitsChart() {
        val (stageA, stageB) = controls
        val chartRange = spec.minimum..spec.maximum
        for (aStep in stageA.range) {
            val absorbedByA = aStep / stageA.scale
            for (bStep in stageB.range) {
                val bPercent = bStep / stageB.scale
                val absorbedByB = (100.0 - absorbedByA) * bPercent / 100.0
                val values = listOf(absorbedByA, bPercent)
                val absorbed = spec.evaluate(values)
                val remaining = spec.companionValue(values)

                assertTrue(absorbed in chartRange)
                assertTrue(remaining in chartRange)
                assertEquals(absorbedByA + absorbedByB, absorbed, epsilon)
                assertEquals(100.0, absorbedByA + absorbedByB + remaining, epsilon)
            }
        }
    }
}
