import Testing
@testable import LiquidBar

@Suite("Command Types")
struct CommandTypesTests {
    // MARK: - ContextAction

    @Test func testContextActionRawValues() {
        #expect(ContextAction.close.rawValue == 0)
        #expect(ContextAction.pin.rawValue == 1)
        #expect(ContextAction.unpin.rawValue == 2)
        #expect(ContextAction.blacklist.rawValue == 3)

        #expect(ContextAction.createTabGroup.rawValue == 10)
        #expect(ContextAction.addToTabGroup.rawValue == 11)
        #expect(ContextAction.removeFromTabGroup.rawValue == 12)
        #expect(ContextAction.renameTabGroup.rawValue == 13)
        #expect(ContextAction.deleteTabGroup.rawValue == 14)
        #expect(ContextAction.setTabGroupColor.rawValue == 15)

        #expect(ContextAction.openCustomItem.rawValue == 20)
        #expect(ContextAction.editCustomItem.rawValue == 21)
        #expect(ContextAction.deleteCustomItem.rawValue == 22)

        #expect(ContextAction.renameWindow.rawValue == 40)
        #expect(ContextAction.setWindowColor.rawValue == 41)
        #expect(ContextAction.resetWindowTitle.rawValue == 42)
        #expect(ContextAction.resetWindowColor.rawValue == 43)
    }

    @Test func testContextActionFromRawValue() {
        #expect(ContextAction(rawValue: 0) == .close)
        #expect(ContextAction(rawValue: 1) == .pin)
        #expect(ContextAction(rawValue: 2) == .unpin)
        #expect(ContextAction(rawValue: 3) == .blacklist)
        #expect(ContextAction(rawValue: 10) == .createTabGroup)
        #expect(ContextAction(rawValue: 14) == .deleteTabGroup)
        #expect(ContextAction(rawValue: 15) == .setTabGroupColor)
        #expect(ContextAction(rawValue: 20) == .openCustomItem)
        #expect(ContextAction(rawValue: 22) == .deleteCustomItem)
        #expect(ContextAction(rawValue: 40) == .renameWindow)
        #expect(ContextAction(rawValue: 43) == .resetWindowColor)
        #expect(ContextAction(rawValue: 99) == nil)
    }

    // MARK: - AppContextAction

    @Test func testAppContextActionRawValues() {
        #expect(AppContextAction.openPreferences.rawValue == 30)
        #expect(AppContextAction.reloadConfig.rawValue == 31)
        #expect(AppContextAction.quit.rawValue == 32)
    }

    @Test func testAppContextActionFromRawValue() {
        #expect(AppContextAction(rawValue: 30) == .openPreferences)
        #expect(AppContextAction(rawValue: 31) == .reloadConfig)
        #expect(AppContextAction(rawValue: 32) == .quit)
        #expect(AppContextAction(rawValue: 99) == nil)
    }

    // MARK: - Command

    @Test func testCommandShutdown() {
        let cmd = Command.shutdown
        if case .shutdown = cmd {
            // pass
        } else {
            Issue.record("Expected .shutdown")
        }
    }

    @Test func testCommandClick() {
        let cmd = Command.click(screenId: 1, index: 3, button: .left)
        if case .click(let screenId, let index, let button) = cmd {
            #expect(screenId == 1)
            #expect(index == 3)
            if case .left = button {} else { Issue.record("Expected .left") }
        } else {
            Issue.record("Expected .click")
        }
    }

    @Test func testCommandReorder() {
        let cmd = Command.reorder(screenId: 2, from: 0, to: 3)
        if case .reorder(let screenId, let from, let to) = cmd {
            #expect(screenId == 2)
            #expect(from == 0)
            #expect(to == 3)
        } else {
            Issue.record("Expected .reorder")
        }
    }

    @Test func testCommandContextAction() {
        let cmd = Command.contextAction(screenId: 1, index: 2, action: .pin)
        if case .contextAction(let screenId, let index, let action) = cmd {
            #expect(screenId == 1)
            #expect(index == 2)
            #expect(action == .pin)
        } else {
            Issue.record("Expected .contextAction")
        }
    }

    // MARK: - MouseButton

    @Test func testMouseButtonCases() {
        let buttons: [MouseButton] = [.left, .middle, .right]
        #expect(buttons.count == 3)
    }
}
