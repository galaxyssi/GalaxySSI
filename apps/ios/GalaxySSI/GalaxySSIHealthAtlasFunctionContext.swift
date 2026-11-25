import Foundation

struct GalaxySSIHealthAtlasFunctionContext {
  let entryID: String
  private let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  private let phase: Double
  init?(entryID: String, selection: GalaxySSIHealthAtlasFunctionSelection?,
        catalogue: GalaxySSIHealthAtlasFunctionCatalogue?) {
    guard let catalogue else { return nil }
    let current = selection ?? GalaxySSIHealthAtlasFunctionSelection()
    guard let story = current.current(entryID: entryID, catalogue: catalogue) else { return nil }
    self.entryID = entryID
    self.story = story
    phase = current.phase(entryID: entryID, storyID: story.id, catalogue: catalogue)
  }
  func lines(for entryID: String, language: String) -> [String] {
    guard entryID == self.entryID else { return [] }
    let index = story.chapter(phase), chapter = story.chapters[index]
    func text(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get(key, language) }
    return [
      text(story.title),
      String(format: text("health_atlas_stage"), Int64(index + 1), Int64(story.chapters.count), text(chapter.title)),
      text(chapter.caption),
      text(story.scope)
    ] + story.references.map { $0.url.absoluteString }
  }
}
