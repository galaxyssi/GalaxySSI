package com.galaxyssi.chat

import android.content.Context
import android.os.Bundle
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationOrganizationRuntimeDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    @Test fun encryptedCheckpointRestoresAllocationWithoutRepeatingCompletedWork(): Unit = runBlocking {
        withTimeout(60_000) {
            val db = AgentEncryptedDatabase(context, "organization-local-${UUID.randomUUID()}")
            val fixture = OrganizationRuntimeFixture()
            try {
                fixture.validate(fixture.seed(EncryptedAgentTeamExecutionStore(db)))
                fixture.recover(EncryptedAgentTeamExecutionStore(db))
                val archives = db.keys("goal-cycle:${fixture.run}:").map { key ->
                    JSONArray(db.readString(key, "")).getJSONObject(0)
                }
                assertEquals(3, archives.size)
                assertTrue(archives.all { !it.getJSONObject("request").getJSONObject("context")
                    .has(CollaborationTeamOrganizationProjection.COMPLETIONS) })
                val outputs = archives.flatMap { archive -> archive.getJSONArray("events").let { events ->
                    (0 until events.length()).mapNotNull { events.getJSONObject(it).optJSONObject("result")?.optString("output") }
                } }
                assertEquals(3, outputs.count { it.startsWith("Fixture result ") })
            } finally { db.clear() }
        }
    }

    @Test fun separateProcessRestoresOrganizationHistoryAndStandbyMembers(): Unit = runBlocking {
        val phase = InstrumentationRegistry.getArguments().getString("organizationPhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val db = AgentEncryptedDatabase(context, "organization-process-fixture")
        val prefs = context.getSharedPreferences("organization-process-fixture", Context.MODE_PRIVATE)
        val store = EncryptedAgentTeamExecutionStore(db)
        val fixture = OrganizationRuntimeFixture()
        withTimeout(60_000) {
            if (phase == "seed") {
                require(store.snapshot(fixture.run) == null) { "Recover the previous fixture first" }
                fixture.validate(fixture.seed(store))
                check(prefs.edit().putInt("seed_pid", android.os.Process.myPid()).commit())
            } else {
                try {
                    assertNotEquals(prefs.getInt("seed_pid", -1), android.os.Process.myPid())
                    fixture.recover(store)
                } finally { db.clear(); prefs.edit().clear().commit() }
            }
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("organization_phase", phase); putInt("process_id", android.os.Process.myPid())
            })
        }
    }
}
