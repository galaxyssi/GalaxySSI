package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.util.Random

class KnowledgeHnswIndexTest {
    private fun normalized(random: Random, size: Int): FloatArray {
        val row = FloatArray(size) { random.nextFloat() - 0.5f }
        val norm = kotlin.math.sqrt(row.sumOf { it.toDouble() * it }).toFloat()
        return row.apply { indices.forEach { this[it] /= norm } }
    }
    @Test fun retrievesAcrossMoreThanFiveHundredItemsWithHighRecall() {
        val random = Random(41)
        val vectors = List(1201) { normalized(random, 32) }
        KnowledgeHnswIndex(32, vectors.size, 16L * 1024 * 1024).use { index ->
            vectors.forEachIndexed { id, vector -> index.add("item-$id", "revision", KnowledgeStoredVector(0, 0, 12, vector)) }
            var recalled = 0
            for (query in listOf(0, 32, 499, 500, 777, 1000, 1200)) {
                val actual = index.search(vectors[query], 10).map { it.key }.toSet()
                val exact = vectors.indices.sortedByDescending { id -> vectors[id].indices.sumOf {
                    vectors[id][it].toDouble() * vectors[query][it]
                } }.take(10).map { "item-$it" }.toSet()
                recalled += actual.intersect(exact).size
                assertEquals("item-$query", index.search(vectors[query], 1).single().key)
            }
            assertTrue("ANN recall@10=$recalled/70", recalled >= 67)
            assertEquals(1201, index.size())
        }
    }
    @Test fun copiesCallerVectorsAndReturnsNoMutableVectorReferences() {
        val row = KnowledgeStoredVector(0, 5, 10, floatArrayOf(1f, 0f))
        KnowledgeHnswIndex(2, 1, 1_000_000).use {
            it.add("key", "revision", row); row.close()
            val hit = it.search(floatArrayOf(1f, 0f), 1).single()
            assertEquals(1.0, hit.similarity, 0.00001)
            assertEquals(5, hit.start); assertEquals(10, hit.end)
        }
    }
    @Test fun rejectsInvalidVectorsDuplicatesAndCapacityOverflow() {
        KnowledgeHnswIndex(2, 1, 1_000_000).use { index ->
            for (vector in listOf(floatArrayOf(0f, 0f), floatArrayOf(Float.NaN, 1f), floatArrayOf(1f))) {
                assertThrows(IllegalArgumentException::class.java) { index.add("a", "r", KnowledgeStoredVector(0, 0, 1, vector)) }
            }
            val row = KnowledgeStoredVector(0, 0, 1, floatArrayOf(1f, 0f))
            index.add("a", "r", row)
            assertThrows(IllegalStateException::class.java) { index.add("a", "r", row) }
            assertThrows(Exception::class.java) { index.add("b", "r", row) }
            assertEquals("a", index.search(row.values, 1).single().key)
        }
    }
    @Test fun memoryAdmissionUsesLongArithmeticWithoutSilentlyDroppingItems() {
        assertTrue(KnowledgeHnswIndex.estimatedBytes(8192, Int.MAX_VALUE) > Int.MAX_VALUE)
        assertThrows(IllegalArgumentException::class.java) { KnowledgeHnswIndex(512, 100_000, 1_000_000) }
    }
    @Test fun closeIsIdempotentAndRejectsFurtherUse() {
        val index = KnowledgeHnswIndex(2, 1, 1_000_000)
        index.add("a", "r", KnowledgeStoredVector(0, 0, 1, floatArrayOf(1f, 0f)))
        index.close(); index.close()
        assertEquals(0, index.size())
        assertThrows(IllegalStateException::class.java) { index.search(floatArrayOf(1f, 0f), 1) }
    }
}
