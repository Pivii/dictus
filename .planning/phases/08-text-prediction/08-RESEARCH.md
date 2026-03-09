# Phase 8: Text Prediction - Research

**Researched:** 2026-03-09
**Domain:** iOS text prediction, spell-checking, UITextChecker, frequency dictionaries
**Confidence:** HIGH

## Summary

Phase 8 implements a 3-slot suggestion bar integrated into the existing ToolbarView, using Apple's built-in `UITextChecker` for word completions and spell-checking, plus a bundled frequency dictionary to rank suggestions by real-world usage (since UITextChecker returns completions alphabetically on iOS, not by probability). The accent suggestion feature (PRED-03) reuses the existing `AccentedCharacters` lookup table in DictusCore.

The primary technical challenges are: (1) extracting the current partial word from `textDocumentProxy.documentContextBeforeInput`, (2) ranking UITextChecker completions with frequency data since iOS does NOT sort by probability despite what Apple docs claim, and (3) implementing the autocorrect undo-on-backspace pattern without adding complexity to the existing keystroke flow.

**Primary recommendation:** Build a `TextPredictionEngine` class in DictusKeyboard that wraps UITextChecker + frequency dictionary lookup, triggered on each keystroke with lightweight debouncing (~50ms). Suggestion state flows through KeyboardView to ToolbarView.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Suggestion bar integrated inside existing ToolbarView, between gear icon (left) and mic pill (right)
- No extra keyboard height -- suggestions share the toolbar row
- 3 slots as plain text separated by thin vertical dividers (Apple-style, not pills)
- Central slot = current word (bold), lateral slots = alternatives
- When no input in progress: toolbar reverts to normal (gear + mic, nothing in between)
- Fallback: if horizontal space too tight, hide the gear icon
- UITextChecker for completions and spell-checking (0 MB, Apple built-in)
- Frequency dictionary for ranking suggestions by usage frequency
- Two dictionary files bundled in DictusKeyboard: French (~1.5MB) + English (~1.5MB)
- Active dictionary selected via SharedKeys.language from App Group preferences
- Completion of current word only -- no next-word prediction
- Auto-replacement on space/punctuation: misspelled word replaced by central slot correction
- Backspace immediately after autocorrection restores original word (undo mechanism)
- Undo only on immediate backspace -- if user types more, correction is committed
- Tapping a lateral suggestion replaces current word + inserts space
- Autocorrect also fixes missing accents (e.g., "cafe" -> "cafe with accent")
- Toggle "Correction automatique" ON/OFF in settings (enabled by default, stored in App Group)
- Accent suggestions: single accentable vowel as first char after space shows accent variants
- As soon as second character typed, bar switches to word completion mode
- Tapping accent variant replaces vowel WITHOUT adding space
- Coexists with adaptive accent key (KBD-02)

### Claude's Discretion
- Exact animation/transition when suggestions appear/disappear in toolbar
- Frequency dictionary format and loading strategy (lazy vs eager)
- UITextChecker language parameter handling
- Suggestion update debouncing/throttling for performance
- Exact accent variant ordering per vowel

### Deferred Ideas (OUT OF SCOPE)
- Next-word prediction (PRED-04) -- requires n-gram/ML model. Deferred to v1.2.
- Swipe typing (PRED-05) -- gesture-based word input. Deferred to v1.2.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PRED-01 | 3-slot suggestion bar above keyboard with current word completion | UITextChecker.completions(forPartialWordRange:in:language:) + frequency dictionary ranking + ToolbarView integration |
| PRED-02 | French autocorrect -- spelling correction applied on word validation | UITextChecker.rangeOfMisspelledWord + guesses(forWordRange:in:language:) + undo-on-backspace pattern |
| PRED-03 | Accent suggestions in suggestion bar | AccentedCharacters.mappings reuse + single-char detection via documentContextBeforeInput |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| UITextChecker | Built-in (UIKit) | Word completions + spell-checking | Zero memory cost, Apple's built-in lexicon, supports French ("fr") |
| Frequency dictionary | Custom JSON | Rank completions by real-world usage | UITextChecker sorts alphabetically on iOS, not by probability |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AccentedCharacters (DictusCore) | Existing | Accent variant lookup for PRED-03 | When user types single vowel after space |
| SharedKeys (DictusCore) | Existing | App Group preferences (language, autocorrect toggle) | Reading active language + autocorrect enabled state |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| UITextChecker | Custom trie/dictionary | Full control over ranking, but massive memory cost + maintenance burden in 50MB extension |
| JSON frequency dict | SQLite FTS | Better query performance for large datasets, but overkill for simple rank lookup of ~10K words |
| Bundled dict files | On-demand download | Saves bundle size, but adds network dependency for offline-first app |

**No installation needed** -- UITextChecker is part of UIKit, frequency dictionaries are bundled JSON files.

## Architecture Patterns

### Recommended Project Structure
```
DictusKeyboard/
  TextPrediction/
    TextPredictionEngine.swift    # Core engine: completions + spelling + ranking
    FrequencyDictionary.swift     # JSON frequency data loader + rank lookup
    SuggestionState.swift         # ObservableObject: current suggestions array
  Views/
    ToolbarView.swift             # Modified: suggestion slots in Spacer area
    SuggestionBarView.swift       # 3-slot suggestion display subview
DictusCore/Sources/DictusCore/
  SharedKeys.swift                # Add: autocorrectEnabled key
  AccentedCharacters.swift        # Existing: reuse for PRED-03
DictusApp/Views/
  SettingsView.swift              # Add: "Correction automatique" toggle
DictusKeyboard/Resources/
  fr_frequency.json               # French word frequency dictionary
  en_frequency.json               # English word frequency dictionary
```

### Pattern 1: Suggestion Engine (TextPredictionEngine)
**What:** A non-UI class that takes a partial word string and returns ranked suggestions.
**When to use:** Called on every keystroke (debounced).
**Example:**
```swift
// Source: UITextChecker Apple docs + frequency ranking pattern
class TextPredictionEngine {
    private let textChecker = UITextChecker()
    private var frequencyDict: [String: Int] = [:]
    private var language: String = "fr"

    func suggestions(for partialWord: String) -> [String] {
        // 1. Get completions from UITextChecker
        let nsWord = partialWord as NSString
        let range = NSRange(location: 0, length: nsWord.length)
        let completions = textChecker.completions(
            forPartialWordRange: range,
            in: partialWord,
            language: language
        ) ?? []

        // 2. Rank by frequency dictionary
        let ranked = completions.sorted { a, b in
            (frequencyDict[a.lowercased()] ?? 0) > (frequencyDict[b.lowercased()] ?? 0)
        }

        // 3. Return top 3 (center = best match, sides = alternatives)
        return Array(ranked.prefix(3))
    }

    func spellCheck(_ word: String) -> String? {
        let nsWord = word as NSString
        let range = NSRange(location: 0, length: nsWord.length)
        let misspelled = textChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0,
            wrap: false, language: language
        )
        guard misspelled.location != NSNotFound else { return nil }
        return textChecker.guesses(
            forWordRange: misspelled, in: word, language: language
        )?.first
    }
}
```

### Pattern 2: Current Word Extraction from textDocumentProxy
**What:** Extract the word being typed from `documentContextBeforeInput`.
**When to use:** On every keystroke to feed the prediction engine.
**Example:**
```swift
// Source: Apple UITextDocumentProxy docs + community patterns
func currentPartialWord(from proxy: UITextDocumentProxy) -> String? {
    guard let before = proxy.documentContextBeforeInput, !before.isEmpty else {
        return nil
    }
    // Find last word boundary (space, newline, punctuation)
    var lastWord = ""
    before.enumerateSubstrings(
        in: before.startIndex...,
        options: .byWords
    ) { word, _, _, _ in
        if let word = word { lastWord = word }
    }
    // Only return if we're mid-word (no trailing space)
    guard !before.hasSuffix(" ") && !before.hasSuffix("\n") else {
        return nil
    }
    return lastWord.isEmpty ? nil : lastWord
}
```

### Pattern 3: Autocorrect Undo via Backspace
**What:** Track the last autocorrection to restore original text on immediate backspace.
**When to use:** After autocorrect replaces a word on space/punctuation.
**Example:**
```swift
// Track autocorrect state for undo
struct AutocorrectState {
    let originalWord: String
    let correctedWord: String
    let insertedSpace: Bool  // Whether a space was added after correction
}

// In onSpace handler:
// 1. Get current word before inserting space
// 2. Spell-check it
// 3. If misspelled, replace with correction + store undo state
// 4. Insert space

// In onDelete handler:
// 1. If undoState exists and backspace is immediate:
//    a. Delete the corrected word + space
//    b. Re-insert original word
//    c. Clear undoState
// 2. Otherwise: normal delete, clear undoState
```

### Anti-Patterns to Avoid
- **Running UITextChecker on every character without debouncing:** Causes lag on older devices. Use 50ms debounce.
- **Loading both language dictionaries at startup:** Load only the active language. Lazy-load on language change.
- **Storing suggestion state in KeyboardState:** Keep it separate to avoid polluting cross-process state with ephemeral UI data. SuggestionState should be a local @StateObject.
- **Using textDocumentProxy.documentContextBeforeInput for long text:** It only returns ~300 characters. Fine for current-word extraction but not for sentence-level analysis.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Spell checking | Custom dictionary lookup | UITextChecker.rangeOfMisspelledWord | Apple's lexicon covers 100K+ French words, handles conjugations, zero memory cost |
| Word completions | Trie data structure | UITextChecker.completions(forPartialWordRange:) | Built-in, handles French morphology, zero bundle size |
| Word boundary detection | Manual character scanning | String.enumerateSubstrings(options: .byWords) | Handles Unicode properly, language-aware tokenization |
| Accent character data | New mapping table | AccentedCharacters.mappings (existing) | Already exists in DictusCore with all French accented variants |

**Key insight:** UITextChecker provides the heavy lifting for free. The custom layer is thin: frequency ranking + UI integration + autocorrect undo logic.

## Common Pitfalls

### Pitfall 1: UITextChecker Returns Alphabetical Order on iOS
**What goes wrong:** Suggestions like "aardvark" appear before "about" for prefix "a".
**Why it happens:** Despite Apple docs claiming probability-based ordering, iOS UITextChecker sorts completions alphabetically (macOS does sort by probability).
**How to avoid:** Always re-rank completions using the frequency dictionary. Never trust UITextChecker's ordering on iOS.
**Warning signs:** Uncommon words appearing as the first suggestion.

### Pitfall 2: UITextChecker Language Parameter Format
**What goes wrong:** Completions return empty or wrong-language results.
**Why it happens:** UITextChecker accepts both "fr" and "fr_FR" but behavior may differ.
**How to avoid:** Use `UITextChecker.availableLanguages` at runtime to confirm French is supported, then use the exact string from that list. Typically "fr" or "fr_FR".
**Warning signs:** Empty completion arrays for valid French prefixes.

### Pitfall 3: Autocorrect Undo State Leak
**What goes wrong:** Pressing backspace undoes a correction that happened several words ago.
**Why it happens:** UndoState not cleared after the user types additional characters.
**How to avoid:** Clear the undo state on ANY action other than immediate backspace: typing a character, tapping a suggestion, moving the cursor.
**Warning signs:** Random word replacements when pressing backspace mid-sentence.

### Pitfall 4: textDocumentProxy Race Condition
**What goes wrong:** documentContextBeforeInput returns stale text after insertText/deleteBackward.
**Why it happens:** UITextDocumentProxy updates are not synchronous -- the proxy may not reflect the just-inserted text immediately.
**How to avoid:** After insertText or deleteBackward, use a small DispatchQueue.main.async delay before reading documentContextBeforeInput for suggestion updates. Or track the current word in a local @State variable alongside proxy reads.
**Warning signs:** Suggestions not updating after typing, or showing suggestions for the previous character.

### Pitfall 5: Memory Budget in Keyboard Extension
**What goes wrong:** Extension crashes or gets killed by iOS.
**Why it happens:** Keyboard extensions have ~50MB memory limit. Loading large dictionaries can push over the limit combined with WhisperKit overhead (though WhisperKit runs in the app, not the extension).
**How to avoid:** Keep frequency dictionary under 2MB. Load lazily. Profile on real device. UITextChecker itself uses shared system resources (zero extension memory).
**Warning signs:** Extension crashes on older devices (iPhone SE, iPhone 8).

### Pitfall 6: Suggestion Bar Competing with Mic Pill for Space
**What goes wrong:** On narrow screens (iPhone SE), 3 suggestions + gear icon + mic pill don't fit.
**Why it happens:** 320pt screen width minus padding leaves ~280pt for all elements.
**How to avoid:** Implement the fallback: hide gear icon when suggestions are active. Measure available width and truncate long suggestion text.
**Warning signs:** Text overlapping or mic pill being pushed off-screen.

## Code Examples

### Extracting Current Word from Proxy
```swift
// Source: Apple UITextDocumentProxy docs
func extractCurrentWord(proxy: UITextDocumentProxy) -> String? {
    guard let before = proxy.documentContextBeforeInput,
          !before.isEmpty,
          !before.hasSuffix(" "),
          !before.hasSuffix("\n") else {
        return nil
    }
    // Use Foundation's word enumeration for Unicode-safe boundary detection
    var currentWord: String?
    before.enumerateSubstrings(
        in: before.startIndex...,
        options: .byWords
    ) { word, _, _, _ in
        currentWord = word
    }
    return currentWord
}
```

### Accent Suggestion Mode Detection
```swift
// Source: CONTEXT.md decision + AccentedCharacters existing code
func accentSuggestions(for partialWord: String) -> [String]? {
    // Only trigger for single vowel character
    guard partialWord.count == 1 else { return nil }
    let lower = partialWord.lowercased()
    guard let variants = AccentedCharacters.mappings[lower] else { return nil }

    // Return: [original, variant1, variant2] - max 3 slots
    // Preserve case from user input
    let isUpper = partialWord != partialWord.lowercased()
    let result = [partialWord] + variants.prefix(2).map { v in
        isUpper ? v.uppercased() : v
    }
    return Array(result.prefix(3))
}
```

### Frequency Dictionary Loading
```swift
// Recommended format: simple JSON object { "word": rank_integer }
// Lower rank = more common (1 = most common word)
struct FrequencyDictionary {
    private var ranks: [String: Int] = [:]

    mutating func load(language: String) {
        let filename = "\(language)_frequency"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        ranks = dict
    }

    func rank(of word: String) -> Int {
        // Lower rank = more common. Unranked words get max rank.
        return ranks[word.lowercased()] ?? Int.max
    }
}
```

### Word Replacement via textDocumentProxy
```swift
// Source: Apple UITextDocumentProxy docs + established keyboard extension pattern
func replaceCurrentWord(
    proxy: UITextDocumentProxy,
    currentWord: String,
    replacement: String,
    addSpace: Bool
) {
    // Delete the current word character by character
    for _ in 0..<currentWord.count {
        proxy.deleteBackward()
    }
    // Insert replacement
    proxy.insertText(replacement)
    if addSpace {
        proxy.insertText(" ")
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom trie for completions | UITextChecker built-in | iOS 3.2+ (stable) | Zero memory cost, Apple maintains lexicon |
| UITextChecker probability sort | Frequency dictionary re-ranking | Community discovery ~2018 | iOS sorts alphabetically despite docs -- must re-rank |
| Word-level ML prediction | UITextChecker + frequency | N/A (ML is v1.2 scope) | Adequate for current-word completion without ML overhead |

**Deprecated/outdated:**
- UITextChecker's documented "probability sorting" on iOS -- does not work as documented. Always re-rank.

## Open Questions

1. **UITextChecker French coverage quality**
   - What we know: UITextChecker supports "fr" language, covers the French lexicon
   - What's unclear: How well it handles French conjugations, informal/slang words, compound words
   - Recommendation: Test on device with common French words. Fallback: frequency dictionary also serves as a whitelist for common words UITextChecker might miss.

2. **Frequency dictionary source and size**
   - What we know: Lexique 3.83 (openlexicon.fr) provides French word frequencies for 140K words. Top 10K-20K words would cover 95%+ of daily typing.
   - What's unclear: Exact file size after JSON conversion and whether 10K or 20K entries is the right cutoff
   - Recommendation: Start with top 20K words from Lexique 3.83, measure JSON file size. Target under 1.5MB. For English, use a comparable source (wordfreq project on GitHub).

3. **Debounce timing for suggestion updates**
   - What we know: Need to balance responsiveness vs. CPU usage
   - What's unclear: Whether 50ms is too slow (noticeable lag) or too fast (unnecessary computation)
   - Recommendation: Start with 50ms debounce, test on oldest supported device (iPhone 8/SE 2). UITextChecker calls are fast (< 5ms typically), so debouncing may be unnecessary.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in) |
| Config file | DictusCore/Tests/ (existing test target) |
| Quick run command | `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DictusCoreTests 2>&1 \| tail -20` |
| Full suite command | `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \| tail -30` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PRED-01 | Suggestion engine returns ranked completions for partial French word | unit | `xcodebuild test -scheme DictusCore -only-testing:DictusCoreTests/TextPredictionEngineTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -x` | No -- Wave 0 |
| PRED-01 | Current word extraction from text context | unit | Same target | No -- Wave 0 |
| PRED-02 | Spell-check detects misspelled French words and returns correction | unit | Same target | No -- Wave 0 |
| PRED-02 | Autocorrect undo state tracks and restores original word | unit | Same target | No -- Wave 0 |
| PRED-03 | Accent suggestions returned for single vowel input | unit | `xcodebuild test -scheme DictusCore -only-testing:DictusCoreTests/AccentedCharacterTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -x` | Partial (AccentedCharacterTests exists but not accent suggestion logic) |

### Sampling Rate
- **Per task commit:** Quick run on TextPredictionEngineTests
- **Per wave merge:** Full DictusCore test suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `DictusCore/Tests/DictusCoreTests/TextPredictionEngineTests.swift` -- covers PRED-01, PRED-02
- [ ] `DictusCore/Tests/DictusCoreTests/FrequencyDictionaryTests.swift` -- covers dictionary loading and ranking
- [ ] Test frequency dictionary fixture: `DictusCore/Tests/DictusCoreTests/Fixtures/fr_frequency_test.json`

Note: UITextChecker requires a running UIKit environment (simulator), so engine tests that call UITextChecker directly need `@testable import` in the keyboard target or must mock the checker. Pure logic tests (frequency ranking, word extraction, accent detection) can run in DictusCoreTests without UIKit dependency.

## Sources

### Primary (HIGH confidence)
- [UITextChecker Apple Documentation](https://developer.apple.com/documentation/uikit/uitextchecker) - API surface, language parameter, available methods
- [UITextDocumentProxy Apple Documentation](https://developer.apple.com/documentation/uikit/uitextdocumentproxy) - documentContextBeforeInput, insertText, deleteBackward
- Existing codebase: ToolbarView.swift, KeyboardView.swift, KeyboardState.swift, AccentedCharacters.swift, SharedKeys.swift, SettingsView.swift

### Secondary (MEDIUM confidence)
- [NSHipster UITextChecker](https://nshipster.com/uitextchecker/) - Confirmed alphabetical sorting bug on iOS, code examples
- [ios-uitextchecker-autocorrect GitHub](https://github.com/ansonl/ios-uitextchecker-autocorrect) - Autocorrect implementation patterns, guessesForWordRange usage
- [Lexique 3.83](http://www.lexique.org/) - French word frequency database, open source
- [wordfreq GitHub](https://github.com/rspeer/wordfreq) - Multi-language word frequency database

### Tertiary (LOW confidence)
- [frodonh/french-words GitHub](https://github.com/frodonh/french-words) - Alternative French frequency source, needs validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - UITextChecker is well-documented Apple API, used in many keyboard extensions
- Architecture: HIGH - Pattern is straightforward: engine + frequency ranking + UI integration
- Pitfalls: HIGH - Alphabetical sorting bug is well-documented by multiple sources (NSHipster, GitHub projects)
- Frequency dictionary: MEDIUM - Source identified (Lexique 3.83) but exact format/size needs validation during implementation

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable domain, UITextChecker API unchanged since iOS 3.2)
