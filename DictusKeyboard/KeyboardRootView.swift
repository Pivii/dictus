// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the keyboard extension.
/// Composes: FullAccessBanner + StatusBar + KeyboardView.
struct KeyboardRootView: View {
    let controller: UIInputViewController
    @StateObject private var state = KeyboardState()

    var body: some View {
        VStack(spacing: 0) {
            // Full Access banner — persistent when disabled
            if !controller.hasFullAccess {
                FullAccessBanner()
            }

            // Status bar — shows during active dictation round-trip.
            // Spinner only shown during active states (recording, transcribing),
            // hidden on terminal states (ready, failed) where work is done.
            if let message = state.statusMessage {
                StatusBar(
                    message: message,
                    showSpinner: state.dictationStatus != .ready
                        && state.dictationStatus != .failed
                )
            }

            // Transcription result stub (Phase 1 only — replaced in Phase 3)
            if let transcription = state.lastTranscription,
               state.dictationStatus == .ready {
                TranscriptionStub(text: transcription, controller: controller)
            }

            // Main keyboard
            KeyboardView(
                controller: controller,
                hasFullAccess: controller.hasFullAccess
            )
        }
        .background(Color(.secondarySystemBackground))
    }
}

/// Status bar shown during dictation round-trip.
struct StatusBar: View {
    let message: String
    var showSpinner: Bool = true

    var body: some View {
        HStack {
            if showSpinner {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
    }
}

/// Temporary view to show received transcription in Phase 1.
/// Phase 3 replaces this with TranscriptionPreviewBar.
struct TranscriptionStub: View {
    let text: String
    let controller: UIInputViewController

    var body: some View {
        HStack {
            Text(text)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("Insérer") {
                controller.textDocumentProxy.insertText(text)
            }
            .font(.caption.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
    }
}
