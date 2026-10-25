import ImageIO
import UniformTypeIdentifiers
let scene = try SeedData.loadScenes().first { $0.id == "shibuya" }!
let building = scene.buildings.first { $0.id == "bldg_7b006717-e9e6-4a94-8843-1f4ce13b2509" }!
let renderer = try RealityRenderer()
renderer.cameraSettings.colorBackground = .color(CGColor(red:0.02,green:0.03,blue:0.07,alpha:1))
let root = Entity()
BuildingNightRenderer.shared.configureEnvironment(in:root)
let box = BuildingNightRenderer.shared.entity(for:building,scale:0.01,isHost:false)
box.position.y = Float(building.height)*0.005
root.addChild(box)
let ground = ModelEntity(mesh:.generatePlane(width:8,depth:8),materials:[SimpleMaterial(color:.init(red:0.07,green:0.09,blue:0.13,alpha:1),isMetallic:false)])
root.addChild(ground)
let light = DirectionalLight()
light.light.intensity = 700
light.light.color = .init(red:0.77,green:0.85,blue:1,alpha:1)
light.look(at:[0,1,0],from:[3,5,4],relativeTo:nil)
root.addChild(light)
let fill = DirectionalLight()
fill.light.intensity = 220
fill.look(at:[0,1,0],from:[-3,3,-2],relativeTo:nil)
root.addChild(fill)
let camera = PerspectiveCamera()
camera.camera.fieldOfViewInDegrees = 48
camera.look(at:[0,1,0],from:[2,1.8,3],relativeTo:nil)
root.addChild(camera)
renderer.entities.append(root)
renderer.activeCamera = camera
let device = MTLCreateSystemDefaultDevice()!
let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm_srgb,width:1000,height:1000,mipmapped:false)
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
var pixels = [UInt8](repeating:0,count:1000*1000*4)
texture.getBytes(&pixels,bytesPerRow:4000,from:MTLRegionMake2D(0,0,1000,1000),mipmapLevel:0)
let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
let context = CGContext(data:&pixels,width:1000,height:1000,bitsPerComponent:8,bytesPerRow:4000,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:info)!
let url = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("astera-realitykit-facade-after.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(destination,context.makeImage()!,nil)
print("RENDER_IMAGE",url.path,CGImageDestinationFinalize(destination))
