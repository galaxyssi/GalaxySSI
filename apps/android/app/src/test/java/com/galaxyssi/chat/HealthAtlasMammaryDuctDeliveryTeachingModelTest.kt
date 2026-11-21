package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMammaryDuctDeliveryTeachingModelTest {
    private val spec = HealthAtlasMammaryDuctDeliveryTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsSplitSecretedVolumeBetweenDuctAndLumen() {
        assertEquals(
            setOf("mammary-glands", "cell-mammary-luminal-cell", "cell-myoepithelial-cell"),
            spec.entryIds,
        )
        assertEquals(1, spec.axis)
        assertEquals(
            listOf("mammary-duct-secreted-volume", "mammary-duct-displaced-share"),
            controls.map { it.key },
        )
        assertEquals(listOf("VU", "%"), spec.inputs.map { it.unit })
        assertEquals("VU", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(8.0, 60.0), defaults)
        assertEquals(4.8, spec.evaluate(defaults), epsilon)
        assertEquals(3.2, spec.companionValue(defaults), epsilon)
    }

    @Test fun zeroAndFullDisplacementMoveNoneOrAllOfTheSecretedVolume() {
        val (secretion, displacement) = controls
        assertEquals(4..12, secretion.range)
        assertEquals(0..100, displacement.range)
        for (step in secretion.range) {
            val volume = step / secretion.scale
            val none = listOf(volume, displacement.range.first / displacement.scale)
            val all = listOf(volume, displacement.range.last / displacement.scale)

            assertEquals(0.0, spec.evaluate(none), epsilon)
            assertEquals(volume, spec.companionValue(none), epsilon)
            assertEquals(volume, spec.evaluate(all), epsilon)
            assertEquals(0.0, spec.companionValue(all), epsilon)
        }
    }

    @Test fun increasingDisplacementTransfersVolumeWithoutChangingTheSecretedTotal() {
        val (secretion, displacement) = controls
        for (secretionStep in secretion.range) {
            val volume = secretionStep / secretion.scale
            var previousDelivered = Double.NEGATIVE_INFINITY
            var previousRetained = Double.POSITIVE_INFINITY
            for (displacementStep in displacement.range) {
                val values = listOf(volume, displacementStep / displacement.scale)
                val delivered = spec.evaluate(values)
                val retained = spec.companionValue(values)

                assertTrue(delivered in spec.minimum..spec.maximum)
                assertTrue(delivered in 0.0..volume)
                assertTrue(retained in 0.0..volume)
                assertTrue(delivered > previousDelivered)
                assertTrue(retained < previousRetained)
                assertEquals(volume, delivered + retained, epsilon)
                previousDelivered = delivered
                previousRetained = retained
            }
        }
    }

    @Test fun increasingSecretionRaisesBothVolumesAtFixedPartialDisplacement() {
        val (secretion, displacement) = controls
        val share = displacement.initial / displacement.scale
        for (step in secretion.range.first until secretion.range.last) {
            val lower = listOf(step / secretion.scale, share)
            val higher = listOf((step + 1) / secretion.scale, share)

            assertTrue(spec.evaluate(higher) > spec.evaluate(lower))
            assertTrue(spec.companionValue(higher) > spec.companionValue(lower))
        }
    }
}
