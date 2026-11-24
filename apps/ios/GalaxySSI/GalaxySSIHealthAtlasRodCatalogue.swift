import Foundation

extension GalaxySSIHealthAtlasFunctionCatalogue {
  func rodPhototransduction() -> Self {
    let updated = stories.map { story -> Story in
      guard story.id == "VISION" else { return story }
      let reference = Reference(title: "health_atlas_vision_story_cng_source", url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2578616/")!)
      guard !story.references.contains(reference) else { return story }
      return Story(id: story.id, owners: story.owners, title: story.title, choiceTitle: story.choiceTitle, scope: story.scope,
        chapters: story.chapters, references: story.references + [reference], durationMs: story.durationMs,
        showStructurePreview: story.showStructurePreview, related: story.related)
    }
    return Self(schema: schema, source: Source(androidPR: 4443, mergeCommit: "c63bffe14e00a4c60e52aec68b6753f7547be308"),
      stories: updated, routes: routes, entryPhases: entryPhases)
  }
}
