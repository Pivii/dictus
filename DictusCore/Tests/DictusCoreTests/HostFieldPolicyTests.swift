// DictusCore/Tests/DictusCoreTests/HostFieldPolicyTests.swift
// Tests for the host-field traits policy (issue #200): autocorrect and
// suggestions must be disabled in search/URL/email/username/secure fields.

import XCTest
@testable import DictusCore

final class HostFieldPolicyTests: XCTestCase {

    /// Shorthand: evaluate with permissive defaults, overriding one axis at a time.
    private func evaluate(
        keyboard: HostFieldPolicy.KeyboardKind = .standard,
        content: HostFieldPolicy.ContentKind = .none,
        autocorrectionDisabled: Bool = false,
        spellCheckingDisabled: Bool = false,
        isSecureEntry: Bool = false
    ) -> HostFieldPolicy {
        HostFieldPolicy.evaluate(
            keyboard: keyboard,
            content: content,
            autocorrectionDisabled: autocorrectionDisabled,
            spellCheckingDisabled: spellCheckingDisabled,
            isSecureEntry: isSecureEntry
        )
    }

    // MARK: - Normal prose fields stay enabled

    func testDefaultFieldAllowsEverything() {
        let policy = evaluate()
        XCTAssertTrue(policy.autocorrectAllowed)
        XCTAssertTrue(policy.suggestionsAllowed)
        XCTAssertEqual(policy, .allowed)
    }

    func testAsciiCapableKeyboardStaysEnabled() {
        // Many normal fields use .asciiCapable — it must NOT disable autocorrect.
        let policy = evaluate(keyboard: .asciiCapable)
        XCTAssertTrue(policy.autocorrectAllowed)
        XCTAssertTrue(policy.suggestionsAllowed)
    }

    func testOtherContentTypeStaysEnabled() {
        // Content types we don't special-case (e.g. .givenName) keep defaults.
        let policy = evaluate(content: .other)
        XCTAssertTrue(policy.autocorrectAllowed)
        XCTAssertTrue(policy.suggestionsAllowed)
    }

    // MARK: - Explicit autocorrection opt-out (Safari search, social search bars)

    func testAutocorrectionTypeNoDisablesEverything() {
        let policy = evaluate(autocorrectionDisabled: true)
        XCTAssertFalse(policy.autocorrectAllowed)
        XCTAssertFalse(policy.suggestionsAllowed)
        XCTAssertEqual(policy.reason, "autocorrectionType.no")
    }

    // MARK: - Keyboard types implying non-prose input

    func testSearchAndTokenKeyboardTypesDisableEverything() {
        let kinds: [HostFieldPolicy.KeyboardKind] = [
            .url, .email, .webSearch, .twitter, .numeric, .phone, .namePhone
        ]
        for kind in kinds {
            let policy = evaluate(keyboard: kind)
            XCTAssertFalse(policy.autocorrectAllowed, "\(kind) should disable autocorrect")
            XCTAssertFalse(policy.suggestionsAllowed, "\(kind) should disable suggestions")
            XCTAssertEqual(policy.reason, "keyboardType.\(kind.rawValue)")
        }
    }

    // MARK: - Content types identifying token fields

    func testTokenContentTypesDisableEverything() {
        let kinds: [HostFieldPolicy.ContentKind] = [
            .username, .password, .url, .email, .oneTimeCode
        ]
        for kind in kinds {
            let policy = evaluate(content: kind)
            XCTAssertFalse(policy.autocorrectAllowed, "\(kind) should disable autocorrect")
            XCTAssertFalse(policy.suggestionsAllowed, "\(kind) should disable suggestions")
            XCTAssertEqual(policy.reason, "textContentType.\(kind.rawValue)")
        }
    }

    // MARK: - Secure entry

    func testSecureEntryDisablesEverything() {
        let policy = evaluate(isSecureEntry: true)
        XCTAssertFalse(policy.autocorrectAllowed)
        XCTAssertFalse(policy.suggestionsAllowed)
        XCTAssertEqual(policy.reason, "secureTextEntry")
    }

    func testSecureEntryWinsOverOtherSignals() {
        // Precedence: secure entry is checked first even when other traits are set.
        let policy = evaluate(keyboard: .webSearch, autocorrectionDisabled: true, isSecureEntry: true)
        XCTAssertEqual(policy.reason, "secureTextEntry")
    }

    // MARK: - Spell checking opt-out (weakest signal)

    func testSpellCheckingNoDisablesAutocorrectButKeepsSuggestions() {
        let policy = evaluate(spellCheckingDisabled: true)
        XCTAssertFalse(policy.autocorrectAllowed)
        XCTAssertTrue(policy.suggestionsAllowed)
        XCTAssertEqual(policy.reason, "spellCheckingType.no")
    }

    func testStrongerSignalWinsOverSpellChecking() {
        // keyboardType beats spellCheckingType in the precedence order.
        let policy = evaluate(keyboard: .webSearch, spellCheckingDisabled: true)
        XCTAssertEqual(policy.reason, "keyboardType.webSearch")
        XCTAssertFalse(policy.suggestionsAllowed)
    }
}
