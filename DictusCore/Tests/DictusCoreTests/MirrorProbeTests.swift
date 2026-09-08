// DictusCore/Tests/DictusCoreTests/MirrorProbeTests.swift
// Tests for the mirror-divergence instrument (issue #530). The instrument's whole
// value is that `off` means one thing and is never ambiguous, so these tests are
// about the alignment arithmetic and the baseline rules, not about logging.

import XCTest
@testable import DictusCore

#if DEBUG
final class MirrorProbeTests: XCTestCase {

    // MARK: - Alignment arithmetic

    func testIdenticalTailsAlignAtZero() {
        XCTAssertEqual(
            MirrorProbe.alignment(shadow: "Une fois ton", mirror: "Une fois ton"),
            0
        )
    }

    func testMirrorCarryingOnePhantomAlignsAtPlusOne() {
        // #530's capture: the keyboard predicts "ton", the mirror reports "tonn".
        XCTAssertEqual(
            MirrorProbe.alignment(shadow: "Une fois ton", mirror: "Une fois tonn"),
            1
        )
    }

    func testMirrorBehindTheKeyboardAlignsAtMinusOne() {
        // The opposite desync: we inserted a character the mirror has not taken.
        XCTAssertEqual(
            MirrorProbe.alignment(shadow: "Une fois tonn", mirror: "Une fois ton"),
            -1
        )
    }

    func testExactMatchWinsOverALongerOffsetMatch() {
        // "aaaa" vs "aaaa" aligns at 0, not at +1 — smallest offset first, so a
        // repeated character cannot make a healthy mirror look desynced.
        XCTAssertEqual(MirrorProbe.alignment(shadow: "bonjour aaaa", mirror: "bonjour aaaa"), 0)
    }

    func testUnrelatedTailsDoNotAlign() {
        // A host-side edit: the shadow no longer describes this document at all.
        XCTAssertNil(
            MirrorProbe.alignment(shadow: "Une fois ton premier", mirror: "Une fois ton")
        )
    }

    func testDivergenceBeyondSixCharactersDoesNotAlign() {
        XCTAssertNil(MirrorProbe.alignment(shadow: "abcdefgh", mirror: "abcdefghijklmno"))
    }

    func testWindowedMirrorShorterThanTheShadowStillAlignsAtZero() {
        // The mirror is a window the host trims (#266), so a shadow that has
        // accumulated more history than the window holds is NOT a divergence.
        let shadow = "Une fois ton premier retour reçu"
        let mirror = "premier retour reçu"
        XCTAssertEqual(MirrorProbe.alignment(shadow: shadow, mirror: mirror), 0)
    }

    func testBothEmptyAlignsAtZero() {
        XCTAssertEqual(MirrorProbe.alignment(shadow: "", mirror: ""), 0)
    }

    // MARK: - Prediction following our own edits

    func testInsertAndDeleteNetToNoChange() {
        // Step 3 of the reproduction: "ton" -> "to" -> "ton". The keyboard predicts
        // a net-unchanged tail. Any offset seen after this is not something the
        // keyboard did.
        let probe = MirrorProbe()
        probe.adopt(mirror: "Une fois ton", event: "test", reason: "test")
        probe.record(.deleteBackward)
        probe.record(.insert("n"))

        let reading = probe.probe(event: "test", mirror: "Une fois ton")
        XCTAssertEqual(reading.offset, 0)
        XCTAssertFalse(reading.diverged)
    }

    func testTheCapturedPhantomShowsAsPlusOne() {
        // The same two operations, against the mirror #530 actually recorded.
        let probe = MirrorProbe()
        probe.adopt(mirror: "Une fois ton", event: "test", reason: "test")
        probe.record(.deleteBackward)
        probe.record(.insert("n"))

        let reading = probe.probe(event: "key-insert", mirror: "Une fois tonn")
        XCTAssertEqual(reading.offset, 1)
        XCTAssertTrue(reading.diverged)
    }

    func testReplaceFollowsDeleteThenInsert() {
        let probe = MirrorProbe()
        probe.adopt(mirror: "je pense quee", event: "test", reason: "test")
        probe.record(.replace(deleted: 4, inserted: "que "))

        XCTAssertEqual(probe.probe(event: "test", mirror: "je pense que ").offset, 0)
    }

    func testDeleteOnAnEmptyPredictionDoesNotUnderflow() {
        let probe = MirrorProbe()
        probe.adopt(mirror: "", event: "test", reason: "test")
        probe.record(.deleteBackward)
        probe.record(.deleteBackward)

        XCTAssertEqual(probe.probe(event: "test", mirror: "").offset, 0)
    }

    // MARK: - Baseline rules

    func testFirstProbeAdoptsAndReportsZero() {
        let probe = MirrorProbe()
        let reading = probe.probe(event: "textDidChange", mirror: "Une fois ton")

        XCTAssertEqual(reading.offset, 0)
        XCTAssertEqual(reading.shadowTail, "Une fois ton")
    }

    func testASmallOffsetIsNotAdoptedAwayAndPersists() {
        // The question #530 asks is whether a divergence CLEARS. If the probe
        // re-baselined on every disagreement, every capture would show off=0
        // forever and answer nothing. It must persist until something clears it.
        let probe = MirrorProbe()
        probe.adopt(mirror: "Une fois ton", event: "test", reason: "test")
        probe.record(.deleteBackward)
        probe.record(.insert("n"))

        XCTAssertEqual(probe.probe(event: "key-insert", mirror: "Une fois tonn").offset, 1)
        // No further keyboard edits: the offset is still there on the next event.
        XCTAssertEqual(probe.probe(event: "textDidChange", mirror: "Une fois tonn").offset, 1)
    }

    func testAnUnalignableChangeReBaselines() {
        // A host-side selection delete. The shadow cannot describe it, so the probe
        // reports "no alignment" once and starts again from the mirror — the next
        // reading is measured against the new baseline, not the dead one.
        let probe = MirrorProbe()
        probe.adopt(mirror: "Une fois ton premier retour", event: "test", reason: "test")

        XCTAssertNil(probe.probe(event: "textDidChange", mirror: "Une fois ton retour").offset)
        XCTAssertEqual(probe.probe(event: "space", mirror: "Une fois ton retour").offset, 0)
    }

    func testResetDropsTheBaseline() {
        let probe = MirrorProbe()
        probe.adopt(mirror: "Une fois ton", event: "test", reason: "test")
        probe.record(.insert("!"))
        probe.reset()

        // With no baseline the next probe adopts rather than reporting a bogus offset.
        XCTAssertEqual(probe.probe(event: "textDidChange", mirror: "something else").offset, 0)
    }
}
#endif
