import SwiftUI
import Testing
import UIKit

@testable import DaGym

/// `DGColor.recoveryAccessible`/`consistencyAccessible` exist because `DGColor.recovery`'s
/// green→yellow→red sweep is exactly the axis deuteranopes/protanopes can't separate. The
/// property that actually has to hold for a "fresh → spent" ramp to stay legible under colour
/// blindness isn't a particular hue order — it's that the stops keep climbing in *lightness*,
/// since lightness survives every common form of colour vision deficiency. This suite checks
/// that property directly, plus that the two documented triggers (the system's "Differentiate
/// Without Color" setting, and `Preferences.colorBlindHeatmaps`) actually select it.
@Suite("Heatmap palette accessibility")
struct HeatmapPaletteTests {
    /// WCAG relative luminance (the standard "how bright does this read" measure, and the one
    /// that best survives colour-blindness simulation) computed from a `Color`'s own sRGB
    /// components — not from the hex literal used to build it, so this would still catch a
    /// regression that changed `Color(hex:)` itself.
    private func relativeLuminance(_ color: Color) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linearize(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    /// Fails on the shipped `recovery` ramp (green → yellow → orange → red dips back down in
    /// lightness at the red end), which is exactly why it needed a colour-blind-safe sibling
    /// instead of just being reordered.
    @Test("recoveryAccessible stops climb monotonically in luminance")
    func recoveryAccessibleIsMonotonicInLuminance() {
        let luminances = DGColor.recoveryAccessible.map(relativeLuminance)
        for (previous, next) in zip(luminances, luminances.dropFirst()) {
            #expect(next > previous)
        }
    }

    @Test("consistencyAccessible stops climb monotonically in luminance")
    func consistencyAccessibleIsMonotonicInLuminance() {
        let luminances = DGColor.consistencyAccessible.map(relativeLuminance)
        for (previous, next) in zip(luminances, luminances.dropFirst()) {
            #expect(next > previous)
        }
    }

    @Test("neither ramp trigger picks the accessible ramp by default")
    func neitherTriggerUsesTheDefaultRamp() {
        let ramp = DGColor.recoveryRamp(differentiateWithoutColor: false, colorBlindHeatmaps: false)
        #expect(ramp == DGColor.recovery)
        #expect(ramp != DGColor.recoveryAccessible)
    }

    @Test("system Differentiate Without Color alone selects the accessible ramp")
    func systemSettingAloneSelectsAccessibleRamp() {
        let ramp = DGColor.recoveryRamp(differentiateWithoutColor: true, colorBlindHeatmaps: false)
        #expect(ramp == DGColor.recoveryAccessible)
    }

    @Test("Preferences.colorBlindHeatmaps alone selects the accessible ramp")
    func preferenceAloneSelectsAccessibleRamp() {
        let ramp = DGColor.recoveryRamp(differentiateWithoutColor: false, colorBlindHeatmaps: true)
        #expect(ramp == DGColor.recoveryAccessible)
    }

    @Test("both triggers together still select the accessible ramp")
    func bothTriggersSelectAccessibleRamp() {
        let ramp = DGColor.recoveryRamp(differentiateWithoutColor: true, colorBlindHeatmaps: true)
        #expect(ramp == DGColor.recoveryAccessible)
    }

    /// `Preferences.colorBlindHeatmaps` itself: off by default, and the toggle Settings writes to
    /// persists through `UserDefaults` the same way every other `Preferences` bool does.
    @MainActor
    @Test("Preferences.colorBlindHeatmaps defaults to false and persists")
    func colorBlindHeatmapsPersists() {
        let suiteName = "HeatmapPaletteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(suite: defaults)
        #expect(preferences.colorBlindHeatmaps == false)

        preferences.colorBlindHeatmaps = true
        #expect(defaults.bool(forKey: Preferences.Key.colorBlindHeatmaps) == true)

        let reloaded = Preferences(suite: defaults)
        #expect(reloaded.colorBlindHeatmaps == true)
    }
}
