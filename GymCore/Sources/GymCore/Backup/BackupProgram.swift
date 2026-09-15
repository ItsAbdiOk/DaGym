import Foundation

public struct BackupProgramWeek: Codable, Sendable, Identifiable {
    public var id: UUID
    public var index: Int
    public var kind: String

    public init(id: UUID, index: Int, kind: String) {
        self.id = id
        self.index = index
        self.kind = kind
    }
}

/// A multi-week program and which routines it cycles through.
public struct BackupProgram: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var weeks: Int
    public var startedAt: Date?
    public var completedAt: Date?
    public var isActive: Bool
    public var routineIDs: [UUID]
    public var createdAt: Date
    public var programWeeks: [BackupProgramWeek]

    public init(
        id: UUID, name: String, weeks: Int, startedAt: Date? = nil, completedAt: Date? = nil,
        isActive: Bool = false, routineIDs: [UUID] = [], createdAt: Date = Date(),
        programWeeks: [BackupProgramWeek] = []
    ) {
        self.id = id
        self.name = name
        self.weeks = weeks
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isActive = isActive
        self.routineIDs = routineIDs
        self.createdAt = createdAt
        self.programWeeks = programWeeks
    }
}

public struct BackupAchievement: Codable, Sendable, Identifiable {
    public var id: UUID
    public var milestoneID: String
    public var tier: String
    public var earnedAt: Date
    public var workoutID: UUID?

    public init(id: UUID, milestoneID: String, tier: String, earnedAt: Date, workoutID: UUID? = nil) {
        self.id = id
        self.milestoneID = milestoneID
        self.tier = tier
        self.earnedAt = earnedAt
        self.workoutID = workoutID
    }
}

/// The weekly schedule, newest row only — a nested `WeeklySchedule` from format 2, the app's
/// opaque JSON string in format 1. `resolvedSchedule` reads either.
public struct BackupSchedule: Codable, Sendable {
    public var schedule: WeeklySchedule?
    /// Format 1: the schedule as the app stored it. Still read; no longer written.
    public var scheduleJSON: String?
    public var updatedAt: Date

    public init(schedule: WeeklySchedule? = nil, scheduleJSON: String? = nil, updatedAt: Date) {
        self.schedule = schedule
        self.scheduleJSON = scheduleJSON
        self.updatedAt = updatedAt
    }

    public var resolvedSchedule: WeeklySchedule? {
        schedule ?? BackupLegacyJSON.decode(WeeklySchedule.self, from: scheduleJSON)
    }
}
