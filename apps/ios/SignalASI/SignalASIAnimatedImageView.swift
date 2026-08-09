import SwiftUI
import UIKit

struct SignalASIAnimatedImageView: UIViewRepresentable {
  let data: Data

  func makeUIView(context: Context) -> UIImageView {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.clipsToBounds = true
    imageView.accessibilityTraits = .image
    return imageView
  }

  func updateUIView(_ imageView: UIImageView, context: Context) {
    let identity = String(data.base64EncodedString().hashValue)
    guard imageView.accessibilityIdentifier != identity else { return }
    imageView.accessibilityIdentifier = identity
    imageView.stopAnimating()
    if let frames = AgentAnimatedImageTiming.frames(from: data) {
      imageView.animationImages = frames.images
      imageView.animationDuration = frames.duration
      imageView.animationRepeatCount = 0
      imageView.image = frames.images.first
      imageView.startAnimating()
    } else {
      imageView.animationImages = nil
      imageView.image = AgentAnimatedImageTiming.staticImage(from: data)
    }
  }
}
