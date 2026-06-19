import Foundation
import CoreGraphics
import Testing
@testable import LiquidBar

@Suite
struct SpacesServiceCurrentSpaceInfoTests {
    @Test func currentSpaceInfoMapsDisplaysByUUIDAndPreservesSpaceType() {
        let displayId: CGDirectDisplayID = 101
        let info = SpacesService.currentSpaceInfo(
            for: [displayId],
            displayUUIDByDisplayId: [displayId: "DISPLAY-UUID-1"],
            managedDisplaySpaces: [[
                "Display Identifier": "DISPLAY-UUID-1",
                "Current Space": [
                    "id64": 999_888,
                    "type": 4
                ]
            ]]
        )

        #expect(info[displayId] == SpacesService.CurrentSpaceInfo(key: "999888", type: 4))
    }

    @Test func currentSpaceInfoDefaultsMissingTypeToDesktop() {
        let displayId: CGDirectDisplayID = 202
        let info = SpacesService.currentSpaceInfo(
            for: [displayId],
            displayUUIDByDisplayId: [displayId: "DISPLAY-UUID-2"],
            managedDisplaySpaces: [[
                "Display Identifier": "DISPLAY-UUID-2",
                "Current Space": [
                    "id64": 123_456
                ]
            ]]
        )

        #expect(info[displayId] == SpacesService.CurrentSpaceInfo(key: "123456", type: SpacesService.CurrentSpaceInfo.desktopType))
    }

    @Test func currentSpaceInfoSkipsDisplaysWithoutMatchingUUID() {
        let info = SpacesService.currentSpaceInfo(
            for: [303],
            displayUUIDByDisplayId: [303: "DISPLAY-UUID-3"],
            managedDisplaySpaces: [[
                "Display Identifier": "DIFFERENT-UUID",
                "Current Space": [
                    "id64": 42,
                    "type": 1
                ]
            ]]
        )

        #expect(info.isEmpty)
    }
}
