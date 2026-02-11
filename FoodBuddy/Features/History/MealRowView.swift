import SwiftUI

struct MealRowView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let meal: Meal
    let mealTypeName: String
    let imageStore: ImageStore

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(mealTypeName)
                    .font(.headline)
                    .lineLimit(1)

                if let aiPreview = trimmedAIPreview {
                    Text(aiPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(meal.entries.count) entr\(meal.entries.count == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(timeSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = latestThumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.gray.opacity(0.2))
                .frame(width: thumbnailSize, height: thumbnailSize)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var thumbnailSize: CGFloat {
        horizontalSizeClass == .regular ? 86 : 72
    }

    private var latestThumbnailImage: PlatformImage? {
        guard let latest = sortedEntries.first else {
            return nil
        }

        if let thumbnailFilename = latest.photoAsset?.thumbnailFilename,
           let image = imageStore.loadImage(filename: thumbnailFilename) {
            return image
        }

        if let fullFilename = latest.photoAsset?.fullImageFilename,
           let image = imageStore.loadImage(filename: fullFilename) {
            return image
        }

        return imageStore.loadImage(filename: latest.imageFilename)
    }

    private var sortedEntries: [MealEntry] {
        meal.entries.sorted(by: { $0.loggedAt > $1.loggedAt })
    }

    private var trimmedAIPreview: String? {
        guard let value = meal.aiDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private var timeSummary: String {
        guard let latest = sortedEntries.first else {
            return "No entries"
        }

        guard let oldest = sortedEntries.last else {
            return latest.loggedAt.formatted(date: .abbreviated, time: .shortened)
        }

        if Calendar.current.isDate(latest.loggedAt, inSameDayAs: oldest.loggedAt) {
            let day = latest.loggedAt.formatted(date: .abbreviated, time: .omitted)
            let start = oldest.loggedAt.formatted(date: .omitted, time: .shortened)
            let end = latest.loggedAt.formatted(date: .omitted, time: .shortened)
            return "\(day) • \(start)-\(end)"
        }

        let start = oldest.loggedAt.formatted(date: .abbreviated, time: .shortened)
        let end = latest.loggedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(start) -> \(end)"
    }
}
