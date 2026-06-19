#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct DiffConfig {
    var perChannelThreshold: UInt8 = 8
    var maxChangedPercent: Double = 0.5
}

struct DiffResult: Codable {
    var file: String
    var width: Int
    var height: Int
    var changedPixels: Int
    var totalPixels: Int
    var changedPercent: Double
}

func loadRGBA(url: URL) throws -> (width: Int, height: Int, bytes: [UInt8]) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "pixel_diff", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image: \(url.path)"])
    }

    let width = img.width
    let height = img.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    try bytes.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else {
            throw NSError(domain: "pixel_diff", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap context"])
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    return (width: width, height: height, bytes: bytes)
}

func writePNG(width: Int, height: Int, rgba: [UInt8], to url: URL) throws {
    let cfdata = Data(rgba) as CFData
    guard let provider = CGDataProvider(data: cfdata) else {
        throw NSError(domain: "pixel_diff", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider"])
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    guard let img = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: cs,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw NSError(domain: "pixel_diff", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
    }

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "pixel_diff", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
    }
    CGImageDestinationAddImage(dest, img, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "pixel_diff", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG: \(url.path)"])
    }
}

func diffImages(baseline: URL, candidate: URL, outDiff: URL?, config: DiffConfig) throws -> DiffResult {
    let b = try loadRGBA(url: baseline)
    let c = try loadRGBA(url: candidate)

    let total = max(1, b.width * b.height)
    var changed = 0

    if b.width != c.width || b.height != c.height {
        changed = total
        return DiffResult(
            file: candidate.lastPathComponent,
            width: c.width,
            height: c.height,
            changedPixels: changed,
            totalPixels: total,
            changedPercent: 100.0
        )
    }

    var diff: [UInt8]? = outDiff == nil ? nil : [UInt8](repeating: 0, count: b.bytes.count)
    let thr = Int(config.perChannelThreshold)

    for i in stride(from: 0, to: b.bytes.count, by: 4) {
        let dr = abs(Int(b.bytes[i + 0]) - Int(c.bytes[i + 0]))
        let dg = abs(Int(b.bytes[i + 1]) - Int(c.bytes[i + 1]))
        let db = abs(Int(b.bytes[i + 2]) - Int(c.bytes[i + 2]))
        let da = abs(Int(b.bytes[i + 3]) - Int(c.bytes[i + 3]))
        let isChanged = (dr > thr) || (dg > thr) || (db > thr) || (da > thr)
        if isChanged { changed += 1 }

        if diff != nil {
            if isChanged {
                diff![i + 0] = 255
                diff![i + 1] = 0
                diff![i + 2] = 0
                diff![i + 3] = 255
            } else {
                // Dim the candidate so deltas are obvious.
                diff![i + 0] = UInt8(Int(c.bytes[i + 0]) / 2)
                diff![i + 1] = UInt8(Int(c.bytes[i + 1]) / 2)
                diff![i + 2] = UInt8(Int(c.bytes[i + 2]) / 2)
                diff![i + 3] = 255
            }
        }
    }

    let percent = (Double(changed) / Double(total)) * 100.0
    if let outDiff, let diffBytes = diff, changed > 0 {
        try FileManager.default.createDirectory(at: outDiff.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writePNG(width: b.width, height: b.height, rgba: diffBytes, to: outDiff)
    }

    return DiffResult(
        file: candidate.lastPathComponent,
        width: b.width,
        height: b.height,
        changedPixels: changed,
        totalPixels: total,
        changedPercent: percent
    )
}

func listPNGFiles(in dir: URL) throws -> [URL] {
    guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
    var out: [URL] = []
    for case let url as URL in e {
        let ext = url.pathExtension.lowercased()
        if ext == "png" || ext == "jpg" || ext == "jpeg" { out.append(url) }
    }
    return out.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func usageAndExit() -> Never {
    fputs("""
    usage:
      pixel_diff.swift --baseline-dir <dir> --candidate-dir <dir> --diff-dir <dir> [--max-changed-percent 0.5] [--per-channel-threshold 8]

    notes:
      - Fails if any baseline is missing or any diff exceeds threshold.
      - Writes per-image diff PNGs into --diff-dir for images with changed pixels.

    """, stderr)
    exit(2)
}

let args = CommandLine.arguments.dropFirst()
func argValue(_ name: String) -> String? {
    guard let idx = args.firstIndex(of: name) else { return nil }
    let next = args.index(after: idx)
    guard next < args.endIndex else { return nil }
    return String(args[next])
}

guard let baselineDirStr = argValue("--baseline-dir"),
      let candidateDirStr = argValue("--candidate-dir"),
      let diffDirStr = argValue("--diff-dir") else {
    usageAndExit()
}

var config = DiffConfig()
if let maxStr = argValue("--max-changed-percent"), let v = Double(maxStr) {
    config.maxChangedPercent = v
}
if let thrStr = argValue("--per-channel-threshold"), let v = Int(thrStr), v >= 0, v <= 255 {
    config.perChannelThreshold = UInt8(v)
}

let baselineDir = URL(fileURLWithPath: baselineDirStr, isDirectory: true)
let candidateDir = URL(fileURLWithPath: candidateDirStr, isDirectory: true)
let diffDir = URL(fileURLWithPath: diffDirStr, isDirectory: true)

let baselineFiles = try listPNGFiles(in: baselineDir)
let candidateFiles = try listPNGFiles(in: candidateDir)

let baselineNames = Set(baselineFiles.map { $0.lastPathComponent })
let candidateNames = Set(candidateFiles.map { $0.lastPathComponent })

var failures: [String] = []

let missingBaselines = candidateNames.subtracting(baselineNames).sorted()
if !missingBaselines.isEmpty {
    failures.append("Missing baselines:\n  - " + missingBaselines.joined(separator: "\n  - "))
}

let staleBaselines = baselineNames.subtracting(candidateNames).sorted()
if !staleBaselines.isEmpty {
    failures.append("Baselines with no matching current screenshot:\n  - " + staleBaselines.joined(separator: "\n  - "))
}

var results: [DiffResult] = []
for candidate in candidateFiles {
    let name = candidate.lastPathComponent
    guard baselineNames.contains(name) else { continue }
    let base = baselineDir.appendingPathComponent(name)
    let outDiff = diffDir.appendingPathComponent(name)
    let r = try diffImages(baseline: base, candidate: candidate, outDiff: outDiff, config: config)
    results.append(r)

    if r.changedPercent > config.maxChangedPercent {
        failures.append(String(format: "Diff too large: %@ changed=%.3f%% (max=%.3f%%)", name, r.changedPercent, config.maxChangedPercent))
    }
}

// Write a small JSON report for visual regression debugging.
let reportURL = diffDir.appendingPathComponent("report.json")
try FileManager.default.createDirectory(at: diffDir, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(results).write(to: reportURL, options: .atomic)

if !failures.isEmpty {
    fputs("Visual regression failures:\n", stderr)
    for f in failures {
        fputs("- \(f)\n", stderr)
    }
    fputs("Diff report: \(reportURL.path)\n", stderr)
    exit(1)
}

print("Visual regression OK (\(results.count) image(s)). Report: \(reportURL.path)")
