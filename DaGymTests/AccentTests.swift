import Foundation
import GymCore
import SwiftUI
import Testing

@testable import DaGym

/// Accent theme persistence and colour-token coverage (plan.md Phase 8).
@MainActor
@Suite("Accent theme")
struct AccentTests {
    /// A fresh, isolated `UserDefaults` suite per test — mirrors `PreferencesTests`.
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("accent persists across a fresh Preferences instance on the same suite")
    func accentRoundTrips() throws {
        let suite = makeSuite(#function)
        let first = Preferences(suite: suite)
        #expect(first.accent == .coral)

        first.accent = .violet
        let second = Preferences(suite: suite)
        #expect(second.accent == .violet)

        second.accent = .ice
        let third = Preferences(suite: suite)
        #expect(third.accent == .ice)
    }

    @Test("an unseeded suite defaults to coral")
    func defaultsToCoral() throws {
        let suite = makeSuite(#function)
        let preferences = Preferences(suite: suite)
        #expect(preferences.accent == .coral)
    }

    @Test("setting Preferences.accent updates DGColor.current")
    func settingAccentUpdatesDGColorCurrent() throws {
        let suite = makeSuite(#function)
        let preferences = Preferences(suite: suite)
        defer { preferences.accent = .coral }

        preferences.accent = .lime
        #expect(DGColor.current == .lime)

        preferences.accent = .ember
        #expect(DGColor.current == .ember)
    }

    @Test("every DGAccent's text variant differs between dark and light mode")
    func textVariantsDifferByScheme() throws {
        for accent in DGAccent.allCases {
            #expect(accent.text(dark: true) != accent.text(dark: false))
        }
    }

    @Test("every DGAccent's text variant differs from its base colour")
    func textVariantsDifferFromBase() throws {
        for accent in DGAccent.allCases {
            #expect(accent.text(dark: true) != accent.base(dark: true))
            #expect(accent.text(dark: false) != accent.base(dark: false))
        }
    }

    @Test("every non-coral DGAccent has distinct dark/light base values")
    func nonCoralBaseValuesDifferByScheme() throws {
        for accent in DGAccent.allCases where accent != .coral {
            #expect(accent.base(dark: true) != accent.base(dark: false))
        }
    }

    @Test("no two DGAccent cases share a base colour")
    func basesAreDistinctAcrossAccents() throws {
        let darkBases = DGAccent.allCases.map { $0.base(dark: true) }
        for (index, color) in darkBases.enumerated() {
            for other in darkBases[(index + 1)...] {
                #expect(color != other)
            }
        }
    }

    @Test("coral is pinned to the shipped hex the app has always used")
    func coralMatchesShippedHex() throws {
        // Pins the exact literal so a future accent refactor can't silently drift the default.
        let shippedCoral = Color(hex: 0xF4705C)
        #expect(DGAccent.coral.base(dark: true) == shippedCoral)
        #expect(DGAccent.coral.base(dark: false) == shippedCoral)

        let shippedCoralTextDark = Color(hex: 0xFF8F7A)
        let shippedCoralTextLight = Color(hex: 0xB83E2A)
        #expect(DGAccent.coral.text(dark: true) == shippedCoralTextDark)
        #expect(DGAccent.coral.text(dark: false) == shippedCoralTextLight)
    }

    @Test("DGAccent round-trips through Codable using its raw string")
    func accentCodable() throws {
        for accent in DGAccent.allCases {
            let data = try JSONEncoder().encode(accent)
            let decoded = try JSONDecoder().decode(DGAccent.self, from: data)
            #expect(decoded == accent)
        }
    }
}
