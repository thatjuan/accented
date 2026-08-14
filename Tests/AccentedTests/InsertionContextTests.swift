@testable import Accented
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct InsertionContextTests {

    private let spanish = CharacterCatalog()

    @Test
    func precedingAtStartIsNil() {
        #expect(InsertionContextDecision.precedingCharacter(in: "abc", caretLocation: 0) == nil)
        #expect(InsertionContextDecision.precedingCharacter(in: "", caretLocation: 0) == nil)
    }

    @Test
    func precedingReadsOneCharacterBack() {
        #expect(InsertionContextDecision.precedingCharacter(in: "abc", caretLocation: 1) == "a")
        #expect(InsertionContextDecision.precedingCharacter(in: "abc", caretLocation: 3) == "c")
        #expect(InsertionContextDecision.precedingCharacter(in: "A", caretLocation: 1) == "A")
    }

    @Test
    func precedingNilWhenThereIsASelection() {
        #expect(InsertionContextDecision.precedingCharacter(in: "abc", caretLocation: 2, selectedLength: 1) == nil)
    }

    @Test
    func modeBrowseWhenNoPreceding() {
        #expect(InsertionContextDecision.mode(preceding: nil, catalog: spanish) == .browse)
        #expect(InsertionContextDecision.mode(preceding: " ", catalog: spanish) == .browse)
    }

    @Test
    func modeVariantsForEnabledBase() {
        #expect(InsertionContextDecision.mode(preceding: "a", catalog: spanish) == .variants(base: "a", uppercase: false))
        #expect(InsertionContextDecision.mode(preceding: "A", catalog: spanish) == .variants(base: "A", uppercase: true))
        #expect(InsertionContextDecision.mode(preceding: "n", catalog: spanish) == .variants(base: "n", uppercase: false))
    }

    @Test
    func modeBrowseForAlreadyAccentedOrUnknown() {
        #expect(InsertionContextDecision.mode(preceding: "á", catalog: spanish) == .browse)
        #expect(InsertionContextDecision.mode(preceding: "k", catalog: spanish) == .browse)
    }

    @Test
    func modeBrowseWhenSelectionIsNonEmpty() {
        #expect(InsertionContextDecision.mode(preceding: "a", selectedLength: 2, catalog: spanish) == .browse)
    }

    @Test
    func usageCountsRoundTripAndBump() {
        let suite = UserDefaults(suiteName: "com.thatjuan.accented.usage-tests")!
        suite.removePersistentDomain(forName: "com.thatjuan.accented.usage-tests")
        #expect(UsageCounts.load(from: suite).isEmpty)
        UsageCounts.bump("á", in: suite)
        UsageCounts.bump("Á", in: suite)
        UsageCounts.bump("é", in: suite)
        #expect(UsageCounts.load(from: suite)["á"] == 2)
        #expect(UsageCounts.load(from: suite)["é"] == 1)
    }
}

#else

enum InsertionLinkCheck {
    static let browse = InsertionContextDecision.mode(preceding: nil, catalog: CharacterCatalog())
}

#endif
