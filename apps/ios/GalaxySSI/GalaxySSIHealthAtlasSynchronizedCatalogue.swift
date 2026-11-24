import Foundation

extension GalaxySSIHealthAtlasFunctionCatalogue {
  // Keep the original imported snapshots immutable; this pinned overlay changes
  // exactly two choice titles and adds the synaptic action-potential reference.
  func synchronizedLessons() -> Self {
    let updated = stories.map { story -> Story in
      var choice = story.choiceTitle, references = story.references
      if story.id == "HEARTBEAT" { choice = "health_atlas_beat_choice" }
      if story.id == "BREATHING" { choice = "health_atlas_breathe_choice" }
      if story.id == "SYNAPTIC_SIGNAL" {
        let reference = Reference(title: "health_atlas_signal_neuro_potential_source",
          url: URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/12-4-the-action-potential")!)
        if !references.contains(reference) { references.insert(reference, at: 0) }
      }
      return Story(id: story.id, owners: story.owners, title: story.title, choiceTitle: choice, scope: story.scope,
        chapters: story.chapters, references: references, durationMs: story.durationMs,
        showStructurePreview: story.showStructurePreview, related: story.related)
    }
    return Self(schema: schema, source: Source(androidPR: 4439, mergeCommit: "eef7fd41df84c075cbc0ba046cca6ab6a5b59bf7"),
      stories: updated, routes: routes, entryPhases: entryPhases)
  }
}
