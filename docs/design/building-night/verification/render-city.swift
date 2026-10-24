import Metal
import ImageIO
import UniformTypeIdentifiers
extension Sky3DView {
 func verificationRoot() -> Entity {
  let root = Entity()
  BuildingNightRenderer.shared.configureEnvironment(in:root)
  buildScene(into:root)
  return root
 }
}
let spotContext = try SeedData.loadContexts().first { $0.id == "shibuya_sky" }!
let date = ISO8601DateFormatter().date(from:"2026-10-24T12:00:00Z")!
let prediction = Recommender.evaluate(spotContext,target:.moon,date:date,weather:nil)
let view = Sky3DView(context:spotContext,prediction:prediction,date:date)
let renderer = try RealityRenderer()
renderer.cameraSettings.colorBackground = .color(CGColor(red:0.02,green:0.03,blue:0.07,alpha:1))
let root = view.verificationRoot()
let camera = PerspectiveCamera()
camera.camera.fieldOfViewInDegrees = 55
let yaw:Float = .pi/5, pitch:Float = 0.35
camera.look(at:[0,1.2,0],from:SIMD3<Float>(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*10,relativeTo:nil)
root.addChild(camera)
renderer.entities.append(root)
renderer.activeCamera = camera
let device = MTLCreateSystemDefaultDevice()!
let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm_srgb,width:1200,height:900,mipmapped:false)
description.usage = [.renderTarget,.shaderRead]
description.storageMode = .shared
let texture = device.makeTexture(descriptor:description)!
let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture:texture))
for _ in 0..<3 {
 try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
  do { try renderer.updateAndRender(deltaTime:1.0/60.0,cameraOutput:output,onComplete:{ _ in continuation.resume() }) }
  catch { continuation.resume(throwing:error) }
 }
}
var pixels = [UInt8](repeating:0,count:1200*900*4)
texture.getBytes(&pixels,bytesPerRow:4800,from:MTLRegionMake2D(0,0,1200,900),mipmapLevel:0)
let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
let context = CGContext(data:&pixels,width:1200,height:900,bitsPerComponent:8,bytesPerRow:4800,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:info)!
let url = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("astera-realitykit-city-after.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(destination,context.makeImage()!,nil)
print("RENDER_IMAGE",url.path,CGImageDestinationFinalize(destination))
