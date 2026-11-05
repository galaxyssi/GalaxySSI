package com.galaxyssi.chat

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.Executors

/** Camera collection is a durable draft; recognition starts only after explicit page submission. */
class HealthCameraActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val names by lazy {
        val fixture = intent.getStringExtra("health_camera_test_id").orEmpty().takeIf { BuildConfig.DEBUG && HealthProfilePolicy.uuid(it) }
        HealthOverviewDatabases(fixture)
    }
    private val store by lazy { HealthOriginalStore(applicationContext, names.originals, names.originalRoot(applicationContext)) }
    private lateinit var camera: HealthCameraController
    private lateinit var cameraArea: FrameLayout
    private lateinit var pages: LinearLayout
    private lateinit var controls: LinearLayout
    private lateinit var hint: TextView
    private lateinit var count: TextView
    private lateinit var shutter: ImageView
    private lateinit var torch: ImageView
    private lateinit var modes: LinearLayout
    private lateinit var guide: View
    private var batchId = ""
    private var batch: HealthPhotoBatch? = null
    private var inCamera = true
    private var active = false
    private var ready = false
    private var busy = false
    private var pendingId = ""
    private var replacement: String? = null
    private var exportId = ""
    private var light = false
    private var generation = 0
    private var querying = false
    private var dirty = false
    private var rendered = ""
    private val pageCursors = arrayListOf<Int>()
    private val thumbnails = linkedMapOf<ImageView, Bitmap>()
    private var dialog: AlertDialog? = null
    private var preview: HealthOriginalPreview? = null
    private val observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) { load() } }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        batchId = state?.getString("batch") ?: intent.getStringExtra("capture_batch").orEmpty()
        inCamera = state?.getBoolean("camera", false) ?: intent.getBooleanExtra("capture_camera", batchId.isBlank())
        exportId = state?.getString("export").orEmpty()
        replacement = state?.getString("replacement")
        state?.getIntegerArrayList("page_cursors")?.let(pageCursors::addAll)
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { back() })
            addView(ui.text(getString(R.string.health_take_photo), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                startActivity(Intent(this@HealthCameraActivity, HealthCenterActivity::class.java).putExtra("health_functions", true))
            })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        modes = ui.line().apply { setPadding(ui.dp(4), ui.dp(4), ui.dp(4), ui.dp(4)); background = ui.background(0xffe6ede9.toInt(), radius = 10) }
        root.addView(modes, LinearLayout.LayoutParams(-1, ui.dp(48)).apply { setMargins(ui.dp(16), ui.dp(10), ui.dp(16), ui.dp(16)) })
        cameraArea = FrameLayout(this).apply { background = ui.background(0xff293d34.toInt(), radius = 20); clipToOutline = true }
        val texture = TextureView(this).apply { isOpaque = false }
        camera = HealthCameraController(this, texture, { available, flash ->
            ready = available; if (!available) light = false
            if (::shutter.isInitialized) { shutter.isEnabled = available && !busy && batch?.submitted == false; shutter.alpha = if (shutter.isEnabled) 1f else .4f }
            if (::torch.isInitialized) { torch.isEnabled = available && flash; torch.alpha = if (torch.isEnabled) 1f else .4f
                torch.isSelected = false; torch.contentDescription = getString(R.string.health_photo_light_on)
                torch.imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.text_primary))
            }
        }, { id, bytes ->
            val weak = WeakReference(this); val handler = main
            HealthPhotoPersistence.save(applicationContext, id, bytes) { saved -> handler.post {
                weak.get()?.let { owner -> if (!owner.isDestroyed && owner.pendingId == id) {
                    owner.busy = false; owner.pendingId = ""; owner.shutter.isEnabled = owner.ready
                    if (owner.active && owner.inCamera && saved) owner.hint.setText(R.string.health_photo_continuous)
                    if (!saved && owner.active) owner.message(R.string.health_photo_save_failed)
                    owner.load()
                } }
            } }
        }, { id ->
            if (id != null) {
                val app = applicationContext
                kotlin.concurrent.thread(name = "health-photo-interrupted", isDaemon = true) {
                    runCatching { HealthOriginalStore(app).use { it.updateJob(id) { job -> job.copy(state = HealthImportState.FAILED, error = "capture_interrupted") } } }
                }
            }
            if (!isDestroyed && (id == null || pendingId == id)) {
                busy = false; pendingId = ""; if (active) { hint.setText(R.string.health_photo_camera_failed); load() }
            }
        })
        cameraArea.addView(texture, FrameLayout.LayoutParams(-1, -1))
        guide = object : View(this) {
            private val pen = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xff75e5a2.toInt(); strokeWidth = ui.dp(2).toFloat(); style = Paint.Style.STROKE }
            override fun onDraw(canvas: Canvas) {
                val ratio = if (batch?.mode == "device") 1.4f else .72f
                val w = minOf(width * .82f, height * .78f * ratio); val h = w / ratio
                canvas.drawRoundRect((width - w) / 2, (height - h) / 2, (width + w) / 2, (height + h) / 2, ui.dp(10).toFloat(), ui.dp(10).toFloat(), pen)
            }
        }
        cameraArea.addView(guide, FrameLayout.LayoutParams(-1, -1))
        cameraArea.addView(ui.text(getString(R.string.health_camera_alignment), 13f).apply {
            gravity = Gravity.CENTER; setTextColor(0xffd4efe0.toInt()); setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(8)); maxLines = 2
        }, FrameLayout.LayoutParams(-1, -2, Gravity.TOP))
        root.addView(cameraArea, LinearLayout.LayoutParams(-1, 0, 1f).apply { marginStart = ui.dp(16); marginEnd = ui.dp(16) })
        pages = ui.column(); root.addView(pages, LinearLayout.LayoutParams(-1, 0, 1f))
        hint = ui.text(getString(R.string.health_photo_continuous), 13f, muted = true).apply {
            setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(8)); gravity = Gravity.CENTER
        }; root.addView(hint)
        controls = ui.line().apply { gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP; setPadding(ui.dp(16), ui.dp(8), ui.dp(16), 0) }
        controls.addView(ui.column().apply {
            gravity = Gravity.CENTER_HORIZONTAL
            addView(action(R.drawable.ic_process_image, R.string.health_choose_images) { chooseImages() })
            addView(ui.text(getString(R.string.health_choose_images), 12f, muted = true).apply { gravity = Gravity.CENTER; maxLines = 2; setOnClickListener { chooseImages() } }, LinearLayout.LayoutParams(-1, ui.dp(32)))
        }, LinearLayout.LayoutParams(0, -2, 1f))
        shutter = action(R.drawable.ic_agent_camera, R.string.health_photo_shutter) { shoot() }.apply {
            setImageDrawable(null)
            background = android.graphics.drawable.GradientDrawable().apply { shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(Color.WHITE); setStroke(ui.dp(4), 0xff294438.toInt()) }
            isEnabled = false
        }; controls.addView(shutter, LinearLayout.LayoutParams(ui.dp(64), ui.dp(64)))
        torch = action(android.R.drawable.ic_lock_power_off, R.string.health_photo_light) {
            light = !light; camera.toggleTorch(light); torch.isSelected = light; torch.alpha = if (light) 1f else .65f
            torch.contentDescription = getString(if (light) R.string.health_photo_light_off else R.string.health_photo_light_on)
            torch.imageTintList = android.content.res.ColorStateList.valueOf(if (light) 0xff139c80.toInt() else getColor(R.color.text_primary))
        }.apply { isEnabled = false }
        controls.addView(ui.column().apply {
            gravity = Gravity.CENTER_HORIZONTAL; addView(torch)
            addView(ui.text(getString(R.string.health_photo_light), 12f, muted = true).apply { gravity = Gravity.CENTER; setOnClickListener { if (torch.isEnabled) torch.performClick() } }, LinearLayout.LayoutParams(-1, ui.dp(32)))
        }, LinearLayout.LayoutParams(0, -2, 1f)); root.addView(controls)
        count = ui.text("", 14f).apply { gravity = Gravity.CENTER; minimumHeight = ui.dp(48); setOnClickListener { showPages() } }
        root.addView(count)
        setContentView(root)
        if (batchId.isBlank()) {
            batchId = UUID.randomUUID().toString()
            val mode = intent.getStringExtra("capture_mode")?.takeIf { it in listOf("report", "device") } ?: "report"
            io.execute { val result = runCatching { store.createCaptureBatch(HealthPhotoBatch(batchId, mode, System.currentTimeMillis(),
                keepOriginal = intent.getBooleanExtra(HEALTH_KEEP_ORIGINAL, true))) }
                main.post { if (!isDestroyed) result.fold({ load(); if (active) {
                    if (inCamera) openCamera() else if (state == null && intent.getBooleanExtra("capture_pick_images", false)) chooseImages()
                } }, { message(R.string.health_photo_save_failed) }) } }
        }
    }
    override fun onStart() {
        super.onStart(); active = true
        contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this), true, observer)
        switchViews(); load()
    }
    override fun onResume() { super.onResume(); if (inCamera && checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) camera.start() }
    override fun onPause() { camera.stop(); super.onPause() }
    override fun onStop() {
        active = false; generation++; contentResolver.unregisterContentObserver(observer)
        cameraArea.visibility = View.GONE
        dialog?.dismiss(); dialog = null; preview?.dismiss(); preview = null
        clearThumbnails(); pages.removeAllViews(); rendered = ""; count.text = ""; super.onStop()
    }
    override fun onDestroy() { camera.dispose(); val finishing = isFinishing
        io.execute { runCatching { if (finishing && batchId.isNotBlank()) store.discardEmptyCapture(batchId) }; runCatching { store.close() } }
        io.shutdown(); super.onDestroy()
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("batch", batchId); out.putBoolean("camera", inCamera)
        out.putString("replacement", replacement); out.putString("export", exportId); out.putIntegerArrayList("page_cursors", pageCursors); super.onSaveInstanceState(out)
    }
    @Deprecated("Native camera back dispatch") override fun onBackPressed() = back()
    private fun back() { if (inCamera && (batch != null)) showPages() else finish() }
    private fun action(icon: Int, label: Int, click: () -> Unit) = ui.icon(icon, label, click).apply { tooltipText = getString(label) }
    private fun switchViews() {
        cameraArea.visibility = if (inCamera) View.VISIBLE else View.GONE
        pages.visibility = if (inCamera) View.GONE else View.VISIBLE; controls.visibility = if (inCamera) View.VISIBLE else View.GONE
    }
    private fun openCamera(retake: String? = null) {
        if (!active || batch?.submitted == true) return
        replacement = retake; inCamera = true; switchViews(); hint.setText(R.string.health_photo_continuous)
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION)
        else camera.start()
    }
    private fun showPages() { inCamera = false; camera.stop(); switchViews(); rendered = ""; load() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == PERMISSION && active) {
            if (results.firstOrNull() == PackageManager.PERMISSION_GRANTED && inCamera) camera.start()
            else { showPages(); hint.setText(R.string.health_import_camera_permission) }
        }
    }
    private fun shoot() {
        if (busy || !ready || !active) return
        val owner = batch ?: return; if (owner.submitted) return
        busy = true; shutter.isEnabled = false; shutter.alpha = .4f; hint.setText(R.string.health_photo_saving)
        val id = UUID.randomUUID().toString(); pendingId = id; val replacing = replacement
        io.execute {
            val result = runCatching { store.addCaptureJob(batchId, HealthImportJob(id, HealthOriginalContentProvider.uri(this, id).toString(),
                System.currentTimeMillis(), mode = requireNotNull(store.captureBatch(batchId)).mode, name = "photo-$id.jpg", mime = "image/jpeg", state = HealthImportState.COPYING, captureBatch = batchId), replacing) }
            main.post { if (!isDestroyed) result.fold({ replacement = null; camera.capture(id); load() }, {
                busy = false; pendingId = ""; shutter.isEnabled = ready; if (active) message(R.string.health_photo_save_failed)
            }) else kotlin.concurrent.thread(name = "health-photo-abandoned", isDaemon = true) {
                runCatching { HealthOriginalStore(applicationContext).use { it.updateJob(id) { job -> job.copy(state = HealthImportState.FAILED, error = "capture_interrupted") } } }
            } }
        }
    }
    private fun chooseImages() {
        if (batch?.submitted == true) return
        showPages()
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true), PICK)
    }
    private fun load() {
        if (!active || batchId.isBlank() || io.isShutdown) return
        if (querying) { dirty = true; return }; querying = true
        val token = generation; val after = pageCursors.lastOrNull() ?: -1
        io.execute {
            val result = runCatching {
                val owner = store.captureBatch(batchId)
                val photos = store.capturePages(batchId, after).map { page -> PhotoRow(page, store.job(page.jobId), store.job(page.jobId)?.originalId?.takeIf(String::isNotBlank)?.let(store::original)?.takeIf(store::present), store.capturePageNumber(page.jobId) ?: 0) }
                Triple(owner, photos, store.capturePageCount(batchId))
            }
            main.post {
                querying = false
                if (active && token == generation && !isDestroyed) result.fold({ (owner, photos, total) ->
                    batch = owner; renderModes(owner)
                    guide.invalidate()
                    shutter.isEnabled = ready && !busy && owner?.submitted == false; shutter.alpha = if (shutter.isEnabled) 1f else .4f
                    count.text = getString(R.string.health_photo_count, total)
                    if (!inCamera) renderPages(photos, owner?.submitted == true, total)
                }, { message(R.string.health_photo_save_failed) })
                if (active && (dirty || token != generation)) { dirty = false; load() }
            }
        }
    }
    private fun renderModes(owner: HealthPhotoBatch?) {
        modes.removeAllViews()
        listOf("report" to R.string.health_capture_report, "device" to R.string.health_capture_device).forEach { (value, label) ->
            modes.addView(ui.text(getString(label), 14f, bold = owner?.mode == value).apply {
                gravity = Gravity.CENTER; background = ui.background(if (owner?.mode == value) Color.WHITE else Color.TRANSPARENT, radius = 8)
                setTextColor(if (owner?.mode == value) 0xff138271.toInt() else getColor(R.color.text_secondary))
                isEnabled = owner != null && !owner.submitted
                setOnClickListener { io.execute { runCatching { store.captureMode(batchId, value) }; main.post { if (active) load() } } }
            }, LinearLayout.LayoutParams(0, -1, 1f))
        }
    }
    private fun renderPages(photos: List<PhotoRow>, submitted: Boolean, total: Int) {
        val signature = "$submitted|$total|${pageCursors.lastOrNull()}|${photos.joinToString { "${it.page.jobId}:${it.page.position}:${it.job?.state}:${it.page.quality}" }}"
        if (signature == rendered && pages.childCount > 0) return
        val scrollY = (pages.getChildAt(0) as? ScrollView)?.scrollY ?: 0
        rendered = signature; clearThumbnails(); pages.removeAllViews()
        val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(16)) }
        pages.addView(ScrollView(this).apply { addView(content); post { scrollTo(0, scrollY) } }, LinearLayout.LayoutParams(-1, 0, 1f))
        if (photos.isEmpty()) ui.add(content, ui.text(getString(R.string.health_photo_empty), 16f), 12)
        photos.forEachIndexed { index, row ->
            ui.add(content, ui.card().apply {
                addView(ui.line().apply {
                    val suggestion = if (submitted) null else row.page.quality?.suggestedCrop
                    val image = object : ImageView(this@HealthCameraActivity) {
                        private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = 0xff10836e.toInt(); strokeWidth = ui.dp(2).toFloat(); style = Paint.Style.STROKE
                        }
                        override fun onDraw(canvas: Canvas) {
                            super.onDraw(canvas)
                            val rendered = drawable ?: return
                            val crop = suggestion ?: return
                            val b = crop.pixels(rendered.intrinsicWidth, rendered.intrinsicHeight)
                            val box = RectF(b[0].toFloat(), b[1].toFloat(), b[2].toFloat(), b[3].toFloat())
                            imageMatrix.mapRect(box)
                            canvas.drawRect(box, stroke)
                        }
                    }.apply { scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = row.original?.name }
                    addView(image, LinearLayout.LayoutParams(ui.dp(80), ui.dp(104)).apply { marginEnd = ui.dp(12) })
                    addView(ui.column().apply {
                        addView(ui.text(getString(R.string.health_photo_page, row.number), 17f, bold = true))
                        ui.add(this, ui.text(qualityText(row), 13f, muted = true), 8)
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                    row.original?.let { original ->
                        val token = generation
                        io.execute { val bitmap = runCatching { HealthPhotoInspector.decode(store, original, 60_000) }.getOrNull()
                            main.post { if (active && token == generation && image.isAttachedToWindow && bitmap != null) { thumbnails[image] = bitmap; image.setImageBitmap(bitmap) } else bitmap?.recycle() } }
                        image.setOnClickListener {
                            preview?.dismiss()
                            preview = HealthOriginalPreview(this@HealthCameraActivity, original,
                                if (original.reviewOnly) null else ({ export(original) })).also { it.show() }
                        }
                    }
                })
                addView(ui.line().apply {
                    if (!submitted) {
                        addView(action(R.drawable.ic_agent_arrow_up, R.string.health_photo_move_up) { mutate { store.moveCapturePage(row.page.jobId, -1) } })
                        addView(action(R.drawable.ic_agent_arrow_up, R.string.health_photo_move_down) { mutate { store.moveCapturePage(row.page.jobId, 1) } }.apply { rotation = 180f })
                        val suggested = row.page.quality?.suggestedCrop
                        addView(action(R.drawable.ic_composer_crop, if (suggested == null) R.string.composer_crop else R.string.health_photo_suggested_crop) {
                            row.original?.let { crop(row.page.jobId, it, suggested) }
                        }.apply { isEnabled = row.original != null })
                        addView(action(R.drawable.ic_agent_camera, R.string.health_photo_retake) { openCamera(row.page.jobId) })
                        addView(action(R.drawable.ic_delete, R.string.health_photo_remove) { confirmRemove(row.page.jobId) })
                    } else addView(ui.row(getString(R.string.health_review_title)) {
                        startActivity(Intent(this@HealthCameraActivity, HealthCaptureActivity::class.java).putExtra("health_job", row.page.jobId))
                    })
                })
            }, 12)
        }
        if (pageCursors.isNotEmpty()) ui.add(content, ui.command(R.string.health_photo_previous) { pageCursors.removeAt(pageCursors.lastIndex); generation++; rendered = ""; load() }, 16)
        if (photos.size == 20 && total > (photos.lastOrNull()?.number ?: 0)) ui.add(content, ui.command(R.string.health_photo_next) {
            pageCursors += photos.last().page.position; generation++; rendered = ""; load()
        }, 16)
        if (!submitted) {
            ui.add(content, ui.row(getString(R.string.health_photo_add)) { openCamera() }, 18)
            ui.add(content, ui.row(getString(R.string.health_choose_images)) { chooseImages() })
            ui.add(content, ui.row(getString(R.string.health_manual)) { startActivity(Intent(this@HealthCameraActivity, HealthCenterActivity::class.java).putExtra("health_manual", true)) })
            ui.add(content, ui.command(R.string.health_photo_start_recognition) { submit() }.apply { isEnabled = total > 0; alpha = if (isEnabled) 1f else .4f }, 20)
        }
        hint.setText(if (submitted) R.string.health_photo_submitted else R.string.health_photo_before_recognition)
    }
    private fun qualityText(row: PhotoRow): String {
        if (row.page.quality != null && row.original == null) return getString(R.string.health_original_missing)
        val quality = row.page.quality ?: return getString(if (row.job?.state == HealthImportState.FAILED) R.string.health_photo_failed else R.string.health_photo_inspecting)
        return listOfNotNull(if (quality.suggestedCrop != null) getString(R.string.health_photo_edges_found)
            else if (quality.reportChecked) getString(R.string.health_photo_edges_unclear) else null,
            if (quality.lowDetail) getString(R.string.health_photo_low_detail) else null,
            if (quality.dark) getString(R.string.health_photo_dark) else null, if (quality.small) getString(R.string.health_photo_small) else null)
            .joinToString("\n").ifBlank { getString(R.string.health_photo_check_original) }
    }
    private fun mutate(operation: () -> Unit) { io.execute { val result = runCatching(operation); main.post { if (active) { result.onFailure { message(R.string.health_photo_changed) }; rendered = ""; load() } } } }
    private fun confirmRemove(id: String) {
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_photo_remove).setMessage(R.string.health_photo_remove_detail)
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.common_delete) { _, _ -> mutate {
                store.removeCapturePage(id); HealthImportScheduler.cancel(applicationContext, id)
            } }.show()
    }
    private fun crop(id: String, original: HealthOriginal, suggested: HealthReportCrop?) {
        val item = ComposerAttachmentItem(original.id, HealthOriginalContentProvider.uri(this, original.id, names.fixture).toString(), original.name, original.mime, original.size, sendOriginal = true)
        startActivityForResult(Intent(this, ComposerAttachmentEditorActivity::class.java).putExtra(ComposerAttachmentEditorActivity.ITEMS, ComposerAttachmentItem.encode(listOf(item)))
            .putExtra("crop_immediately", true).putExtra("health_original_parent", original.id)
            .putExtra(HEALTH_CROP_BATCH, batchId).putExtra(HEALTH_CROP_PAGE, id)
            .putExtra(HEALTH_REPORT_CROP, suggested?.encode()), CROP)
    }
    @Deprecated("Native picker/crop callback") override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        if (requestCode == PICK) {
            val uris = data?.clipData?.let { clip -> (0 until clip.itemCount).map { clip.getItemAt(it).uri } } ?: listOfNotNull(data?.data)
            uris.distinct().forEach(::collect)
        } else if (requestCode == CROP) {
            if (data?.getStringExtra(HEALTH_CROP_RESULT)?.let(HealthProfilePolicy::uuid) == true) {
                rendered = ""; load()
            }
        } else if (requestCode == EXPORT) {
            val uri = data?.data ?: return; val id = exportId
            io.execute {
                val result = runCatching { val original = requireNotNull(store.original(id));
                    HealthPrivacyStore.track(applicationContext, HealthAccessScope.originals(1)) {
                        contentResolver.openOutputStream(uri, "wt")?.use { store.copyVerified(original, it) } ?: error("Save destination unavailable")
                    }
                }
                main.post { if (active) message(if (result.isSuccess) R.string.health_original_saved else R.string.health_import_save_failed) }
            }
        }
    }
    private fun export(original: HealthOriginal) {
        exportId = original.id
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(original.mime)
            .putExtra(Intent.EXTRA_TITLE, original.name), EXPORT)
    }
    private fun collect(uri: android.net.Uri) {
        io.execute {
            val result = runCatching {
                runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                val owner = requireNotNull(store.captureBatch(batchId)); val id = UUID.randomUUID().toString()
                store.addCaptureJob(batchId, HealthImportJob(id, uri.toString(), System.currentTimeMillis(), mode = owner.mode, captureBatch = batchId))
                HealthImportScheduler.enqueue(applicationContext, id, prepareCapture = true)
            }
            main.post { if (active) { result.onFailure { message(R.string.health_photo_changed) }; pageCursors.clear(); rendered = ""; load() } }
        }
    }
    private fun submit() {
        io.execute {
            val result = runCatching { store.submitCaptureBatch(batchId).forEach { HealthImportScheduler.enqueue(applicationContext, it) } }
            main.post { if (active) result.fold({ setResult(RESULT_OK, Intent().putExtra("capture_batch", batchId)); finish() }, { message(R.string.health_photo_not_ready); load() }) }
        }
    }
    private fun clearThumbnails() { thumbnails.forEach { (view, bitmap) -> view.setImageDrawable(null); bitmap.recycle() }; thumbnails.clear() }
    private fun message(resource: Int) { android.widget.Toast.makeText(this, resource, android.widget.Toast.LENGTH_LONG).show() }
    private data class PhotoRow(val page: HealthPhotoPage, val job: HealthImportJob?, val original: HealthOriginal?, val number: Int)
    companion object { private const val PERMISSION = 88; private const val PICK = 89; private const val CROP = 90; private const val EXPORT = 91 }
}

internal const val HEALTH_REPORT_CROP = "health_report_crop"
