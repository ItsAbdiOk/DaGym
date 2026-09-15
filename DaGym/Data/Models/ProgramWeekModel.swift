import Foundation
import SwiftData

/// One week of a `ProgramModel`'s cycle.
@Model
final class ProgramWeekModel {
    var id = UUID()
    var index: Int = 0
    /// "normal" / "deload" / "rest".
    var kind: String = "normal"

    /// Inverse declared on `ProgramModel.programWeeks`.
    var program: ProgramModel?

    init(id: UUID = UUID(), index: Int = 0, kind: String = "normal", program: ProgramModel? = nil) {
        self.id = id
        self.index = index
        self.kind = kind
        self.program = program
    }

    var weekKind: ProgramWeekKind {
        get { ProgramWeekKind(rawValue: kind) ?? .normal }
        set { kind = newValue.rawValue }
    }
}

/// A program week's training intent.
enum ProgramWeekKind: String, CaseIterable, Hashable {
    case normal
    case deload
    case rest

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .deload: "Deload"
        case .rest: "Rest"
        }
    }
}
