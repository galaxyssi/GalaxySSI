package com.galaxyssi.chat

import android.content.Context
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

internal enum class HealthAgentLabIntent { ABNORMAL, RESULTS, NOTE, REMIND }

internal object HealthAgentLab {
    const val marker = "local-health-labs:"
    class Once(val version: String, val until: Long) {
        private val used = java.util.concurrent.atomic.AtomicBoolean()
        fun claim() = used.compareAndSet(false, true)
    }
    val metrics = HealthMetric.entries.filter { it.form in setOf(HealthResultForm.LABORATORY, HealthResultForm.QUALITATIVE) }.toSet()
    private val other = Regex("我(的)?(爸|妈|父|母|孩子|女儿|儿子|老公|老婆|朋友)|家人|患者|别人|他(的|这次)|她(的|这次)|举例|假如|假设")
    private val otherReport = Regex("(爸爸|妈妈|父亲|母亲|孩子|朋友|同事|同学|丈夫|妻子|伴侣|家属|你们?|他们|她们)的(最近|上次|这次)?(体检|化验|检验|检查|报告|指标)")
    private val generalQuestion = Regex("意思|为什么|怎么治|该吃|有什么原因|是什么病|一般人|科普|模板|范文|怎么写|写一份|写一篇|预约|多少钱")
    private const val SHOW = "(?:请)?(?:帮我|给我)?(?:查看|查询|显示|打开|列出|调出|看看|查查|看一下|查一下|看下|查下|看|查)?"
    private const val END = "(?:呢|吗|吧)?"
    private val reportOverview = Regex(SHOW + "(?:我的?)?(?:(?:上次|这次|本次|最新|最近(?:一次)?)(?:的)?)?" +
        "(体检|化验|检验|检查|检测)(?:的)?(异常(?:的)?(?:指标|结果|项目)?|情况|概况|结果|指标|记录|报告)(?:怎么样|如何)?" + END)
    private val scopedResults = Regex(SHOW + "(?:全部(?:的)?(?:结果|指标|记录)?|所有(?:的)?(?:结果|指标|记录)|整体情况|结果|报告|指标)" + END)
    private val scopedAbnormal = Regex(SHOW + "(?:有)?(?:哪些|哪几项|哪项)?(?:是|有)?(?:异常|偏高|偏低|超标|不正常)(?:的)?(?:指标|项目)?(?:有哪些|是哪几项)?" + END)
    fun intent(raw: String, following: Boolean): HealthAgentLabIntent? {
        val s = raw.lowercase().filterNot(Char::isWhitespace).trimEnd('？', '?', '。', '.', '！', '!')
        if (s.length !in 2..220 || other.containsMatchIn(s) || otherReport.containsMatchIn(s)) return null
        if (Regex("(?:不要|不需要|不用|别)(?:再)?(?:查|看|打开|显示|列出|读取)").containsMatchIn(s)) return null
        if (Regex("不(要|用|必)(再)?(给我)?提醒|取消提醒|别提醒").containsMatchIn(s)) return null
        if (following && Regex("(复查|复检|复测|随访)").containsMatchIn(s) &&
            Regex("(提醒|安排|计划|下个?月|下周|医生让)").containsMatchIn(s)) return HealthAgentLabIntent.REMIND
        if (following && Regex("(那次|这次|当时|采样|采血|抽血|补充|其实|我是|不是空腹)").containsMatchIn(s) &&
            Regex("(餐后|饭后|餐前|空腹|采样|采血|抽血|补充)").containsMatchIn(s)) return HealthAgentLabIntent.NOTE
        if (generalQuestion.containsMatchIn(s)) return null
        // A report title can be a complete request. An unqualified "all results" needs a local report in this chat.
        reportOverview.matchEntire(s)?.let { match ->
            if (!following && "我的" !in s && match.groupValues[1] in setOf("检查", "检测")) return null
            return if (match.groupValues[2].startsWith("异常")) HealthAgentLabIntent.ABNORMAL else HealthAgentLabIntent.RESULTS
        }
        if (following && scopedResults.matches(s)) return HealthAgentLabIntent.RESULTS
        if (following && scopedAbnormal.matches(s)) return HealthAgentLabIntent.ABNORMAL
        if (!Regex("体检|化验|检验|健康中心|检查报告|检测报告|化验单|检验单|体检单").containsMatchIn(s)) return null
        if (!Regex("我|帮|查|看|列|最近|上次|这次|本次|健康中心|哪些|哪项|哪几").containsMatchIn(s)) return null
        return when {
            Regex("异常|不正常|偏高|偏低|超标|超出|不在.*范围").containsMatchIn(s) -> HealthAgentLabIntent.ABNORMAL
            Regex("结果|指标|记录|报告|列出|检查了什么").containsMatchIn(s) -> HealthAgentLabIntent.RESULTS
            else -> null
        }
    }

    fun suggestedCondition(text: String): String? {
        val s = text.filterNot(Char::isWhitespace)
        if (s.any { it in "？?" } || Regex("可能|好像|不确定|不是.*餐后|不是.*饭后").containsMatchIn(s)) return null
        if (Regex("饭后|餐后").containsMatchIn(s) && "空腹" !in s) return when {
            Regex("[饭餐]后[12一二两]个?小时").containsMatchIn(s) -> if (Regex("[饭餐]后[1一]").containsMatchIn(s)) "after_meal_1h" else "after_meal_2h"
            Regex("[饭餐]后(测|采|抽|的|$)").containsMatchIn(s) -> "after_meal"
            else -> null
        }
        if ("餐后" in s || "饭后" in s) return null
        return when {
            "不是空腹" in s || "非空腹" in s -> "non_fasting"
            "空腹" in s && !Regex("不|没").containsMatchIn(s) -> "fasting"
            else -> null
        }
    }
    fun suggestedDay(text: String, today: LocalDate): LocalDate? = when {
        Regex("下个?月").containsMatchIn(text) -> today.plusMonths(1)
        Regex("下周|下星期").containsMatchIn(text) -> today.plusWeeks(1)
        "明天" in text -> today.plusDays(1)
        else -> null
    }
    data class Snapshot(val day: LocalDate?, val imported: Boolean, val rows: List<HealthObservation>, val privacy: HealthPrivacyPolicy,
        val olderUntil: Long? = null) {
        val abnormal get() = rows.filter { HealthOverviewRangePolicy.report(it)?.outside == true }
        val unknown get() = rows.count { HealthOverviewRangePolicy.report(it)?.position in setOf(null, HealthOverviewRangePosition.NOT_COMPARABLE) }
    }
    fun read(ctx: Context, names: HealthOverviewDatabases, until: Long, once: Once? = null, check: () -> Unit = {}): Snapshot =
        HealthPrivacyStore(ctx, names.privacy).use { privacy ->
            val scope = HealthAccessScope(if (once == null) HealthAccessPurpose.HEALTH_ANALYSIS else HealthAccessPurpose.LOCAL_LAB_READ_ONCE,
                metrics, until = until + 1, zone = ZoneId.systemDefault().id)
            val query = {
                val permission = privacy.policy()
                HealthRecordStore(ctx, names.records).use recordRead@{ records ->
                    fun latest(report: Boolean) = records.measurementPage(0, until + 1, limit = 1, labReport = report, check = check).records.firstOrNull()
                    val imported = latest(true)
                    val recent = imported ?: latest(false) ?: return@recordRead Snapshot(null, false, emptyList(), permission)
                    val zone = ZoneId.systemDefault()
                    val day = Instant.ofEpochMilli(recent.draft.measuredAt).atZone(zone).toLocalDate()
                    val rows = ArrayList<HealthObservation>()
                    var cursor: HealthPageCursor? = null
                    do {
                        val page = records.measurementPage(day.atStartOfDay(zone).toInstant().toEpochMilli(), until + 1,
                            cursor, labReport = imported != null, check = check)
                        rows.addAll(page.records)
                        cursor = page.next
                    } while (cursor != null)
                    val start = day.atStartOfDay(zone).toInstant().toEpochMilli()
                    val older = start.takeIf { it > 1 && records.measurementPage(0, it, limit = 1, labReport = imported != null, check = check).records.isNotEmpty() }
                    Snapshot(day, imported != null, rows, permission, older?.minus(1))
                }
            }
            if (once != null) privacy.trackOneLocalLabRead(once, scope, query) else privacy.track(scope, query)
        }

    fun annotate(ctx: Context, names: HealthOverviewDatabases, record: HealthObservation, permission: HealthPrivacyPolicy,
        note: String, condition: String?) {
        require(permission.metrics && note.isNotBlank() && note.length <= 500 && (condition == null || condition in healthGlucoseConditions))
        HealthPrivacyStore(ctx, names.privacy).use { privacy -> privacy.withCurrentPolicy(permission) {
            HealthRecordStore(ctx, names.records).use { records ->
                val current = records.record(record.id)?.takeIf { it.profileId == "self" && it.revision == record.revision } ?: throw HealthCareConflict()
                val prior = current.editable()
                val draft = prior.copy(note = listOf(prior.note, ctx.getString(R.string.health_agent_self_note, note.trim()))
                    .filter(String::isNotBlank).joinToString("\n"), condition = condition ?: prior.condition)
                check(draft.note.length <= 2000 && records.save(draft) is HealthSaveResult.Saved)
            }
        } }
    }

    fun schedule(ctx: Context, names: HealthOverviewDatabases, record: HealthObservation, permission: HealthPrivacyPolicy,
        chat: String, due: Long) {
        require(permission.metrics && permission.profile && HealthProfilePolicy.uuid(chat))
        HealthCareEngine.evaluate(ctx, names)
        HealthReminderStore(ctx, names.reminders).use { it.settings() }
        HealthPrivacyStore(ctx, names.privacy).use { privacy -> privacy.withCurrentPolicy(permission) {
            HealthRecordStore(ctx, names.records).use { records ->
                require(records.record(record.id)?.let { it.revision == record.revision && it.profileId == "self" } == true)
                HealthCareStore(ctx, names.care).use { care ->
                    val current = care.forMetric(record.draft.metric) ?: throw HealthCareConflict()
                    val version = HealthCareEngine.inputVersion(care.settings().version, permission.version, records.metricVersion(record.draft.metric))
                    val key = UUID.nameUUIDFromBytes("local-lab-review:${record.id}".toByteArray()).toString()
                    care.scheduleLocalRecheck(current.id, HealthCareRecordRef(record.id, record.revision), key, chat, version,
                        permission, due, ctx.getString(R.string.health_agent_recheck, ctx.getString(record.draft.metric.titleResource())))
                }
            }
        } }
    }
}
