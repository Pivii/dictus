// DictusApp/Views/ModelPreparationPresentation.swift
// The environment action a record button uses to reach MainTabView's preparation screen (#484).
import SwiftUI

/// Raises the model preparation screen for a record tap that arrived during a load (#484).
///
/// WHY AN ENVIRONMENT ACTION AND NOT A PARAMETER: the state lives in `MainTabView`
/// (`preparation`), and its two callers sit at different depths beneath it — `HomeView` inside
/// a `NavigationStack` inside the `TabView`, `RecordingView` as a sibling in the same `ZStack`.
/// `RecordingView` also has two construction sites outside that hierarchy (`TestDictationView`,
/// a `#Preview`), and a required closure would force both to invent one. Reading it from the
/// environment gives every caller the same call and no view a new signature.
///
/// WHY THE DEFAULT IS A NO-OP rather than a fatal error: a `RecordingView` built outside
/// `MainTabView` genuinely has no root to present through, and the correct behaviour there is
/// the one that shipped before this issue. Only `MainTabView` installs a real handler.
struct PresentModelPreparationAction {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func callAsFunction() {
        handler()
    }
}

private struct PresentModelPreparationKey: EnvironmentKey {
    static let defaultValue = PresentModelPreparationAction { }
}

extension EnvironmentValues {
    var presentModelPreparation: PresentModelPreparationAction {
        get { self[PresentModelPreparationKey.self] }
        set { self[PresentModelPreparationKey.self] = newValue }
    }
}
