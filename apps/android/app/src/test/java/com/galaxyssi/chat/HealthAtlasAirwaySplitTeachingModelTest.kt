package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasAirwaySplitTeachingModelTest {
    private val spec = HealthAtlasAirwaySplitTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultInputsUseScaledFlowAndResistanceUnits() {
        assertEquals(setOf("trachea", "bronchi", "bronchioles"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals("L/s", spec.unit)
        assertEquals(listOf("L/s", "cmH\u2082O\u00b7s/L", "cmH\u2082O\u00b7s/L"), spec.inputs.map { it.unit })
        assertTrue(controls.all { it.initial in it.range && it.scale.isFinite() && it.scale > 0 })

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(0.30, 1.5, 3.0), defaults)
        assertEquals(0.20, spec.evaluate(defaults), epsilon)
        assertEquals(0.10, spec.companionValue(defaults), epsilon)
    }

    @Test fun equalResistancesSplitEvenlyAndSwappingBranchesSwapsFlows() {
        val equal = listOf(0.50, 2.0, 2.0)
        assertEquals(0.25, spec.evaluate(equal), epsilon)
        assertEquals(0.25, spec.companionValue(equal), epsilon)

        val unequal = listOf(0.50, 1.0, 4.0)
        val swapped = listOf(0.50, 4.0, 1.0)
        assertEquals(0.40, spec.evaluate(unequal), epsilon)
        assertEquals(0.10, spec.companionValue(unequal), epsilon)
        assertEquals(spec.evaluate(unequal), spec.companionValue(swapped), epsilon)
        assertEquals(spec.companionValue(unequal), spec.evaluate(swapped), epsilon)
    }

    @Test fun everySliderCombinationConservesFlowSharesPressureDropAndFitsChart() {
        val (totalControl, selectedControl, otherControl) = controls
        var minimum = Double.POSITIVE_INFINITY
        var maximum = Double.NEGATIVE_INFINITY
        for (totalStep in totalControl.range) {
            val total = totalStep / totalControl.scale
            for (selectedStep in selectedControl.range) {
                val selected = selectedStep / selectedControl.scale
                for (otherStep in otherControl.range) {
                    val other = otherStep / otherControl.scale
                    val values = listOf(total, selected, other)
                    val selectedFlow = spec.evaluate(values)
                    val otherFlow = spec.companionValue(values)
                    assertTrue(selectedFlow in spec.minimum..spec.maximum)
                    assertTrue(otherFlow in spec.minimum..spec.maximum)
                    assertTrue(selectedFlow > 0 && otherFlow > 0)
                    assertEquals(total, selectedFlow + otherFlow, epsilon)
                    assertEquals(selectedFlow * selected, otherFlow * other, epsilon)
                    minimum = minOf(minimum, selectedFlow)
                    maximum = maxOf(maximum, selectedFlow)
                }
            }
        }
        assertEquals(0.02, minimum, epsilon)
        assertEquals(0.48, maximum, epsilon)
    }

    @Test fun raisingOneResistanceRedistributesTheFixedTotal() {
        val base = listOf(0.30, 1.5, 3.0)
        val higherSelectedResistance = listOf(0.30, 2.0, 3.0)
        val higherOtherResistance = listOf(0.30, 1.5, 4.0)
        val higherTotal = listOf(0.60, 1.5, 3.0)

        assertTrue(spec.evaluate(higherSelectedResistance) < spec.evaluate(base))
        assertTrue(spec.companionValue(higherSelectedResistance) > spec.companionValue(base))
        assertTrue(spec.evaluate(higherOtherResistance) > spec.evaluate(base))
        assertTrue(spec.companionValue(higherOtherResistance) < spec.companionValue(base))
        assertEquals(2 * spec.evaluate(base), spec.evaluate(higherTotal), epsilon)
        assertEquals(2 * spec.companionValue(base), spec.companionValue(higherTotal), epsilon)

        val baseDrop = spec.evaluate(base) * base[1]
        assertTrue(spec.evaluate(higherSelectedResistance) * higherSelectedResistance[1] > baseDrop)
        val totalAtFixedDrop = baseDrop / higherSelectedResistance[1] + baseDrop / higherSelectedResistance[2]
        assertEquals(0.25, totalAtFixedDrop, epsilon)
    }
}
