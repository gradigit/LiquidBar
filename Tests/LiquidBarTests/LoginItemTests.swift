import Foundation
import Testing
@testable import LiquidBar

@Test func launchAgentPlistSerializationKeepsExecutablePathLiteral() throws {
    let craftedPath = "/tmp/Liquid</string><key>Program</key><string>/tmp/evil</string><key>ProgramArguments</key><array><string>/tmp/evil"
    let data = try LoginItem.launchAgentPlistData(executablePath: craftedPath)
    let plist = try #require(
        PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    )

    #expect(plist["Label"] as? String == LoginItem.label)
    #expect(plist["Program"] == nil)
    #expect(plist["ProgramArguments"] as? [String] == [craftedPath])
    #expect(plist["RunAtLoad"] as? Bool == true)
    #expect(plist["KeepAlive"] as? Bool == false)
}
