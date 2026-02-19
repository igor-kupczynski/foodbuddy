import SwiftUI

struct DQSCategoryGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private var highQualityCategories: [DQSCategory] {
        DQSCategory.allCases.filter(\.isHighQuality)
    }

    private var lowQualityCategories: [DQSCategory] {
        DQSCategory.allCases.filter { !$0.isHighQuality }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("How to Use This") {
                    Text("Use this as a quick reference when assigning category and servings. Aim for the closest match, then estimate servings with the guide below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dqs-category-help-intro")
                }

                Section("High Quality Categories") {
                    ForEach(highQualityCategories, id: \.self) { category in
                        categoryCard(for: category)
                    }
                }

                Section("Low Quality Categories") {
                    ForEach(lowQualityCategories, id: \.self) { category in
                        categoryCard(for: category)
                    }
                }

                Section("Note") {
                    Text("Some foods can count in two categories. Example: sweetened yogurt can be both Dairy and Sweets.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dqs-category-help-double-counting")
                }
            }
            .navigationTitle("DQS Category Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("dqs-category-help-done")
                }
            }
        }
    }

    private func categoryCard(for category: DQSCategory) -> some View {
        let guide = category.guideContent

        return VStack(alignment: .leading, spacing: 6) {
            Text(category.displayName)
                .font(.headline)

            Text("Serving: \(guide.servingGuide)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dqs-category-help-serving-\(category.rawValue)")

            Text("Examples: \(guide.examples.joined(separator: ", "))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dqs-category-help-examples-\(category.rawValue)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dqs-category-help-row-\(category.rawValue)")
    }
}
