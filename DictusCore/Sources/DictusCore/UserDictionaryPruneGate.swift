// DictusCore/Sources/DictusCore/UserDictionaryPruneGate.swift
// The single precondition the one-shot user-dictionary prune runs under.
import Foundation

/// Decides whether the one-shot duplicate prune (#287) may run right now.
///
/// WHY this is a named type in DictusCore rather than a condition at the call
/// site. The prune's precondition is not "a dictionary is loaded" — it is **"the
/// dictionary I am about to ask is the one the user is typing in"**. Three
/// separate defects came from picking a call site that happened to satisfy that
/// and trusting it:
///
/// 1. a completion from a superseded load could prune against whichever trie was
///    mounted at that instant;
/// 2. the load completion was the only trigger, and it was systematically
///    starved, so the prune never ran at all;
/// 3. the pre-load attempt added to fix (2) runs before `setLanguage`, so a
///    language changed from the app while the keyboard process stayed alive left
///    the *previous* language's trie mounted and prunable.
///
/// Each fix moved the language question rather than closing it. Stating the
/// invariant once, where it can be tested, is what closes it: any call site is
/// safe, because the operation checks for itself instead of being trusted.
///
/// WHY it lives here and not in the keyboard extension: DictusCore is the only
/// target in this repo with a test bundle, and after three defects this rule has
/// earned coverage more than it has earned brevity.
public enum UserDictionaryPruneGate {

    /// What the caller should do, and — when the answer is no — what to report.
    public enum Decision: Equatable {
        /// The mounted dictionary is the active language's. Prune.
        case run
        /// Already pruned on this install. Nothing to do, nothing owed.
        case alreadyDone
        /// No dictionary is mounted: none loaded yet, or a load is in flight and
        /// has torn the previous one down. Wait for a load to finish.
        case notMounted
        /// A dictionary is mounted, but not the one the user is typing in.
        /// Pruning here would judge one language's words by another language's
        /// vocabulary, and consume the one shot doing it.
        case languageMismatch(mounted: String, active: String)

        /// Cause as a log-safe token. Language codes only — never user content.
        public var reason: String {
            switch self {
            case .run: return "ok"
            case .alreadyDone: return "already-done"
            case .notMounted: return "dictionary-not-mounted"
            case .languageMismatch(let mounted, let active):
                return "language-mismatch mounted=\(mounted) active=\(active)"
            }
        }
    }

    /// - Parameters:
    ///   - alreadyPruned: `UserDictionary.hasPrunedTrieDuplicates`.
    ///   - mountedLanguage: the language whose data is mmap'd right now, or nil
    ///     when nothing is. Must describe what is *mounted*, not what was last
    ///     requested — a load that has been asked for but has not finished has
    ///     already torn down the dictionary it is replacing.
    ///   - activeLanguage: the language the user is typing in
    ///     (`SupportedLanguage.active`).
    public static func decide(
        alreadyPruned: Bool,
        mountedLanguage: String?,
        activeLanguage: String
    ) -> Decision {
        guard !alreadyPruned else { return .alreadyDone }
        guard let mounted = mountedLanguage else { return .notMounted }
        guard mounted == activeLanguage else {
            return .languageMismatch(mounted: mounted, active: activeLanguage)
        }
        return .run
    }
}
