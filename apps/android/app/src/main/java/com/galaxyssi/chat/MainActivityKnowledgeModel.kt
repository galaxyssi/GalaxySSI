package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.Switch
import android.widget.TextView
import java.io.Closeable

internal fun MainActivity.showKnowledgeModelPage() {
    showFeaturePage(getString(R.string.knowledge_model_title))
    setFeatureBackAction { showAgentKnowledgePage() }
    val controller = KnowledgeSemanticRuntime.production(applicationContext)
    val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    featureContent.addView(root)
    root.addView(featureRow(getString(R.string.knowledge_model_name), getString(R.string.knowledge_model_metadata),
        R.drawable.ic_local_model, ""))
    val status = TextView(this).apply { textSize = 14f; setPadding(dp(14), dp(8), dp(14), dp(8)); setTextColor(getColorCompat(R.color.text_primary)) }
    root.addView(status)
    val progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100; visibility = View.GONE }
    root.addView(progress)
    val counts = TextView(this).apply { textSize = 12f; setPadding(dp(14), dp(4), dp(14), dp(8)); setTextColor(getColorCompat(R.color.text_secondary)) }
    root.addView(counts)
    val enabled = Switch(this).apply { showText = false; contentDescription = getString(R.string.knowledge_model_enabled) }
    root.addView(LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(14), dp(8), dp(14), dp(8))
        addView(TextView(this@showKnowledgeModelPage).apply {
            text = getString(R.string.knowledge_model_enabled); textSize = 15f; setTextColor(getColorCompat(R.color.text_primary))
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(enabled)
    })
    val download = featureRow(getString(R.string.knowledge_model_download), "", R.drawable.ic_rich_download, "").apply {
        isClickable = true; isFocusable = true; setOnClickListener { controller.download() }
    }
    val cancel = featureRow(getString(R.string.knowledge_model_cancel), "", R.drawable.ic_rich_pause, "").apply {
        isClickable = true; isFocusable = true; setOnClickListener { controller.cancelDownload() }
    }
    val importRow = featureRow(getString(R.string.knowledge_model_import), "", R.drawable.ic_import, "").apply {
        isClickable = true; isFocusable = true
        setOnClickListener {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, REQUEST_IMPORT_KNOWLEDGE_MODEL)
        }
    }
    val index = featureRow(getString(R.string.knowledge_model_index), "", R.drawable.ic_agent_knowledge, "").apply {
        isClickable = true; isFocusable = true; setOnClickListener { controller.requestIndex() }
    }
    listOf(download, cancel, importRow, index).forEach { root.addView(it) }
    fun render(state: KnowledgeModelState) {
        if (root.parent !== featureContent) return
        val transferring = state.phase == "downloading" || state.phase == "importing"
        val percent = (state.downloaded * 100 / KnowledgeEmbeddingModel.BYTES).toInt().coerceIn(0, 100)
        status.text = when (state.phase) {
            "error" -> getString(R.string.knowledge_model_error, state.error)
            "downloading" -> getString(R.string.knowledge_model_downloading, percent)
            "loading" -> getString(R.string.knowledge_model_loading)
            "importing" -> getString(R.string.knowledge_model_importing)
            "indexing" -> getString(R.string.knowledge_model_indexing)
            else -> getString(when {
                !state.installed -> R.string.knowledge_model_not_installed
                !state.enabled -> R.string.knowledge_model_disabled
                else -> R.string.knowledge_model_ready
            })
        }
        progress.visibility = if (transferring) View.VISIBLE else View.GONE
        progress.progress = percent
        counts.text = getString(if (state.enrollmentPending) R.string.knowledge_model_discovering_counts
            else R.string.knowledge_model_counts, state.indexedChunks, state.pendingDocuments)
        enabled.setOnCheckedChangeListener(null)
        enabled.isChecked = state.enabled
        enabled.isEnabled = state.loaded && state.installed && !transferring
        enabled.setOnCheckedChangeListener { _, checked -> controller.setEnabled(checked) }
        download.visibility = if (transferring) View.GONE else View.VISIBLE
        cancel.visibility = if (controller.downloadPending) View.VISIBLE else View.GONE
        importRow.isEnabled = !transferring
        index.isEnabled = state.enabled && state.installed && !transferring
    }
    var observation: Closeable? = null
    root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) {
            observation = controller.observe { state -> handler.post { render(state) } }
        }
        override fun onViewDetachedFromWindow(view: View) { observation?.close(); observation = null }
    })
    if (root.isAttachedToWindow) observation = controller.observe { state -> handler.post { render(state) } }
    render(controller.state)
}

internal fun MainActivity.importKnowledgeModel(uri: Uri) {
    KnowledgeSemanticRuntime.production(applicationContext).importModel {
        requireNotNull(contentResolver.openInputStream(uri)) { "Cannot open the selected embedding model" }
    }
    showKnowledgeModelPage()
}
