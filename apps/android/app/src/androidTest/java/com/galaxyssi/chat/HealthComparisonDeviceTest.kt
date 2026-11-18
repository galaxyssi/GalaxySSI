package com.galaxyssi.chat

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthComparisonDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val first = LocalDate.of(2024, 1, 1)
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { context.deleteDatabase(names.activity); clearHealthOverviewFixture(context, names) }
    }
    @Test fun activityHistoryRetainsOldYearsWithoutRollingReplacement() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            store.save(HealthActivityKind.STEPS, first, 4321)
            store.save(HealthActivityKind.CYCLING, first, 5_400_000)
            store.save(HealthActivityKind.STEPS, first.plusYears(3), 1234)
        }
        HealthActivityHistoryStore(context, names.activity).use { store ->
            assertEquals(4321L, store.read(HealthActivityKind.STEPS, first, first).single().total)
            assertEquals(5_400_000L, store.read(HealthActivityKind.CYCLING, first, first).single().total)
            assertEquals(1234L, store.read(HealthActivityKind.STEPS, first.plusYears(3), first.plusYears(3)).single().total)
        }
    }
    @Test fun duplicateOrStaleCheckpointDoesNotOverwriteHistory() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            listOf(100L, 100L, 60L, 130L).forEach { store.save(HealthActivityKind.STEPS, first, it) }
            assertEquals(130L, store.read(HealthActivityKind.STEPS, first, first).single().total)
            assertTrue(store.read(HealthActivityKind.STEPS, first.plusDays(1), first.plusDays(1)).isEmpty())
        }
    }
    @Test fun activityKindsAndExplicitZeroStaySeparate() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            store.save(HealthActivityKind.STEPS, first, 0); store.save(HealthActivityKind.CYCLING, first, 60_000)
            assertEquals(0L, store.read(HealthActivityKind.STEPS, first, first).single().total)
            assertEquals(60_000L, store.read(HealthActivityKind.CYCLING, first, first).single().total)
        }
    }
    @Test fun rangeQueryIsBoundedWhileStoredHistoryIsNot() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            repeat(400) { store.save(HealthActivityKind.STEPS, first.plusDays(it.toLong()), it.toLong()) }
            assertEquals(7, store.read(HealthActivityKind.STEPS, first.plusDays(200), first.plusDays(206)).size)
            assertEquals(400, store.read(HealthActivityKind.STEPS, first, first.plusDays(399)).size)
        }
    }
    private fun import(names: HealthOverviewDatabases, at: Long, name: String): Pair<HealthImportJob, HealthOriginal> =
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            val job = HealthImportJob(UUID.randomUUID().toString(), "content://health.test/$name", at, name = name)
            originals.createJob(job)
            val original = originals.importOriginal(job.id, name.byteInputStream(), "$name.pdf", "application/pdf", "file")
            job to original
        }
    private fun reading(records: HealthRecordStore, job: HealthImportJob, original: HealthOriginal, value: String, at: Long): HealthObservation {
        val draft = HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to value), "mmol/L", at, "fasting",
            evidence = HealthEvidence(original.id, job.id, "glucose", original.sha256, 1, value, confirmed = true), reference = "4-6")
        return (records.save(draft) as HealthSaveResult.Saved).record
    }
    @Test fun sameDayImportsRemainDistinctBatchesAndKeepSamplingDates() = fixture { names ->
        val at = first.atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli()
        val one = import(names, at, "one"); val two = import(names, at, "two")
        HealthRecordStore(context, names.records).use { records ->
            val x = reading(records, one.first, one.second, "5.4", at - 86_400_000)
            reading(records, two.first, two.second, "5.8", at - 172_800_000)
            HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
                val batches = HealthMeasurementBatches(originals)
                assertEquals(2, batches.page().items.size)
                val selected = batches.load(records, HealthMeasurementBatches.keyFor(one.first))
                assertEquals(x.id, selected.latest[HealthMetric.GLUCOSE]?.id)
                assertEquals(at - 86_400_000, selected.latest[HealthMetric.GLUCOSE]?.draft?.measuredAt)
            }
        }
    }
    @Test fun batchListPaginatesWithoutDuplicateOrMissingImports() = fixture { names ->
        repeat(34) { import(names, 1_600_000_000_000L + it, "report-$it") }
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            val repo = HealthMeasurementBatches(originals)
            val first = repo.page(); val second = repo.page(first.next)
            assertEquals(30, first.items.size); assertEquals(4, second.items.size); assertNull(second.next)
            assertEquals(34, (first.items + second.items).map { it.key }.distinct().size)
        }
    }
    @Test fun multiFileImportGroupsByBatchButKeepsEachReportAndItsSamplingTime() = fixture { names ->
        val at = 1_600_000_000_000L
        val batch = HealthPhotoBatch(UUID.randomUUID().toString(), "report", at)
        val files = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            originals.createCaptureBatch(batch)
            (0..1).map { index ->
                val job = HealthImportJob(UUID.randomUUID().toString(), "content://health.test/$index", at + index, captureBatch = batch.id)
                originals.addCaptureJob(batch.id, job)
                job to originals.importOriginal(job.id, "synthetic-$index".byteInputStream(), "report-$index.pdf", "application/pdf", "file")
            }
        }
        HealthRecordStore(context, names.records).use { records ->
            val old = reading(records, files[0].first, files[0].second, "5.1", at - 86_400_000)
            val recent = reading(records, files[1].first, files[1].second, "5.4", at)
            HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
                val repo = HealthMeasurementBatches(originals)
                val owner = repo.page().items.single()
                assertEquals(2, owner.reports); assertEquals("batch:${batch.id}", owner.key)
                assertEquals(recent.id, repo.load(records, owner.key).latest[HealthMetric.GLUCOSE]?.id)
                assertEquals(old.id, repo.load(records, owner.key, files[0].second.id).latest[HealthMetric.GLUCOSE]?.id)
            }
        }
    }
    @Test fun reportSelectionCannotReadOutsideItsBatch() = fixture { names ->
        val a = import(names, 1_600_000_000_000, "a"); val b = import(names, 1_600_000_000_001, "b")
        HealthRecordStore(context, names.records).use { records ->
            HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
                assertThrows(IllegalStateException::class.java) {
                    HealthMeasurementBatches(originals).load(records, HealthMeasurementBatches.keyFor(a.first), b.second.id)
                }
            }
        }
    }
    @Test fun trendHandoffRetainsCollectionConditionUnitAndSource() = fixture { names ->
        val record = HealthObservation(UUID.randomUUID().toString(), 1,
            HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.4"), "mmol/L", 1_600_000_000_000, "after_meal_2h", "left"), 1)
        val intent = healthComparableTrendIntent(context, names, record)
        val spec = requireNotNull(intent.healthTrendSpec())
        assertEquals("mmol/L", spec.unit); assertEquals("after_meal_2h", spec.source.condition)
        assertEquals("left", spec.source.side); assertTrue(spec.source.manualOnly)
        assertEquals(names, intent.healthNavigationDatabases())
        assertEquals(spec, Intent().putHealthTrend(spec).healthTrendSpec())
    }
    @Test fun batchOverviewDoesNotChangeTodayStepValueOrPersistMeasurementEdits() = fixture { names ->
        val at = first.atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli()
        val imported = import(names, at, "sample")
        HealthRecordStore(context, names.records).use { records ->
            val saved = reading(records, imported.first, imported.second, "5.4", at)
            records.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "1234"), "steps", at))
            val latest = HealthOverviewRepository.load(context, records, names, at + 1_000, ZoneId.of("UTC"))
            val selected = HealthOverviewRepository.batch(context, records, names, latest, HealthMeasurementBatches.keyFor(imported.first))
            assertEquals(latest.metrics.single { it.metric == HealthMetric.STEPS }, selected.metrics.single { it.metric == HealthMetric.STEPS })
            assertEquals(saved, records.record(saved.id))
        }
    }
}
