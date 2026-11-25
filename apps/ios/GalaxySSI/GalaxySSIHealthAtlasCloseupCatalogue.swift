import Foundation

extension GalaxySSIHealthAtlasFunctionCatalogue {
  func mechanismCloseups() -> Self {
    let updated = stories.map { story -> Story in
      let reference: Reference?
      switch story.id {
      case "HEARING": reference = .init(title: "health_atlas_hear_tip_source", url: URL(string: "https://doi.org/10.1073/pnas.2318270121")!)
      case "NEPHRON": reference = .init(title: "health_atlas_nephron_barrier_source", url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4010685/")!)
      default: reference = nil
      }
      guard let reference, !story.references.contains(reference) else { return story }
      var references = story.references
      references.insert(reference, at: min(1, references.count))
      return Story(id: story.id, owners: story.owners, title: story.title, choiceTitle: story.choiceTitle, scope: story.scope,
        chapters: story.chapters, references: references, durationMs: story.durationMs,
        showStructurePreview: story.showStructurePreview, related: story.related)
    }
    return Self(schema: schema, source: Source(androidPR: 4440, mergeCommit: "5fecc676dac71a5ef7128f6ec5893e69660b5746"),
      stories: updated, routes: routes, entryPhases: entryPhases)
  }
}
