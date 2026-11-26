package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentModelPickerDeviceTest {
    @Test fun selectingAnInlineModelAndEffortKeepsBrandAndDoesNotChangeOtherChats() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val prefix = "picker-fixture-${UUID.randomUUID()}"
                val isolated = object : ContextWrapper(activity) {
                    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                        super.getSharedPreferences("$prefix-$name", mode)
                }
                val codex = AgentCallableTarget(
                    "fixture-desktop:codex", "Codex Agent \u00b7 Desktop-T14",
                    AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE,
                    listOf(AgentCapability.CHAT, AgentCapability.REASONING),
                    invocationProfile = AgentInvocationProfile(
                        defaultModelId = "gpt-5.6-sol",
                        models = listOf("gpt-6.2-astra", "gpt-6.2-sol", "gpt-6-astra", "gpt-5.6-sol")
                            .map { AgentModelOption(it) },
                        reasoningEfforts = listOf(AgentModelReasoningEffort.LOW, AgentModelReasoningEffort.MEDIUM,
                            AgentModelReasoningEffort.HIGH, AgentModelReasoningEffort.XHIGH)
                    )
                )
                val conversation = "$prefix-current"
                val other = "$prefix-other"
                val saved = AgentModelSelectionSettings
                saved.selectManual(isolated, other, codex.id, "gpt-6-astra", codex.title, AgentModelReasoningEffort.HIGH)
                saved.selectManual(isolated, conversation, codex.id, "gpt-6-astra", codex.title, AgentModelReasoningEffort.HIGH)
                activity.showFeaturePage(activity.getString(R.string.agent_model_selection_title))
                val content = activity.featureContent
                val footer = activity.findViewById<LinearLayout>(R.id.featurePinnedFooter)
                val page = AgentModelPickerPage(activity, activity.navigationContentGate.begin(), isolated)
                content.tag = page
                page.bind(AgentModelPickerSnapshot(conversation, listOf(codex), emptyList()))

                val provider = content.findViewWithTag<ViewGroup>("agent-model-provider:${codex.id}")
                val logo = provider.getChildAt(0) as ImageView
                assertNotNull(logo.drawable)
                assertNull(logo.imageTintList)
                assertEquals(R.drawable.logo_codex_product, activity.controlCenterTargetIcon(codex))
                assertTrue(content.findViewWithTag<View>("agent-model-option:${codex.id}:gpt-6-astra").isSelected)
                assertNull(content.findViewWithTag<View>("agent-model-option:${codex.id}:gpt-5.6-sol"))
                assertTrue(content.findViewWithTag<View>("agent-model-older").performClick())
                assertNotNull(content.findViewWithTag<View>("agent-model-option:${codex.id}:gpt-5.6-sol"))

                assertTrue(content.findViewWithTag<View>("agent-model-option:${codex.id}:gpt-6.2-sol").performClick())
                assertEquals("gpt-6.2-sol", saved.selection(isolated, conversation).modelId)
                assertTrue(footer.findViewWithTag<View>("agent-model-effort:high").isSelected)
                assertTrue(footer.findViewWithTag<View>("agent-model-effort:xhigh").performClick())
                assertEquals(AgentModelReasoningEffort.XHIGH, saved.defaultSelection(isolated).reasoningEffort)
                assertEquals("gpt-6-astra", saved.selection(isolated, other).modelId)

                assertTrue(content.findViewWithTag<View>("agent-model-source:CLOUD").performClick())
                assertEquals("gpt-6.2-sol", saved.selection(isolated, conversation).modelId)
                assertTrue(content.findViewWithTag<View>("agent-model-auto").performClick())
                assertEquals(AgentModelSelectionMode.AUTO, saved.defaultSelection(isolated).mode)
                assertNull(footer.findViewWithTag<View>("agent-model-effort:xhigh"))
                activity.hideFeaturePage()
                assertEquals(View.GONE, footer.visibility)
                assertFalse(footer.childCount > 0)
            }
        }
    }
}
