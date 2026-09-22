package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ControlCenterCloudEntryDeviceTest {
    @Test fun modelActionsAppearBeforeInstalledTargetsWithoutRoutingSection() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.showMainTab(PAGE_SETTINGS)
                activity.openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.MODEL_HUB))
                val texts = descendants(activity.featureContent).filterIsInstance<TextView>()
                    .map { it.text.toString() }
                val add = texts.indexOf(activity.getString(R.string.cc_add_cloud_provider_title))
                val scan = texts.indexOf(activity.getString(R.string.conversation_hub_scan_add))
                val installed = texts.indexOf(activity.getString(R.string.my_agent_installed))
                assertTrue(add >= 0 && scan > add && installed > scan)
                assertFalse(texts.contains(activity.getString(R.string.my_agent_strategy)))
                assertFalse(texts.contains(activity.getString(R.string.my_agent_routing)))
                assertTrue(texts.contains(activity.getString(R.string.my_agent_downloaded_models)))
                activity.mobileNativeAgent.agentRegistrySnapshot()
                    .filter { it.displayName.contains("Codex", ignoreCase = true) }
                    .forEach {
                        android.util.Log.i("ModelEntryVerification", "Codex status=${it.status}" +
                            " activeRuns=${it.activeRuns} capacity=${it.maxParallelRuns}" +
                            " heartbeatAgeMs=${System.currentTimeMillis() - it.lastHeartbeatMillis}")
                        AppStore.contactById(activity, it.agentId)?.let { contact ->
                            android.util.Log.i("ModelEntryVerification",
                                "Codex reportedStatus=${contact.optString("setup_status")}" +
                                    " reportedRuns=${contact.optInt("active_runs")}" +
                                    " reportAgeMs=${System.currentTimeMillis() - contact.optLong("setup_updated_at")}")
                        }
                    }
            }
        }
    }

    @Test fun cloudTargetsUseProviderLogosWithoutStatusTinting() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val icons = mapOf("deepseek" to R.drawable.logo_provider_deepseek,
                    "openai" to R.drawable.logo_provider_openai,
                    "anthropic" to R.drawable.logo_provider_anthropic,
                    "gemini" to R.drawable.logo_provider_gemini)
                icons.forEach { (provider, icon) ->
                    val target = AgentCallableTarget(id = "cloud:$provider", title = "Renamed provider",
                        kind = AgentConnectorKind.MODEL, status = AgentConnectorStatus.AVAILABLE,
                        capabilities = listOf(AgentCapability.CHAT))
                    val row = activity.controlCenterTargetRow(target)
                    assertEquals(icon, row.iconRes)
                    assertTrue(row.preserveIconColor)
                }
            }
        }
    }

    @Test fun configuredDeepSeekOpensDetailsWithSendAndSeparateConfiguration() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val contact = AppStore.contactById(activity, "cloud:deepseek")
                assumeNotNull(contact)
                val before = fingerprint(contact.toString())
                activity.showMainTab(PAGE_SETTINGS)
                activity.openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.MODEL_HUB))
                activity.handleControlCenterAction("routing.target:cloud:deepseek")
                assertEquals(activity.getString(R.string.contact_detail_title), activity.featureTitle.text.toString())
                val views = descendants(activity.featureContent).filterIsInstance<TextView>()
                assertTrue(views.any { it.text == activity.getString(R.string.contact_send_message) && it.isClickable })
                assertTrue(views.any { it.text == activity.getString(R.string.cloud_config_title) })
                assertFalse(views.any { it.text == activity.getString(R.string.cloud_section_key) })
                assertEquals(before, fingerprint(AppStore.contactById(activity, "cloud:deepseek").toString()))
                activity.featureBackButton.performClick()
                assertEquals(ControlCenterRoute.MODEL_HUB, activity.controlCenterDestination?.route)
            }
        }
    }

    private fun fingerprint(value: String): String = java.security.MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
