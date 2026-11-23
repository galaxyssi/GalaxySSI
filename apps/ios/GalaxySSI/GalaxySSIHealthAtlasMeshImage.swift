import SwiftUI
import UIKit
import MetalKit

struct GalaxySSIHealthAtlasMeshImage: UIViewRepresentable {
  let asset: String
  let logicalSize: CGSize
  let vertices: [CGPoint]
  let columns: Int
  let rows: Int
  func makeUIView(context: Context) -> Host { Host(asset: asset, logicalSize: logicalSize, columns: columns, rows: rows) }
  func updateUIView(_ view: Host, context: Context) { view.update(vertices) }

  final class Host: UIView {
    private let image: UIImage?
    private let logicalSize: CGSize
    private let source: [CGPoint]
    private let indices: [UInt16]
    private var vertices: [CGPoint] = []
    private var metal: MTKView?
    private var renderer: Renderer?
    init(asset: String, logicalSize: CGSize, columns: Int, rows: Int) {
      image = UIImage(named: asset); self.logicalSize = logicalSize
      source = GalaxySSIHealthAtlasImageMesh.sourcePoints(columns: columns, rows: rows, size: logicalSize)
      indices = GalaxySSIHealthAtlasImageMesh.indices(columns: columns, rows: rows)
      super.init(frame: .zero)
      isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
      if let image, let device = MTLCreateSystemDefaultDevice(),
         let renderer = try? Renderer(device: device, image: image, source: source, logicalSize: logicalSize, indices: indices) {
        let view = MTKView(frame: .zero, device: device)
        view.isPaused = true; view.enableSetNeedsDisplay = false; view.isOpaque = false; view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0); view.colorPixelFormat = .bgra8Unorm
        view.delegate = renderer
        self.renderer = renderer; metal = view; addSubview(view)
      }
    }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
      super.layoutSubviews(); metal?.frame = bounds; metal?.draw()
    }
    func update(_ points: [CGPoint]) {
      guard points.count == source.count, !points.isEmpty, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
      vertices = points
      if let metal, let renderer { renderer.vertices = points; metal.draw() }
      else { setNeedsDisplay() }
    }
    override func draw(_ rect: CGRect) {
      guard metal == nil, let image, let context = UIGraphicsGetCurrentContext(), vertices.count == source.count,
        logicalSize.width > 0, logicalSize.height > 0 else { return }
      // Same triangle mesh if Metal is unavailable; never silently replace it with a static image.
      let destination = vertices.map { CGPoint(x: $0.x * bounds.width / logicalSize.width, y: $0.y * bounds.height / logicalSize.height) }
      context.interpolationQuality = .medium; context.setShouldAntialias(false)
      for triangle in stride(from: 0, to: indices.count, by: 3) {
        let ids = (0..<3).map { Int(indices[triangle + $0]) }
        let src = ids.map { source[$0] }, dst = ids.map { destination[$0] }
        guard let transform = GalaxySSIHealthAtlasImageMesh.transform(source: src, destination: dst) else { continue }
        context.saveGState(); context.beginPath()
        context.move(to: dst[0]); context.addLine(to: dst[1]); context.addLine(to: dst[2]); context.closePath()
        context.clip(); context.concatenate(transform)
        image.draw(in: CGRect(origin: .zero, size: logicalSize))
        context.restoreGState()
      }
    }
  }

  final class Renderer: NSObject, MTKViewDelegate {
    private struct Vertex { let position: SIMD2<Float>; let uv: SIMD2<Float> }
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let texture: MTLTexture
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private let source: [CGPoint]
    private let logicalSize: CGSize
    var vertices: [CGPoint] = []
    private enum Failure: Error { case unavailable }
    init(device: MTLDevice, image: UIImage, source: [CGPoint], logicalSize: CGSize, indices: [UInt16]) throws {
      guard let cgImage = image.cgImage, let queue = device.makeCommandQueue(), !source.isEmpty, !indices.isEmpty else { throw Failure.unavailable }
      let library = try device.makeDefaultLibrary(bundle: Bundle(for: GalaxySSIStore.self))
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "galaxyssiAtlasMeshVertex")
      descriptor.fragmentFunction = library.makeFunction(name: "galaxyssiAtlasMeshFragment")
      let color = descriptor.colorAttachments[0]!
      color.pixelFormat = .bgra8Unorm; color.isBlendingEnabled = true
      color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
      color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      self.device = device; self.queue = queue; pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
      texture = try Self.makeTexture(device: device, image: cgImage)
      guard let buffer = indices.withUnsafeBufferPointer({ pointer in
        device.makeBuffer(bytes: pointer.baseAddress!, length: pointer.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)
      }) else { throw Failure.unavailable }
      indexBuffer = buffer; indexCount = indices.count; self.source = source; self.logicalSize = logicalSize
      super.init()
    }
    private static func makeTexture(device: MTLDevice, image: CGImage) throws -> MTLTexture {
      let width = image.width, height = image.height
      guard width > 0, height > 0, width <= 8192, height <= 8192 else { throw Failure.unavailable }
      let rowBytes = width * 4
      let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
      guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info),
        let bytes = context.data else { throw Failure.unavailable }
      // Top-left texture coordinates, known premultiplied RGBA, decoded only once.
      context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
      context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
        width: width, height: height, mipmapped: false)
      descriptor.storageMode = .shared; descriptor.usage = .shaderRead
      guard let texture = device.makeTexture(descriptor: descriptor) else { throw Failure.unavailable }
      texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
        withBytes: bytes, bytesPerRow: rowBytes)
      return texture
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
      guard vertices.count == source.count, logicalSize.width > 0, logicalSize.height > 0,
        let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
        let command = queue.makeCommandBuffer() else { return }
      let values = zip(vertices, source).map { point, uv in
        Vertex(position: SIMD2(Float(point.x / logicalSize.width * 2 - 1), Float(1 - point.y / logicalSize.height * 2)),
          uv: SIMD2(Float(uv.x / logicalSize.width), Float(uv.y / logicalSize.height)))
      }
      // Each command retains an immutable vertex buffer until GPU completion.
      guard let buffer = values.withUnsafeBufferPointer({ pointer in
        device.makeBuffer(bytes: pointer.baseAddress!, length: pointer.count * MemoryLayout<Vertex>.stride, options: .storageModeShared)
      }), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
      encoder.setRenderPipelineState(pipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0); encoder.setFragmentTexture(texture, index: 0)
      encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
      encoder.endEncoding(); command.present(drawable); command.commit()
    }
  }
}
