import SwiftUI
import UIKit

struct MockCameraCaptureView: View {
    let onImagePicked: (PlatformImage) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)

                Text("Mock Camera")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("UI-test-only capture surface.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("mock-camera-cancel")

                    Button("Use Mock Photo") {
                        let image = makeMockImage()
                        dismiss()
                        DispatchQueue.main.async {
                            onImagePicked(image)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("mock-camera-use-photo")
                }
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mock-camera-root")
    }

    private func makeMockImage() -> PlatformImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let insetRect = CGRect(x: 12, y: 12, width: 40, height: 40)
            UIColor.systemBlue.setFill()
            context.fill(insetRect)
        }
    }
}
