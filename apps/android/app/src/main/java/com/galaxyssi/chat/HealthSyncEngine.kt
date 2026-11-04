package com.galaxyssi.chat

import android.os.RemoteException
import java.io.IOException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

internal enum class HealthSyncOutcome {
    NOT_STARTED, RUNNING, UPDATED, NO_NEW, PERMISSION, UNAVAILABLE, NETWORK, TRANSPORT, TIMEOUT, STORAGE, FAILED
}

internal data class HealthSyncCheckpoint(
    val scope: HealthConnectScope,
    val token: String = "",
    val snapshotCursor: String = "",
    val snapshotFrom: Long = 0,
    val snapshotUntil: Long = 0,
    val stepDate: String = "",
    val stepZone: String = "",
    val lastAttempt: Long = 0,
    val lastSuccess: Long = 0,
    val latestMeasurement: Long = 0,
    val pendingInserts: Int = 0,
    val pendingDeletes: Int = 0,
    val lastInserts: Int = 0,
    val lastDeletes: Int = 0,
    val historyGap: Boolean = false,
    val outcome: HealthSyncOutcome = HealthSyncOutcome.NOT_STARTED,
) {
    init {
        require(token.length <= 32768 && snapshotCursor.length <= 32768)
        require(snapshotFrom == 0L && snapshotUntil == 0L || snapshotFrom > 0 && snapshotUntil > snapshotFrom)
        require(listOf(lastAttempt, lastSuccess, latestMeasurement).all { it >= 0 })
        require(listOf(pendingInserts, pendingDeletes, lastInserts, lastDeletes).all { it >= 0 })
        require(stepDate.isEmpty() || LocalDate.parse(stepDate).toString() == stepDate)
        require(stepZone.isEmpty() || ZoneId.of(stepZone).id == stepZone)
    }

    fun json() = JSONObject().put("scope", scope.name).put("token", token).put("cursor", snapshotCursor)
        .put("from", snapshotFrom).put("until", snapshotUntil).put("day", stepDate).put("zone", stepZone)
        .put("attempt", lastAttempt).put("success", lastSuccess).put("latest", latestMeasurement)
        .put("pending_inserts", pendingInserts).put("pending_deletes", pendingDeletes)
        .put("last_inserts", lastInserts).put("last_deletes", lastDeletes).put("gap", historyGap).put("outcome", outcome.name)

    companion object {
        fun from(json: JSONObject) = HealthSyncCheckpoint(HealthConnectScope.valueOf(json.getString("scope")),
            json.getString("token"), json.getString("cursor"), json.getLong("from"), json.getLong("until"),
            json.getString("day"), json.getString("zone"), json.getLong("attempt"), json.getLong("success"), json.getLong("latest"),
            json.getInt("pending_inserts"), json.getInt("pending_deletes"), json.getInt("last_inserts"), json.getInt("last_deletes"),
            json.getBoolean("gap"), HealthSyncOutcome.valueOf(json.getString("outcome")))
    }
}

internal data class HealthSyncSnapshotPage(val rows: Sequence<HealthConnectMeasurement>, val next: String)
internal data class HealthSyncChangePage(val rows: Sequence<HealthConnectMeasurement>, val next: String,
    val hasMore: Boolean, val expired: Boolean = false, val deletions: Int = 0)

internal interface HealthSyncGateway {
    suspend fun granted(): Set<String>
    suspend fun token(scope: HealthConnectScope): String
    suspend fun snapshot(scope: HealthConnectScope, from: Instant, until: Instant, cursor: String): HealthSyncSnapshotPage
    suspend fun changes(scope: HealthConnectScope, token: String, until: Instant): HealthSyncChangePage
    suspend fun stepDay(day: LocalDate, zone: ZoneId): HealthConnectMeasurement?
}

internal object HealthSyncEngine {
    private val oneRun = Mutex()
    const val DAY = 86_400_000L
    private const val HISTORY_DAYS = 29L
    private const val CHUNK = 120
    private class ProviderFailure(val outcome: HealthSyncOutcome) : Exception()

    suspend fun run(
        store: HealthRecordStore, selected: Set<HealthConnectScope>, availability: HealthPlatformAvailability,
        reader: HealthSyncGateway?, now: () -> Long, zone: ZoneId, progress: (HealthSyncCheckpoint) -> Unit = {},
    ): Boolean {
        require(selected.isNotEmpty())
        if (!oneRun.tryLock()) return false
        try {
            for (scope in HealthConnectScope.entries.filter { it in selected }) {
                currentCoroutineContext().ensureActive()
                var state = store.healthSyncCheckpoint(scope).copy(lastAttempt = now(), outcome = HealthSyncOutcome.RUNNING)
                store.saveHealthSyncCheckpoint(state)
                progress(state)
                try {
                    if (availability != HealthPlatformAvailability.AVAILABLE || reader == null)
                        throw ProviderFailure(if (availability == HealthPlatformAvailability.CHECK_FAILED) HealthSyncOutcome.TRANSPORT else HealthSyncOutcome.UNAVAILABLE)
                    state = syncScope(scope, store, reader, state, now, zone)
                    state = state.copy(lastSuccess = now(), lastInserts = state.pendingInserts, lastDeletes = state.pendingDeletes,
                        pendingInserts = 0, pendingDeletes = 0,
                        outcome = if (state.pendingInserts == 0) HealthSyncOutcome.NO_NEW else HealthSyncOutcome.UPDATED)
                } catch (failure: ProviderFailure) {
                    state = store.healthSyncCheckpoint(scope).copy(outcome = failure.outcome)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: android.database.sqlite.SQLiteException) {
                    state = store.healthSyncCheckpoint(scope).copy(outcome = HealthSyncOutcome.STORAGE)
                } catch (_: Exception) {
                    state = store.healthSyncCheckpoint(scope).copy(outcome = HealthSyncOutcome.FAILED)
                }
                store.saveHealthSyncCheckpoint(state)
                progress(state)
            }
            return true
        } finally {
            oneRun.unlock()
        }
    }

    private suspend fun syncScope(
        scope: HealthConnectScope, store: HealthRecordStore, reader: HealthSyncGateway, initial: HealthSyncCheckpoint,
        now: () -> Long, zone: ZoneId,
    ): HealthSyncCheckpoint {
        var mark = initial
        suspend fun granted() {
            if (scope.permission !in provider { reader.granted() }) throw ProviderFailure(HealthSyncOutcome.PERMISSION)
        }
        fun persist(next: HealthSyncCheckpoint) {
            store.saveHealthSyncCheckpoint(next)
            mark = next
        }
        suspend fun apply(rows: Sequence<HealthConnectMeasurement>, after: (HealthSyncCheckpoint) -> HealthSyncCheckpoint) {
            val job = currentCoroutineContext()
            val chunks = rows.chunked(CHUNK).iterator()
            while (chunks.hasNext()) {
                job.ensureActive()
                val chunk = chunks.next()
                val clock = now()
                require(chunk.all { it.draft.metric == scope.metric && HealthObservationPolicy.validate(it.draft, clock) == null })
                granted()
                mark = store.saveHealthSyncChunk(mark, chunk) { job.ensureActive() }
            }
            granted()
            job.ensureActive()
            persist(after(mark))
        }
        granted()
        if (scope == HealthConnectScope.STEPS) {
            val stableZone = mark.stepZone.takeIf(String::isNotEmpty)?.let(ZoneId::of) ?: zone
            val today = Instant.ofEpochMilli(now()).atZone(stableZone).toLocalDate()
            val latest = today.minusDays(1)
            val earliest = today.minusDays(HISTORY_DAYS)
            val previous = mark.stepDate.takeIf(String::isNotEmpty)?.let(LocalDate::parse)
            var day = previous?.plusDays(1)?.let { minOf(it, today.minusDays(2)) } ?: latest
            if (day < earliest) { day = earliest; persist(mark.copy(historyGap = true, stepZone = stableZone.id)) }
            while (day <= latest) {
                granted()
                val data = provider { reader.stepDay(day, stableZone) }
                val completed = day
                apply(sequenceOfNotNull(data)) { it.copy(stepDate = maxOf(previous ?: completed, completed).toString(), stepZone = stableZone.id) }
                day = day.plusDays(1)
            }
            return mark
        }
        suspend fun bootstrap(recover: Boolean = false) {
            granted()
            val token = provider { reader.token(scope) }
            require(token.isNotBlank())
            val until = now()
            val earliest = until - HISTORY_DAYS * DAY
            val intended = when {
                mark.lastSuccess > 0L -> mark.lastSuccess - DAY
                mark.snapshotFrom > 0L -> mark.snapshotFrom
                recover -> earliest
                else -> until - DAY
            }
            val from = minOf(until - 1, maxOf(1L, intended, earliest))
            persist(mark.copy(token = token, snapshotFrom = from, snapshotUntil = until, snapshotCursor = "",
                historyGap = mark.historyGap || intended < earliest || (recover && mark.lastSuccess == 0L && mark.snapshotFrom == 0L)))
        }
        if (mark.token.isEmpty()) bootstrap()
        else if (mark.snapshotFrom in 1L until (now() - HISTORY_DAYS * DAY)) bootstrap(recover = true)
        var expired = false
        var resetSnapshotCursor = false
        val snapshotPages = linkedSetOf<String>()
        val changePages = linkedSetOf<String>()
        while (true) {
            granted()
            if (mark.snapshotUntil != 0L) {
                val page = try {
                    provider { reader.snapshot(scope, Instant.ofEpochMilli(mark.snapshotFrom),
                        Instant.ofEpochMilli(mark.snapshotUntil), mark.snapshotCursor) }
                } catch (invalid: IllegalArgumentException) {
                    if (resetSnapshotCursor || mark.snapshotCursor.isEmpty()) throw invalid
                    resetSnapshotCursor = true
                    snapshotPages.clear()
                    persist(mark.copy(snapshotCursor = ""))
                    continue
                }
                if (page.next.isNotEmpty()) checkNext(page.next, mark.snapshotCursor, snapshotPages)
                apply(page.rows) {
                    if (page.next.isEmpty()) it.copy(snapshotFrom = 0, snapshotUntil = 0, snapshotCursor = "")
                    else it.copy(snapshotCursor = page.next)
                }
                continue
            }
            val page = provider { reader.changes(scope, mark.token, Instant.ofEpochMilli(now())) }
            if (page.expired) {
                if (expired) throw ProviderFailure(HealthSyncOutcome.TRANSPORT)
                expired = true
                bootstrap(recover = true)
                snapshotPages.clear()
                changePages.clear()
                continue
            }
            check(page.next.isNotBlank() && page.next.length <= 32768)
            if (page.hasMore) checkNext(page.next, mark.token, changePages)
            apply(page.rows) { it.copy(token = page.next, pendingDeletes = Math.addExact(it.pendingDeletes, page.deletions)) }
            if (!page.hasMore) return mark
        }
    }

    private fun <T : Any> sequenceOfNotNull(value: T?): Sequence<T> = if (value == null) emptySequence() else sequenceOf(value)

    private fun checkNext(next: String, current: String, recent: LinkedHashSet<String>) {
        check(next.length <= 32768 && next != current && recent.add(next)) { "Invalid Health Connect continuation" }
        if (recent.size > 32) recent.remove(recent.first())
    }

    private suspend fun <T> provider(work: suspend () -> T): T = try {
        withTimeout(15_000) { work() }
    } catch (_: TimeoutCancellationException) {
        throw ProviderFailure(HealthSyncOutcome.TIMEOUT)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: SecurityException) {
        throw ProviderFailure(HealthSyncOutcome.PERMISSION)
    } catch (_: UnknownHostException) {
        throw ProviderFailure(HealthSyncOutcome.NETWORK)
    } catch (_: SocketTimeoutException) {
        throw ProviderFailure(HealthSyncOutcome.NETWORK)
    } catch (_: SocketException) {
        throw ProviderFailure(HealthSyncOutcome.NETWORK)
    } catch (_: RemoteException) {
        throw ProviderFailure(HealthSyncOutcome.TRANSPORT)
    } catch (_: IOException) {
        throw ProviderFailure(HealthSyncOutcome.TRANSPORT)
    }
}
