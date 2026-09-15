import CoreTransferable
import GymCore
import SwiftUI
import UniformTypeIdentifiers

/// The two shapes a workout card is exported in: Stories-shaped portrait or a square post.
enum WorkoutShareCardFormat: CaseIterable, Identifiable {
    case story
    case square

    var id: Self { self }

    /// Pixel size — the card renders at `scale = 1`, so points are pixels.
    var size: CGSize {
        switch self {
        case .story: CGSize(width: 1080, height: 1920)
        case .square: CGSize(width: 1080, height: 1080)
        }
    }

    var menuTitle: String {
        switch self {
        case .story: "Share Story Card"
        case .square: "Share Square Card"
        }
    }

    var symbol: String {
        switch self {
        case .story: "rectangle.portrait"
        case .square: "square"
        }
    }

    var filenameSuffix: String {
        switch self {
        case .story: "story"
        case .square: "square"
        }
    }
}

/// The rendered card as a PNG for `ShareLink` — Messages, Instagram, AirDrop all take it as an
/// image, and the suggested name keeps a saved file recognisable.
struct WorkoutShareImage: Transferable {
    var image: UIImage
    var filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { file in
            file.image.pngData() ?? Data()
        }
        .suggestedFileName { "\($0.filename).png" }
    }
}

/// Renders `WorkoutShareCardView` off-screen at the format's pixel size. Main actor because
/// `ImageRenderer` is. `reduceTransparency` is passed in (the accessibility environment keys
/// are read-only) so the card honours the setting of the screen it was shared from. The body
/// map's "hit" steps are four opacities of one hue, so they read the same under colour-vision
/// deficiency; the colour-blind ramp only exists for the recovery map, which the card never draws.
@MainActor
enum WorkoutShareCardRenderer {
    static func render(
        _ model: ShareCardModel, format: WorkoutShareCardFormat, preferences: Preferences,
        reduceTransparency: Bool = false
    ) -> UIImage? {
        let card = WorkoutShareCardView(model: model, format: format, reduceTransparency: reduceTransparency)
            .frame(width: format.size.width, height: format.size.height)
            .environment(preferences)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// The card itself: dark `DGColor` ground, condensed Barlow numbers, the muscles-hit body map
/// thumbnails and a small wordmark. Sized in pixels by the renderer, never by Dynamic Type —
/// it's an image, so every size here is fixed.
struct WorkoutShareCardView: View {
    var model: ShareCardModel
    var format: WorkoutShareCardFormat
    /// Drops the coral wash for a flat ground — the image equivalent of Reduce Transparency.
    var reduceTransparency = false

    private var isStory: Bool { format == .story }
    private var pad: CGFloat { 72 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DGColor.bgBase
            if !reduceTransparency {
                RadialGradient(
                    colors: [DGColor.coral.opacity(0.28), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: format.size.width * 0.9
                )
            }
            VStack(alignment: .leading, spacing: isStory ? 56 : 36) {
                header
                statRow
                if let prHeadline = model.prHeadline { prCard(prHeadline) }
                musclesRow
                Spacer(minLength: 0)
                wordmark
            }
            .padding(pad)
        }
        .frame(width: format.size.width, height: format.size.height)
        .clipped()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session complete".uppercased())
                .font(.custom(DGFont.Family.condensedBold, size: 32))
                .kerning(4)
                .foregroundStyle(DGColor.coralText)
            Text(model.title.uppercased())
                .font(.custom(DGFont.Family.condensedExtraBold, size: isStory ? 112 : 88))
                .foregroundStyle(DGColor.ink1)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(model.dateText)
                .font(.custom(DGFont.Family.medium, size: 34))
                .foregroundStyle(DGColor.ink3)
        }
        .padding(.top, isStory ? 120 : 0)
    }

    private var statRow: some View {
        HStack(alignment: .top, spacing: 24) {
            stat(model.durationText, label: "Time")
            stat(model.setsText, label: "Sets")
            stat(model.volumeText, label: model.distanceText.map { "Volume · \($0)" } ?? "Volume")
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.custom(DGFont.Family.condensedExtraBold, size: isStory ? 84 : 68))
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label.uppercased())
                .font(.custom(DGFont.Family.condensedBold, size: 26))
                .kerning(2)
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            DGColor.surface1.opacity(reduceTransparency ? 1 : 0.85), in: RoundedRectangle(cornerRadius: 28)
        )
    }

    private func prCard(_ headline: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Image(systemName: "star.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(DGColor.prGold)
                Text(headline.uppercased())
                    .font(.custom(DGFont.Family.condensedBold, size: 44))
                    .foregroundStyle(DGColor.prGold)
            }
            ForEach(model.prLines.prefix(isStory ? 5 : 3), id: \.self) { line in
                Text(line)
                    .font(.custom(DGFont.Family.medium, size: 32))
                    .foregroundStyle(DGColor.ink2)
                    .lineLimit(1)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DGColor.prGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(DGColor.prGold.opacity(0.5), lineWidth: 3))
    }

    private var musclesRow: some View {
        HStack(alignment: .center, spacing: 40) {
            BodyMapPair(intensity: model.musclesHit, height: isStory ? 420 : 300)
            VStack(alignment: .leading, spacing: 18) {
                Text("Muscles hit".uppercased())
                    .font(.custom(DGFont.Family.condensedBold, size: 30))
                    .kerning(3)
                    .foregroundStyle(DGColor.ink3)
                ForEach(model.topMuscles, id: \.muscle) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        Text(item.muscle.displayName)
                            .font(.custom(DGFont.Family.medium, size: 38))
                            .foregroundStyle(DGColor.ink1)
                        Text(item.percentText)
                            .font(.custom(DGFont.Family.condensedBold, size: 38))
                            .foregroundStyle(DGColor.ink3)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(DGColor.coral)
                .frame(width: 18, height: 40)
            Text("DaGym")
                .font(.custom(DGFont.Family.condensedExtraBold, size: 44))
                .foregroundStyle(DGColor.ink2)
        }
    }
}

#Preview("Story") {
    WorkoutShareCardView(
        model: ShareCardModel(
            summary: WorkoutSummary(
                durationSeconds: 3124, volumeKg: 6840, setsDone: 18,
                prs: [PersonalRecordInfo(exerciseName: "Bench", line: "82.5 × 8 (e1RM 102.5)")],
                musclesHit: [.chest: 1, .triceps: 0.6, .delts: 0.5]
            ),
            title: "Push A", unit: .kg, distanceUnit: .km
        ),
        format: .story
    )
    .environment(Preferences())
    .scaleEffect(0.3)
}
