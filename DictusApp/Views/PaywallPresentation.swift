// DictusApp/Views/PaywallPresentation.swift
// One way to open the paywall, shared by every entry point.
import SwiftUI

extension View {
    /// Presents the paywall over the whole screen.
    ///
    /// WHY modal rather than a push inside the tab's NavigationStack:
    /// the iOS 26 tab bar floats above scroll content instead of insetting it,
    /// so a pushed paywall had the tab bar sitting across its subscribe button.
    /// Hiding the bar for the duration of the push fixed that but moved the cost
    /// to the way back: the bar is only re-inserted once the pop animation has
    /// finished, and re-inserting it changes the safe area, so the screen behind
    /// visibly re-laid out — everything jumped upward a frame after landing.
    /// A cover never touches the tab bar at all, so the screen underneath is
    /// already whole when the paywall goes away.
    ///
    /// The purchase funnel is also the one place tab navigation should not be
    /// offered, which a cover gives for free rather than by suppression.
    ///
    /// WHY its own NavigationStack: the cover is presented outside the tab's
    /// stack, so the paywall would otherwise have no navigation bar to hang its
    /// close button on.
    func paywallCover(isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            NavigationStack {
                PaywallView()
            }
        }
    }
}
