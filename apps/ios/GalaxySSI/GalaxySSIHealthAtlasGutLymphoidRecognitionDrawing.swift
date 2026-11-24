import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gutLymphoidRecognition(_ t: Double) {
    gutLymphoidSamplingAnatomy()
    let m = GalaxySSIHealthAtlasGutLymphoidMotion.self, approach = m.contact(t)
    let tx = 267-41*approach, ty = 258-34*approach, tip = 182+24*approach
    gutLymphoidDendritic(tip)
    oval(tx-20,ty-17,tx+20,ty+17,fill:0xB5D8CA,border:Self.teal)
    oval(tx-9,ty-10,tx+11,ty+10,fill:0x79AAA1,border:Self.teal); disc(tx-12,ty-8,2,Self.cream)
    let display = m.display(t)
    if display > 0 {
      let y = 222+8*(1-approach)
      line(tip-2,y+3,tip+2,y+3,0x895D84,1.8)
      gutLymphoidProtein(tip+1,y,2.7*display)
    }
    gutLymphoidRecognitionLabels(tx,ty)
  }
}
