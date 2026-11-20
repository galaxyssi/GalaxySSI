package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasGermlineTest {
    private fun states(id: String) = (0..3).map { requireNotNull(HealthAtlasGermline.counts(id, it)) }
    @Test fun premeioticReplicationChangesDnaButNotChromosomeCount() {
        val states = states("cell-spermatogonium")
        assertEquals(listOf(46, 46, 46, 46), states.map { it.chromosomes })
        assertEquals(listOf(46, 46, 92, 92), states.map { it.dnaMolecules })
        assertEquals(listOf(false, false, true, true), states.map { it.duplicated })
        assertTrue(states.all { it.target == HealthAtlasGermline.Target.LINEAGE_CELL })
    }
    @Test fun successiveMeioticDivisionsTrackOneDescendantNotAllDaughters() {
        val states = states("cell-spermatocyte")
        assertEquals(listOf(46, 23, 23, 23), states.map { it.chromosomes })
        assertEquals(listOf(92, 46, 23, 23), states.map { it.dnaMolecules })
        assertEquals(listOf(2, 1, 1, 1), states.map { it.sets })
        assertEquals(listOf(4, 2, 1, 1), states.map { it.dnaContent })
        assertEquals(states[2], states[3])
    }
    @Test fun oocyteSequenceKeepsMaternalCountsSeparateUntilZygote() {
        val states = states("cell-oocyte-or-ovum")
        assertEquals(listOf(23, 23, 23, 46), states.map { it.chromosomes })
        assertEquals(listOf(46, 46, 23, 46), states.map { it.dnaMolecules })
        assertTrue(states.take(3).all { it.target == HealthAtlasGermline.Target.MATERNAL_GENOME })
        assertEquals(HealthAtlasGermline.Target.COMBINED_GENOMES, states[3].target)
        assertEquals(2, states[3].dnaContent)
    }
    @Test fun spermDoesNotGainMaternalChromosomesAtMembraneFusion() {
        for (state in states("cell-spermatozoon")) {
            assertEquals(23, state.chromosomes); assertEquals(23, state.dnaMolecules)
            assertEquals(HealthAtlasGermline.Target.PATERNAL_GENOME, state.target)
        }
    }
    @Test fun scopeAndInvalidStatesAreStrict() {
        for (id in listOf("male", "female", "cell-sertoli-cell", "cell-granulosa-cell", "cell-trophoblast", "cell-neuron"))
            for (stage in 0..3) assertNull(HealthAtlasGermline.counts(id, stage))
        for (id in HealthAtlasGermline.supported) for (stage in listOf(-1, 4, Int.MAX_VALUE))
            assertTrue(runCatching { HealthAtlasGermline.counts(id, stage) }.isFailure)
        for ((sets, dna) in listOf(0 to 0, 3 to 6, 1 to 3, 2 to 1, 2 to 3, 2 to 5))
            assertTrue(runCatching { HealthAtlasGermline.Counts(sets, dna, HealthAtlasGermline.Target.LINEAGE_CELL) }.isFailure)
    }
}
