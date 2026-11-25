import SwiftUI

private typealias FibroblastTissue = GalaxySSIHealthAtlasFibroblastShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func fibroblastPatch() {
    rounded(39,107,326,281,17,0x186B514A)
    fill(FibroblastTissue.side,0xDFB4BE); stroke(FibroblastTissue.side,Self.coral,1.25)
    for row in 0...3 { let y = 160 + Double(row) * 24; line(314,y,325,y - 10,0xC28A99,1.4) }
    gradient(FibroblastTissue.dermis,108,274,0xFFEEE7,0xECD0D8); stroke(FibroblastTissue.dermis,Self.coral,1.35)
    fill(FibroblastTissue.epidermalEdge,0xD99A92); stroke(FibroblastTissue.epidermalEdge,Self.coral,1.25)
    for path in [FibroblastTissue.epidermalBand,FibroblastTissue.epidermalTop] {
      gradient(path,79,134,0xFFECDB,0xF0BCB0); stroke(path,Self.coral,1.35)
    }
    stroke(FibroblastTissue.surfaceDetail,0xFFF3E4,1.5)
  }
  func fibroblastCell() {
    gradient(FibroblastTissue.cell,192,226,0xE0D8F2,0xAF93C7); stroke(FibroblastTissue.cell,Self.violet,1.35)
    oval(166,200,190,213,fill: 0x795489,border: 0x634372); stroke(FibroblastTissue.cellDetail,0xF6ECFC,1.45)
  }
  func fibroblastLabels() {
    label("fibroblast_story_epidermis",91,51,116)
    line(91,59,91,113,FibroblastTissue.leader,1.15); disc(91,113,2.6,Self.coral,border: Self.cream)
    label("fibroblast_story_dermis",278,51,126)
    line(300,57,340,73,FibroblastTissue.leader,1.15); line(340,73,340,157,FibroblastTissue.leader,1.15)
    line(340,157,321,174,FibroblastTissue.leader,1.15); disc(321,174,2.6,Self.coral,border: Self.cream)
    label("fibroblast_story_collagen",88,323,138)
    line(88,308,88,235,FibroblastTissue.leader,1.15); disc(88,235,2.6,FibroblastTissue.collagen,border: Self.cream)
    label("fibroblast_story_fibroblast",244,323,134)
    line(244,308,244,287,FibroblastTissue.leader,1.15); line(244,287,184,216,FibroblastTissue.leader,1.15)
    disc(184,216,2.6,Self.violet,border: Self.cream)
  }
}
