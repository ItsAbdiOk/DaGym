// Vendored from MuscleMap (https://github.com/melihcolpan/MuscleMap) by Melih Colpan,
// MIT-licensed (full text at DaGym/Vendor/MuscleMap/LICENSE). This file is not authored
// here — do not hand-edit; DaGym/Vendor is excluded from SwiftLint (see .swiftlint.yml).

//
//  MuscleSide.swift
//  MuscleMap
//
//  Created by Melih Colpan on 2026-02-09.
//  Copyright © 2026 Melih Colpan. All rights reserved.
//  Licensed under the MIT License.
//

// Vendoring change: the upstream `displayName` properties (and MMMuscle's
// `localizationKey`) were removed — they read from `Bundle.module`, which only exists in a
// SwiftPM target, and DaGym names muscles from its own GymCore `Muscle` enum instead.
import Foundation

/// Represents which side of the body a muscle belongs to.
public enum MuscleSide: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case both

}

/// Represents which face of the body to display.
public enum BodySide: String, CaseIterable, Codable, Sendable {
    case front
    case back

}

/// Represents the body gender model.
public enum BodyGender: String, CaseIterable, Codable, Sendable {
    case male
    case female

}
