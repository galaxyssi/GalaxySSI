package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasBladderExpansionTeachingModelTest {
    private val kind = HealthAtlasPhysiologyKind.BLADDER_EXPANSION

    @Test fun sphericalProxyUsesActualVolumeAreaRelationship() {
        val initial = HealthAtlasPhysiology(kind)
        assertEquals(58.74010519681994, initial.result, 1e-10)
        val radius = HealthAtlasBladderExpansionTeachingModel.radiusCm(200.0)
        assertEquals(200.0, 4 * PI * radius * radius * radius / 3, 1e-10)
        assertEquals(4 * PI * radius * radius, initial.companionValue, 1e-10)
        val unchanged = initial.withInput(1, 0)
        assertEquals(0.0, unchanged.result, 0.0)
        assertTrue(unchanged.companionValue > 0.0)
    }

    @Test fun absoluteAndRelativeAreaRespondInTheExpectedDirections() {
        val start = HealthAtlasPhysiology(kind)
        val biggerStart = start.withInput(0, 150)
        assertTrue(biggerStart.companionValue > start.companionValue)
        assertTrue(biggerStart.result < start.result)
        val maxAdded = start.withInput(1, 300)
        assertTrue(maxAdded.companionValue > start.companionValue)
        assertTrue(maxAdded.result > start.result)
        val maxFraction = maxAdded.withInput(0, 50)
        assertTrue(maxFraction.result in kind.minimum..kind.maximum)
        assertEquals(maxFraction.result, maxFraction.resultAt(300.0), 1e-10)
    }

    @Test fun onlyBladderAndItsLiningShareThisGeometry() {
        assertEquals(setOf("bladder", "cell-urothelial-cell"), kind.teaching?.entryIds)
        val parameters = intArrayOf(100, 100)
        assertEquals(kind, HealthAtlasPhysiology.restore("bladder", parameters)?.kind)
        assertEquals(kind, HealthAtlasPhysiology.restore("cell-urothelial-cell", parameters)?.kind)
        assertEquals(HealthAtlasPhysiologyKind.RENAL_EXCRETION, HealthAtlasPhysiologyKind.forItem("kidneys"))
    }
}
