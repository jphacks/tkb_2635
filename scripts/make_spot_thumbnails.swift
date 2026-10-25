#!/usr/bin/env swift
// 同梱3Dの地面写真から、観測地点を中心に800m四方を切り出す。通信はしない。
// 実行: swift scripts/make_spot_thumbnails.swift（macOS / Xcode の usdcat が必要）
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ThumbnailSpot: Decodable {
    let id: String
    let latitude: Double
    let longitude: Double
    let sceneId: String?
}
struct ThumbnailScene: Decodable {
    let id: String
    let originLatitude: Double
    let originLongitude: Double
}
struct GroundPhoto {
    let image: CGImage
    let west: Double
    let east: Double
    let south: Double
    let north: Double
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Packages/StarCore/Sources/StarCore/Resources")
let output = root.appendingPathComponent("App/Resources/SpotThumbnails")
let coverageMeters = 800.0
let pixels = 512

func run(_ executable: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "ThumbnailCommand", code: Int(process.terminationStatus))
    }
    return data
}

func ground(sceneId: String) throws -> GroundPhoto {
    let model = root.appendingPathComponent("App/Resources/City/City_\(sceneId).usdz").path
    let layer = String(decoding: try run("/usr/bin/usdcat", [model, "--flatten", "--mask", "/ground_night,/ground_photo"]), as: UTF8.self)
    let regex = try NSRegularExpression(pattern: #"point3f\[\] points = \[(.*?)\]"#)
    guard let match = regex.firstMatch(in: layer, range: NSRange(layer.startIndex..., in: layer)),
          let range = Range(match.range(at: 1), in: layer) else {
        throw NSError(domain: "GroundBoundsMissing", code: 1)
    }
    let numbers = layer[range].split { "(), ".contains($0) }.compactMap { Double($0) }
    guard numbers.count == 12 else { throw NSError(domain: "GroundBoundsInvalid", code: 1) }
    let data = try run("/usr/bin/unzip", ["-p", model, "textures/ground_photo.jpg"])
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "GroundImageMissing", code: 1)
    }
    return GroundPhoto(image: image, west: numbers[0], east: numbers[3], south: numbers[1], north: numbers[7])
}

let decoder = JSONDecoder()
let spots = try decoder.decode([ThumbnailSpot].self, from: Data(contentsOf: resources.appendingPathComponent("spots.json")))
let scenes = try decoder.decode([ThumbnailScene].self, from: Data(contentsOf: resources.appendingPathComponent("buildings.json")))
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var count = 0
// シーンごとに処理し、4Kの地面写真を全地点ぶん同時にメモリへ展開しない。
for scene in scenes {
    let matching = spots.filter { $0.sceneId == scene.id }
    guard !matching.isEmpty else { continue }
    let photo = try ground(sceneId: scene.id)
    for spot in matching {
        let east = (spot.longitude - scene.originLongitude) * 111_320 * cos(scene.originLatitude * .pi / 180)
        let north = (spot.latitude - scene.originLatitude) * 110_574
        let sx = Double(photo.image.width) / (photo.east - photo.west)
        let sy = Double(photo.image.height) / (photo.north - photo.south)
        let rect = CGRect(x: (east - coverageMeters / 2 - photo.west) * sx,
                          y: (photo.north - north - coverageMeters / 2) * sy,
                          width: coverageMeters * sx, height: coverageMeters * sy).integral
        guard CGRect(x: 0, y: 0, width: photo.image.width, height: photo.image.height).contains(rect),
              let crop = photo.image.cropping(to: rect),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw NSError(domain: "SpotOutsideGroundPhoto-\(spot.id)", code: 1)
        }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let url = output.appendingPathComponent("spot_\(spot.id).jpg")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "ThumbnailOutput", code: 1)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "ThumbnailWrite", code: 1) }
        count += 1
    }
}
guard count == spots.count else { throw NSError(domain: "SpotThumbnailCoverage", code: count) }
print("\(count)地点の航空写真（800m四方、512px）を作成しました")
