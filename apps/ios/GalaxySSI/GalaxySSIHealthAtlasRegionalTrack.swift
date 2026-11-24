import SwiftUI

struct GalaxySSIHealthAtlasRegionalTrack {
  let route: GalaxySSIHealthAtlasSectionLesson.Route
  let path: Path
  let length: Double
  init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
    self.route = route
    path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    length = GalaxySSIHealthAtlasCurveLength.route(route, width: 360, height: 360) ?? 0
  }
}
