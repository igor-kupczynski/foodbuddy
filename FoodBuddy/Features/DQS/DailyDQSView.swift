import SwiftData
import SwiftUI

struct DailyDQSView: View {
    private struct MealFoodItemGroup: Identifiable {
        let meal: Meal
        let mealTypeName: String
        let items: [FoodItem]

        var id: UUID { meal.id }
    }

    @Query private var meals: [Meal]
    @Query(sort: [SortDescriptor(\MealType.displayName)]) private var mealTypes: [MealType]

    private let date: Date
    private let scoringEngine = DQSScoringEngine()

    @State private var isShowingManualItemSheet = false

    init(date: Date) {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        self.date = dayStart
        _meals = Query(
            filter: #Predicate<Meal> { meal in
                meal.createdAt >= dayStart && meal.createdAt < dayEnd
            },
            sort: [SortDescriptor(\Meal.updatedAt, order: .reverse)]
        )
    }

    private var dailyScore: DQSScoringEngine.DailyScore {
        scoringEngine.score(for: date, foodItems: meals.flatMap(\.foodItems))
    }

    private var highQualityBreakdowns: [DQSScoringEngine.CategoryBreakdown] {
        dailyScore.categoryBreakdowns.filter { $0.category.isHighQuality }
    }

    private var lowQualityBreakdowns: [DQSScoringEngine.CategoryBreakdown] {
        dailyScore.categoryBreakdowns.filter { !$0.category.isHighQuality }
    }

    private var mealGroups: [MealFoodItemGroup] {
        meals.compactMap { meal in
            let items = meal.foodItems.sorted(by: { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.category.displayName < rhs.category.displayName
                }
                return lhs.name < rhs.name
            })

            guard !items.isEmpty else {
                return nil
            }

            return MealFoodItemGroup(
                meal: meal,
                mealTypeName: mealTypes.first(where: { $0.id == meal.typeId })?.displayName ?? "Meal",
                items: items
            )
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)

                    Spacer()

                    DailyScoreBadge(score: dailyScore.totalScore)
                        .accessibilityIdentifier("dqs-daily-total-score")
                }

                Text(dailyScore.interpretation)
                    .foregroundStyle(.secondary)
            }

            Section("High Quality") {
                ForEach(highQualityBreakdowns, id: \.category) { breakdown in
                    categoryRow(breakdown)
                        .accessibilityIdentifier("dqs-category-row-\(breakdown.category.rawValue)")
                }
            }

            Section("Low Quality") {
                ForEach(lowQualityBreakdowns, id: \.category) { breakdown in
                    categoryRow(breakdown)
                        .accessibilityIdentifier("dqs-category-row-\(breakdown.category.rawValue)")
                }
            }

            Section {
                if mealGroups.isEmpty {
                    Text("No food items for this day yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mealGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.mealTypeName)
                                .font(.subheadline.weight(.semibold))

                            ForEach(group.items) { item in
                                NavigationLink {
                                    FoodItemEditView(foodItem: item)
                                } label: {
                                    foodItemRow(item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("dqs-food-item-row-\(item.id.uuidString)")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(item.name)
                                .accessibilityValue(
                                    "\(item.category.displayName), \(item.servings.formatted(.number.precision(.fractionLength(0...1)))) servings"
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("Inspired by Racing Weight by Matt Fitzgerald")
            }
        }
        .navigationTitle("Daily DQS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("+ Add Food Item") {
                    isShowingManualItemSheet = true
                }
                .accessibilityIdentifier("dqs-add-food-item")
            }
        }
        .sheet(isPresented: $isShowingManualItemSheet) {
            ManualFoodItemSheet(source: .day(date: date))
        }
    }

    private func categoryRow(_ breakdown: DQSScoringEngine.CategoryBreakdown) -> some View {
        HStack {
            Text(breakdown.category.displayName)

            Spacer()

            Text("\(breakdown.servings.formatted(.number.precision(.fractionLength(0...1)))) srv")
                .foregroundStyle(.secondary)

            Text(pointsText(for: breakdown.points))
                .fontWeight(.semibold)
                .foregroundStyle(breakdown.points >= 0 ? .green : .red)
        }
    }

    private func foodItemRow(_ item: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                Text("\(item.servings.formatted(.number.precision(.fractionLength(0...1)))) srv")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.category.displayName)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
    }

    private func pointsText(for points: Int) -> String {
        if points > 0 {
            return "+\(points)"
        }
        return "\(points)"
    }
}
