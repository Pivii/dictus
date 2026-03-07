// DictusCore/Sources/DictusCore/Design/GlassModifier.swift
// Reusable glass effect modifier supporting iOS 26 Liquid Glass with graceful fallback.
import SwiftUI

/// Applies glass effect: `.glassEffect()` on iOS 26+, `.regularMaterial` on iOS 16-25.
///
/// WHY a custom modifier instead of applying material directly:
/// Centralizes the iOS version check. Every surface that should look "glassy" calls
/// `.dictusGlass()` and automatically gets the best available effect for the device.
/// When iOS 26 ships, all surfaces upgrade to Liquid Glass without any code changes.
public struct GlassModifier<S: Shape>: ViewModifier {
    public let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.regularMaterial))
        }
    }
}

/// Convenience View extension for applying glass effects.
public extension View {
    /// Apply glass effect with a custom shape (default: rounded rectangle with 16pt corners).
    ///
    /// - Parameter shape: The shape to use for the glass effect clipping.
    /// - Returns: View with glass effect applied.
    func dictusGlass<S: Shape>(in shape: S = RoundedRectangle(cornerRadius: 16)) -> some View {
        modifier(GlassModifier(shape: shape))
    }

    /// Apply glass effect optimized for toolbar/navigation bar surfaces.
    /// Uses Capsule shape for a pill-shaped glass background.
    func dictusGlassBar() -> some View {
        modifier(GlassModifier(shape: Capsule()))
    }
}
