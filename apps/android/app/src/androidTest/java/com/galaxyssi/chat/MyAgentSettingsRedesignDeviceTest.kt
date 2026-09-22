package com.galaxyssi.chat

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MyAgentSettingsRedesignDeviceTest {
    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    @Test fun advancedSectionKeepsExpansionAcrossRefresh() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val renderer = ControlCenterRenderer(context)
            val content = LinearLayout(context)
            val page = ControlCenterPageSpec(sections = listOf(ControlCenterSectionSpec(
                "Advanced", listOf(ControlCenterRowSpec("test", "Model", "", R.drawable.ic_local_model)), true)))
            renderer.render(content, page) {}
            assertEquals(View.GONE, content.getChildAt(1).visibility)
            content.getChildAt(0).performClick()
            assertEquals(View.VISIBLE, content.getChildAt(1).visibility)
            renderer.render(content, page) {}
            assertEquals(View.VISIBLE, content.getChildAt(1).visibility)
            content.getChildAt(0).performClick()
            renderer.render(content, page) {}
            assertEquals(View.GONE, content.getChildAt(1).visibility)
        }
    }

    @Test fun hubsKeepBackNavigationAndDoNotMutateResourcePreferences() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val stores = listOf("galaxyssi_voice_assistant", "galaxyssi_whisper_models_v2",
            "galaxyssi_qnn_large_turbo_download_v1", "galaxyssi_local_model_downloads_v1",
            "galaxyssi_agent_model_selection_v2", "galaxyssi_embedded_runtime_bootstrap_v1")
        fun snapshot() = stores.associateWith { context.getSharedPreferences(it, Context.MODE_PRIVATE).all.toMap() }
        val before = snapshot()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.showMainTab(PAGE_SETTINGS)
                val routes = ControlCenterHomeGrouping.orderedGroups.flatMap(ControlCenterHomeGrouping::routes) +
                    listOf(ControlCenterRoute.OBSIDIAN_HUB, ControlCenterRoute.STORAGE_HUB,
                        ControlCenterRoute.NOTIFICATIONS_HUB, ControlCenterRoute.DIAGNOSTICS_HUB,
                        ControlCenterRoute.GLOBAL_AGENT, ControlCenterRoute.DATA_BACKUP,
                        ControlCenterRoute.EXECUTION_POLICY, ControlCenterRoute.MEMORY,
                        ControlCenterRoute.ON_DEVICE_RUNTIME)
                routes.forEach { route ->
                    activity.openControlCenterDestination(ControlCenterDestination(route))
                    assertEquals(route, activity.controlCenterDestination?.route)
                    assertEquals(View.VISIBLE, activity.featurePage.visibility)
                    assertEquals(View.VISIBLE, activity.featureBackButton.visibility)
                    assertTrue(activity.featureContent.childCount > 0)
                    activity.featureBackButton.performClick()
                    assertNull("Back must return home for $route", activity.controlCenterDestination)
                    assertEquals(View.GONE, activity.featurePage.visibility)
                }
            }
        }
        assertEquals(before, snapshot())
    }

    @Test fun asrResourcesStayAccessibleBeforeFoldedAdvancedSettings() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.showMainTab(PAGE_SETTINGS)
                activity.openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.VOICE))
                activity.handleControlCenterAction("voice.asr")
                val headers = (0 until activity.featureContent.childCount)
                    .map(activity.featureContent::getChildAt).filterIsInstance<TextView>()
                    .filter { it.tag?.toString()?.startsWith("my-agent-section:") == true }
                assertEquals(listOf(R.string.voice_asr_recognition_mode_section,
                    R.string.voice_asr_qnn_section, R.string.voice_asr_model_section).map(activity::getString),
                    headers.take(3).map { it.text.toString() })
                assertTrue(descendants(activity.featureContent).filterIsInstance<TextView>()
                    .any { it.text.toString().contains("Tiny", ignoreCase = true) })
                activity.featureBackButton.performClick()
                assertEquals(ControlCenterRoute.VOICE, activity.controlCenterDestination?.route)
            }
        }
    }

    @Test fun localModelDownloadsImportsAndDiagnosticsRemainAccessible() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.showMainTab(PAGE_SETTINGS)
                activity.openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.MODEL_HUB))
                activity.handleControlCenterAction("local_model.open")
                val labels = descendants(activity.featureContent).filterIsInstance<TextView>().map { it.text.toString() }
                listOf(R.string.local_model_qnn_section, R.string.local_model_search_title,
                    R.string.local_model_qnn_import_title, R.string.local_model_context_window,
                    R.string.local_model_preflight_section).forEach {
                    assertTrue("Missing model control: $it", activity.getString(it) in labels)
                }
                assertTrue(activity.localModelRowBindings.isNotEmpty())
                activity.featureBackButton.performClick()
                assertEquals(ControlCenterRoute.MODEL_HUB, activity.controlCenterDestination?.route)
            }
        }
    }
}
