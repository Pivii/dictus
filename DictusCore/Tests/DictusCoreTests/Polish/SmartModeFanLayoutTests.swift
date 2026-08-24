// DictusCore/Tests/DictusCoreTests/Polish/SmartModeFanLayoutTests.swift
// The arithmetic that settled #79's fan-capacity contradiction.
import XCTest
@testable import DictusCore

final class SmartModeFanLayoutTests: XCTestCase {

    /// The real `KeyMetrics` values, which live in the keyboard target and cannot be
    /// imported here: `4 × keyHeight + 3 × rowSpacing` for each device class.
    private let standardHeight: CGFloat = 4 * 43 + 3 * 11   // 205
    private let compactHeight: CGFloat = 4 * 40 + 3 * 9     // 187

    // MARK: - Capacity

    func testFanHoldsFourEntries() {
        XCTAssertEqual(SmartModeFanLayout.maximumEntries, 4)
    }

    func testCapacityIsThreeModesPlusNormal() {
        XCTAssertEqual(SmartModeCatalogue.maximumPinnedModes, 3)
        XCTAssertEqual(SmartModeFanLayout.maximumEntries, SmartModeCatalogue.maximumPinnedModes + 1)
    }

    /// The measurement the decision rests on: four entries clear Apple's 44 pt
    /// minimum on the smallest supported screen. This is the assertion to look at
    /// first if anyone proposes raising the cap again.
    func testFourEntriesClearTheMinimumTargetOnEveryDeviceClass() {
        for available in [standardHeight, compactHeight] {
            let height = SmartModeFanLayout.rowHeight(
                availableHeight: available, entryCount: 4, showsReason: false
            )
            XCTAssertGreaterThanOrEqual(
                height, SmartModeFanLayout.minimumRowHeight,
                "four entries must stay tappable at \(available) pt"
            )
        }
    }

    /// And five do not, on the SE — which is why the acceptance criterion lost to the
    /// geometry paragraph.
    func testFiveEntriesFallBelowTheMinimumOnCompact() {
        let height = SmartModeFanLayout.rowHeight(
            availableHeight: compactHeight, entryCount: 5, showsReason: false
        )
        XCTAssertLessThan(height, SmartModeFanLayout.minimumRowHeight)
    }

    // MARK: - Rows

    func testRowsDivideTheAreaCompletely() {
        let height = SmartModeFanLayout.rowHeight(
            availableHeight: standardHeight, entryCount: 4, showsReason: false
        )
        XCTAssertEqual(height * 4, standardHeight, accuracy: 0.001)
    }

    func testTheReasonStripIsSubtractedOnlyWhenShown() {
        let without = SmartModeFanLayout.rowHeight(
            availableHeight: standardHeight, entryCount: 4, showsReason: false
        )
        let with = SmartModeFanLayout.rowHeight(
            availableHeight: standardHeight, entryCount: 4, showsReason: true
        )
        XCTAssertEqual(
            with * 4, standardHeight - SmartModeFanLayout.reasonHeight, accuracy: 0.001
        )
        XCTAssertLessThan(with, without)
    }

    func testNoEntriesMeansNoRowHeightRatherThanADivideByZero() {
        XCTAssertEqual(
            SmartModeFanLayout.rowHeight(
                availableHeight: standardHeight, entryCount: 0, showsReason: false
            ),
            0
        )
    }

    // MARK: - Entries

    func testNormalIsAlwaysTheFirstEntry() {
        let entries = SmartModeFanLayout.entries(pinned: [SmartModeCatalogue.notes], armed: nil)
        XCTAssertEqual(entries.first, .normal)
        XCTAssertNil(entries.first?.smartMode)
    }

    func testPinnedOrderIsPreserved() {
        let pinned = [
            SmartModeCatalogue.translate(to: .german),
            SmartModeCatalogue.notes
        ]
        let entries = SmartModeFanLayout.entries(pinned: pinned, armed: nil)
        XCTAssertEqual(entries.map(\.id), ["normal", "translate.de", "notes"])
    }

    /// The store caps the list too, but this side is the one that physically cannot
    /// draw more, so it refuses independently.
    func testMoreThanThreePinnedIsTruncated() {
        let entries = SmartModeFanLayout.entries(pinned: SmartModeCatalogue.builtIns, armed: nil)
        XCTAssertEqual(entries.count, SmartModeFanLayout.maximumEntries)
    }

    // MARK: - Opening on an empty pinned list (#402)

    /// Row 1 of #402's table. Nothing pinned and nothing armed: no rows, so the
    /// keyboard refuses and says where the mode list lives. A one-row fan here would
    /// be a menu with one item and nothing to undo.
    func testNothingPinnedAndNothingArmedGivesNoRows() {
        XCTAssertTrue(SmartModeFanLayout.entries(pinned: [], armed: nil).isEmpty)
    }

    /// Row 2, and the bug. A user who unpins every mode while one is armed keeps
    /// dictating in it forever unless the fan opens on Normal — releasing back on the
    /// mic aborts the gesture, so the mic is not the way out.
    func testNothingPinnedButAModeArmedGivesTheNormalRowAlone() {
        let entries = SmartModeFanLayout.entries(
            pinned: [], armed: SmartModeCatalogue.translate(to: .german)
        )
        XCTAssertEqual(entries, [.normal])
        XCTAssertNil(entries.first?.smartMode, "the single row must be the one that disarms")
    }

    /// Row 3: with modes pinned, the armed mode changes nothing. It is not a row of
    /// its own, and it does not reorder the ones the user arranged.
    func testTheArmedModeDoesNotChangeAPopulatedFan() {
        let pinned = [SmartModeCatalogue.notes, SmartModeCatalogue.translate(to: .english)]
        let unarmed = SmartModeFanLayout.entries(pinned: pinned, armed: nil)
        for armed in [SmartModeCatalogue.notes, SmartModeCatalogue.translate(to: .german)] {
            XCTAssertEqual(SmartModeFanLayout.entries(pinned: pinned, armed: armed), unarmed)
        }
        XCTAssertEqual(unarmed.map(\.id), ["normal", "notes", "translate.en"])
    }

    /// The one-row fan gets the whole area, which is far above the touch-target
    /// floor — so #402 raises no layout question, and this is the assertion that says
    /// why nobody had to design a special case for it.
    func testTheSingleNormalRowIsComfortablyTappable() {
        for available in [standardHeight, compactHeight] {
            XCTAssertGreaterThan(
                SmartModeFanLayout.rowHeight(
                    availableHeight: available, entryCount: 1, showsReason: true
                ),
                SmartModeFanLayout.minimumRowHeight
            )
        }
    }

    // MARK: - Hit testing

    func testEachRowMapsToItsOwnIndex() {
        let height = SmartModeFanLayout.rowHeight(
            availableHeight: standardHeight, entryCount: 4, showsReason: false
        )
        for index in 0..<4 {
            let midpoint = height * CGFloat(index) + height / 2
            XCTAssertEqual(
                SmartModeFanLayout.entryIndex(
                    atY: midpoint, availableHeight: standardHeight,
                    entryCount: 4, showsReason: false
                ),
                index
            )
        }
    }

    /// The documented abort: the finger has travelled back up onto the mic, which is
    /// above the fan's origin.
    func testNegativeYIsNoRow() {
        XCTAssertNil(SmartModeFanLayout.entryIndex(
            atY: -1, availableHeight: standardHeight, entryCount: 4, showsReason: false
        ))
    }

    func testPastTheLastRowIsNoRow() {
        XCTAssertNil(SmartModeFanLayout.entryIndex(
            atY: standardHeight + 1, availableHeight: standardHeight,
            entryCount: 4, showsReason: false
        ))
    }

    /// With a reason strip showing, the rows end early and the strip itself is not a
    /// target — releasing on the explanation must not arm the last mode.
    func testTheReasonStripIsNotATarget() {
        let rows = SmartModeFanLayout.rowHeight(
            availableHeight: standardHeight, entryCount: 4, showsReason: true
        ) * 4
        XCTAssertNil(SmartModeFanLayout.entryIndex(
            atY: rows + 2, availableHeight: standardHeight, entryCount: 4, showsReason: true
        ))
    }

    func testTheTopEdgeBelongsToTheFirstRow() {
        XCTAssertEqual(
            SmartModeFanLayout.entryIndex(
                atY: 0, availableHeight: standardHeight, entryCount: 4, showsReason: false
            ),
            0
        )
    }
}
