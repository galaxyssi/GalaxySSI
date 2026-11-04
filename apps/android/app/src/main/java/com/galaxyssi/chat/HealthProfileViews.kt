package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.text.InputFilter
import android.text.InputType
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

internal fun Activity.healthProfileDatabaseName(): String {
    val requested = intent.getStringExtra("health_profile_test_db").orEmpty()
    // Instrumentation may use a separate private database, never arbitrary paths or another profile.
    return if (BuildConfig.DEBUG && requested.matches(Regex("health-profile-test-[0-9a-f-]{36}\\.db")) &&
        HealthProfilePolicy.uuid(requested.removePrefix("health-profile-test-").removeSuffix(".db"))) requested else "health_profiles_v1.db"
}

internal fun Activity.healthProfileBody(title: Int, back: () -> Unit): LinearLayout {
    val ui = HealthCenterViews(this)
    window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
    if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
    val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)); isSaveEnabled = false; importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS }
    root.addView(ui.line().apply {
        addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back, back))
        addView(ui.text(getString(title), 19f, bold = true).apply { gravity = Gravity.CENTER; maxLines = 1; setAutoSizeTextTypeUniformWithConfiguration(12, 19, 1, android.util.TypedValue.COMPLEX_UNIT_SP) }, LinearLayout.LayoutParams(0, -1, 1f))
        addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@healthProfileBody, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
    }, LinearLayout.LayoutParams(-1, ui.dp(56)))
    val body = ui.column(); root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root); return body
}
internal fun Activity.healthProfileContent(body: LinearLayout): LinearLayout {
    val ui = HealthCenterViews(this); body.removeAllViews()
    val content = ui.column().apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24)) }
    body.addView(ScrollView(this).apply { isFillViewport = true; addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f)); return content
}
internal fun Activity.healthProfileInput(text: String, max: Int, multiline: Boolean = false): EditText = EditText(this).apply {
    isSaveEnabled = false; importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
    inputType = InputType.TYPE_CLASS_TEXT or if (multiline) InputType.TYPE_TEXT_FLAG_MULTI_LINE else InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
    imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or if (multiline) EditorInfo.IME_ACTION_NONE else EditorInfo.IME_ACTION_DONE
    filters = arrayOf(InputFilter.LengthFilter(max)); setText(text); setTextColor(getColor(R.color.text_primary)); textSize = 16f
    if (multiline) { minLines = 3; maxLines = 6; gravity = Gravity.TOP } else setSingleLine(true)
}
internal fun HealthCenterViews.profileRow(title: String, subtitle: String = "", action: () -> Unit): LinearLayout = row(title, subtitle, action).apply {
    val content = getChildAt(0) as LinearLayout
    (0 until content.childCount).map { content.getChildAt(it) }.filterIsInstance<TextView>().forEachIndexed { index, text -> text.maxLines = if (index == 0) 2 else 3; text.ellipsize = TextUtils.TruncateAt.END }
}
internal fun HealthProfileField.titleResource(): Int = when (this) {
    HealthProfileField.NAME -> R.string.health_profile_name
    HealthProfileField.BIRTH_DATE -> R.string.health_profile_birth
    HealthProfileField.REFERENCE_SEX -> R.string.health_profile_sex
    HealthProfileField.HEIGHT -> R.string.health_metric_height
    HealthProfileField.PHYSIOLOGICAL_CONTEXT -> R.string.health_profile_stage
}
internal fun HealthBackgroundKind.titleResource(): Int = when (this) {
    HealthBackgroundKind.HISTORY -> R.string.health_profile_history
    HealthBackgroundKind.MEDICATION -> R.string.health_profile_medication
    HealthBackgroundKind.ALLERGY -> R.string.health_profile_allergy
}
internal fun Activity.healthProfileDisplay(field: HealthProfileField, value: HealthProfileInput?): String = when {
    value == null || value.text.isEmpty() -> getString(R.string.health_profile_missing)
    field == HealthProfileField.REFERENCE_SEX -> when (val sex = runCatching { HealthReferenceSex.valueOf(value.text) }.getOrNull()) {
        null -> value.text
        else -> getString(when (sex) {
        HealthReferenceSex.FEMALE -> R.string.health_profile_female; HealthReferenceSex.MALE -> R.string.health_profile_male
        HealthReferenceSex.OTHER -> R.string.health_other; HealthReferenceSex.NOT_DISCLOSED -> R.string.health_profile_not_disclosed
        })
    }
    field == HealthProfileField.HEIGHT -> "${value.text} ${value.unit}"
    else -> value.text
}
internal fun Activity.healthProfileError(failure: Throwable): String = getString(when {
    failure is HealthProfileConflict -> R.string.health_profile_conflict
    failure is HealthProfileValidation -> when (failure.code) {
        "date" -> R.string.health_profile_date_error; "height", "unit" -> R.string.health_profile_height_error
        "entry_name" -> R.string.health_profile_entry_name_error; else -> R.string.health_profile_text_error
    }
    else -> R.string.health_storage_error
})
