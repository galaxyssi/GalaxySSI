package com.galaxyssi.chat

import java.io.File
import java.util.PriorityQueue

/** Bounded runs and fan-in; even the run descriptor set grows logarithmically, not per item. */
internal class KnowledgeExternalOrder(private val scratch: KnowledgeEncryptedScratch,
    private val budget: Long = 512 * 1024, private val fanIn: Int = 16) {
    private val pending = ArrayList<KnowledgeOrderKey>()
    private val levels = ArrayList<MutableList<File>>()
    private var pendingBytes = 0L
    private var finished = false
    internal var peakBufferedBytes = 0L
        private set
    internal var peakMergeHeads = 0
        private set
    internal var peakRunFiles = 0
        private set
    init { require(budget > 0 && fanIn in 2..16) }
    fun add(key: KnowledgeOrderKey) {
        check(!finished)
        if (pending.isNotEmpty() && pendingBytes + key.estimatedBytes > budget) flush()
        pending.add(key)
        pendingBytes += key.estimatedBytes
        peakBufferedBytes = maxOf(peakBufferedBytes, pendingBytes)
        if (pendingBytes >= budget) flush()
    }
    fun finish(): File {
        check(!finished)
        flush()
        finished = true
        val files = levels.flatMap { it }.toMutableList()
        if (files.isEmpty()) return scratch.create().also { KnowledgeOrderRun.Writer(scratch.output(it)).close() }
        while (files.size > 1) {
            val group = files.take(fanIn)
            val merged = merge(group)
            repeat(group.size) { files.removeAt(0) }
            files.add(merged)
        }
        return files.single()
    }
    private fun flush() {
        if (pending.isEmpty()) return
        check(!Thread.currentThread().isInterrupted)
        pending.sort()
        val file = scratch.create()
        KnowledgeOrderRun.Writer(scratch.output(file)).use { writer -> pending.forEach(writer::add) }
        pending.clear()
        pendingBytes = 0
        carry(file, 0)
    }
    private fun carry(file: File, level: Int) {
        if (levels.size == level) levels.add(ArrayList())
        levels[level].add(file)
        peakRunFiles = maxOf(peakRunFiles, levels.sumOf { it.size })
        if (levels[level].size == fanIn) {
            val merged = merge(levels[level])
            levels[level].clear()
            carry(merged, level + 1)
        }
    }
    private fun merge(files: List<File>): File {
        data class Head(val key: KnowledgeOrderKey, val reader: KnowledgeOrderRun.Reader)
        val readers = ArrayList<KnowledgeOrderRun.Reader>()
        val queue = PriorityQueue<Head>(compareBy { it.key })
        val result = scratch.create()
        try {
            for (file in files) {
                val reader = KnowledgeOrderRun.Reader(scratch.input(file))
                readers.add(reader)
                reader.next()?.let { queue.add(Head(it, reader)) }
            }
            peakMergeHeads = maxOf(peakMergeHeads, queue.size)
            KnowledgeOrderRun.Writer(scratch.output(result)).use { writer ->
                while (queue.isNotEmpty()) {
                    check(!Thread.currentThread().isInterrupted)
                    val head = queue.remove()
                    writer.add(head.key)
                    head.reader.next()?.let { queue.add(Head(it, head.reader)) }
                }
            }
        } finally { readers.forEach { it.close() } }
        files.forEach(scratch::remove)
        return result
    }
}
