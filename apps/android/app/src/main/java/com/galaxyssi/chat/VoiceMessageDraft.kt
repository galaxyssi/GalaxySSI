package com.galaxyssi.chat

import java.util.UUID

/** One transient draft per live voice session. Transport can start only after an atomic claim. */
internal class VoiceMessageDraft(private val now: () -> Long = { System.nanoTime() / 1_000_000 }) {
    data class Speaker(val session: String, val conversation: String, val turn: String)
    data class Person(val id: String, val name: String)
    data class Claim(val revision: String, val recipient: Person, val text: String)
    private data class Draft(val speaker: Speaker, val text: String, val people: List<Person>,
        val selected: Person?, val revision: String, val expires: Long, val phase: String,
        val message: Long = 0)
    private var current: Draft? = null

    private fun observed(s: Speaker): Draft? {
        val d = current ?: return null
        if (now() >= d.expires) { current = null; return null }
        return d.takeIf { it.speaker.session == s.session && it.speaker.conversation == s.conversation }
    }
    private fun requireLive(s: Speaker) {
        if (s.session.isBlank() || s.conversation.isBlank() || s.turn.isBlank())
            throw AppControlFailure("voice_turn_missing", "A live voice utterance is required.")
    }
    private fun info(d: Draft): AgentNativeJsonObject = buildMap {
        put("state", d.phase); put("revision", d.revision); put("delivery_verified", false)
        d.selected?.let { put("recipient", it.name); put("contact_id", it.id) }
        if (d.phase == "choose_recipient") put("choices", d.people.mapIndexed { i, p ->
            mapOf("option" to i + 1, "name" to p.name, "contact_id" to p.id, "id_suffix" to p.id.takeLast(4))
        })
        if (d.phase in editable) put("text", d.text)
        if (d.message > 0) put("message_id", d.message)
    }
    @Synchronized fun status(s: Speaker): AgentNativeJsonObject = observed(s)?.let(::info).orEmpty()
    private fun draft(s: Speaker, text: String, contacts: List<Person>): AgentNativeJsonObject {
        val people = contacts.distinctBy { it.id }
        val selected = people.singleOrNull()
        val d = Draft(s, text, people, selected, UUID.randomUUID().toString(), now() + 180_000,
            if (selected != null) "awaiting_confirmation" else "choose_recipient")
        current = d
        return info(d)
    }
    @Synchronized fun begin(s: Speaker, text: String, people: List<Person>): AgentNativeJsonObject {
        requireLive(s)
        val existing = observed(s)
        if (existing != null && (existing.phase in editable || existing.phase == "dispatching" || existing.speaker.turn == s.turn))
            return info(existing)
        if (text.isBlank() || text.length > 10000) throw AppControlFailure("empty_message", "A message body is required.")
        return draft(s, text, people)
    }
    @Synchronized fun change(s: Speaker, revision: String, candidates: List<Person>): AgentNativeJsonObject {
        val d = requireRevision(s, revision)
        if (d.phase !in editable) return info(d)
        return draft(s, d.text, candidates)
    }
    @Synchronized fun choose(s: Speaker, revision: String, id: String, spokenOption: Int): AgentNativeJsonObject {
        val d = requireRevision(s, revision)
        if (d.phase != "choose_recipient") return info(d)
        if (s.turn == d.speaker.turn) throw AppControlFailure("clarify_recipient", "The user must distinguish the candidates in a later utterance.")
        val person = d.people.getOrNull(spokenOption - 1)?.takeIf { it.id == id }
            ?: throw AppControlFailure("clarify_recipient", "Read the numbered choices and ask the user to choose by number.")
        return draft(s, d.text, listOf(person))
    }
    @Synchronized fun claim(s: Speaker, revision: String, userConfirmed: Boolean): Claim {
        val d = requireRevision(s, revision)
        if (d.phase != "awaiting_confirmation" || d.selected == null || !userConfirmed || s.turn == d.speaker.turn)
            throw AppControlFailure("not_confirmed", "No new explicit user confirmation for this recipient and message.")
        current = d.copy(phase = "dispatching", speaker = s)
        return Claim(revision, d.selected, d.text)
    }
    @Synchronized fun finish(claim: Claim, state: String, message: Long): AgentNativeJsonObject {
        val d = current
        if (d == null || d.revision != claim.revision || d.phase != "dispatching")
            return mapOf("state" to state, "message_id" to message, "delivery_verified" to false)
        val next = d.copy(phase = state, message = message, text = "", people = emptyList())
        current = next
        return info(next)
    }
    @Synchronized fun cancel(s: Speaker, revision: String): AgentNativeJsonObject {
        val d = requireRevision(s, revision)
        if (d.phase !in editable) return info(d)
        current = null
        return mapOf("state" to "cancelled_before_send")
    }
    private fun requireRevision(s: Speaker, revision: String): Draft {
        requireLive(s)
        return observed(s)?.takeIf { it.revision == revision }
            ?: throw AppControlFailure("stale_voice_draft", "This draft has changed or expired; do not send.")
    }
    @Synchronized fun clear() { current = null }
    companion object {
        private val editable = setOf("awaiting_confirmation", "choose_recipient")
        fun explicitConfirmation(spoken: String): Boolean = spoken.trim().trimEnd('。', '！', '!', '.', '，', ',').trim().lowercase() in
            setOf("确认发送", "确认发出", "发送吧", "发吧", "可以发送", "confirm send", "send it", "yes, send it")
        private val ordinals = listOf("一","二","三","四","五","六","七","八","九","十")
        private val english = listOf("first","second","third","fourth","fifth","sixth","seventh","eighth","ninth","tenth")
        fun explicitChoice(spoken: String): Int {
            val value = spoken.trim().trimEnd('。', '.', '！', '!').trim().lowercase()
            val number = value.removePrefix("选").removePrefix("第").removeSuffix("个").removePrefix("option ").trim()
            return number.toIntOrNull()?.takeIf { it in 1..500 } ?: (ordinals.indexOf(number) + 1).takeIf { it > 0 }
                ?: (english.indexOf(value.removePrefix("the ").removeSuffix(" one")) + 1)
        }
    }
}
