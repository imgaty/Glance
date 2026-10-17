//
//  main.swift
//  DeviceClips
//
//  Created by Gaty on 17/10/2026.
//

import AppKit

// Each model's turn, into Resources/Headphones: all of them, or those named.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let output = root.appending(path: "Resources/Headphones")
let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "dev.vibe.Glance.DeviceClips")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

let wanted = Set(CommandLine.arguments.dropFirst())
for model in models where wanted.isEmpty || wanted.contains(model.name) {
    // The maker's model, downloaded once.
    let file = cache.appending(path: "\(model.name).usdz")
    if !FileManager.default.fileExists(atPath: file.path) {
        let (downloaded, response) = try await URLSession.shared.download(from: model.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            print("\(model.name): couldn't download \(model.url)")
            continue
        }
        try FileManager.default.moveItem(at: downloaded, to: file)
    }
    guard let frames = Render.turn(model, from: file) else {
        print("\(model.name): couldn't draw it")
        continue
    }
    let clip = output.appending(path: "\(model.name).mov")
    try await Clip.write(frames, to: clip)
    let size = (try? FileManager.default.attributesOfItem(atPath: clip.path)[.size] as? Int) ?? 0
    print("\(model.name): \(frames[0].width)×\(frames[0].height), \(size / 1024) KB")
}
