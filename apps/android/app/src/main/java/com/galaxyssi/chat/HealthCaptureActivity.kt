package com.galaxyssi.chat

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.FileProvider
import java.util.UUID
import java.util.concurrent.Executors

/** Collects originals and review suggestions; only the separate confirmed editor writes observations. */
class HealthCaptureActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val originals by lazy { HealthOriginalStore(applicationContext) }
    private lateinit var body: LinearLayout
    private lateinit var title: TextView
    private var route = "capture"
    private var selectedId = ""
    private var page = 1
    private var candidateOffset = 0
    private var mode = "report"
    private var active = false
    private var generation = 0
    private var querying = false
    private var dirty = false
    private var pendingCamera = ""
    private var exportId = ""
    private var cropId = ""
    private var preview: HealthOriginalPreview? = null
    private var rawDialog: AlertDialog? = null
    private var actionDialog: AlertDialog? = null
    private val libraryPages = arrayListOf<Pair<Long, String>>()
    private val jobPages = arrayListOf<Pair<Long, String>>()
    private val recordPages = arrayListOf<HealthPageCursor>()
    private var renderedKey = ""
    private val taskViews = linkedMapOf<String, HealthImportTaskView>()
    private var nextReviewPage: TextView? = null
    private var availableReviewPages = 0
    private val stack = ArrayDeque<Triple<String, String, Int>>()
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { refresh() }
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            if (uri?.lastPathSegment != "jobs" || route in listOf("capture", "review")) refresh()
        }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        route = state?.getString("route") ?: intent.getStringExtra("route") ?: "capture"
        selectedId = state?.getString("selected") ?: intent.getStringExtra("original").orEmpty()
        if (state == null && selectedId.isNotBlank()) route = "original"
        page = state?.getInt("page", 1) ?: 1
        candidateOffset = state?.getInt("candidate_offset", 0) ?: 0
        mode = state?.getString("mode") ?: "report"
        pendingCamera = state?.getString("camera") ?: getSharedPreferences("health_capture_pending", MODE_PRIVATE).getString("token", "").orEmpty()
        exportId = state?.getString("export").orEmpty(); cropId = state?.getString("crop").orEmpty()
        fun restore(key: String) = state?.getStringArrayList(key).orEmpty().mapNotNull { value ->
            val parts = value.split('|'); val time = parts.firstOrNull()?.toLongOrNull()
            if (parts.size == 2 && time != null && runCatching { UUID.fromString(parts[1]) }.isSuccess) time to parts[1] else null
        }
        libraryPages.addAll(restore("library_pages")); jobPages.addAll(restore("job_pages"))
        recordPages.addAll(restore("record_pages").map { HealthPageCursor(it.first, it.second) })
        state?.getStringArrayList("stack")?.forEach { value ->
            val parts = value.split('|'); if (parts.size == 3) stack.addLast(Triple(parts[0], parts[1], parts[2].toInt()))
        }
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { back() })
            title = ui.text("", 19f, bold = true).apply { gravity = Gravity.CENTER }
            addView(title, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                startActivity(Intent(this@HealthCaptureActivity, HealthCenterActivity::class.java).putExtra("health_functions", true))
            })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    override fun onStart() {
        super.onStart(); active = true
        contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this), true, observer)
        refresh()
    }
    override fun onStop() {
        active = false; generation++; contentResolver.unregisterContentObserver(observer)
        preview?.dismiss(); preview = null; rawDialog?.dismiss(); rawDialog = null; actionDialog?.dismiss(); actionDialog = null
        taskViews.clear(); renderedKey = ""; nextReviewPage = null; body.removeAllViews()
        super.onStop()
    }
    override fun onDestroy() { worker.execute { originals.close() }; worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("route", route); out.putString("selected", selectedId); out.putInt("page", page); out.putString("mode", mode)
        out.putInt("candidate_offset", candidateOffset)
        out.putString("camera", pendingCamera); out.putString("export", exportId); out.putString("crop", cropId)
        out.putStringArrayList("library_pages", ArrayList(libraryPages.map { "${it.first}|${it.second}" }))
        out.putStringArrayList("job_pages", ArrayList(jobPages.map { "${it.first}|${it.second}" }))
        out.putStringArrayList("record_pages", ArrayList(recordPages.map { "${it.measuredAt}|${it.id}" }))
        out.putStringArrayList("stack", ArrayList(stack.map { "${it.first}|${it.second}|${it.third}" }))
        super.onSaveInstanceState(out)
    }
    @Deprecated("Native activity back callback") override fun onBackPressed() = back()
    private fun back() {
        if (stack.isEmpty()) { finish(); return }
        val previous = stack.removeLast(); route = previous.first; selectedId = previous.second; page = previous.third
        generation++; refresh()
    }
    private fun open(next: String, id: String = "", number: Int = 1) {
        if (next == "original" && selectedId != id) recordPages.clear()
        stack.addLast(Triple(route, selectedId, page)); route = next; selectedId = id; page = number; candidateOffset = 0; generation++; refresh()
    }
    private fun content(): LinearLayout {
        body.removeAllViews()
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
        body.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        return content
    }
    private fun refresh() {
        if (!active) return
        if (querying) { dirty = true; return }
        querying = true
        val token = generation
        val currentRoute = route; val id = selectedId; val number = page; val offset = candidateOffset
        val cameraToken = pendingCamera
        val fileCursor = libraryPages.lastOrNull(); val taskCursor = jobPages.lastOrNull(); val recordCursor = recordPages.lastOrNull()
        worker.execute {
            val result = runCatching {
                when (currentRoute) {
                    "library" -> CaptureSnapshot(files = originals.originals(fileCursor))
                    "original" -> {
                        val original = originals.original(id)
                        val records = HealthRecordStore(applicationContext).use { it.page(after = recordCursor, originalId = id) }
                        CaptureSnapshot(original = original, available = original?.let(originals::present) == true,
                            saved = records.records, recordsNext = records.next)
                    }
                    "review" -> {
                        val job = originals.job(id)
                        val original = job?.originalId?.takeIf(String::isNotBlank)?.let(originals::original)
                        val scanned = if (job == null) null else originals.page(id, number)
                        val suggestions = if (job == null || original == null || scanned == null) emptyList()
                            else HealthOcrCandidates.suggest(job, original, scanned)
                        val visible = suggestions.drop(offset).take(20)
                        val saved = HealthRecordStore(applicationContext).use { records -> visible.mapNotNull { records.recordForEvidence(it) } }
                        CaptureSnapshot(job = job, original = original, page = scanned, saved = saved,
                            suggestions = visible, hasMore = suggestions.size > offset + visible.size)
                    }
                    else -> CaptureSnapshot(jobs = originals.jobs(taskCursor), pendingPhoto = cameraToken.isNotBlank() && HealthCaptureFiles.file(applicationContext, cameraToken).let { it.isFile && it.length() > 0 })
                }
            }
            main.post {
                querying = false
                if (active && token == generation && !isDestroyed) result.fold({ render(currentRoute, it) }, { showFailure("storage") })
                if (active && (dirty || token != generation)) { dirty = false; refresh() }
            }
        }
    }
    private fun render(screen: String, data: CaptureSnapshot) {
        val key = when (screen) {
            "capture" -> "capture|$mode|${data.pendingPhoto}|${data.jobs.joinToString { it.id }}"
            "review" -> "review|$selectedId|$page|$candidateOffset|${data.page?.page}|${data.saved.joinToString { "${it.id}:${it.revision}" }}"
            else -> ""
        }
        if (key.isNotBlank() && key == renderedKey && body.childCount > 0) {
            if (screen == "capture") data.jobs.forEach { taskViews[it.id]?.bind(it, jobState(it)) }
            else {
                availableReviewPages = data.job?.nextPage ?: 0
                nextReviewPage?.visibility = if (page < availableReviewPages) View.VISIBLE else View.GONE
            }
            return
        }
        val previousScroll = if (renderedKey.substringBefore('|') == screen) (body.getChildAt(0) as? ScrollView)?.scrollY ?: 0 else 0
        renderedKey = key; taskViews.clear(); nextReviewPage = null
        title.text = getString(when (screen) {
            "library" -> R.string.health_original_library
            "original" -> R.string.health_original_detail
            "review" -> R.string.health_review_title
            else -> R.string.health_record_center
        })
        val content = content()
        when (screen) {
            "library" -> renderLibrary(content, data.files)
            "original" -> renderOriginal(content, data.original, data.available, data.saved, data.recordsNext)
            "review" -> renderReview(content, data)
            else -> renderCapture(content, data.jobs, data.pendingPhoto)
        }
        if (previousScroll > 0) (body.getChildAt(0) as? ScrollView)?.let { scroll -> scroll.post { if (active) scroll.scrollTo(0, previousScroll) } }
    }
    private fun renderCapture(content: LinearLayout, jobs: List<HealthImportJob>, pendingPhoto: Boolean) {
        content.addView(ui.text(getString(R.string.health_capture_heading), 23f, bold = true))
        ui.add(content, ui.line().apply {
            listOf("report" to R.string.health_capture_report, "device" to R.string.health_capture_device).forEach { (value, label) ->
                addView(ui.text(getString(label), 14f, bold = mode == value).apply {
                    minimumHeight = ui.dp(44); gravity = Gravity.CENTER
                    background = ui.background(if (mode == value) 0xffe7f6ee.toInt() else getColor(R.color.surface_bg), radius = 8)
                    setOnClickListener { mode = value; refresh() }
                }, LinearLayout.LayoutParams(0, -2, 1f))
            }
        }, 14)
        ui.add(content, ui.card().apply {
            addView(ui.row(getString(R.string.health_take_photo), getString(R.string.health_camera_alignment)) { camera() })
            addView(ui.row(getString(R.string.health_choose_images)) { choose(images = true) })
            addView(ui.row(getString(R.string.health_choose_files)) { choose(images = false) })
            addView(ui.row(getString(R.string.health_original_library)) { open("library") })
        }, 14)
        if (pendingPhoto) {
            ui.add(content, ui.row(getString(R.string.health_camera_recover)) {
                val token = pendingCamera
                importSource(FileProvider.getUriForFile(this, "$packageName.files", HealthCaptureFiles.file(this, token)), token)
            }, 14)
        }
        ui.add(content, ui.text(getString(R.string.health_local_recognition), 12f, muted = true), 16)
        ui.add(content, ui.text(getString(R.string.health_import_tasks), 19f, bold = true), 20)
        if (jobs.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_import_tasks), 14f, muted = true), 12)
        jobs.forEach { job ->
            val view = HealthImportTaskView(this, ui,
                { value -> worker.execute { HealthImportScheduler.cancel(applicationContext, value.id) } }, ::retry,
                { open("review", it.id) }, { open("original", it.originalId) })
            view.bind(job, jobState(job)); taskViews[job.id] = view; ui.add(content, view, 12)
        }
        if (jobPages.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { jobPages.removeAt(jobPages.lastIndex); generation++; refresh() }, 16)
        if (jobs.size == 30) ui.add(content, ui.command(R.string.health_next_page) { jobs.last().let { jobPages += it.createdAt to it.id }; generation++; refresh() }, 16)
    }
    private fun renderLibrary(content: LinearLayout, files: List<HealthOriginal>) {
        ui.add(content, ui.row(getString(R.string.health_choose_files)) { choose(false) })
        if (files.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_originals), 15f, muted = true), 12)
        files.forEach { original -> ui.add(content, ui.row(original.name,
            "${original.mime} \u00b7 ${android.text.format.Formatter.formatShortFileSize(this, original.size)}") { open("original", original.id) }, 8) }
        if (libraryPages.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { libraryPages.removeAt(libraryPages.lastIndex); generation++; refresh() }, 16)
        if (files.size == 30) ui.add(content, ui.command(R.string.health_next_page) { files.last().let { libraryPages += it.importedAt to it.id }; generation++; refresh() }, 16)
    }
    private fun renderOriginal(content: LinearLayout, original: HealthOriginal?, available: Boolean, saved: List<HealthObservation>, next: HealthPageCursor?) {
        if (original == null) { content.addView(ui.text(getString(R.string.health_original_missing))); return }
        content.addView(ui.card().apply {
            addView(ui.text(original.name, 20f, bold = true))
            ui.add(this, ui.text(original.mime, 13f, muted = true), 8)
            addView(ui.text(android.text.format.Formatter.formatShortFileSize(this@HealthCaptureActivity, original.size), 14f))
            ui.add(this, ui.text(getString(R.string.health_original_imported_at, java.text.DateFormat.getDateTimeInstance().format(java.util.Date(original.importedAt))), 12f, muted = true), 8)
            ui.add(this, ui.text(original.sha256, 11f, muted = true).apply { setTextIsSelectable(true) }, 12)
        })
        if (!available) {
            ui.add(content, ui.text(getString(R.string.health_original_missing), 14f), 16)
            ui.add(content, ui.row(getString(R.string.health_choose_files)) { choose(false) }, 12)
            return
        }
        ui.add(content, ui.row(getString(R.string.health_open_original)) {
            preview?.dismiss()
            preview = HealthOriginalPreview(this, original) { export(original) }.also { it.show() }
        }, 14)
        if (original.mime.startsWith("image/")) ui.add(content, ui.row(getString(R.string.composer_crop)) { crop(original) })
        original.source.takeIf { it.startsWith("crop:") }?.substringAfter("crop:")?.let { parent ->
            ui.add(content, ui.row(getString(R.string.health_view_uncropped)) { open("original", parent) })
        }
        if (saved.isNotEmpty()) {
            ui.add(content, ui.text(getString(R.string.health_linked_records), 18f, bold = true), 18)
            saved.forEach { record -> ui.add(content, ui.row(getString(record.draft.metric.titleResource()), record.draft.values.values.joinToString(" / ") + " " + record.draft.unit) {
                startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_record", record.id))
            }) }
        }
        if (recordPages.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { recordPages.removeAt(recordPages.lastIndex); generation++; refresh() }, 16)
        if (next != null) ui.add(content, ui.command(R.string.health_next_page) { recordPages += next; generation++; refresh() }, 16)
        ui.add(content, ui.row(getString(R.string.health_save_original)) { export(original) })
        ui.add(content, ui.row(getString(R.string.health_recognize_again)) {
            importSource(HealthOriginalContentProvider.uri(this, original.id))
        })
        ui.add(content, ui.row(getString(R.string.health_remove_original)) {
            actionDialog = AlertDialog.Builder(this).setTitle(R.string.health_remove_original).setMessage(R.string.health_remove_original_explanation)
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.common_delete) { _, _ ->
                    worker.execute {
                        val removed = originals.removeOriginalBytes(original)
                        main.post { if (active) { if (!removed) showFailure("storage") else Toast.makeText(this, R.string.health_original_removed, Toast.LENGTH_SHORT).show(); refresh() } }
                    }
                }.show()
        }, 18)
    }
    private fun renderReview(content: LinearLayout, data: CaptureSnapshot) {
        val job = data.job; val original = data.original; val scanned = data.page
        if (job == null || original == null || scanned == null) { content.addView(ui.text(getString(R.string.health_review_not_ready))); return }
        content.addView(ui.text(getString(R.string.health_source_page, scanned.page), 14f, muted = true))
        ui.add(content, ui.row(getString(R.string.health_view_original), original.name) { open("original", original.id) }, 8)
        if (scanned.blurry) ui.add(content, ui.text(getString(R.string.health_ocr_quality_warning), 14f), 12)
        val suggestions = data.suggestions
        if (suggestions.isEmpty()) ui.add(content, ui.text(getString(R.string.health_no_matched_fields), 15f), 12)
        suggestions.forEach { draft ->
            val previous = data.saved.firstOrNull { it.draft.evidence?.let { saved ->
                saved.originalId == original.id && saved.page == scanned.page && saved.candidateId == draft.evidence?.candidateId
            } == true }
            ui.add(content, ui.card().apply {
                addView(ui.text(getString(draft.metric.titleResource()), 18f, bold = true))
                ui.add(this, ui.text(draft.evidence!!.rawText, 14f), 8)
                ui.add(this, ui.row(getString(if (previous == null) R.string.health_check_fields else R.string.health_already_confirmed)) {
                    if (previous != null) startActivity(Intent(this@HealthCaptureActivity, HealthCenterActivity::class.java).putExtra("health_record", previous.id))
                    else editSuggestion(draft)
                }, 8)
            }, 12)
        }
        ui.add(content, ui.row(getString(R.string.health_unmatched_manual)) {
            val evidence = HealthEvidence(original.id, job.id, "manual", original.sha256, scanned.page,
                scanned.lines.take(15).joinToString("\n") { it.text }.take(8000), scanned.lines.take(15).map { it.box }.filter { it.size == 4 })
            chooseManualMetric(evidence)
        }, 14)
        ui.add(content, ui.row(getString(R.string.health_show_raw_text)) {
            rawText(scanned)
        })
        if (candidateOffset > 0) ui.add(content, ui.command(R.string.health_previous_candidates) { candidateOffset = (candidateOffset - 20).coerceAtLeast(0); generation++; refresh() }, 16)
        if (data.hasMore) ui.add(content, ui.command(R.string.health_more_candidates) { candidateOffset += 20; generation++; refresh() }, 16)
        if (page > 1) ui.add(content, ui.command(R.string.health_previous_page) { page--; candidateOffset = 0; generation++; refresh() }, 16)
        availableReviewPages = job.nextPage
        nextReviewPage = ui.command(R.string.health_next_page) {
            if (page < availableReviewPages) { page++; candidateOffset = 0; generation++; refresh() }
        }.apply { visibility = if (page < availableReviewPages) View.VISIBLE else View.GONE }
        ui.add(content, requireNotNull(nextReviewPage), 16)
    }
    private fun rawText(scanned: HealthOcrPage, offset: Int = 0) {
        val text = ui.text(scanned.lines.drop(offset).take(80).joinToString("\n") { it.text }, 14f).apply {
            setTextIsSelectable(true); setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(16))
        }
        rawDialog?.dismiss()
        rawDialog = AlertDialog.Builder(this).setTitle(R.string.health_show_raw_text).setView(ScrollView(this).apply { addView(text) })
            .setNegativeButton(R.string.common_close, null).apply {
                if (offset + 80 < scanned.lines.size) setPositiveButton(R.string.health_more_text) { _, _ -> rawText(scanned, offset + 80) }
                if (offset > 0) setNeutralButton(R.string.health_previous_page) { _, _ -> rawText(scanned, (offset - 80).coerceAtLeast(0)) }
            }.show()
    }
    private fun chooseManualMetric(evidence: HealthEvidence) {
        val metrics = HealthMetric.entries
        actionDialog = AlertDialog.Builder(this).setTitle(R.string.health_choose_metric)
            .setItems(metrics.map { getString(it.titleResource()) }.toTypedArray()) { _, index ->
                editSuggestion(HealthDraft(metrics[index], unit = "", measuredAt = 0, evidence = evidence.copy(candidateId = "manual-${metrics[index].name}")))
            }.show()
    }
    private fun editSuggestion(draft: HealthDraft) {
        val key = HealthRecordStore.draftKey(draft)
        worker.execute {
            val result = runCatching { HealthRecordStore(applicationContext).use { store ->
                if (store.draft(key) == null) store.saveDraft(draft)
            } }
            main.post { if (active) result.fold({
                startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("review_draft", key))
            }, { showFailure("storage") }) }
        }
    }
    private fun choose(images: Boolean) {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
            .setType(if (images) "image/*" else "*/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true), PICK)
    }
    private fun camera() {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION); return
        }
        val token = UUID.randomUUID().toString()
        worker.execute {
            val file = HealthCaptureFiles.file(applicationContext, token)
            val prepared = runCatching {
                check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs()); file.createNewFile()
                FileProvider.getUriForFile(applicationContext, "$packageName.files", file)
            }
            main.post {
                if (!active) { kotlin.concurrent.thread(name = "health-camera-cleanup", isDaemon = true) { file.delete() }; return@post }
                prepared.fold({ uri ->
                    pendingCamera = token
                    getSharedPreferences("health_capture_pending", MODE_PRIVATE).edit().putString("token", token).apply()
                    val intent = Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE).putExtra(android.provider.MediaStore.EXTRA_OUTPUT, uri)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        .apply { clipData = ClipData.newRawUri("Health capture", uri) }
                    runCatching { startActivityForResult(intent, CAMERA) }.onFailure { worker.execute { file.delete() }; showFailure("camera_unavailable") }
                }, { showFailure("storage") })
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) camera() else showFailure("camera_permission")
        }
    }
    @Deprecated("Native document and camera result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CAMERA) {
            val token = pendingCamera
            if (token.isBlank()) return
            val file = HealthCaptureFiles.file(this, token)
            if (resultCode == RESULT_OK) importSource(FileProvider.getUriForFile(this, "$packageName.files", file), token)
            else {
                worker.execute { file.delete(); getSharedPreferences("health_capture_pending", MODE_PRIVATE).edit().remove("token").apply() }
                pendingCamera = ""
            }
        } else if (requestCode == PICK && resultCode == RESULT_OK) {
            val uris = data?.clipData?.let { clip -> (0 until clip.itemCount).map { clip.getItemAt(it).uri } }
                ?: listOfNotNull(data?.data)
            uris.distinct().forEach { importSource(it) }
        } else if (requestCode == EXPORT && resultCode == RESULT_OK) {
            val uri = data?.data ?: return
            val id = exportId
            worker.execute {
                val result = runCatching {
                    val original = originals.original(id) ?: throw HealthImportFailure("original_missing")
                    contentResolver.openOutputStream(uri, "wt")?.use { originals.copyVerified(original, it) }
                        ?: throw HealthImportFailure("save_failed")
                }
                main.post { if (active) result.fold({ Toast.makeText(this, R.string.health_original_saved, Toast.LENGTH_LONG).show() }, { showFailure("save_failed") }) }
            }
        } else if (requestCode == CROP && resultCode == RESULT_OK) {
            val items = data?.getStringExtra(ComposerAttachmentEditorActivity.ITEMS)?.let { ComposerAttachmentItem.decode(it) }.orEmpty()
            items.singleOrNull()?.let { importSource(Uri.parse(it.uri)) }
        }
    }
    private fun importSource(uri: Uri, cameraToken: String = "") {
        val selectedMode = mode
        worker.execute {
            runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            val id = cameraToken.ifBlank { UUID.randomUUID().toString() }
            val result = runCatching {
                if (originals.job(id) == null) originals.createJob(HealthImportJob(id, uri.toString(), System.currentTimeMillis(), selectedMode, cameraToken))
                HealthImportScheduler.enqueue(applicationContext, id)
                if (cameraToken.isNotBlank()) getSharedPreferences("health_capture_pending", MODE_PRIVATE).edit().remove("token").apply()
            }
            main.post { if (active) result.fold({
                if (pendingCamera == cameraToken) pendingCamera = ""
                jobPages.clear(); route = "capture"; generation++; refresh()
            }, { showFailure("source_permission") }) }
        }
    }
    private fun retry(job: HealthImportJob) { worker.execute {
        originals.updateJob(job.id, restartCancelled = true) { it.copy(state = HealthImportState.QUEUED, error = "") }
        HealthImportScheduler.enqueue(applicationContext, job.id)
    } }
    private fun export(original: HealthOriginal) {
        exportId = original.id
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
            .setType(original.mime.ifBlank { "application/octet-stream" }).putExtra(Intent.EXTRA_TITLE, original.name), EXPORT)
    }
    private fun crop(original: HealthOriginal) {
        cropId = original.id
        val item = ComposerAttachmentItem(original.id, HealthOriginalContentProvider.uri(this, original.id).toString(), original.name, original.mime, original.size, sendOriginal = true)
        startActivityForResult(Intent(this, ComposerAttachmentEditorActivity::class.java)
            .putExtra(ComposerAttachmentEditorActivity.ITEMS, ComposerAttachmentItem.encode(listOf(item)))
            .putExtra("crop_immediately", true).putExtra("health_original_parent", original.id), CROP)
    }
    private fun jobState(job: HealthImportJob): String = when (job.state) {
        HealthImportState.QUEUED -> getString(R.string.health_import_queued)
        HealthImportState.COPYING -> if (job.totalBytes > 0) getString(R.string.health_import_copy_percent, (job.copiedBytes * 100 / job.totalBytes).coerceIn(0, 100))
            else getString(R.string.health_import_copying)
        HealthImportState.RECOGNIZING -> getString(R.string.health_import_recognizing, job.nextPage + 1, job.pageCount.coerceAtLeast(1))
        HealthImportState.REVIEW -> getString(R.string.health_import_review_ready, job.nextPage)
        HealthImportState.ORIGINAL_ONLY -> getString(R.string.health_import_original_only)
        HealthImportState.CANCELLED -> getString(R.string.health_import_cancelled)
        HealthImportState.FAILED -> getString(failureText(job.error))
    }
    private fun showFailure(code: String) { Toast.makeText(this, failureText(code), Toast.LENGTH_LONG).show() }
    private fun failureText(code: String): Int = when (code) {
        "image_unsupported" -> R.string.health_import_image_unsupported
        "pdf_password" -> R.string.health_import_pdf_password
        "pdf_unsupported" -> R.string.health_import_pdf_unsupported
        "source_permission", "source_unavailable" -> R.string.health_import_source_unavailable
        "camera_permission" -> R.string.health_import_camera_permission
        "camera_unavailable" -> R.string.health_import_camera_unavailable
        "ocr_timeout" -> R.string.health_import_ocr_timeout
        "save_failed" -> R.string.health_import_save_failed
        "storage_full" -> R.string.health_import_storage_full
        "page_complexity" -> R.string.health_import_complexity
        "memory_pressure" -> R.string.health_import_memory_pressure
        else -> R.string.health_import_failed
    }
    private data class CaptureSnapshot(val jobs: List<HealthImportJob> = emptyList(), val files: List<HealthOriginal> = emptyList(),
        val job: HealthImportJob? = null, val original: HealthOriginal? = null, val page: HealthOcrPage? = null, val saved: List<HealthObservation> = emptyList(),
        val suggestions: List<HealthDraft> = emptyList(), val hasMore: Boolean = false, val available: Boolean = true, val pendingPhoto: Boolean = false,
        val recordsNext: HealthPageCursor? = null)
    companion object { private const val PICK = 81; private const val CAMERA = 82; private const val EXPORT = 83; private const val CROP = 84; private const val CAMERA_PERMISSION = 85 }
}
