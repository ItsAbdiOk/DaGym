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

    @Test("the default accent is pinned to the redesign's terracotta")
    func coralMatchesShippedHex() throws {
        // Pins the exact literals (the prototype's `--ac` / `--act`) so a future accent refactor
        // can't silently drift the default.
        #expect(DGAccent.coral.base(dark: false) == Color(hex: 0xB4552F))
        #expect(DGAccent.coral.base(dark: true) == Color(hex: 0xC96A42))
        #expect(DGAccent.coral.text(dark: false) == Color(hex: 0x9A4524))
        #expect(DGAccent.coral.text(dark: true) == Color(hex: 0xE59470))
    }

    @Test("coral, coralText, coralWash and hitSteps are the same value on every read within one accent")
    func accentColoursAreStableWithinAnAccent() throws {
        let before = DGColor.current
        defer { DGColor.current = before }
        DGColor.current = .coral
        // A fresh `UIColor` provider per access used to make every read unequal to the last, so
        // no view touching coral could ever be skipped by SwiftUI's diffing.
        #expect(DGColor.coral == DGColor.coral)
        #expect(DGColor.coralText == DGColor.coralText)
        #expect(DGColor.coralWash == DGColor.coralWash)
        #expect(DGColor.hitSteps == DGColor.hitSteps)
    }

    @Test("the per-accent cache never pins the previous accent's colour")
    func accentColoursChangeWithTheAccent() throws {
        let before = DGColor.current
        defer { DGColor.current = before }
        let environment = EnvironmentValues()
        DGColor.current = .coral
        let coral = DGColor.coral.resolve(in: environment)
        DGColor.current = .violet
        let violet = DGColor.coral.resolve(in: environment)
        #expect(coral != violet)
        DGColor.current = .coral
        #expect(DGColor.coral.resolve(in: environment) == coral)
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
