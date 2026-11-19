package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasCirculationTest {
    @Test fun doubleCirculationIsClosedAndDoesNotMixTheHeartSides() {
        val legs = HealthAtlasCirculation.legs
        assertEquals(listOf(HealthAtlasBloodNode.TISSUES, HealthAtlasBloodNode.RIGHT_HEART,
            HealthAtlasBloodNode.LUNGS, HealthAtlasBloodNode.LEFT_HEART), legs.map { it.from })
        for (index in legs.indices) assertEquals(legs[index].to, legs[(index + 1) % legs.size].from)
        assertFalse(legs.any { it.from == HealthAtlasBloodNode.RIGHT_HEART && it.to == HealthAtlasBloodNode.LEFT_HEART })
    }
    @Test fun pulmonaryArteriesAndVeinsHaveCorrectRelativeOxygenation() {
        assertEquals(listOf(false, false, true, true), HealthAtlasCirculation.legs.map { it.oxygenRich })
        assertEquals(HealthAtlasBloodNode.LUNGS, HealthAtlasCirculation.legs[1].to)
        assertEquals(HealthAtlasBloodNode.LUNGS, HealthAtlasCirculation.legs[2].from)
    }
    @Test fun stageBoundariesAndCompletionNeverIndexOutsideTheCircuit() {
        for ((phase, stage) in listOf(0f to 0, .249f to 0, .25f to 1, .5f to 2, .75f to 3, 1f to 3)) {
            assertEquals(stage, HealthAtlasCirculation.stage(phase))
            assertTrue(HealthAtlasCirculation.fraction(phase) in 0f..1f)
        }
        assertEquals(1f, HealthAtlasCirculation.fraction(1f))
    }
    @Test fun badAnimationValuesAreBoundedWithoutProducingInvalidGeometry() {
        for (phase in listOf(Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, -1f)) {
            assertEquals(0f, HealthAtlasCirculation.phase(phase))
            assertEquals(0, HealthAtlasCirculation.stage(phase))
        }
        assertEquals(1f, HealthAtlasCirculation.phase(2f))
    }
    @Test fun unrelatedOrgansAndMicroscopicCellsDoNotInheritTheCircuit() {
        for (id in listOf("cardio", "heart", "atria", "ventricles", "blood", "arteries", "veins", "capillaries"))
            assertTrue(HealthAtlasCirculation.supports(id))
        for (id in listOf("cell-pericyte", "cell-cardiomyocyte", "cell-erythrocyte", "lungs", "kidneys", "brain", "unknown"))
            assertFalse(HealthAtlasCirculation.supports(id))
    }
}
