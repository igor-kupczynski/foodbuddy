import SwiftUI

struct EntryRowView: View {
    let entry: MealEntry
    let imageStore: ImageStore

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.loggedAt, style: .date)
                    .font(.headline)
                Text(entry.loggedAt, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let statusText = photoSyncStatusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(photoSyncStatusColor)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.gray.opacity(0.2))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var thumbnailImage: PlatformImage? {
        if let filename = entry.photoAsset?.thumbnailFilename,
           let image = imageStore.loadImage(filename: filename) {
            return image
        }

        if let filename = entry.photoAsset?.fullImageFilename,
           let image = imageStore.loadImage(filename: filename) {
            return image
        }

        return imageStore.loadImage(filename: entry.imageFilename)
    }

    private var photoSyncStatusText: String? {
        guard let asset = entry.photoAsset else {
            return nil
        }

        switch asset.state {
        case .pending:
            return "Photo sync pending"
        case .failed:
            return "Photo sync failed"
        case .uploaded, .deleted:
            return nil
        }
    }

    private var photoSyncStatusColor: Color {
        guard let asset = entry.photoAsset else {
            return .secondary
        }

        switch asset.state {
        case .failed:
            return .red
        case .pending:
            return .secondary
        case .uploaded, .deleted:
            return .secondary
        }
    }
}
