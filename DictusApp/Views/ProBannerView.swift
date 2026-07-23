// DictusApp/Views/ProBannerView.swift
// Compact gradient banner for HomeView, hidden when Pro is active.
import SwiftUI
import DictusCore

/// Compact Pro banner at the bottom of HomeView.
///
/// WHY a separate view:
/// Keeps HomeView clean and makes the banner independently testable.
/// The banner has its own visibility logic (hidden when Pro active)
/// and navigation target (pushes PaywallView).
struct ProBannerView: View {
    @EnvironmentObject var proStatus: ProStatusManager

    var body: some View {
        if !proStatus.isProActive {
            NavigationLink {
                PaywallView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundColor(.dictusAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Dictus Pro")
                            .font(.dictusSubheading)
                            .foregroundColor(.primary)
                        Text("AI reformulation, history & more")
                            .font(.dictusCaption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [Color.dictusAccent.opacity(0.15), Color.dictusAccentHighlight.opacity(0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                )
                .dictusGlass()
            }
            .buttonStyle(GlassPressStyle(pressedScale: 0.97))
            .transition(.opacity.combined(with: .scale))
            .animation(.easeOut(duration: 0.3), value: proStatus.isProActive)
        }
    }
}
