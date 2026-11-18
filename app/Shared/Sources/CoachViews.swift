import SwiftUI

/// The original idea's "you've only trained arms lately": the last two weeks
/// of logged volume, painted onto the body map region by region, with the
/// top regions and the untouched ones listed underneath.
struct MuscleBalanceCard: View {
    let balance: [MuscleRegion: Double]

    private var weights: [String: Double] {
        let peak = balance.values.max() ?? 0
        guard peak > 0 else { return [:] }
        var result: [String: Double] = [:]
        for muscle in muscles {
            if let share = balance[muscle.region], share > 0 {
                result[muscle.id] = share / peak
            }
        }
        return result
    }

    private var ranked: [(MuscleRegion, Double)] {
        balance.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var untouched: [MuscleRegion] {
        CoachEngine.majorRegions.filter { (balance[$0] ?? 0) == 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Muscle balance")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("Last 14 days")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if balance.isEmpty {
                Text("Log a few sessions to see which muscles you train and which you skip.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                HStack(spacing: 12) {
                    MuscleMapView(side: .front, weights: weights)
                        .frame(height: 190)
                    MuscleMapView(side: .back, weights: weights)
                        .frame(height: 190)
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

                ForEach(ranked.prefix(4), id: \.0) { region, share in
                    HStack(spacing: 10) {
                        Text(region.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 100, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppTheme.fill)
                                Capsule()
                                    .fill(AppTheme.brand)
                                    .frame(width: proxy.size.width * share)
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(region.displayName): \(Int((share * 100).rounded())) percent")
                }
                if !untouched.isEmpty {
                    Text("Not trained lately: " + untouched.map { $0.displayName.lowercased() }.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .cardStyle()
    }
}
