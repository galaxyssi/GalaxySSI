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
    private val zone = ZoneId.of("UTC")
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { context.deleteDatabase(names.activity); clearHealthOverviewFixture(context, names) }
    }
    private fun time(date: String) = LocalDate.parse(date).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
    private fun reading(records: HealthRecordStore, date: String, value: String = "5.4", condition: String = "fasting"): HealthObservation =
        (records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to value), "mmol/L", time(date), condition, reference = "4-6")) as HealthSaveResult.Saved).record
    @Test fun activityHistoryRetainsOldYearsWithoutRollingReplacement() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            store.save(HealthActivityKind.STEPS, first, 4321); store.save(HealthActivityKind.CYCLING, first, 5_400_000)
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
    @Test fun differentUploadsWithSameSamplingWeekFormOnePeriodWithoutChangingOriginals() = fixture { names ->
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            HealthRecordStore(context, names.records).use { records ->
                val saved = (0..1).map { index ->
                    val job = HealthImportJob(UUID.randomUUID().toString(), "content://health.test/$index", time(if (index == 0) "2025-01-10" else "2025-03-10"))
                    originals.createJob(job)
                    val original = originals.importOriginal(job.id, "unique synthetic $index".byteInputStream(), "report-$index.pdf", "application/pdf", "file")
                    val draft = HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to if (index == 0) "5.1" else "5.4"), "mmol/L", time(if (index == 0) "2024-11-12" else "2024-11-14"), "fasting",
                        evidence = HealthEvidence(original.id, job.id, "glucose", original.sha256, 1, "synthetic", confirmed = true))
                    (records.save(draft) as HealthSaveResult.Saved).record to original
                }
                val periods = HealthMeasurementPeriods.page(records, HealthMeasurementPeriodKind.WEEK, time("2025-04-01"), zone)
                assertEquals(1, periods.periods.size)
                val result = HealthMeasurementPeriods.load(records, periods.periods.single(), time("2025-04-01"), zone).series.single()
                assertEquals(2L, result.count); assertEquals(saved[1].first.id, result.latest.id)
                saved.forEach { (record, original) ->
                    assertEquals(record, records.record(record.id)); assertEquals(original, originals.original(original.id))
                    assertEquals(record.id, records.originalPage(original.id).records.single().id)
                }
            }
        }
    }
    @Test fun differentSamplingMonthsNeverMergeEvenWhenImportedTogether() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            reading(records, "2024-10-31"); reading(records, "2024-11-01", "5.8")
            val periods = HealthMeasurementPeriods.page(records, HealthMeasurementPeriodKind.MONTH, time("2024-12-01"), zone)
            assertEquals(listOf(LocalDate.parse("2024-11-01"), LocalDate.parse("2024-10-01")), periods.periods.map { it.first })
            assertEquals(1L, HealthMeasurementPeriods.load(records, periods.periods[0], time("2024-12-01"), zone).series.single().count)
        }
    }
    @Test fun periodPickerPaginatesSparseYearsWithoutRepeatedPeriods() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            repeat(27) { index -> reading(records, first.plusMonths(index.toLong()).toString(), "${5 + index % 2}.1") }
            val periods = arrayListOf<HealthMeasurementPeriod>(); var cursor: LocalDate? = null
            do {
                val page = HealthMeasurementPeriods.page(records, HealthMeasurementPeriodKind.MONTH, time("2027-01-01"), zone, cursor)
                assertTrue(page.periods.size <= 12); periods += page.periods; cursor = page.next
            } while (cursor != null)
            assertEquals(27, periods.size); assertEquals(27, periods.distinct().size)
        }
    }
    @Test fun periodCountsKeepFastingAndPostMealSeparate() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            reading(records, "2024-11-12", "5.1"); reading(records, "2024-11-13", "5.4"); reading(records, "2024-11-14", "7.8", "after_meal_2h")
            val period = HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.WEEK, LocalDate.parse("2024-11-12"))
            val result = HealthMeasurementPeriods.load(records, period, time("2024-12-01"), zone)
            assertEquals(2, result.series.size); assertEquals(2L, result.series.single { it.key.condition == "fasting" }.count)
            assertEquals("5.4", result.series.single { it.key.condition == "fasting" }.latest.draft.values["glucose"])
        }
    }
    @Test fun measurementPagingKeepsAllNinetyFiveRecordsAndExcludesStepsAndDeletedRows() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            val start = time("2024-11-12")
            repeat(95) { records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", start + it * 60_000)) }
            records.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "1000"), "steps", start))
            val removed = reading(records, "2024-11-13"); assertTrue(records.delete(removed.id, removed.revision))
            val ids = linkedSetOf<String>(); var cursor: HealthPageCursor? = null
            do {
                val page = records.measurementPage(time("2024-11-11"), time("2024-11-18"), cursor)
                assertTrue(page.records.size <= 30); page.records.forEach { assertTrue(ids.add(it.id)); assertNotEquals(HealthMetric.STEPS, it.draft.metric) }; cursor = page.next
            } while (cursor != null)
            assertEquals(95, ids.size)
        }
    }
    @Test fun periodOverviewDoesNotChangeTodayStepsOrRewriteMeasurements() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            val saved = reading(records, "2024-11-12")
            records.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "1234"), "steps", time("2024-11-12")))
            val latest = HealthOverviewRepository.load(context, records, names, time("2024-11-18"), zone)
            val selected = HealthOverviewRepository.measurements(context, records, names, latest,
                HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.WEEK, LocalDate.parse("2024-11-12")))
            assertEquals(latest.metrics.single { it.metric == HealthMetric.STEPS }, selected.metrics.single { it.metric == HealthMetric.STEPS })
            assertEquals(saved, records.record(saved.id))
        }
    }
    @Test fun trendHandoffRetainsCollectionConditionUnitAndSource() = fixture { names ->
        val record = HealthObservation(UUID.randomUUID().toString(), 1,
            HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.4"), "mmol/L", 1_600_000_000_000, "after_meal_2h", "left"), 1)
        val intent = healthComparableTrendIntent(context, names, record); val spec = requireNotNull(intent.healthTrendSpec())
        assertEquals("mmol/L", spec.unit); assertEquals("after_meal_2h", spec.source.condition); assertEquals("left", spec.source.side)
        assertTrue(spec.source.manualOnly); assertEquals(names, intent.healthNavigationDatabases()); assertEquals(spec, Intent().putHealthTrend(spec).healthTrendSpec())
    }
    @Test fun cancellationStopsPeriodScanningWithoutChangingRecords() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            val saved = reading(records, "2024-11-12")
            assertThrows(java.util.concurrent.CancellationException::class.java) {
                HealthMeasurementPeriods.load(records, HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.MONTH, first), time("2025-01-01"), zone) {
                    throw java.util.concurrent.CancellationException()
                }
            }
            assertEquals(saved, records.record(saved.id))
        }
    }
}
