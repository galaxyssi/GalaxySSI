package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePreparationDeviceTest {
    @Test fun unrelatedWriterCommitsWhileOldBodiesAreBeingPrepared() = KnowledgeSourceReplaceFixture().use { f ->
        val old = f.item(1)
        val other = f.item(9).copy(source = "independent-source")
        f.store.upsert(old)
        val writer = Executors.newSingleThreadExecutor()
        try { KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource(old.source, sequenceOf(f.item(2)))
            val prepared = KnowledgeSourceReplacement(f.db, stage, old.source).prepare { count ->
                assertEquals(1L, count)
                writer.submit {
                    val samples = LongArray(50) { i ->
                        val started = System.nanoTime()
                        f.store.upsert(other.copy(summary = "durable-sample-$i"))
                        System.nanoTime() - started
                    }.sorted()
                    println("KNOWLEDGE_SOURCE_PREPARE_WRITE samples=50 durable=true p50_ns=${samples[24]} " +
                        "p95_ns=${samples[47]} p99_ns=${samples[49]} over_200ms=${samples.count { it > 200_000_000 }}")
                }.get(30, TimeUnit.SECONDS)
            }
            assertEquals(listOf(old), stage.previous().toList())
            prepared.commit()
            assertEquals(setOf(f.item(2).id, other.id), f.items().map { it.id }.toSet())
        } } finally { writer.shutdownNow(); assertTrue(writer.awaitTermination(10, TimeUnit.SECONDS)) }
    }

    @Test fun concurrentBodyAndPermissionChangesRejectThePreparedReplacement() {
        for (permissionOnly in listOf(false, true)) KnowledgeSourceReplaceFixture().use { f ->
            val old = f.item(1)
            f.store.upsert(old)
            KnowledgeBackupStaging(f.context).use { stage ->
                stage.acceptSource(old.source, sequenceOf(f.item(2)))
                val prepared = KnowledgeSourceReplacement(f.db, stage, old.source).prepare()
                val changed = if (permissionOnly) old.copy(cloudAccess = AgentKnowledgeCloudAccess.FULL)
                    else old.copy(content = "concurrent source edit")
                f.store.upsert(changed)
                assertThrows(KnowledgeSourceReplacementChanged::class.java) { prepared.commit() }
                assertEquals(listOf(changed), f.items())
            }
        }
    }

    @Test fun formerlyAbsentSourceCannotOverwriteAConcurrentCreation() = KnowledgeSourceReplaceFixture().use { f ->
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource(f.item(1).source, sequenceOf(f.item(1)))
            val prepared = KnowledgeSourceReplacement(f.db, stage, f.item(1).source).prepare()
            f.store.upsert(f.item(2))
            assertThrows(KnowledgeSourceReplacementChanged::class.java) { prepared.commit() }
            assertEquals(listOf(f.item(2)), f.items())
        }
    }

    @Test fun deletionAndIdenticalRecreationCannotPassAnOldRevision() = KnowledgeSourceReplaceFixture().use { f ->
        val old = f.item(1)
        f.store.upsert(old)
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource(old.source, sequenceOf(f.item(2)))
            val prepared = KnowledgeSourceReplacement(f.db, stage, old.source).prepare()
            f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", old.id))) }
            f.store.upsert(old)
            assertThrows(KnowledgeSourceReplacementChanged::class.java) { prepared.commit() }
            assertEquals(listOf(old), f.items())
        }
    }

    @Test fun incomingIdentityClaimedByAnotherSourceStillFailsBeforeAnyMutation() = KnowledgeSourceReplaceFixture().use { f ->
        val old = f.item(1)
        f.store.upsert(old)
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource(old.source, sequenceOf(f.item(2), f.item(3)))
            val prepared = KnowledgeSourceReplacement(f.db, stage, old.source).prepare()
            val claimed = f.item(3).copy(source = "independent-source")
            f.store.upsert(claimed)
            assertThrows(IllegalArgumentException::class.java) { prepared.commit() }
            assertEquals(setOf(old, claimed), f.items().toSet())
        }
    }

    @Test fun cancelledPreparationAndRepeatedPublicationCannotMutateSources() = KnowledgeSourceReplaceFixture().use { f ->
        val old = f.item(1)
        f.store.upsert(old)
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource(old.source, sequenceOf(f.item(2)))
            assertThrows(InterruptedException::class.java) {
                KnowledgeSourceReplacement(f.db, stage, old.source).prepare { throw InterruptedException("test cancellation") }
            }
            assertEquals(listOf(old), f.items())
        }
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptSource(old.source, sequenceOf(f.item(2)))
            val prepared = KnowledgeSourceReplacement(f.db, stage, old.source).prepare()
            prepared.commit()
            assertThrows(IllegalStateException::class.java) { prepared.commit() }
            assertEquals(listOf(f.item(2).id), f.items().map { it.id })
        }
    }
}
