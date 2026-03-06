// DictusKeyboard/Views/ToolbarView.swift
import SwiftUI
import DictusCore

/// Toolbar displayed above the keyboard with app shortcut and AnimatedMicButton.
/// Inspired by Wispr Flow -- the mic button is the primary dictation trigger.
///
/// WHY AnimatedMicButton replaces inline micIcon:
/// AnimatedMicButton provides 4 visual states (idle glow, recording pulse,
/// transcribing shimmer, success flash) that give the user clear feedback
/// about the dictation lifecycle. The inline micIcon only had basic color changes.
struct ToolbarView: View {
    let hasFullAccess: Bool
    let dictationStatus: DictationStatus
    var onMicTap: () -> Void

    /// Icon size scales with Dynamic Type.
    @ScaledMetric private var gearIconSize: CGFloat = 16

    var body: some View {
        HStack {
            // Left: gear icon to open DictusApp settings
            if hasFullAccess {
                // Safe to force-unwrap: compile-time literal, always valid URL
                Link(destination: URL(string: "dictus://")!) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: gearIconSize, weight: .medium))
                        .foregroundColor(Color(.systemGray))
                        .frame(width: 32, height: 32)
                }
            }

            Spacer()

            // Right: AnimatedMicButton with state-dependent animations
            if !hasFullAccess {
                // Disabled state: show idle button with reduced opacity
                AnimatedMicButton(status: .idle, onTap: {})
                    .scaleEffect(0.45)
                    .frame(width: 32, height: 32)
                    .disabled(true)
                    .opacity(0.4)
            } else {
                AnimatedMicButton(status: dictationStatus, onTap: onMicTap)
                    .scaleEffect(0.45)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(toolbarBackground)
    }

    /// Toolbar background: glass bar on iOS 26, separator line on older versions.
    ///
    /// WHY conditional glass:
    /// On iOS 26, the glass bar blends with the native keyboard chrome for a cohesive look.
    /// On older iOS versions, a simple separator line is more appropriate since there's
    /// no glass design language to match.
    @ViewBuilder
    private var toolbarBackground: some View {
        if #available(iOS 26, *) {
            Color.clear
                .dictusGlassBar()
        } else {
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(.separator).opacity(0.3))
                    .frame(height: 0.5)
            }
        }
    }
}
