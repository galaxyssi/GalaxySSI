package com.galaxyssi.chat

internal fun MainActivity.myAgentSurfaceActive(): Boolean =
    activeMainTab == PAGE_SETTINGS || controlCenterDestination != null || controlCenterBackStack.isNotEmpty()

/** Navigation-only presentation. Existing stores remain the source of truth. */
internal fun MainActivity.myAgentRow(
    action: String, title: Int, icon: Int, status: String = "", subtitle: String = ""
) = ControlCenterRowSpec(action, getString(title), subtitle, icon, status,
    tone = controlCenterIconTone(icon), preserveIconColor = isFullColorFeatureIcon(icon))

internal fun MainActivity.myAgentHomeRow(route: ControlCenterRoute): ControlCenterRowSpec {
    val (title, icon) = when (route) {
        ControlCenterRoute.MODEL_HUB -> R.string.my_agent_models to R.drawable.ic_settings_model
        ControlCenterRoute.DEVICE_HUB -> R.string.my_agent_devices to R.drawable.ic_device_node
        ControlCenterRoute.VOICE -> R.string.my_agent_voice to R.drawable.ic_settings_voice
        ControlCenterRoute.MEMORY_HUB -> R.string.my_agent_memory to R.drawable.ic_agent_memory
        ControlCenterRoute.PROACTIVE_HUB -> R.string.my_agent_proactive to R.drawable.ic_agent_node
        ControlCenterRoute.SKILLS_HUB -> R.string.my_agent_skills to R.drawable.ic_agent_skill
        ControlCenterRoute.SAFETY_HUB -> R.string.my_agent_safety to R.drawable.ic_security_shield
        ControlCenterRoute.GENERAL -> R.string.my_agent_general to R.drawable.ic_tab_settings
        ControlCenterRoute.ADVANCED -> R.string.my_agent_advanced to R.drawable.ic_agent_control
        else -> error("Not a home destination: $route")
    }
    return myAgentRow(routeAction(route), title, icon)
}

private fun MainActivity.myAgentSection(title: Int, vararg rows: ControlCenterRowSpec) =
    ControlCenterSectionSpec(getString(title), rows.toList())

internal fun MainActivity.renderMyAgentModelsPage() {
    val registry = mobileNativeAgent.agentRegistrySnapshot()
    val targets = controlCenterResourceTargets(mobileNativeAgent.snapshot().callableTargets)
        .filter { target ->
            val contact = AppStore.contactById(this, target.id)
                ?: target.id.takeIf { it.startsWith("cloud:") }
                    ?.let { AppStore.contactById(this, it.removePrefix("cloud:")) }
            target.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                contact != null && !contact.optBoolean("deleted", false)
        }.distinctBy { it.id }
    showControlCenterFeature(getString(R.string.my_agent_models), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_add,
            myAgentRow("routing.add_cloud", R.string.cc_add_cloud_provider_title, R.drawable.ic_avatar_cloud_model),
            myAgentRow("my_agent.scan", R.string.conversation_hub_scan_add, R.drawable.ic_scan)),
        ControlCenterSectionSpec(getString(R.string.my_agent_installed),
            targets.map {
                val row = controlCenterTargetRow(it, findAgentRegistration(registry, it.id))
                row.copy(subtitle = "", preserveIconColor = row.preserveIconColor || isFullColorFeatureIcon(row.iconRes))
            } +
                myAgentRow("local_model.open", R.string.my_agent_downloaded_models, R.drawable.ic_local_model))
    )))
}

internal fun MainActivity.renderMyAgentDevicesPage() {
    val computers = desktopControlDevices()
    val rows = computers.map {
        ControlCenterRowSpec("my_agent.desktop:${it.id}", it.name, "", R.drawable.ic_device_node)
    }
    showControlCenterFeature(getString(R.string.my_agent_devices), ControlCenterPageSpec(sections = listOf(
        ControlCenterSectionSpec(getString(R.string.my_agent_computers), rows +
            myAgentRow("my_agent.scan", R.string.conversation_hub_scan_add, R.drawable.ic_scan)),
        myAgentSection(R.string.my_agent_watches,
            myAgentRow("advanced.watch_setup", R.string.my_agent_watch_setup, R.drawable.ic_protocol_link)),
        myAgentSection(R.string.my_agent_other,
            myAgentRow(routeAction(ControlCenterRoute.SMART_SPACES), R.string.my_agent_smart_home, R.drawable.ic_device_node))
    )))
}

internal fun MainActivity.renderMyAgentMemoryHub() {
    val capture = mobileNativeAgent.safetySettings().memoryCapture
    showControlCenterFeature(getString(R.string.my_agent_memory), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_records,
            myAgentRow(routeAction(ControlCenterRoute.MEMORY), R.string.my_agent_memory_items, R.drawable.ic_agent_memory),
            myAgentRow(routeAction(ControlCenterRoute.KNOWLEDGE), R.string.agent_knowledge_title, R.drawable.ic_agent_knowledge),
            myAgentRow("memory.inbox", R.string.my_agent_review, R.drawable.ic_info_outline),
            myAgentRow(routeAction(ControlCenterRoute.OBSIDIAN_HUB), R.string.my_agent_obsidian, R.drawable.ic_agent_knowledge)),
        myAgentSection(R.string.my_agent_record_scope,
            myAgentRow("memory.toggle_capture", R.string.my_agent_capture, R.drawable.ic_agent_memory)
                .copy(switchValue = capture, showChevron = false))
    ), footer = getString(R.string.my_agent_private_note)))
}

internal fun MainActivity.renderMyAgentSkillsPage() {
    showControlCenterFeature(getString(R.string.my_agent_skills), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_installed,
            myAgentRow("my_agent.skills", R.string.my_agent_automations, R.drawable.ic_agent_skill),
            myAgentRow("my_agent.tools", R.string.my_agent_tools, R.drawable.ic_agent_control),
            myAgentRow("my_agent.mcp", R.string.agent_mcp_title, R.drawable.ic_protocol_link)),
        myAgentSection(R.string.my_agent_learning,
            myAgentRow(routeAction(ControlCenterRoute.LEARNING), R.string.my_agent_learning, R.drawable.ic_agent_memory))
    )))
}

internal fun MainActivity.renderMyAgentSafetyPage() {
    showControlCenterFeature(getString(R.string.my_agent_safety), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_safety,
            myAgentRow(routeAction(ControlCenterRoute.PERMISSIONS_HUB), R.string.my_agent_permissions, R.drawable.ic_security_shield),
            myAgentRow(routeAction(ControlCenterRoute.DATA_BACKUP), R.string.my_agent_backup, R.drawable.ic_settings_download),
            myAgentRow(routeAction(ControlCenterRoute.DEVICE_HUB), R.string.my_agent_paired_devices, R.drawable.ic_device_node)),
        myAgentSection(R.string.my_agent_data,
            myAgentRow(routeAction(ControlCenterRoute.STORAGE_HUB), R.string.my_agent_storage, R.drawable.ic_device_node)),
        myAgentSection(R.string.my_agent_reset,
            myAgentRow(routeAction(ControlCenterRoute.RESET), R.string.my_agent_reset, R.drawable.ic_reset_data).copy(tone = ControlCenterTone.RED))
    )))
}

internal fun MainActivity.renderMyAgentProactivePage() {
    val settings = GlobalSuperAgentRuntime.get(this).cachedSettings()
    showControlCenterFeature(getString(R.string.my_agent_proactive), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_proactive,
            myAgentRow("global.toggle_enabled", R.string.my_agent_cognition, R.drawable.ic_agent_node)
                .copy(switchValue = settings.enabled, showChevron = false),
            myAgentRow("global.toggle_proactive", R.string.cc_global_proactive_title, R.drawable.ic_tab_discover)
                .copy(switchValue = settings.proactiveInsightsEnabled, showChevron = false, enabled = settings.enabled)),
        myAgentSection(R.string.my_agent_goals,
            myAgentRow("global.long_horizon", R.string.cc_global_goals_title, R.drawable.ic_agent_history),
            myAgentRow("global.research", R.string.cc_global_research_title, R.drawable.ic_agent_knowledge),
            myAgentRow("global.insights", R.string.my_agent_insights, R.drawable.ic_info_outline)),
        myAgentSection(R.string.my_agent_current,
            myAgentRow("global.runs", R.string.cc_global_runs_title, R.drawable.ic_agent_control),
            myAgentRow("global.continuity", R.string.cc_global_continuity_title, R.drawable.ic_agent_history)),
        ControlCenterSectionSpec(getString(R.string.my_agent_cognition_advanced), listOf(
            myAgentRow(routeAction(ControlCenterRoute.GLOBAL_AGENT), R.string.my_agent_cognition_advanced, R.drawable.ic_settings_diagnostics)
        ), collapsed = true)
    )))
}

internal fun MainActivity.renderMyAgentObsidianPage() {
    val settings = ObsidianAndroidBridge.settings(this)
    showControlCenterFeature(getString(R.string.my_agent_obsidian), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_connection,
            myAgentRow("obsidian.configure", R.string.cc_obsidian_vault_title, R.drawable.ic_agent_knowledge,
                settings.vaultName.ifBlank { getString(R.string.cc_obsidian_not_configured) })),
        myAgentSection(R.string.my_agent_data,
            myAgentRow("obsidian.sync", R.string.cc_obsidian_sync_title, R.drawable.ic_reset_data).copy(enabled = settings.enabled),
            myAgentRow("obsidian.candidates", R.string.cc_obsidian_candidates_title, R.drawable.ic_info_outline,
                ObsidianAndroidBridge.pendingCandidates(this).size.toString()).copy(enabled = settings.enabled),
            myAgentRow("obsidian.disconnect", R.string.cc_obsidian_disconnect_title, R.drawable.ic_protocol_link).copy(enabled = settings.enabled))
    )))
}

internal fun MainActivity.renderMyAgentStoragePage() {
    showControlCenterFeature(getString(R.string.my_agent_storage), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_data,
            myAgentRow("local_model.open", R.string.my_agent_downloaded_models, R.drawable.ic_local_model),
            myAgentRow("voice.asr", R.string.my_agent_speech_models, R.drawable.ic_settings_voice),
            myAgentRow(routeAction(ControlCenterRoute.ON_DEVICE_RUNTIME), R.string.my_agent_environment, R.drawable.ic_process_terminal)),
        myAgentSection(R.string.my_agent_temporary_cache,
            myAgentRow("data.cache", R.string.cc_clear_cache_title, R.drawable.ic_delete, formatBytes(directorySize(cacheDir))))
    ), footer = getString(R.string.my_agent_storage_note)))
}

internal fun MainActivity.renderMyAgentNotificationsPage() {
    showControlCenterFeature(getString(R.string.my_agent_notifications), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_notifications,
            myAgentRow("general.notifications", R.string.my_agent_notification_system, R.drawable.ic_settings_notification,
                getString(if (appNotificationsEnabled()) R.string.status_enabled else R.string.common_off)))
    ), footer = getString(R.string.my_agent_notification_note)))
}

internal fun MainActivity.renderMyAgentDiagnosticsPage() {
    showControlCenterFeature(getString(R.string.my_agent_diagnostics), ControlCenterPageSpec(sections = listOf(
        myAgentSection(R.string.my_agent_connection,
            myAgentRow("advanced.protocol", R.string.advanced_protocol_logs, R.drawable.ic_protocol_link),
            myAgentRow("advanced.web_sources", R.string.web_sources_title, R.drawable.ic_process_network)),
        myAgentSection(R.string.my_agent_voice,
            myAgentRow("advanced.voice_performance", R.string.my_agent_voice_health, R.drawable.ic_settings_voice)),
        myAgentSection(R.string.my_agent_memory_audit,
            myAgentRow("memory.audit", R.string.cc_memory_audit_title, R.drawable.ic_agent_memory),
            myAgentRow("memory.evolution_history", R.string.cc_memory_evolution_history_title, R.drawable.ic_agent_history),
            myAgentRow("memory.graph", R.string.cc_memory_graph_title, R.drawable.ic_protocol_link)),
        myAgentSection(R.string.my_agent_maintenance,
            myAgentRow("advanced.agent_lab", R.string.cc_agent_lab_title, R.drawable.ic_settings_diagnostics),
            myAgentRow("agent.memory_telemetry", R.string.my_agent_details, R.drawable.ic_info_outline))
    )))
}

internal fun MainActivity.handleMyAgentDesignAction(action: String): Boolean {
    when {
        action == "my_agent.scan" -> { startSecurityScan() }
        action.startsWith("my_agent.desktop:") -> {
            desktopControlDevices().firstOrNull { it.id == action.substringAfter("my_agent.desktop:") }?.let {
                DesktopRemoteControl.requestAuthorizations(it.id)
                openExistingControlCenterPage { showDesktopRemoteControlPage(it) }
            }
        }
        action == "my_agent.skills" || action == "my_agent.tools" || action == "my_agent.mcp" -> {
            val kind = when (action) {
                "my_agent.skills" -> AgentCapabilityCatalogKind.AUTOMATION
                "my_agent.mcp" -> AgentCapabilityCatalogKind.MCP
                else -> AgentCapabilityCatalogKind.NATIVE_TOOL
            }
            openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.MCP, capabilityKindPayload(kind)))
        }
        action == "obsidian.disconnect" && controlCenterDestination?.route == ControlCenterRoute.OBSIDIAN_HUB -> {
            ObsidianAndroidBridge.disconnect(this)
            renderMyAgentObsidianPage()
        }
        else -> return false
    }
    return true
}
