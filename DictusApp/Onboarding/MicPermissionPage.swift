// DictusApp/Onboarding/MicPermissionPage.swift
// Step 2 of onboarding: request microphone permission.
import SwiftUI
import AVFoundation

/// Requests microphone permission with clear explanation of privacy.
///
/// WHY we don't block on denial:
/// Apple's HIG and research best practices recommend against blocking progress
/// on a denied permission. The user can still set up the keyboard and download
/// a model — they just won't be able to record until they grant mic access later.
struct MicPermissionPage: View {
    let onNext: () -> Void

    /// nil = not yet requested, true = granted, false = denied
    @State private var permissionGranted: Bool?
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Mic icon
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.dictusAccent)
                .padding(.bottom, 24)

            // Title
            Text("Microphone")
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .padding(.bottom, 16)

            // Explanation
            Text("Dictus a besoin du microphone pour transcrire votre voix. Vos enregistrements restent sur votre appareil.")
                .font(.dictusBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Permission result feedback
            if let granted = permissionGranted {
                if granted {
                    Label("Microphone autorise", systemImage: "checkmark.circle.fill")
                        .font(.dictusBody)
                        .foregroundColor(.dictusSuccess)
                        .padding(.bottom, 16)
                } else {
                    Text("Vous pouvez activer le micro plus tard dans Reglages")
                        .font(.dictusCaption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }
            }

            // Action button
            if permissionGranted == nil {
                // Request permission button
                Button(action: requestPermission) {
                    Text("Autoriser le micro")
                        .font(.dictusSubheading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.dictusAccent)
                        )
                }
                .disabled(isRequesting)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            } else {
                // Next button (visible after permission response)
                Button(action: onNext) {
                    Text("Continuer")
                        .font(.dictusSubheading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.dictusAccent)
                        )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Private

    private func requestPermission() {
        isRequesting = true

        // Check current status first — if already determined, don't re-prompt
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            permissionGranted = true
            autoAdvance()
        case .denied:
            permissionGranted = false
            isRequesting = false
        case .undetermined:
            // Bridge the completion-handler API to async-friendly code.
            //
            // WHY not async/await wrapper here:
            // requestRecordPermission uses a completion handler callback (pre-async API).
            // We could use withCheckedContinuation, but since we're updating @State
            // on main thread anyway, a simple DispatchQueue.main.async in the callback
            // is simpler and avoids the continuation overhead.
            session.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    permissionGranted = allowed
                    isRequesting = false
                    if allowed {
                        autoAdvance()
                    }
                }
            }
        @unknown default:
            permissionGranted = false
            isRequesting = false
        }
    }

    private func autoAdvance() {
        // Auto-advance after brief delay to show the checkmark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onNext()
        }
    }
}
