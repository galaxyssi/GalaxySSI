package com.galaxyssi.chat

import android.content.Context

/** Separate encrypted test namespace; survives cleanup of the originating test conversation. */
internal class CollaborationPilotArtifactStore(context: Context, private val pilotId: String) {
    init { require(pilotId.matches(Regex("[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}"))) }
    internal val database = AgentEncryptedDatabase(context, "remote-pilot-artifacts-$pilotId")

    fun freeze(artifact: CollaborationPilotArtifact): CollaborationPilotArtifact.Reference {
        require(artifact.source.pilotId == pilotId)
        val ref = artifact.reference
        // The encrypted store's shared lock and transaction make same-source writes atomic.
        database.indexedTransaction {
            if (database.contains(ref.artifactId)) {
                CollaborationPilotArtifact.restore(database.readString(ref.artifactId, ""), artifact.source, ref)
            } else {
                database.writeString(ref.artifactId, artifact.envelope())
            }
        }
        return ref
    }

    fun read(source: CollaborationPilotArtifact.Source, ref: CollaborationPilotArtifact.Reference): CollaborationPilotArtifact {
        require(source.pilotId == pilotId)
        return CollaborationPilotArtifact.restore(database.readString(ref.artifactId, ""), source, ref)
    }
}
