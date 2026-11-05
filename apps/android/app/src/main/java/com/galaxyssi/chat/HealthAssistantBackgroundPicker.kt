package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal data class HealthAnalysisBackgroundChoice(val token: String, val kind: HealthBackgroundKind, val label: String)

internal fun Activity.chooseHealthAnalysisBackground(
    tasks: CoroutineScope,
    names: HealthOverviewDatabases,
    initial: Map<String, HealthAnalysisBackgroundChoice>,
    blocked: () -> Unit,
    confirm: (Map<String, HealthAnalysisBackgroundChoice>) -> Unit
): AlertDialog {
    val ui = HealthCenterViews(this)
    val kinds = HealthBackgroundKind.entries
    val selection = initial.toMutableMap()
    val root = ui.column().apply {
        val padding = ui.dp(16)
        setPadding(padding, ui.dp(8), padding, 0)
        isSaveEnabled = false
        importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
    }
    val count = ui.text("", 13f, muted = true)
    val status = ui.text("", 13f, muted = true)
    val rows = ui.column()
    val scroll = ScrollView(this).apply { addView(rows); isSaveEnabled = false }
    val pager = ui.line()
    val options = Spinner(this).apply {
        tag = "health-assistant-background-category"
        contentDescription = getString(R.string.health_assistant_background)
        adapter = ArrayAdapter(this@chooseHealthAnalysisBackground, android.R.layout.simple_spinner_dropdown_item,
            kinds.map { getString(it.titleResource()) } + getString(R.string.health_assistant_background_selected))
    }
    ui.add(root, options)
    ui.add(root, count, 4)
    ui.add(root, status)
    root.addView(scroll, LinearLayout.LayoutParams(-1, ui.dp((resources.configuration.screenHeightDp * 2 / 5).coerceIn(96, 320))))
    ui.add(root, pager)
    var request: Job? = null
    val dialog = AlertDialog.Builder(this).setTitle(R.string.health_assistant_background).setView(root)
        .setNegativeButton(android.R.string.cancel, null)
        .setPositiveButton(android.R.string.ok) { _, _ -> confirm(selection.toMap()) }.show()

    fun showCount() { count.text = getString(R.string.health_assistant_background_count, selection.size, healthAnalysisBackgroundLimit) }
    fun addChoice(id: String, item: HealthAnalysisBackgroundChoice, subtitle: String = "") {
        rows.addView(CheckBox(this).apply {
            tag = "health-assistant-background-choice-$id"
            minimumHeight = ui.dp(48)
            isSaveEnabled = false
            text = if (subtitle.isBlank()) item.label else getString(R.string.health_assistant_background_item, item.label, subtitle)
            isChecked = selection[id] == item
            setOnClickListener {
                if (!isChecked) selection.remove(id)
                else if (id in selection || selection.size < healthAnalysisBackgroundLimit) selection[id] = item
                else isChecked = false
                showCount()
            }
        })
    }
    fun clearRows() {
        rows.removeAllViews()
        pager.removeAllViews()
        status.text = ""
        scroll.scrollTo(0, 0)
    }
    fun pagingButton(title: Int, name: String, action: () -> Unit) {
        pager.addView(Button(this).apply {
            tag = name
            setText(title)
            setOnClickListener { action() }
        }, LinearLayout.LayoutParams(0, -2, 1f))
    }
    fun load(kind: HealthBackgroundKind, path: List<HealthBackgroundCursor?>) {
        request?.cancel()
        clearRows()
        status.setText(R.string.health_assistant_background_loading)
        request = tasks.launch {
            try {
                val (page, returnedToStart) = withContext(Dispatchers.IO) {
                    try { HealthAnalysis.backgroundPage(applicationContext, names, kind, path.last()) to false }
                    catch (failure: HealthProfileConflict) {
                        if (path.last() == null) throw failure
                        HealthAnalysis.backgroundPage(applicationContext, names, kind, null) to true
                    }
                }
                if (!dialog.isShowing) return@launch
                val currentPath = if (returnedToStart) listOf(null) else path
                status.text = when {
                    returnedToStart -> getString(R.string.health_assistant_background_reloaded)
                    page.entries.isEmpty() -> getString(R.string.health_profile_no_entries)
                    else -> ""
                }
                page.entries.forEach { entry ->
                    addChoice(entry.id, HealthAnalysisBackgroundChoice(entry.token, entry.kind, entry.name),
                        listOf(entry.detail, entry.dose, entry.timing).firstOrNull { it.isNotBlank() }?.take(96).orEmpty())
                }
                if (currentPath.size > 1) pagingButton(R.string.health_assistant_background_previous, "health-assistant-background-previous") {
                    load(kind, currentPath.dropLast(1))
                }
                page.next?.let { next ->
                    pagingButton(R.string.health_assistant_background_next, "health-assistant-background-next") {
                        load(kind, currentPath + next)
                    }
                }
            } catch (failure: Exception) {
                if (failure is CancellationException) throw failure
                if (!dialog.isShowing) return@launch
                if (failure is HealthAnalysisProfileBlocked) blocked()
                else status.setText(R.string.health_storage_error)
            }
        }
    }
    options.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
        override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
            val kind = kinds.getOrNull(position)
            if (kind != null) load(kind, listOf(null)) else {
                request?.cancel()
                clearRows()
                if (selection.isEmpty()) status.setText(R.string.health_assistant_profile_none)
                selection.forEach { (id, item) -> addChoice(id, item, getString(item.kind.titleResource())) }
            }
        }
    }
    dialog.setOnDismissListener { request?.cancel(); clearRows(); selection.clear() }
    showCount()
    return dialog
}
