package com.galaxyssi.chat

/** Iterative validation avoids consuming call-stack depth for long, flat task pipelines. */
internal object AgentDependencyGraph {
    fun isAcyclic(edges: Map<String, Set<String>>): Boolean {
        if (edges.values.any { parents -> parents.any { it !in edges } }) return false
        val counts = edges.mapValuesTo(linkedMapOf()) { it.value.size }
        val successors = mutableMapOf<String, MutableList<String>>()
        edges.forEach { (child, parents) -> parents.forEach { successors.getOrPut(it) { mutableListOf() }.add(child) } }
        val ready = java.util.ArrayDeque(counts.filterValues { it == 0 }.keys)
        var visited = 0
        while (ready.isNotEmpty()) {
            val parent = ready.removeFirst()
            visited++
            successors[parent].orEmpty().forEach { child ->
                counts[child] = counts.getValue(child) - 1
                if (counts[child] == 0) ready.add(child)
            }
        }
        return visited == edges.size
    }
}
