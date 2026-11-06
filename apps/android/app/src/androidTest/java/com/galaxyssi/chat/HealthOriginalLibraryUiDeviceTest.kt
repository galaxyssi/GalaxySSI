package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOriginalLibraryUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun fixture(test: (ActivityScenario<HealthOriginalLibraryActivity>) -> Unit) {
        val context = instrumentation.targetContext
        assumeFalse("Visible library acceptance needs an unlocked device", context.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthOriginalLibraryActivity>(Intent(context, HealthOriginalLibraryActivity::class.java)
                .putHealthNavigationFixture(names)).use(test)
        } finally { clearHealthOverviewFixture(context, names) }
    }
    @Test fun libraryHasNativeFiltersSelectionAndNoBottomTabs() = fixture { scenario ->
        await(scenario); scenario.onActivity { activity ->
            assertNotNull(views(activity.window.decorView).firstOrNull { it.tag == "health-library-mode" })
            assertEquals(2, (activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).childCount)
        }
    }
    @Test fun viewModeSurvivesRecreationAndBackgroundDropsImageReferences() = fixture { scenario ->
        await(scenario); scenario.onActivity { activity -> views(activity.window.decorView).single { it.tag == "health-library-mode" }.performClick() }; await(scenario)
        scenario.recreate(); await(scenario)
        lateinit var held: HealthOriginalLibraryActivity
        scenario.onActivity { activity -> held = activity; assertEquals(activity.getString(R.string.health_library_grid), views(activity.window.decorView).single { it.tag == "health-library-mode" }.contentDescription.toString()) }
        scenario.moveToState(Lifecycle.State.CREATED)
        val images = HealthOriginalLibraryActivity::class.java.getDeclaredField("images").apply { isAccessible = true }.get(held) as Collection<*>
        assertTrue(images.isEmpty()); scenario.moveToState(Lifecycle.State.RESUMED); await(scenario)
    }
    private fun await(scenario: ActivityScenario<HealthOriginalLibraryActivity>) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do { var ready = false; scenario.onActivity { ready = views(it.window.decorView).any { view -> view.tag == "health-library-mode" } }; if (ready) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < until)
        fail("Library did not finish its native load")
    }
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
}
