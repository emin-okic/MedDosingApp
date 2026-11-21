import SwiftUI

struct MonthYearPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let doseLogs: [DoseLog]
    let medications: [Medication]

    @State private var pickerYear: Int

    init(selectedDate: Binding<Date>, doseLogs: [DoseLog], medications: [Medication]) {
        self._selectedDate = selectedDate
        self.doseLogs = doseLogs
        self.medications = medications
        let currentYear = Calendar.current.component(.year, from: selectedDate.wrappedValue)
        self._pickerYear = State(initialValue: currentYear)
    }

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Year selector: < 2026 >
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                pickerYear -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.mint)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("Previous year")

                        Spacer()

                        Text(String(pickerYear))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                pickerYear += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.mint)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("Next year")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // 12 Months Grid (3 columns x 4 rows)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(1...12, id: \.self) { monthIndex in
                            monthCell(monthIndex: monthIndex)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    // Quick Jump to Today Button
                    Button {
                        selectedDate = calendar.startOfDay(for: .now)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.subheadline.weight(.semibold))
                            Text("Jump to Today")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel("Jump to today's date")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Select Month & Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(.mint)
    }

    private func monthCell(monthIndex: Int) -> some View {
        let selectedYear = calendar.component(.year, from: selectedDate)
        let selectedMonth = calendar.component(.month, from: selectedDate)
        let isSelected = (selectedYear == pickerYear && selectedMonth == monthIndex)

        let todayYear = calendar.component(.year, from: .now)
        let todayMonth = calendar.component(.month, from: .now)
        let isCurrentMonth = (todayYear == pickerYear && todayMonth == monthIndex)

        let monthName = calendar.shortMonthSymbols[monthIndex - 1]
        let adherence = monthAdherence(year: pickerYear, month: monthIndex)

        return Button {
            var components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
            components.year = pickerYear
            components.month = monthIndex

            let firstOfMonth = calendar.date(from: DateComponents(year: pickerYear, month: monthIndex, day: 1)) ?? Date()
            let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
            let maxDay = range?.count ?? 28
            components.day = min(components.day ?? 1, maxDay)

            if let targetDate = calendar.date(from: components) {
                selectedDate = calendar.startOfDay(for: targetDate)
            }
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Text(monthName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isSelected ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)

                if let adherence = adherence {
                    Text("\(adherence)%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected ? Color(red: 0.04, green: 0.08, blue: 0.12).opacity(0.85) : .mint)
                } else {
                    Text("No logs")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? Color(red: 0.04, green: 0.08, blue: 0.12).opacity(0.65) : .white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.mint : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCurrentMonth && !isSelected ? Color.mint.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isCurrentMonth && !isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.monthSymbols[monthIndex - 1]) \(pickerYear), \(adherence != nil ? "\(adherence!)% adherence" : "No logs")")
    }

    private func monthAdherence(year: Int, month: Int) -> Int? {
        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else { return nil }

        let logsInMonth = doseLogs.filter {
            let comp = calendar.dateComponents([.year, .month], from: $0.takenAt)
            return comp.year == year && comp.month == month
        }

        guard !logsInMonth.isEmpty else { return nil }

        var totalScheduled = 0
        let startOfToday = calendar.startOfDay(for: .now)

        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            if calendar.startOfDay(for: date) > startOfToday { continue }
            let weekday = Weekday.from(date: date)
            let dailyScheduled = medications.filter { $0.days.contains(weekday) }.reduce(0) { $0 + $1.times.count }
            totalScheduled += dailyScheduled
        }

        guard totalScheduled > 0 else { return nil }
        return min(100, Int((Double(logsInMonth.count) / Double(totalScheduled) * 100).rounded()))
    }
}
