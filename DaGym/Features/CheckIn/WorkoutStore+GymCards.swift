import Foundation
import SwiftData

/// One gym check-in card as the UI reads it.
struct GymCardInfo: Identifiable, Hashable {
    let id: UUID
    var name: String
    var value: String
    var symbology: GymCardSymbology
    var lastUsedAt: Date?
}

/// Gym check-in cards (features.md adopt 6). Sorted by `sortOrder`; the rail opens on the most
/// recently shown card.
extension WorkoutStore {
    func gymCards() -> [GymCardInfo] {
        let descriptor = FetchDescriptor<GymCardModel>(sortBy: [SortDescriptor(\.sortOrder)])
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(Self.cardInfo)
    }

    /// The card to open the rail on: the last one shown, else the first.
    func lastUsedGymCard() -> GymCardInfo? {
        let cards = gymCards()
        return cards.max { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) } ?? cards.first
    }

    /// Adds a card at the end of the rail; a blank name becomes "Gym card". Nil for an empty value.
    @discardableResult
    func addGymCard(name: String, value: String, symbology: GymCardSymbology) -> GymCardInfo? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? context.fetch(FetchDescriptor<GymCardModel>())) ?? []
        let model = GymCardModel(
            name: trimmedName.isEmpty ? "Gym card" : trimmedName, value: trimmedValue,
            symbology: symbology.rawValue, sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(model)
        save()
        return Self.cardInfo(model)
    }

    func renameGymCard(id: UUID, name: String) {
        guard let model = fetchGymCardModel(id: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.name = trimmed.isEmpty ? "Gym card" : trimmed
        save()
    }

    func deleteGymCard(id: UUID) {
        guard let model = fetchGymCardModel(id: id) else { return }
        context.delete(model)
        save()
    }

    /// Stamps the card as the one last shown so the rail reopens on it.
    func markGymCardUsed(id: UUID, at date: Date = Date()) {
        guard let model = fetchGymCardModel(id: id) else { return }
        model.lastUsedAt = date
        save()
    }

    /// Reorders the rail to `ids` (cards not listed keep their relative order after them).
    func reorderGymCards(_ ids: [UUID]) {
        let descriptor = FetchDescriptor<GymCardModel>(sortBy: [SortDescriptor(\.sortOrder)])
        let models = (try? context.fetch(descriptor)) ?? []
        let ordered = ids.compactMap { id in models.first { $0.id == id } }
        let rest = models.filter { model in !ids.contains(model.id) }
        for (index, model) in (ordered + rest).enumerated() {
            model.sortOrder = index
        }
        save()
    }

    private func fetchGymCardModel(id: UUID) -> GymCardModel? {
        var descriptor = FetchDescriptor<GymCardModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func cardInfo(_ model: GymCardModel) -> GymCardInfo {
        GymCardInfo(
            id: model.id, name: model.name, value: model.value,
            symbology: GymCardSymbology(rawValue: model.symbology) ?? .code128, lastUsedAt: model.lastUsedAt
        )
    }
}
