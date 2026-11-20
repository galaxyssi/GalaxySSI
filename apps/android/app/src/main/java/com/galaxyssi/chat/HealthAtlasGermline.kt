package com.galaxyssi.chat

/** Stage-end teaching counts. No anaphase intermediates, karyotype testing or patient inference. */
internal object HealthAtlasGermline {
    const val SOURCE = "https://openstax.org/books/biology-2e/pages/11-1-the-process-of-meiosis"
    enum class Target { LINEAGE_CELL, PATERNAL_GENOME, MATERNAL_GENOME, COMBINED_GENOMES }
    data class Counts(val sets: Int, val dnaContent: Int, val target: Target) {
        init { require(sets in 1..2 && (dnaContent == sets || dnaContent == 2 * sets)) }
        val chromosomes get() = 23 * sets
        val dnaMolecules get() = 23 * dnaContent
        val duplicated get() = dnaContent == 2 * sets
    }
    val supported = setOf("cell-spermatogonium", "cell-spermatocyte", "cell-spermatozoon", "cell-oocyte-or-ovum")
    fun counts(id: String, stage: Int): Counts? {
        require(stage in 0..3)
        return when (id) {
            "cell-spermatogonium" -> Counts(2, if (stage < 2) 2 else 4, Target.LINEAGE_CELL)
            "cell-spermatocyte" -> when (stage) {
                0 -> Counts(2, 4, Target.LINEAGE_CELL)
                1 -> Counts(1, 2, Target.LINEAGE_CELL)
                else -> Counts(1, 1, Target.LINEAGE_CELL)
            }
            "cell-spermatozoon" -> Counts(1, 1, Target.PATERNAL_GENOME)
            "cell-oocyte-or-ovum" -> when (stage) {
                0, 1 -> Counts(1, 2, Target.MATERNAL_GENOME)
                2 -> Counts(1, 1, Target.MATERNAL_GENOME)
                else -> Counts(2, 2, Target.COMBINED_GENOMES)
            }
            else -> null
        }
    }
}
