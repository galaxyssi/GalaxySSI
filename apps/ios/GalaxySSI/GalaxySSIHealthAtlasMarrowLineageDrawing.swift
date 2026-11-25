import SwiftUI

private typealias MarrowLineage = GalaxySSIHealthAtlasMarrowGeometry
private typealias MarrowLineageTime = GalaxySSIHealthAtlasMarrowMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func marrowCommitment(_ t: Double) {
    marrowLineageRoute(MarrowLineage.erythroidRoute,fraction: MarrowLineageTime.progress(t,start: 0.04,end: 0.70),color: MarrowLineage.red)
    marrowLineageRoute(MarrowLineage.megakaryocyteRoute,fraction: MarrowLineageTime.progress(t,start: 0.25,end: 0.92),color: MarrowLineage.stem)
    marrowStem(74,181,radius: 27); marrowErythroblast(268,104,radius: 23,nucleus: 11); marrowMegakaryocyte(268,248)
    marrowCallout("marrow_story_label_stem",75,126,120,75,154)
    marrowCallout("marrow_story_label_red_lineage",261,46,172,268,81)
    marrowCallout("marrow_story_label_mega_lineage",249,306,197,268,279)
    label("marrow_story_label_illustrative",180,340,260)
  }
  private func marrowLineageRoute(_ route: GalaxySSIHealthAtlasSectionLesson.Route, fraction: Double, color: UInt32) {
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360)
    stroke(path,0xB9ADB6,1.45)
    if fraction > 0 { stroke(path.trimmedPath(from: 0,to: CGFloat(fraction)),color,2.7) }
    at(route,0.96) { x, y in at(route,1) { tx, ty in arrow(x,y,tx,ty,fraction >= 0.96 ? color : MarrowLineage.leader) } }
  }
  func marrowMaturation(_ t: Double) {
    arrow(111,169,140,169,MarrowLineage.leader); arrow(222,169,258,169,MarrowLineage.leader)
    marrowErythroblast(71,169,radius: 30,nucleus: 19)
    let frame = MarrowLineageTime.maturation(t), r = frame.radius
    oval(frame.x - r,169 - r,frame.x + r,169 + r,fill: 0xE7A7B2,border: MarrowLineage.red)
    if frame.extrude > 0.55 { disc(frame.nucleusX,frame.nucleusY,frame.nucleusRadius + 2.4,0xE5A5AD,border: MarrowLineage.red) }
    marrowNucleus(frame.nucleusX,frame.nucleusY,radius: frame.nucleusRadius); marrowReticulocyte(289,169,radius: 19)
    marrowCallout("marrow_story_label_early",72,102,108,71,139)
    marrowCallout("marrow_story_label_late",180,102,106,176,147)
    marrowCallout("marrow_story_label_reticulocyte",289,102,108,289,154)
  }
  func marrowRelease(_ t: Double) {
    marrowTissue(flow: t * 1.15,release: true); marrowReticulocyte(110,127,radius: 10)
    marrowReleasedCell(MarrowLineageTime.release(t,fromX: 156,fromY: 165,entryX: 179,endX: 330))
    marrowReleasedCell(MarrowLineageTime.release((t - 0.28) / 0.72,fromX: 137,fromY: 175,entryX: 157,endX: 265))
    marrowCallout("marrow_story_label_reticulocyte",103,43,130,108,120)
    marrowCallout("marrow_story_label_lining",257,43,132,235,MarrowLineageTime.vesselY(235) - 26)
    marrowSinusoidLabel()
  }
  private func marrowReleasedCell(_ frame: GalaxySSIHealthAtlasMarrowMotion.Release) {
    var local = context; local.translateBy(x: frame.x, y: frame.y); local.scaleBy(x: frame.scaleX, y: frame.scaleY)
    copy(local).marrowReticulocyte(0,0,radius: 11)
  }
}
