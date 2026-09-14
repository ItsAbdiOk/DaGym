import Foundation

/// Equipment filter / picker options shared with `NewExerciseSheet`; also the equipment-profile
/// vocabulary `WorkoutStore+Equipment` stores, so its own file lets the watch compile it.
enum EquipmentOption: String, CaseIterable, Identifiable {
    case barbell, dumbbell, bodyweight, cable, machine, kettlebell, bands, ezBar, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .bodyweight: "Bodyweight"
        case .cable: "Cable"
        case .machine: "Machine"
        case .kettlebell: "Kettlebell"
        case .bands: "Bands"
        case .ezBar: "EZ Bar"
        case .other: "Other"
        }
    }
}
