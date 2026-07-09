import CoreGraphics
import Foundation
import Testing
@testable import LiquidBar

@Suite("WindowServerSurface")
struct WindowServerSurfaceTests {
    @Test func parsesCommonCGWindowDictionaryTypes() throws {
        let dict: [CFString: Any] = [
            kCGWindowOwnerPID as CFString: NSNumber(value: 42),
            kCGWindowNumber as CFString: NSNumber(value: 1001),
            kCGWindowOwnerName as CFString: "Firefox",
            kCGWindowName as CFString: "Bybit API",
            kCGWindowLayer as CFString: NSNumber(value: 0),
            kCGWindowIsOnscreen as CFString: NSNumber(value: true),
            kCGWindowBounds as CFString: [
                "X": 10.0,
                "Y": 20.0,
                "Width": 300.0,
                "Height": 200.0,
            ],
        ]

        let surface = try #require(WindowServerSurface(dict))

        #expect(surface.pid == 42)
        #expect(surface.windowId == 1001)
        #expect(surface.ownerName == "Firefox")
        #expect(surface.title == "Bybit API")
        #expect(surface.layer == 0)
        #expect(surface.isOnscreen)
        #expect(surface.frame == CGRect(x: 10, y: 20, width: 300, height: 200))
        #expect(surface.bounds.width == 300)
    }

    @Test func parsesCoreGraphicsBoundsDictionary() throws {
        let cgBounds = try #require(CGRectCreateDictionaryRepresentation(
            CGRect(x: 1, y: 2, width: 640, height: 480)
        ) as NSDictionary?)
        let dict: [CFString: Any] = [
            kCGWindowOwnerPID as CFString: Int32(7),
            kCGWindowNumber as CFString: UInt32(8),
            kCGWindowBounds as CFString: cgBounds,
        ]

        let surface = try #require(WindowServerSurface(dict))

        #expect(surface.pid == 7)
        #expect(surface.windowId == 8)
        #expect(surface.frame == CGRect(x: 1, y: 2, width: 640, height: 480))
        #expect(surface.layer == 0)
        #expect(!surface.isOnscreen)
    }

    @Test func rejectsSurfacesWithoutIdentityOrBounds() {
        let missingWindowId: [CFString: Any] = [
            kCGWindowOwnerPID as CFString: Int32(7),
            kCGWindowBounds as CFString: ["X": 0.0, "Y": 0.0, "Width": 1.0, "Height": 1.0],
        ]
        let missingBounds: [CFString: Any] = [
            kCGWindowOwnerPID as CFString: Int32(7),
            kCGWindowNumber as CFString: UInt32(8),
        ]

        #expect(WindowServerSurface(missingWindowId) == nil)
        #expect(WindowServerSurface(missingBounds) == nil)
    }
}
