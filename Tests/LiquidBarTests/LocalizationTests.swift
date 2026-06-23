import Foundation
import Testing
@testable import LiquidBar

@Suite("Localization")
struct LocalizationTests {
    @Test func koreanStringsResolveThroughPackageBundle() throws {
        #expect(L10n.tr("LiquidBar Preferences", localeIdentifier: "ko") == "LiquidBar 설정")
        #expect(L10n.tr("Show menu bar icon", localeIdentifier: "ko") == "메뉴 막대 아이콘 표시")
        #expect(L10n.tr("Version %@", localeIdentifier: "ko", "1.0.0") == "버전 1.0.0")
        #expect(L10n.tr("Update available: v%@", localeIdentifier: "ko", "1.0.1") == "업데이트 사용 가능: v1.0.1")
    }

    @Test func englishAndKoreanStringTablesHaveMatchingKeys() throws {
        let english = try loadStrings(localization: "en")
        let korean = try loadStrings(localization: "ko")

        #expect(Set(english.keys) == Set(korean.keys))
        #expect(english.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(korean.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Test func reviewedKoreanStringsUseNaturalProductTerminology() throws {
        let korean = try loadStrings(localization: "ko")

        #expect(korean["Preferences…"] == "설정…")
        #expect(korean["Auto-hide macOS Dock"] == "macOS Dock 자동 숨김")
        #expect(korean["Input Monitoring:"] == "입력 모니터링:")
        #expect(korean["Screen Recording:"] == "화면 기록:")
        #expect(korean["Open Settings"] == "설정 열기")
        #expect(korean["Quit LiquidBar"] == "LiquidBar 종료")
        #expect(korean["Language:"] == "언어:")
        #expect(korean["English"] == "영어")
        #expect(korean["Korean"] == "한국어")
        #expect(korean["CPU"] == "CPU")
        #expect(korean["GPU"] == "GPU")
        #expect(korean["RAM"] == "RAM")
    }

    private func loadStrings(localization: String) throws -> [String: String] {
        let url = try #require(L10n.resourceURL(forLocalization: localization))
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: String])
    }
}
