package com.signalasi.chat

import android.app.AlertDialog
import android.text.InputType
import android.widget.EditText
import android.widget.Toast
import java.util.Locale

internal fun MainActivity.showAgentEvolutionLabPage() {
    val evalStore = AgentEvalOpsStore(this)
    val settings = evalStore.settings()
    val dashboard = evalStore.dashboard()
    val runtime = AgentEvolutionLabRuntimeRegistry.get(this)
    val runtimeSnapshot = runtime.snapshot()
    val campaigns = AgentLabStore(this).list(12)
    val failures = AgentFailureMemoryStore(this).list(activeOnly = true)
    val governance = AgentCognitiveGovernanceStore(this)
    val gaps = governance.gaps(AgentKnowledgeGapStatus.OPEN)
    val decisions = governance.decisions()
    val attention = AgentAttentionDecisionStore(this).list(200)
    val androidWorld = AgentAndroidWorldStore(this)
    val worldTasks = androidWorld.tasks()
    val worldResults = androidWorld.results()
    val releases = AgentShadowReleaseStore(this).list()
    val protocolRows = AgentProtocolAdapterRegistry.descriptors(this).map { descriptor ->
        ControlCenterRowSpec(
            actionId = "lab.protocol:${descriptor.protocol.wireValue}",
            title = descriptor.protocol.wireValue.uppercase(Locale.ROOT),
            subtitle = getString(
                R.string.cc_agent_lab_protocol_subtitle,
                descriptor.version,
                descriptor.operations.size
            ),
            iconRes = R.drawable.ic_protocol_link,
            status = descriptor.connectedEndpoints.toString(),
            tone = if (descriptor.state == AgentProtocolAdapterState.DISABLED) {
                ControlCenterTone.NEUTRAL
            } else {
                ControlCenterTone.BLUE
            },
            showChevron = false
        )
    }
    val campaignRows = campaigns.map { campaign ->
        val completed = campaign.trials.count { it.status in setOf(
            AgentLabTrialStatus.COMPLETED,
            AgentLabTrialStatus.FAILED,
            AgentLabTrialStatus.CANCELLED
        ) }
        ControlCenterRowSpec(
            actionId = "lab.campaign:${campaign.id}",
            title = campaign.task.replace(Regex("\\s+"), " ").take(80),
            subtitle = getString(R.string.cc_agent_lab_campaign_progress, completed, campaign.trials.size),
            iconRes = R.drawable.ic_process_analysis,
            status = campaign.status.name.lowercase(Locale.ROOT).replace('_', ' '),
            tone = when (campaign.status) {
                AgentLabCampaignStatus.RUNNING -> ControlCenterTone.GREEN
                AgentLabCampaignStatus.READY_FOR_REVIEW -> ControlCenterTone.BLUE
                AgentLabCampaignStatus.CANCELLED -> ControlCenterTone.NEUTRAL
                else -> ControlCenterTone.VIOLET
            }
        )
    }.ifEmpty {
        listOf(ControlCenterRowSpec(
            actionId = "lab.create",
            title = getString(R.string.cc_agent_lab_no_campaigns),
            subtitle = getString(R.string.cc_agent_lab_no_campaigns_subtitle),
            iconRes = R.drawable.ic_process_analysis,
            tone = ControlCenterTone.NEUTRAL
        ))
    }
    showControlCenterFeature(
        getString(R.string.cc_agent_lab_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_agent_lab_banner_title),
                subtitle = getString(R.string.cc_agent_lab_banner_subtitle),
                iconRes = R.drawable.ic_settings_diagnostics,
                tone = ControlCenterTone.BLUE,
                actionId = "lab.refresh"
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_lab_section_eval),
                    listOf(
                        ControlCenterRowSpec(
                            "lab.create",
                            getString(R.string.cc_agent_lab_new_experiment),
                            getString(R.string.cc_agent_lab_available_agents, runtimeSnapshot.availableAgents.size),
                            R.drawable.ic_agent_node,
                            getString(R.string.cc_agent_lab_add),
                            ControlCenterTone.GREEN
                        ),
                        ControlCenterRowSpec(
                            "lab.results",
                            getString(R.string.cc_agent_lab_verified_runs),
                            getString(R.string.cc_agent_lab_runs_subtitle, dashboard.totalRuns),
                            R.drawable.ic_process_analysis,
                            dashboard.verifiedRuns.toString(),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "lab.results",
                            getString(R.string.cc_agent_lab_pass_metrics),
                            getString(R.string.cc_agent_lab_pass_metrics_subtitle),
                            R.drawable.ic_settings_diagnostics,
                            String.format(Locale.US, "%.1f%% / %.1f%%", dashboard.passAt1 * 100.0, dashboard.passPowerK * 100.0),
                            ControlCenterTone.GREEN
                        ),
                        ControlCenterRowSpec(
                            "lab.results",
                            getString(R.string.cc_agent_lab_recovery_rate),
                            getString(R.string.cc_agent_lab_recovery_subtitle),
                            R.drawable.ic_reset_data,
                            String.format(Locale.US, "%.1f%%", dashboard.recoveryRate * 100.0),
                            ControlCenterTone.AMBER
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_lab_section_controls),
                    listOf(
                        evalToggleRow("lab.toggle_capture", R.string.cc_agent_lab_capture, settings.captureRealRuns),
                        evalToggleRow("lab.toggle_continuous", R.string.cc_agent_lab_continuous, settings.continuousEvaluationEnabled),
                        evalToggleRow("lab.toggle_shadow_routing", R.string.cc_agent_lab_shadow_routing, settings.shadowRoutingEnabled),
                        evalToggleRow("lab.toggle_auto_routing", R.string.cc_agent_lab_auto_routing, settings.automaticQualityRoutingEnabled),
                        evalToggleRow("lab.toggle_skill_md", R.string.cc_agent_lab_skill_md, settings.skillMarkdownCompatibilityEnabled),
                        evalToggleRow("lab.toggle_protocols", R.string.cc_agent_lab_protocols, settings.protocolAdaptersEnabled),
                        evalToggleRow("lab.toggle_shadow_release", R.string.cc_agent_lab_shadow_release, settings.shadowReleaseEnabled),
                        ControlCenterRowSpec(
                            "lab.repetitions",
                            getString(R.string.cc_agent_lab_repetitions),
                            getString(R.string.cc_agent_lab_repetitions_subtitle),
                            R.drawable.ic_process_analysis,
                            settings.repeatedTrials.toString(),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "lab.attention_threshold",
                            getString(R.string.cc_agent_lab_attention_threshold),
                            getString(R.string.cc_agent_lab_attention_threshold_subtitle),
                            R.drawable.ic_settings_diagnostics,
                            String.format(Locale.US, "%.2f", settings.attentionThreshold),
                            ControlCenterTone.AMBER
                        )
                    )
                ),
                ControlCenterSectionSpec(getString(R.string.cc_agent_lab_section_campaigns), campaignRows),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_lab_section_learning),
                    listOf(
                        ControlCenterRowSpec("memory.manage", getString(R.string.agent_memory_title), getString(R.string.cc_agent_lab_memory_trust_subtitle), R.drawable.ic_agent_node, "", ControlCenterTone.BLUE),
                        ControlCenterRowSpec("lab.failures", getString(R.string.cc_agent_lab_failure_memory), getString(R.string.cc_agent_lab_failure_memory_subtitle), R.drawable.ic_reset_data, failures.size.toString(), ControlCenterTone.AMBER),
                        ControlCenterRowSpec("lab.gaps", getString(R.string.cc_agent_lab_knowledge_gaps), getString(R.string.cc_agent_lab_knowledge_gaps_subtitle, decisions.size), R.drawable.ic_process_analysis, gaps.size.toString(), ControlCenterTone.VIOLET),
                        ControlCenterRowSpec("lab.attention", getString(R.string.cc_agent_lab_attention_history), getString(R.string.cc_agent_lab_attention_history_subtitle), R.drawable.ic_settings_diagnostics, attention.size.toString(), ControlCenterTone.GREEN)
                    )
                ),
                ControlCenterSectionSpec(getString(R.string.cc_agent_lab_section_protocols), protocolRows),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_lab_section_android_world),
                    listOf(
                        ControlCenterRowSpec("lab.android_world.import", getString(R.string.cc_agent_lab_android_world_import), getString(R.string.cc_agent_lab_android_world_import_subtitle), R.drawable.ic_process_analysis, worldTasks.size.toString(), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("lab.android_world.results", getString(R.string.cc_agent_lab_android_world_results), getString(R.string.cc_agent_lab_android_world_results_subtitle), R.drawable.ic_settings_diagnostics, worldResults.size.toString(), ControlCenterTone.GREEN)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_lab_section_shadow_release),
                    listOf(ControlCenterRowSpec(
                        "lab.releases",
                        getString(R.string.cc_agent_lab_shadow_releases),
                        getString(R.string.cc_agent_lab_shadow_releases_subtitle),
                        R.drawable.ic_reset_data,
                        releases.size.toString(),
                        ControlCenterTone.AMBER
                    ))
                )
            ),
            footer = getString(R.string.cc_agent_lab_footer)
        )
    )
}

private fun MainActivity.evalToggleRow(action: String, title: Int, enabled: Boolean) = ControlCenterRowSpec(
    actionId = action,
    title = getString(title),
    subtitle = getString(R.string.cc_agent_lab_toggle_subtitle),
    iconRes = R.drawable.ic_settings_diagnostics,
    status = "",
    tone = if (enabled) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL,
    switchValue = enabled,
    showChevron = false
)

internal fun MainActivity.handleAgentEvolutionLabAction(actionId: String): Boolean {
    val store = AgentEvalOpsStore(this)
    val toggle: ((AgentEvalOpsSettings) -> AgentEvalOpsSettings)? = when (actionId) {
        "lab.toggle_capture" -> { current -> current.copy(captureRealRuns = !current.captureRealRuns) }
        "lab.toggle_continuous" -> { current -> current.copy(continuousEvaluationEnabled = !current.continuousEvaluationEnabled) }
        "lab.toggle_shadow_routing" -> { current -> current.copy(shadowRoutingEnabled = !current.shadowRoutingEnabled) }
        "lab.toggle_auto_routing" -> { current -> current.copy(automaticQualityRoutingEnabled = !current.automaticQualityRoutingEnabled) }
        "lab.toggle_skill_md" -> { current -> current.copy(skillMarkdownCompatibilityEnabled = !current.skillMarkdownCompatibilityEnabled) }
        "lab.toggle_protocols" -> { current -> current.copy(protocolAdaptersEnabled = !current.protocolAdaptersEnabled) }
        "lab.toggle_shadow_release" -> { current -> current.copy(shadowReleaseEnabled = !current.shadowReleaseEnabled) }
        else -> null
    }
    if (toggle != null) {
        store.updateSettings(toggle)
        showAgentEvolutionLabPage()
        return true
    }
    when (actionId) {
        "advanced.agent_lab" -> openExistingControlCenterPage { showAgentEvolutionLabPage() }
        "lab.refresh" -> showAgentEvolutionLabPage()
        "lab.create" -> showAgentLabTaskDialog()
        "lab.results" -> showAgentEvalResultsDialog()
        "lab.repetitions" -> showAgentLabRepetitionsDialog()
        "lab.attention_threshold" -> showAgentAttentionThresholdDialog()
        "lab.failures" -> showAgentFailureMemoriesDialog()
        "lab.gaps" -> showAgentKnowledgeGapsDialog()
        "lab.attention" -> showAgentAttentionHistoryDialog()
        "lab.android_world.import" -> showAndroidWorldImportDialog()
        "lab.android_world.results" -> showAndroidWorldResultsDialog()
        "lab.releases" -> showAgentShadowReleasesDialog()
        else -> when {
            actionId.startsWith("lab.campaign:") -> showAgentLabCampaignDialog(actionId.substringAfter(':'))
            actionId.startsWith("lab.protocol:") -> showProtocolAdapterDialog(actionId.substringAfter(':'))
            else -> return false
        }
    }
    return true
}

private fun MainActivity.showAgentLabTaskDialog() {
    val input = EditText(this).apply {
        hint = getString(R.string.cc_agent_lab_task_hint)
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        minLines = 3
        maxLines = 8
        setPadding(dp(20), dp(12), dp(20), dp(12))
    }
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_agent_lab_new_experiment)
        .setView(input)
        .setPositiveButton(R.string.cc_agent_lab_next) { _, _ ->
            val task = input.text?.toString().orEmpty().trim()
            if (task.isBlank()) {
                Toast.makeText(this, R.string.cc_agent_lab_task_required, Toast.LENGTH_SHORT).show()
            } else showAgentLabAgentPicker(task)
        }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

private fun MainActivity.showAgentLabAgentPicker(task: String) {
    val agents = AgentEvolutionLabRuntimeRegistry.get(this).availableAgents()
    if (agents.size < 2) {
        Toast.makeText(this, R.string.cc_agent_lab_two_agents_required, Toast.LENGTH_LONG).show()
        return
    }
    val selected = BooleanArray(agents.size) { index -> index < 2 }
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_agent_lab_choose_agents)
        .setMultiChoiceItems(agents.map(AgentRegistration::displayName).toTypedArray(), selected) { _, index, checked ->
            selected[index] = checked
        }
        .setPositiveButton(R.string.cc_agent_lab_start) { _, _ ->
            val ids = agents.indices.filter { selected[it] }.map { agents[it].agentId }
            if (ids.size < 2) {
                Toast.makeText(this, R.string.cc_agent_lab_two_agents_required, Toast.LENGTH_LONG).show()
            } else {
                runCatching {
                    AgentEvolutionLabRuntimeRegistry.get(this).createAndStart(
                        task,
                        ids,
                        AgentEvalOpsStore(this).settings().repeatedTrials
                    )
                }.onSuccess {
                    Toast.makeText(this, R.string.cc_agent_lab_started, Toast.LENGTH_SHORT).show()
                    showAgentEvolutionLabPage()
                }.onFailure { error ->
                    Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show()
                }
            }
        }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

private fun MainActivity.showAgentLabCampaignDialog(campaignId: String) {
    val labStore = AgentLabStore(this)
    val campaign = labStore.get(campaignId) ?: return
    val results = labStore.blindResults(campaignId, AgentEvalOpsStore(this), AgentRunRecorder(this))
    if (results.isEmpty()) {
        AlertDialog.Builder(this)
            .setTitle(campaign.task.take(120))
            .setMessage(getString(R.string.cc_agent_lab_campaign_progress, campaign.trials.count { it.status != AgentLabTrialStatus.PENDING }, campaign.trials.size))
            .setPositiveButton(R.string.cc_agent_lab_cancel_campaign) { _, _ ->
                AgentEvolutionLabRuntimeRegistry.get(this).cancel(campaignId)
                showAgentEvolutionLabPage()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
        return
    }
    var selected = results.indexOfFirst { it.trialId == campaign.winnerTrialId }
    val labels = results.map { result ->
        buildString {
            append(result.label).append(" · ").append(result.verdict.wireValue)
            append(" · ").append(result.durationMillis / 1_000L).append('s')
            if (result.outputPreview.isNotBlank()) append("\n").append(result.outputPreview.replace(Regex("\\s+"), " ").take(240))
            if (result.failureReasons.isNotEmpty()) append("\n").append(result.failureReasons.joinToString(", ").take(200))
        }
    }.toTypedArray()
    val builder = AlertDialog.Builder(this)
        .setTitle(R.string.cc_agent_lab_blind_review)
        .setSingleChoiceItems(labels, selected) { _, which -> selected = which }
        .setPositiveButton(R.string.cc_agent_lab_choose_winner) { _, _ ->
            results.getOrNull(selected)?.let { result ->
                labStore.selectWinner(campaignId, result.trialId)
                Toast.makeText(this, R.string.cc_agent_lab_winner_saved, Toast.LENGTH_SHORT).show()
                showAgentEvolutionLabPage()
            }
        }
        .setNegativeButton(android.R.string.cancel, null)
    if (campaign.winnerTrialId.isNotBlank()) {
        builder.setNeutralButton(R.string.cc_agent_lab_save_skill) { _, _ -> saveAgentLabWinnerAsSkill(campaignId) }
    }
    builder.show()
}

private fun MainActivity.saveAgentLabWinnerAsSkill(campaignId: String) {
    val store = AgentLabStore(this)
    val campaign = store.get(campaignId) ?: return
    val recorder = AgentRunRecorder(this)
    val runs = store.winnerRunIds(campaignId).mapNotNull(recorder::run)
    runCatching {
        val manifest = AgentConversationSkillCompiler(agentSkillRuntime) {
            mobileNativeAgent.nativeToolCatalog()
        }.compile(runs, campaign.task.take(100))
        AgentSkillMarkdownInstaller(agentSkillRuntime).installForReview(AgentSkillMarkdownCodec.encode(manifest))
    }.onSuccess {
        Toast.makeText(this, R.string.cc_agent_lab_skill_review_ready, Toast.LENGTH_LONG).show()
    }.onFailure { error ->
        Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show()
    }
}

private fun MainActivity.showAgentEvalResultsDialog() {
    val samples = AgentEvalOpsStore(this).samples(100)
    val message = samples.take(30).joinToString("\n\n") { sample ->
        val conditions = sample.observedConditions
            .ifEmpty { setOf(sample.condition) }
            .joinToString(" + ", transform = AgentEvalCondition::wireValue)
        "${sample.taskClass.wireValue} · ${sample.resourceId}\n${sample.verdict.wireValue} · ${sample.durationMillis / 1_000L}s · $conditions"
    }.ifBlank { getString(R.string.cc_agent_lab_no_results) }
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_verified_runs).setMessage(message)
        .setPositiveButton(android.R.string.ok, null).show()
}

private fun MainActivity.showAgentLabRepetitionsDialog() {
    val values = intArrayOf(2, 3, 5, 10)
    val current = AgentEvalOpsStore(this).settings().repeatedTrials
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_repetitions)
        .setSingleChoiceItems(values.map(Int::toString).toTypedArray(), values.indexOf(current)) { dialog, index ->
            AgentEvalOpsStore(this).updateSettings { it.copy(repeatedTrials = values[index]) }
            dialog.dismiss()
            showAgentEvolutionLabPage()
        }.show()
}

private fun MainActivity.showAgentAttentionThresholdDialog() {
    val values = doubleArrayOf(0.40, 0.50, 0.58, 0.70, 0.80)
    val current = AgentEvalOpsStore(this).settings().attentionThreshold
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_attention_threshold)
        .setSingleChoiceItems(values.map { String.format(Locale.US, "%.2f", it) }.toTypedArray(), values.indexOfFirst { it == current }) { dialog, index ->
            AgentEvalOpsStore(this).updateSettings { it.copy(attentionThreshold = values[index]) }
            dialog.dismiss()
            showAgentEvolutionLabPage()
        }.show()
}

private fun MainActivity.showAgentFailureMemoriesDialog() {
    val items = AgentFailureMemoryStore(this).list(activeOnly = true, limit = 50)
    val text = items.joinToString("\n\n") { item ->
        "${item.taskFamily}\n${item.resourceId} · ${item.evidenceCount}\n${item.failureReasons.joinToString(", ").take(240)}"
    }.ifBlank { getString(R.string.cc_agent_lab_no_failures) }
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_failure_memory).setMessage(text)
        .setPositiveButton(android.R.string.ok, null).show()
}

private fun MainActivity.showAgentKnowledgeGapsDialog() {
    val store = AgentCognitiveGovernanceStore(this)
    val gaps = store.gaps(AgentKnowledgeGapStatus.OPEN, 50)
    val text = gaps.joinToString("\n\n") { gap ->
        "${gap.topic}\n${gap.unknownQuestions.joinToString("; ").take(260)}\n${gap.missingEvidence.joinToString(", ").take(180)}"
    }.ifBlank { getString(R.string.cc_agent_lab_no_gaps) }
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_knowledge_gaps).setMessage(text)
        .setPositiveButton(android.R.string.ok, null).show()
}

private fun MainActivity.showAgentAttentionHistoryDialog() {
    val records = AgentAttentionDecisionStore(this).list(50)
    val text = records.joinToString("\n\n") { record ->
        "${record.decision.disposition.name.lowercase(Locale.ROOT)} · ${String.format(Locale.US, "%.3f", record.decision.value)}\n${record.whyNow}\n${record.impactIfIgnored}"
    }.ifBlank { getString(R.string.cc_agent_lab_no_attention) }
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_attention_history).setMessage(text)
        .setPositiveButton(android.R.string.ok, null).show()
}

private fun MainActivity.showAndroidWorldImportDialog() {
    val input = EditText(this).apply {
        hint = getString(R.string.cc_agent_lab_android_world_json_hint)
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        minLines = 8
        maxLines = 16
        setPadding(dp(20), dp(12), dp(20), dp(12))
    }
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_android_world_import)
        .setView(input)
        .setPositiveButton(R.string.common_import) { _, _ ->
            runCatching { AgentAndroidWorldStore(this).import(input.text?.toString().orEmpty()) }
                .onSuccess {
                    Toast.makeText(this, R.string.cc_agent_lab_android_world_imported, Toast.LENGTH_SHORT).show()
                    showAgentEvolutionLabPage()
                }.onFailure { error -> Toast.makeText(this, error.message.orEmpty(), Toast.LENGTH_LONG).show() }
        }
        .setNegativeButton(android.R.string.cancel, null).show()
}

private fun MainActivity.showAndroidWorldResultsDialog() {
    val results = AgentAndroidWorldStore(this).results(50)
    val text = results.joinToString("\n\n") { result ->
        "${result.taskId} · ${if (result.passed) "passed" else "failed"}\n${result.verifierResults.joinToString(", ") { it.reason }}"
    }.ifBlank { getString(R.string.cc_agent_lab_no_results) }
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_android_world_results).setMessage(text)
        .setPositiveButton(android.R.string.ok, null).show()
}

private fun MainActivity.showProtocolAdapterDialog(wireValue: String) {
    val descriptor = AgentProtocolAdapterRegistry.descriptors(this).firstOrNull {
        it.protocol.wireValue == wireValue
    } ?: return
    AlertDialog.Builder(this).setTitle(descriptor.protocol.wireValue.uppercase(Locale.ROOT))
        .setMessage("${descriptor.state.name.lowercase(Locale.ROOT)}\n${descriptor.operations.joinToString("\n")}\nlocal_permission_boundary=${descriptor.localPermissionBoundary}")
        .setPositiveButton(android.R.string.ok, null).show()
}

private fun MainActivity.showAgentShadowReleasesDialog() {
    val releases = AgentShadowReleaseStore(this).list(50)
    val text = releases.joinToString("\n\n") { release ->
        "${release.candidateBranch}\n${release.stage.name.lowercase(Locale.ROOT)} · ${release.deviceModel}\n${release.rollbackReason}"
    }.ifBlank { getString(R.string.cc_agent_lab_no_releases) }
    AlertDialog.Builder(this).setTitle(R.string.cc_agent_lab_shadow_releases).setMessage(text)
        .setPositiveButton(android.R.string.ok, null).show()
}
