package com.signalasi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentEvalBenchmarkDeviceAcceptanceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun requireSmT575() {
        assertEquals("SM-T575", Build.MODEL.replace('_', '-').uppercase())
    }

    @Test
    fun fixedSuiteAndLocalizedEntryAreAvailableOnTargetDevice() {
        val suite = AgentEvalBenchmarkCatalog.standard

        assertEquals(60, suite.cases.size)
        assertEquals(10, suite.cases.count { it.dimension == AgentBenchmarkDimension.LONG_TERM_MEMORY })
        assertTrue(context.getString(R.string.cc_agent_benchmark_title).isNotBlank())
        assertTrue(context.getString(R.string.cc_agent_benchmark_subtitle, 60, 3).contains("60"))
    }

    @Test
    fun androidWorldCompatibleFixturesInstallWithProgrammaticVerifiers() {
        AgentAndroidWorldBenchmarkFixtures.install(context)
        val tasks = AgentAndroidWorldStore(context).tasks(200)
            .filter { it.sourceVersion == AgentEvalBenchmarkCatalog.standard.version }

        assertEquals(10, tasks.size)
        tasks.forEach { task ->
            assertTrue(task.verifiers.isNotEmpty())
            assertTrue(task.requiredPackages.contains(context.packageName))
            assertNotNull(AgentEvalBenchmarkCatalog.standard.case(task.id))
        }
    }

    @Test
    fun repeatedTrialPolicyIsThreeToTenOnDevice() {
        assertEquals(3, AgentEvalOpsSettings(repeatedTrials = 2).normalized().repeatedTrials)
        assertEquals(10, AgentEvalOpsSettings(repeatedTrials = 99).normalized().repeatedTrials)
    }
}
