import Testing
import Carbon
@testable import LiquidBar

@Suite("HotkeyShortcut")
struct HotkeyShortcutTests {
    @Test func testParseOptionTab() {
        let shortcut = HotkeyShortcut.parse("option+tab")
        #expect(shortcut != nil)
        #expect(shortcut?.keyCode == UInt32(kVK_Tab))
    }

    @Test func testParseCommandShiftK() {
        let shortcut = HotkeyShortcut.parse("cmd+shift+k")
        #expect(shortcut != nil)
        #expect(shortcut?.keyCode == UInt32(kVK_ANSI_K))
    }

    @Test func testParseRequiresModifierAndKey() {
        #expect(HotkeyShortcut.parse("tab") == nil)
        #expect(HotkeyShortcut.parse("option") == nil)
        #expect(HotkeyShortcut.parse("garbage+unknown") == nil)
    }
}
