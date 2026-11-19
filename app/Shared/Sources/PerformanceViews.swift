import Charts
import SwiftUI

extension PerformanceRecord {
    /// A value in the athlete's units: weights in kg or lb, the rest as recorded.
    func formatted(_ value: Double) -> String {
        if unit == "kg" { return WeightUnit.current.format(kg: value) }
        let number = Performances.number(value, unit: unit)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    var sourceLine: String {
        switch source {
        case .lift: "From your logged sets — the heaviest set each day."
        case .test: "From your tests in Progress."
        case .custom: "Added by you."
        }
    }
}

/// One performance on the twin: the best, how it moved in six weeks, a line.
struct PerformanceTile: View {
    let record: PerformanceRecord

    private var change: String? {
        guard let since = Calendar.current.date(byAdding: .day, value: -42, to: .now),
              let delta = record.improvement(since: since), abs(delta) > 0.0001 else { return nil }
        let amount = record.unit == "kg" ? WeightUnit.current.format(kg: abs(delta))
            : "\(Performances.number(abs(delta), unit: record.unit))\(record.unit.isEmpty ? "" : " \(record.unit)")"
        return delta > 0 ? "+\(amount) in 6 weeks" : "−\(amount) in 6 weeks"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.name)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
            BigFigure(record.best.map { record.formatted($0.value) } ?? "–", size: 30)
            Text(change ?? "Personal best")
                .font(.caption)
                .foregroundStyle(change == nil ? AppTheme.mutedText : (change?.hasPrefix("+") == true ? AppTheme.green : AppTheme.secondaryText))
            Spacer(minLength: 6)
            if record.history.count >= 2 {
                Chart(Array(record.history.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Day", point.date), y: .value("Value", point.value))
                        .foregroundStyle(AuraTone.training.mark)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 26)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(AuraBackground(.calm, focus: UnitPoint(x: 0.2, y: 0.4), radius: 120))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.name): best \(record.best.map { record.formatted($0.value) } ?? "none")")
    }
}

/// A performance up close: its best, its history, every result.
struct PerformanceDetailSheet: View {
    let record: PerformanceRecord
    @Environment(\.dismiss) private var dismiss
    @State private var addingResult = false
    @State private var confirmDelete = false

    /// V8: the best, big on the training (ember) card — the number the eye lands on.
    private var bestCard: some View {
        AuraCard(.training, focus: UnitPoint(x: 0.25, y: 0.55), radius: 200) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your best")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                BigFigure(record.best.map { record.formatted($0.value) } ?? "–", size: 64)
                if let best = record.best {
                    Text(best.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    bestCard
                    if record.history.count >= 2 {
                        Chart(Array(record.history.enumerated()), id: \.offset) { _, point in
                            LineMark(x: .value("Day", point.date), y: .value("Value", point.value))
                                .foregroundStyle(AuraTone.training.mark)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Day", point.date), y: .value("Value", point.value))
                                .foregroundStyle(AuraTone.training.mark)
                                .symbolSize(24)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(record.history.reversed().enumerated()), id: \.offset) { _, point in
                            HStack {
                                Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Spacer()
                                Text(record.formatted(point.value))
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.ink)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                        }
                    }
                    Text(record.sourceLine)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                    if case .custom(let id) = record.source {
                        Button { addingResult = true } label: { HeroCTALabel("Add a result") }
                            .buttonStyle(.primary)
                        Button("Remove this performance", role: .destructive) { confirmDelete = true }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .confirmationDialog("Remove \(record.name) and all its results?", isPresented: $confirmDelete, titleVisibility: .visible) {
                                Button("Remove", role: .destructive) {
                                    AcademyStore.save(AcademyStore.removingPerformance(id, in: AcademyStore.load()))
                                    dismiss()
                                }
                            }
                    }
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(record.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $addingResult, onDismiss: { dismiss() }) {
                AddPerformanceSheet(fixedName: record.name, fixedUnit: record.unit, fixedHigherIsBetter: record.higherIsBetter)
            }
        }
    }
}

/// Add a performance (or a new result for one): name, unit, which way is
/// better, the value and the day.
struct AddPerformanceSheet: View {
    var fixedName: String? = nil
    var fixedUnit: String? = nil
    var fixedHigherIsBetter: Bool? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "weight"
    @State private var customUnit = ""
    @State private var higherIsBetter = true
    @State private var valueText = ""
    @State private var date = Date.now

    private var units: [(id: String, title: String)] {
        [("weight", WeightUnit.current.rawValue), ("s", "seconds"), ("cm", "cm"), ("m", "metres"), ("reps", "reps"), ("level", "level"), ("other", "other")]
    }

    private var value: Double? { Double(valueText.replacingOccurrences(of: ",", with: ".")) }

    private var storedUnit: String {
        if let fixedUnit { return fixedUnit }
        switch unit {
        case "weight": return "kg"
        case "other": return customUnit.trimmingCharacters(in: .whitespaces)
        default: return unit
        }
    }

    private var canSave: Bool {
        value != nil && !(fixedName ?? name).trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if fixedName == nil {
                        field("What", TextField("Bench press, 5 km run, beep test…", text: $name))
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Measured in").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                                ForEach(units, id: \.id) { option in
                                    Button {
                                        unit = option.id
                                        higherIsBetter = option.id != "s"
                                    } label: {
                                        Text(option.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.ink)
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(Capsule().fill(unit == option.id ? AuraTone.training.mark.opacity(0.35) : Color.white.opacity(0.05)))
                                            .overlay { Capsule().strokeBorder(Color.white.opacity(unit == option.id ? 0.3 : 0.1), lineWidth: 1) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if unit == "other" { field("Unit", TextField("e.g. km/h", text: $customUnit)) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Better when it's").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                            HStack(spacing: 8) {
                                ForEach([true, false], id: \.self) { higher in
                                    Button { higherIsBetter = higher } label: {
                                        Text(higher ? "Higher" : "Lower")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.ink)
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(Capsule().fill(higherIsBetter == higher ? AuraTone.training.mark.opacity(0.35) : Color.white.opacity(0.05)))
                                            .overlay { Capsule().strokeBorder(Color.white.opacity(higherIsBetter == higher ? 0.3 : 0.1), lineWidth: 1) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    field(fixedUnit == "kg" || (fixedUnit == nil && unit == "weight") ? "Result (\(WeightUnit.current.rawValue))" : "Result",
                          valueField)
                    DatePicker("Day", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .foregroundStyle(AppTheme.ink)
                    Button(action: save) { HeroCTALabel("Save") }
                        .buttonStyle(.primary)
                        .disabled(!canSave)
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(fixedName ?? "Add a performance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var valueField: some View {
        #if os(iOS)
        TextField("0", text: $valueText).keyboardType(.decimalPad)
        #else
        TextField("0", text: $valueText)
        #endif
    }

    private func field(_ title: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
            content
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .padding(14)
                .glassSurface(cornerRadius: 14)
        }
    }

    private func save() {
        guard var number = value else { return }
        if storedUnit == "kg" { number = WeightUnit.current.kg(from: number) }
        let state = AcademyStore.recording(fixedName ?? name, unit: storedUnit, higherIsBetter: fixedHigherIsBetter ?? higherIsBetter,
                                           value: number, at: date, in: AcademyStore.load())
        AcademyStore.save(state)
        dismiss()
    }
}
