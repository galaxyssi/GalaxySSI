package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMucosalSamplingTeachingModelTest {
    private val spec = HealthAtlasMucosalSamplingTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun atlasEntriesAndDefaultsDescribeTheSelectedAreaShare() {
        assertEquals(setOf("tonsils", "adenoids", "appendix", "gut-associated-lymphoid-tissue"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(
            listOf("mucosal-sampling-selected-tiles", "mucosal-sampling-unselected-tiles"),
            controls.map { it.key },
        )
        assertEquals(listOf(1..12, 1..12), controls.map { it.range })
        assertEquals("%", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(3.0, 9.0), defaults)
        assertEquals(25.0, spec.evaluate(defaults), epsilon)
        assertEquals(75.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun equalTileRatiosGiveEqualSharesAndGraphValuesAreNotRounded() {
        assertEquals(25.0, spec.evaluate(listOf(2.0, 6.0)), epsilon)
        assertEquals(50.0, spec.evaluate(listOf(12.0, 12.0)), epsilon)
        assertEquals(28.0, spec.evaluate(listOf(3.5, 9.0)), epsilon)
        assertEquals(100.0 / 13.0, spec.evaluate(listOf(1.0, 12.0)), epsilon)
        assertEquals(1200.0 / 13.0, spec.evaluate(listOf(12.0, 1.0)), epsilon)
    }

    @Test fun everySliderStepChangesShareAndThePartitionAlwaysTotals100Percent() {
        val (selectedControl, unselectedControl) = controls
        for (selectedStep in selectedControl.range) {
            for (unselectedStep in unselectedControl.range) {
                val selected = selectedStep / selectedControl.scale
                val unselected = unselectedStep / unselectedControl.scale
                val values = listOf(selected, unselected)
                val share = spec.evaluate(values)
                val otherShare = spec.companionValue(values)
                assertTrue(share in spec.minimum..spec.maximum)
                assertTrue(otherShare in 0.0..100.0)
                assertEquals(100.0, share + otherShare, epsilon)
                if (selectedStep < selectedControl.range.last) {
                    val nextSelected = (selectedStep + 1) / selectedControl.scale
                    assertTrue(spec.evaluate(listOf(nextSelected, unselected)) > share)
                }
                if (unselectedStep < unselectedControl.range.last) {
                    val nextUnselected = (unselectedStep + 1) / unselectedControl.scale
                    assertTrue(spec.evaluate(listOf(selected, nextUnselected)) < share)
                }
            }
        }
    }
}
