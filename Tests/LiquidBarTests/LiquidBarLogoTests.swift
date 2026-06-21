import AppKit
import Testing
@testable import LiquidBar

@Suite
@MainActor
struct LiquidBarLogoTests {
    @Test func appIconRendersAtRequestedSize() throws {
        let image = LiquidBarLogo.makeAppIcon(size: NSSize(width: 128, height: 128))

        #expect(image.size == NSSize(width: 128, height: 128))
        let tiff = try #require(image.tiffRepresentation)
        #expect(!tiff.isEmpty)
    }

    @Test func applicationIconFallsBackToGeneratedRenderer() throws {
        let image = LiquidBarLogo.makeApplicationIcon(bundle: Bundle(for: EmptyBundleToken.self))

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(image.accessibilityDescription == "LiquidBar")
        let tiff = try #require(image.tiffRepresentation)
        #expect(!tiff.isEmpty)
    }

    @Test func highResolutionLogoAssetsArePresent() throws {
        let root = repositoryRoot()
        let expectedPNGs: [(String, Int)] = [
            ("Assets/Brand/liquidbar-logo-1024.png", 1024),
            ("Assets/Brand/liquidbar-logo-512.png", 512),
            ("Assets/Brand/liquidbar-logo-256.png", 256),
            ("Assets/Brand/liquidbar-logo-128.png", 128),
            ("Assets/Brand/liquidbar-logo-64.png", 64),
            ("Assets/Brand/liquidbar-logo-32.png", 32),
            ("Assets/Brand/liquidbar-logo-16.png", 16),
            ("Assets/AppIcon/LiquidBar.iconset/icon_512x512@2x.png", 1024),
            ("Assets/AppIcon/LiquidBar.iconset/icon_512x512.png", 512),
            ("Assets/AppIcon/LiquidBar.iconset/icon_16x16.png", 16),
        ]

        for (relativePath, expectedSize) in expectedPNGs {
            let url = root.appendingPathComponent(relativePath)
            let rep = try bitmapRep(at: url)
            #expect(rep.pixelsWide == expectedSize)
            #expect(rep.pixelsHigh == expectedSize)
            #expect(rep.hasAlpha)
            #expect(try cornerAlpha(in: rep) == 0.0)
        }

        let icns = root.appendingPathComponent("Assets/AppIcon/LiquidBar.icns")
        #expect(FileManager.default.fileExists(atPath: icns.path))
        #expect(try Data(contentsOf: icns).isEmpty == false)
        let image = try #require(NSImage(contentsOf: icns))
        #expect(image.representations.contains { $0.pixelsWide == 1024 && $0.pixelsHigh == 1024 })
    }

    @Test func transparentBrandBarAssetIsPresent() throws {
        let root = repositoryRoot()
        let url = root.appendingPathComponent("Assets/Brand/liquidbar-brand-bar-transparent.png")
        let rep = try bitmapRep(at: url)

        #expect(rep.pixelsWide == 1562)
        #expect(rep.pixelsHigh == 376)
        #expect(rep.hasAlpha)
        #expect(try cornerAlpha(in: rep) == 0.0)
        #expect(Double(rep.pixelsWide) / Double(rep.pixelsHigh) > 4.0)

        let bbox = try alphaBoundingBox(in: rep)
        #expect(bbox.width > bbox.height * 3.5)
        #expect(bbox.minX > 0)
        #expect(bbox.minY > 0)
    }

    @Test func brandBarImageFallsBackToGeneratedRenderer() throws {
        let size = NSSize(width: 280, height: 68)
        let image = LiquidBarLogo.makeBrandBarImage(
            bundle: Bundle(for: EmptyBundleToken.self),
            displaySize: size
        )

        #expect(image.size == size)
        #expect(image.accessibilityDescription == "LiquidBar")
        let tiff = try #require(image.tiffRepresentation)
        #expect(!tiff.isEmpty)
    }

    @Test func menuBarGlyphIsTemplateImage() throws {
        let image = LiquidBarLogo.makeMenuBarTemplateImage()

        #expect(image.size == LiquidBarLogo.menuBarTemplateSize)
        #expect(LiquidBarLogo.menuBarStatusItemLength > LiquidBarLogo.menuBarTemplateSize.width)
        #expect(image.isTemplate)
        let tiff = try #require(image.tiffRepresentation)
        #expect(!tiff.isEmpty)
    }

    @Test func generatedMenuBarTemplateAssetUsesHorizontalBarFootprint() throws {
        let root = repositoryRoot()
        let url = root.appendingPathComponent("Assets/MenuBar/liquidbar-menubar-template.png")
        let rep = try bitmapRep(at: url)

        #expect(rep.pixelsWide == 112)
        #expect(rep.pixelsHigh == 72)
        #expect(rep.hasAlpha)

        let bbox = try alphaBoundingBox(in: rep)
        #expect(bbox.minX >= 3)
        #expect(bbox.minX <= 5)
        #expect(bbox.maxX >= 106)
        #expect(bbox.maxX <= 108)
        #expect(bbox.minY >= 14)
        #expect(bbox.minY <= 16)
        #expect(bbox.maxY >= 56)
        #expect(bbox.maxY <= 58)
        #expect(bbox.height >= 41)
        #expect(bbox.height <= 43)
    }

    @Test func logoSnapshotsCanBeExportedForVisualQA() throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["LIQUIDBAR_LOGO_VISUAL_QA_DIR"],
              !outputDirectory.isEmpty else { return }

        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try writePNG(
            LiquidBarLogo.makeAppIcon(size: NSSize(width: 256, height: 256)),
            to: directory.appendingPathComponent("liquidbar-app-icon.png")
        )
        try writePNG(
            LiquidBarLogo.makeMenuBarTemplateImage(size: NSSize(width: 64, height: 64)),
            to: directory.appendingPathComponent("liquidbar-menu-template.png")
        )
        try writePNG(
            LiquidBarLogo.makeMenuBarTemplateImage(size: NSSize(width: 18, height: 18)),
            to: directory.appendingPathComponent("liquidbar-menu-template-18.png")
        )
        try writePNG(
            LiquidBarLogo.makeMenuBarTemplateImage(),
            to: directory.appendingPathComponent("liquidbar-menu-template-status-item.png")
        )
        try writePNG(
            LiquidBarLogo.makeBrandBarImage(displaySize: NSSize(width: 320, height: 78)),
            to: directory.appendingPathComponent("liquidbar-brand-bar.png")
        )
        let menuBarTemplateAsset = try #require(NSImage(
            contentsOf: repositoryRoot().appendingPathComponent("Assets/MenuBar/liquidbar-menubar-template.png")
        ))
        menuBarTemplateAsset.size = LiquidBarLogo.menuBarTemplateSize
        menuBarTemplateAsset.isTemplate = true
        try writePNG(
            menuBarTemplateAsset,
            to: directory.appendingPathComponent("liquidbar-menu-template-asset.png")
        )
    }

    private func writePNG(_ image: NSImage, to url: URL) throws {
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func bitmapRep(at url: URL) throws -> NSBitmapImageRep {
        let data = try Data(contentsOf: url)
        return try #require(NSBitmapImageRep(data: data))
    }

    private func cornerAlpha(in rep: NSBitmapImageRep) throws -> CGFloat {
        let color = try #require(rep.colorAt(x: 0, y: 0))
        return color.alphaComponent
    }

    private func alphaBoundingBox(in rep: NSBitmapImageRep) throws -> CGRect {
        var minX = rep.pixelsWide
        var minY = rep.pixelsHigh
        var maxX = -1
        var maxY = -1

        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let alpha = try #require(rep.colorAt(x: x, y: y)).alphaComponent
                guard alpha > 0.01 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        #expect(maxX >= minX)
        #expect(maxY >= minY)
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private final class EmptyBundleToken {}
}
