import Foundation
import Testing
@testable import Marcdown

struct MergeTests {
    @Test func separateEditsMergeCleanly() {
        let result = Merge.merge(
            base: "one\ntwo\nthree\n",
            mine: "ONE\ntwo\nthree\n",
            theirs: "one\ntwo\nTHREE\n"
        )
        #expect(result == Merge.Result(text: "ONE\ntwo\nTHREE\n", conflicts: 0))
    }

    @Test func insertionsOnBothSidesMergeCleanly() {
        let result = Merge.merge(
            base: "a\nb\n",
            mine: "mine\na\nb\n",
            theirs: "a\nb\ntheirs\n"
        )
        #expect(result == Merge.Result(text: "mine\na\nb\ntheirs\n", conflicts: 0))
    }

    @Test func sameEditOnBothSidesIsNoConflict() {
        let result = Merge.merge(base: "a\nb\n", mine: "a\nB\n", theirs: "a\nB\n")
        #expect(result == Merge.Result(text: "a\nB\n", conflicts: 0))
    }

    @Test func deletionMerges() {
        let result = Merge.merge(base: "a\nb\nc\nd\n", mine: "a\nc\nd\n", theirs: "a\nb\nc\nD\n")
        #expect(result == Merge.Result(text: "a\nc\nD\n", conflicts: 0))
    }

    @Test func separateWordsInOneLineMergeCleanly() {
        let result = Merge.merge(
            base: "The quick brown fox.\n",
            mine: "The slow brown fox.\n",
            theirs: "The quick brown cat.\n"
        )
        #expect(result == Merge.Result(text: "The slow brown cat.\n", conflicts: 0))
    }

    @Test func sameWordEditedTwiceConflictsInline() {
        let result = Merge.merge(
            base: "Wir treffen uns am Montag um 10 im Büro.\n",
            mine: "Wir treffen uns am Montag um 11 im Büro.\n",
            theirs: "Wir treffen uns am Dienstag um 9 im Büro.\n"
        )
        #expect(result == Merge.Result(text: "Wir treffen uns am Dienstag um 👤 11 🔀 9 💾 im Büro.\n", conflicts: 1))
    }

    @Test func inlineConflictWithoutTrailingNewline() {
        let result = Merge.merge(base: "a\nb", mine: "a\nmine", theirs: "a\ntheirs")
        #expect(result == Merge.Result(text: "a\n👤 mine 🔀 theirs 💾", conflicts: 1))
    }

    @Test func conflictOverSeveralLinesUsesBlock() {
        let result = Merge.merge(base: "a\nb\nc\n", mine: "a\nX\nY\nc\n", theirs: "a\nZ\nc\n")
        #expect(result == Merge.Result(text: "a\n🔽 👤\nX\nY\n🔀 ───\nZ\n🔼 💾\nc\n", conflicts: 1))
    }

    @Test func deletedLineAgainstEditUsesBlock() {
        let result = Merge.merge(base: "a\nb\nc\n", mine: "a\nc\n", theirs: "a\nB\nc\n")
        #expect(result == Merge.Result(text: "a\n🔽 👤\n🔀 ───\nB\n🔼 💾\nc\n", conflicts: 1))
    }

    @Test func conflictsAreCounted() {
        let result = Merge.merge(base: "a\nx\nb\ny\n", mine: "1\nx\n2\ny\n", theirs: "3\nx\n4\ny\n")
        #expect(result.conflicts == 2)
    }

    @Test func firstConflictSpansTheBlock() {
        let text = "a\n🔽 👤\nm\n🔀 ───\nt\n🔼 💾\nc\n"
        let block = "🔽 👤\nm\n🔀 ───\nt\n🔼 💾"
        #expect(Merge.firstConflict(in: text) == NSRange(location: 2, length: (block as NSString).length))
    }

    @Test func firstConflictSpansTheInlineConflict() {
        let text = "am 👤 11 🔀 9 💾 im"
        #expect(Merge.firstConflict(in: text) == NSRange(location: 3, length: ("👤 11 🔀 9 💾" as NSString).length))
    }

    @Test func noMarkersNoConflict() {
        #expect(Merge.firstConflict(in: "plain text\n") == nil)
    }
}
