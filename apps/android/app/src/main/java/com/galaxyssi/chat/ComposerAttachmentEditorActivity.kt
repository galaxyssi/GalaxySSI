package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import com.canhub.cropper.CropImageOptions
import com.canhub.cropper.CropImageView
import java.io.File
import java.util.UUID
import kotlin.concurrent.thread

/** Camera and document-picker images use the same non-sending editor. */
class ComposerAttachmentEditorActivity : Activity() {
    private val items = mutableListOf<ComposerAttachmentItem>()
    private val createdFiles = mutableSetOf<String>()
    private var selected = 0
    private var cropping = false
    private var loaded = false
    private var saving = false
    private var accepted = false
    private var pendingRotation = 0
    private var fineRotation = 0
    private var selectedRatio = 0
    private lateinit var root: LinearLayout
    private lateinit var image: CropImageView
    private lateinit var title: TextView
    private lateinit var done: TextView
    private lateinit var controls: LinearLayout
    private lateinit var thumbnails: LinearLayout
    private lateinit var strip: HorizontalScrollView
    private lateinit var document: TextView
    private var rotationLabel: TextView? = null
    private var cameraId: String = ""
    private var pendingCropFile: File? = null

    override fun onCreate(state: Bundle?) {
        AppDisplaySettings.applyToResources(this)
        super.onCreate(state)
        val payload = state?.getString(ITEMS) ?: intent.getStringExtra(ITEMS) ?: "[]"
        runCatching { items.addAll(ComposerAttachmentItem.decode(payload)) }.onFailure { finish(); return }
        if (items.isEmpty()) { finish(); return }
        selected = (state?.getInt(INDEX) ?: intent.getIntExtra(INDEX, 0)).coerceIn(items.indices)
        cameraId = state?.getString("camera_id") ?: items[selected].id
        cropping = state?.getBoolean("cropping") ?: intent.getBooleanExtra("crop_immediately", false)
        if (!items[selected].isImage) cropping = false
        fineRotation = state?.getInt("fine_rotation") ?: 0
        selectedRatio = state?.getInt("ratio") ?: 0
        createdFiles.addAll(state?.getStringArrayList("created").orEmpty())
        val page = getColor(R.color.page_bg)
        window.statusBarColor = page
        window.navigationBarColor = page
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(page) }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(label(R.string.common_cancel).apply { setOnClickListener { onBackPressed() } }, rowParams(72, 52))
        title = label(R.string.composer_attachment_preview)
        header.addView(title, LinearLayout.LayoutParams(0, dp(52), 1f))
        done = label(R.string.composer_crop_done).apply { setTextColor(accent); setOnClickListener { complete() } }
        header.addView(done, rowParams(72, 52))
        root.addView(header)
        val canvas = FrameLayout(this).apply { setBackgroundColor(Color.rgb(32, 36, 39)) }
        image = CropImageView(this).apply {
            id = R.id.composerCropImage
            setImageCropOptions(CropImageOptions(multiTouchEnabled = true, maxZoom = 12,
                initialCropWindowPaddingRatio = 0.04f, progressBarColor = accent,
                borderLineThickness = dp(1).toFloat(), borderCornerThickness = dp(3).toFloat(),
                guidelinesThickness = resources.displayMetrics.density * 0.5f))
            setOnSetImageUriCompleteListener { _, _, error ->
                loaded = error == null
                if (error != null) showError(error)
                if (loaded && pendingRotation != 0) { rotateImage(pendingRotation); pendingRotation = 0 }
                done.isEnabled = !saving && (!cropping || loaded)
            }
            setOnCropImageCompleteListener { _, result -> persistCrop(result) }
        }
        canvas.addView(image, FrameLayout.LayoutParams(-1, -1))
        document = label(R.string.composer_attachment_preview).apply { setTextColor(Color.WHITE) }
        canvas.addView(document, FrameLayout.LayoutParams(-1, -1))
        root.addView(canvas, LinearLayout.LayoutParams(-1, 0, 1f))
        thumbnails = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(12), dp(8), dp(12), dp(8)) }
        strip = HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(thumbnails) }
        root.addView(strip, LinearLayout.LayoutParams(-1, dp(88)))
        controls = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(controls)
        setContentView(root)
        showSelected()
    }

    private fun showSelected() {
        if (items.isEmpty()) { complete(); return }
        selected = selected.coerceIn(items.indices)
        val item = items[selected]
        title.setText(if (cropping) R.string.composer_crop else if (isCameraItem())
            R.string.composer_photo_preview else R.string.composer_attachment_preview)
        image.visibility = if (item.isImage) View.VISIBLE else View.GONE
        document.visibility = if (item.isImage) View.GONE else View.VISIBLE
        document.text = item.name + "\n" + AgentInputAttachment.humanSize(item.size)
        image.isShowCropOverlay = cropping
        if (!cropping) image.clearAspectRatio()
        strip.visibility = if (!cropping && items.size > 1) View.VISIBLE else View.GONE
        loaded = false
        if (item.isImage) image.setImageUriAsync(android.net.Uri.parse(if (cropping) item.source else item.uri))
        done.isEnabled = !cropping
        renderThumbnails()
        renderControls()
    }

    private fun renderThumbnails() {
        thumbnails.removeAllViews()
        items.forEachIndexed { index, item ->
            val tile = FrameLayout(this).apply {
                setPadding(dp(2), dp(2), dp(2), dp(2))
                setBackgroundColor(if (index == selected) accent else Color.TRANSPARENT)
                contentDescription = item.name
                setOnClickListener { if (!saving) { selected = index; showSelected() } }
            }
            if (item.isImage) {
                val thumb = ImageView(this).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
                tile.addView(thumb, FrameLayout.LayoutParams(-1, -1))
                ComposerThumbnailLoader.load(this, thumb, android.net.Uri.parse(item.uri), dp(96))
            } else {
                tile.addView(label(R.string.composer_attachment_preview).apply {
                    text = item.name; textSize = 11f; maxLines = 3; setBackgroundColor(getColor(R.color.page_bg))
                }, FrameLayout.LayoutParams(-1, -1))
            }
            thumbnails.addView(tile, rowParams(72, 72).apply { marginEnd = dp(8) })
        }
    }

    private fun renderControls() {
        controls.removeAllViews()
        if (cropping) {
            val ratios = LinearLayout(this)
            listOf(getString(R.string.composer_crop_free), getString(R.string.composer_crop_original), "1:1", "4:3", "16:9")
                .forEachIndexed { index, name ->
                    ratios.addView(TextView(this).apply {
                        text = name; textSize = 14f; gravity = Gravity.CENTER
                        setTextColor(if (index == selectedRatio) accent else getColor(R.color.text_primary))
                        setOnClickListener {
                            if (!loaded || saving) return@setOnClickListener
                            selectedRatio = index
                            for (i in 0 until ratios.childCount) (ratios.getChildAt(i) as TextView).setTextColor(
                                if (i == index) accent else getColor(R.color.text_primary))
                            when (index) {
                                0 -> image.clearAspectRatio()
                                1 -> image.wholeImageRect?.let { rect ->
                                    if (image.rotatedDegrees % 180 == 0) image.setAspectRatio(rect.width(), rect.height())
                                    else image.setAspectRatio(rect.height(), rect.width())
                                }
                                2 -> image.setAspectRatio(1, 1)
                                3 -> image.setAspectRatio(4, 3)
                                else -> image.setAspectRatio(16, 9)
                            }
                        }
                    }, LinearLayout.LayoutParams(0, dp(44), 1f))
                }
            controls.addView(ratios)
            rotationLabel = TextView(this).apply { text = "$fineRotation\u00b0"; gravity = Gravity.CENTER; textSize = 12f }
            controls.addView(rotationLabel)
            controls.addView(SeekBar(this).apply {
                contentDescription = getString(R.string.composer_crop_rotate)
                max = 90; progress = fineRotation + 45
                progressTintList = android.content.res.ColorStateList.valueOf(accent)
                thumbTintList = android.content.res.ColorStateList.valueOf(accent)
                setPadding(dp(24), 0, dp(24), 0)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(bar: SeekBar?, value: Int, user: Boolean) {
                        if (!user || !loaded || saving) return
                        val degrees = value - 45
                        image.rotateImage(degrees - fineRotation)
                        fineRotation = degrees
                        rotationLabel?.text = "$degrees\u00b0"
                    }
                    override fun onStartTrackingTouch(bar: SeekBar?) = Unit
                    override fun onStopTrackingTouch(bar: SeekBar?) = Unit
                })
            }, LinearLayout.LayoutParams(-1, dp(40)))
        }
        val actions = LinearLayout(this).apply { gravity = Gravity.CENTER; setPadding(dp(12), dp(4), dp(12), dp(8)) }
        if (cropping) {
            tool(actions, R.drawable.ic_composer_rotate, R.string.composer_crop_rotate) { image.rotateImage(-90) }
            tool(actions, R.drawable.ic_composer_flip, R.string.composer_crop_flip) { image.flipImageHorizontally() }
            tool(actions, R.drawable.ic_reset_data, R.string.composer_crop_reset) {
                image.clearAspectRatio(); image.resetCropRect(); fineRotation = 0; selectedRatio = 0; renderControls()
            }
        } else {
            if (isCameraItem()) {
                tool(actions, android.R.drawable.ic_menu_camera, R.string.composer_crop_retake) {
                    accepted = false
                    setResult(RESULT_OK, Intent().putExtra(ROUTE, intent.getStringExtra(ROUTE))
                        .putExtra(TARGET, intent.getStringExtra(TARGET)).putExtra("retake", true))
                    finish()
                }
            }
            if (items[selected].isImage) {
                tool(actions, R.drawable.ic_composer_crop, R.string.composer_crop) {
                    cropping = true; fineRotation = 0; selectedRatio = 0; showSelected()
                }
                tool(actions, R.drawable.ic_composer_rotate, R.string.composer_crop_rotate) {
                    cropping = true; fineRotation = 0; selectedRatio = 0; pendingRotation = -90; showSelected()
                }
            }
            tool(actions, android.R.drawable.ic_menu_delete, R.string.agent_attachment_remove) {
                items.removeAt(selected); if (items.isEmpty()) complete() else showSelected()
            }
        }
        controls.addView(actions)
    }

    private fun tool(row: LinearLayout, icon: Int, text: Int, action: () -> Unit) {
        row.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; isFocusable = true
            contentDescription = getString(text)
            setOnClickListener { if (!saving && (!cropping || loaded)) action() }
            addView(ImageView(context).apply { setImageResource(icon); imageTintList = android.content.res.ColorStateList.valueOf(
                if (text == R.string.composer_crop) accent else getColor(R.color.text_primary)) }, rowParams(24, 24))
            addView(label(text).apply { textSize = 12f }, rowParams(-2, 28))
        }, LinearLayout.LayoutParams(0, dp(64), 1f))
    }

    private fun complete() {
        if (saving) return
        if (cropping) {
            if (!loaded) return
            saving = true; done.isEnabled = false; title.setText(R.string.composer_crop_saving)
            val png = items[selected].mime.equals("image/png", true)
            val temporary = File(cacheDir, "composer-crops/crop-${UUID.randomUUID()}.${if (png) "png" else "jpg"}")
            pendingCropFile = temporary
            runCatching {
                check(temporary.parentFile!!.mkdirs() || temporary.parentFile!!.isDirectory)
                image.croppedImageAsync(if (png) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG,
                95, options = CropImageView.RequestSizeOptions.NONE,
                customOutputUri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.files", temporary))
            }
                .onFailure { temporary.delete(); pendingCropFile = null
                    saving = false; done.isEnabled = true; title.setText(R.string.composer_crop); showError(it) }
        } else {
            accepted = true
            setResult(RESULT_OK, Intent().putExtra(ITEMS, ComposerAttachmentItem.encode(items))
                .putExtra(ROUTE, intent.getStringExtra(ROUTE)).putExtra(TARGET, intent.getStringExtra(TARGET)))
            finish()
        }
    }

    private fun persistCrop(result: CropImageView.CropResult) {
        val output = result.uriContent
        if (result.error != null || output == null) {
            pendingCropFile?.delete(); pendingCropFile = null
            saving = false; done.isEnabled = true; title.setText(R.string.composer_crop)
            showError(result.error ?: IllegalStateException("No cropped image")); return
        }
        val current = items[selected]
        val temporary = pendingCropFile ?: run {
            saving = false; done.isEnabled = true; title.setText(R.string.composer_crop)
            showError(IllegalStateException("Crop output is unavailable")); return
        }
        val app = applicationContext
        val activity = java.lang.ref.WeakReference(this)
        thread(name = "composer-crop-save") {
            val file = File(app.filesDir, "composer-attachments-v1/${UUID.randomUUID()}.${if (current.mime.equals("image/png", true)) "png" else "jpg"}")
            val stored = runCatching {
                AttachmentLocalStore.storeFile(temporary, file)
                val name = current.name.substringBeforeLast('.', current.name).removeSuffix("-cropped") +
                    "-cropped.${file.extension}"
                val mime = if (file.extension == "png") "image/png" else "image/jpeg"
                current.cropped(LocalAttachmentUris.forFile(app, file, name, mime).toString(), name, file.length(), mime)
            }
            temporary.delete()
            val owner = activity.get()
            if (owner == null || owner.isFinishing || owner.isDestroyed) { file.delete(); return@thread }
            owner.runOnUiThread {
                if (owner.isFinishing || owner.isDestroyed) { file.delete(); return@runOnUiThread }
                saving = false; done.isEnabled = true; title.setText(R.string.composer_crop)
                pendingCropFile = null
                stored.onSuccess { item ->
                    createdFiles.add(file.absolutePath)
                    items[selected] = item; cropping = false; fineRotation = 0; showSelected()
                }.onFailure { file.delete(); showError(it) }
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (saving) return
        if (cropping) { cropping = false; fineRotation = 0; showSelected() } else super.onBackPressed()
    }

    override fun onSaveInstanceState(out: Bundle) {
        out.putString(ITEMS, ComposerAttachmentItem.encode(items)); out.putInt(INDEX, selected)
        out.putBoolean("cropping", cropping); out.putInt("fine_rotation", fineRotation)
        out.putInt("ratio", selectedRatio)
        out.putString("camera_id", cameraId)
        out.putStringArrayList("created", ArrayList(createdFiles))
        super.onSaveInstanceState(out)
    }

    override fun onDestroy() {
        if (::image.isInitialized) {
            image.setOnSetImageUriCompleteListener(null)
            image.setOnCropImageCompleteListener(null)
            image.clearImage()
        }
        if (isFinishing) {
            val retained = if (accepted) items.map { it.uri }.toSet() else emptySet()
            createdFiles.forEach { path ->
                val file = File(path)
                val uri = runCatching { LocalAttachmentUris.forFile(this, file).toString().substringBefore('?') }.getOrNull()
                if (retained.none { it.substringBefore('?') == uri }) file.delete()
            }
        }
        super.onDestroy()
    }

    private fun label(resource: Int) = TextView(this).apply {
        setText(resource); textSize = 16f; gravity = Gravity.CENTER; setTextColor(getColor(R.color.text_primary))
    }
    private fun rowParams(width: Int, height: Int) = LinearLayout.LayoutParams(if (width < 0) width else dp(width), dp(height))
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private val accent get() = Color.rgb(0, 165, 142)
    private fun isCameraItem() = intent.getBooleanExtra(CAMERA, false) && items.getOrNull(selected)?.id == cameraId
    private fun showError(error: Throwable) = Toast.makeText(this,
        getString(R.string.composer_crop_failed, error.message.orEmpty()), Toast.LENGTH_LONG).show()

    companion object {
        internal const val ITEMS = "composer_items"
        internal const val INDEX = "composer_index"
        internal const val ROUTE = "composer_route"
        internal const val TARGET = "composer_target"
        internal const val CAMERA = "composer_camera"
    }
}
