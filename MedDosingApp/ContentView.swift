import SwiftUI
import UserNotifications

enum DayAdherenceStatus {
    case noneScheduled
    case complete
    case partial
    case noneTaken
    case upcoming
}

struct ContentView: View {
    @State private var medications: [Medication] = MedicationStore.load([Medication].self, key: "medications")
    @State private var doseLogs: [DoseLog] = MedicationStore.load([DoseLog].self, key: "doseLogs")
    @State private var notificationStatus = ""
    @State private var selectedMedication: Medication?
    @State private var isShowingMedicationsList = false
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var isShowingMonthPicker = false

    private var selectedDayDoses: [ScheduledDose] {
        let weekday = Weekday.from(date: selectedDate)
        return medications.flatMap { medication in
            guard medication.days.contains(weekday) else { return [ScheduledDose]() }
            return medication.times.map { ScheduledDose(medication: medication, time: $0) }
        }
        .sorted { $0.time.sortOrder < $1.time.sortOrder }
    }

    private var takenForSelectedDateCount: Int {
        selectedDayDoses.filter { dose in
            doseLogs.contains {
                $0.medicationID == dose.medication.id &&
                $0.doseTime == dose.time &&
                Calendar.current.isDate($0.takenAt, inSameDayAs: selectedDate)
            }
        }.count
    }

    private var adherencePercentage: Int {
        guard !selectedDayDoses.isEmpty else { return 0 }
        return Int((Double(takenForSelectedDateCount) / Double(selectedDayDoses.count) * 100).rounded())
    }

    private var daysInSelectedMonth: [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return [] }
        var dates: [Date] = []
        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            dates.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        return dates
    }

    private var monthlyAdherenceData: (percentage: Int, subtitle: String) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: selectedDate)
        let month = calendar.component(.month, from: selectedDate)

        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return (0, "No data available")
        }

        let logsInMonth = doseLogs.filter {
            let comp = calendar.dateComponents([.year, .month], from: $0.takenAt)
            return comp.year == year && comp.month == month
        }

        let startOfToday = calendar.startOfDay(for: .now)
        var totalScheduled = 0

        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            let isFutureMonth = startOfMonth > startOfToday
            if !isFutureMonth && calendar.startOfDay(for: date) > startOfToday {
                continue
            }
            let weekday = Weekday.from(date: date)
            let dailyScheduled = medications.filter { $0.days.contains(weekday) }.reduce(0) { $0 + $1.times.count }
            totalScheduled += dailyScheduled
        }

        guard totalScheduled > 0 else {
            return (0, "No doses scheduled this month")
        }

        let pct = min(100, Int((Double(logsInMonth.count) / Double(totalScheduled) * 100).rounded()))
        let subtitle = "\(logsInMonth.count) of \(totalScheduled) doses logged"
        return (pct, subtitle)
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.08, blue: 0.12)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    dateNavigator
                    monthlyAdherenceBanner
                    progressCard
                    scheduleSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .tint(.mint)
        .preferredColorScheme(.dark)
        .onChange(of: medications) { _, newValue in
            MedicationStore.save(newValue, key: "medications")
        }
        .onChange(of: doseLogs) { _, newValue in
            MedicationStore.save(newValue, key: "doseLogs")
        }
        .sheet(item: $selectedMedication) { medication in
            MedicationEditorView(
                medication: medication,
                onSave: updateMedication,
                onDelete: deleteMedication
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingMedicationsList) {
            MedicationsManagementView(
                medications: $medications,
                onAddMedication: addMedication,
                onUpdateMedication: updateMedication,
                onDeleteMedication: deleteMedication
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingMonthPicker) {
            MonthYearPickerSheet(
                selectedDate: $selectedDate,
                doseLogs: doseLogs,
                medications: medications
            )
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    if Calendar.current.isDateInToday(selectedDate) {
                        Text("Good \(timeOfDayGreeting)")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    } else {
                        HStack(spacing: 6) {
                            Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                            if Calendar.current.isDateInYesterday(selectedDate) {
                                Text("(Yesterday)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.mint)
                            } else if Calendar.current.isDateInTomorrow(selectedDate) {
                                Text("(Tomorrow)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.mint)
                            }
                        }
                        Text(selectedDate.formatted(.dateTime.month(.wide).day().year()))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Spacer()

                Button {
                    isShowingMedicationsList = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                            .font(.subheadline)
                        Text("Meds (\(medications.count))")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.mint, in: Capsule())
                    .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                }
                .accessibilityLabel("Manage medications, \(medications.count) active")
            }

            if !notificationStatus.isEmpty {
                Text(notificationStatus)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.mint)
                    .transition(.opacity)
            }
        }
    }

    private var dateNavigator: some View {
        VStack(spacing: 12) {
            // Month & Year Header (EveryDollar style)
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.mint)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Previous month")

                Spacer()

                Button {
                    isShowingMonthPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.mint)
                        Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.mint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .accessibilityLabel("Switch month and year, currently \(selectedDate.formatted(.dateTime.month(.wide).year()))")

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.mint)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Next month")
            }

            // Day Stepper & Horizontal Day Strip
            HStack(spacing: 8) {
                Button {
                    changeDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 60)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Previous day")

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(daysInSelectedMonth, id: \.self) { date in
                                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                let isToday = Calendar.current.isDateInToday(date)
                                let status = adherenceStatus(for: date)

                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selectedDate = Calendar.current.startOfDay(for: date)
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(date.formatted(.dateTime.weekday(.narrow)))
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(isSelected ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white.opacity(0.6))

                                        Text(date.formatted(.dateTime.day()))
                                            .font(.system(size: 15, weight: isSelected ? .bold : .semibold))
                                            .foregroundStyle(isSelected ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)

                                        Circle()
                                            .fill(statusColor(for: status, isSelected: isSelected))
                                            .frame(width: 5, height: 5)
                                            .opacity(status == .noneScheduled ? 0 : 1)
                                    }
                                    .frame(width: 42, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(isSelected ? Color.mint : (isToday ? Color.white.opacity(0.12) : Color.white.opacity(0.05)))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(isToday && !isSelected ? Color.mint.opacity(0.6) : Color.white.opacity(0.06), lineWidth: isToday && !isSelected ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(Calendar.current.startOfDay(for: date))
                                .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day())), \(isSelected ? "Selected" : "")")
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onAppear {
                        proxy.scrollTo(Calendar.current.startOfDay(for: selectedDate), anchor: .center)
                    }
                    .onChange(of: selectedDate) { _, newDate in
                        withAnimation {
                            proxy.scrollTo(Calendar.current.startOfDay(for: newDate), anchor: .center)
                        }
                    }
                }

                Button {
                    changeDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 60)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Next day")
            }
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var monthlyAdherenceBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 3.5)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: CGFloat(monthlyAdherenceData.percentage) / 100)
                    .stroke(Color.mint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 32, height: 32)

                Text("\(monthlyAdherenceData.percentage)%")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedDate.formatted(.dateTime.month(.wide))) Adherence")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text(monthlyAdherenceData.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            if !Calendar.current.isDateInToday(selectedDate) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedDate = Calendar.current.startOfDay(for: .now)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2.weight(.bold))
                        Text("Today")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.mint.opacity(0.2), in: Capsule())
                    .overlay(Capsule().stroke(Color.mint.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(Color.mint)
                }
                .accessibilityLabel("Jump back to today")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var progressCard: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 10)
                    .frame(width: 82, height: 82)

                Circle()
                    .trim(from: 0, to: CGFloat(adherencePercentage) / 100)
                    .stroke(
                        Color.mint,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 82, height: 82)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: adherencePercentage)

                VStack(spacing: 0) {
                    Text("\(adherencePercentage)%")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("done")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(progressCardTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(takenForSelectedDateCount) of \(selectedDayDoses.count) doses logged")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))

                Text(progressEncouragement)
                    .font(.caption)
                    .foregroundStyle(.mint)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var progressCardTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today's Progress"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday's Progress"
        } else if Calendar.current.isDateInTomorrow(selectedDate) {
            return "Tomorrow's Progress"
        } else {
            return "\(selectedDate.formatted(.dateTime.month(.abbreviated).day())) Progress"
        }
    }

    private var progressEncouragement: String {
        if selectedDayDoses.isEmpty { return "No doses scheduled for this day" }
        if takenForSelectedDateCount == selectedDayDoses.count {
            return Calendar.current.isDateInToday(selectedDate) ? "All done for today! Great job." : "All doses logged for this day!"
        }
        let remaining = selectedDayDoses.count - takenForSelectedDateCount
        let isPast = Calendar.current.startOfDay(for: selectedDate) < Calendar.current.startOfDay(for: .now)
        if isPast {
            return "\(remaining) \(remaining == 1 ? "dose was" : "doses were") missed or not logged"
        } else if Calendar.current.isDateInToday(selectedDate) {
            return "\(remaining) remaining today"
        } else {
            return "\(remaining) scheduled for this day"
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(scheduleSectionTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(Weekday.from(date: selectedDate).accessibilityName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.mint)
            }

            if selectedDayDoses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 38))
                        .foregroundStyle(.mint)
                        .padding(.top, 16)
                    Text("No doses scheduled for this day")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Tap 'Meds' above to manage your schedule and days.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(selectedDayDoses) { dose in
                    doseRow(dose)
                }
            }
        }
    }

    private var scheduleSectionTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today's Schedule"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday's Schedule"
        } else if Calendar.current.isDateInTomorrow(selectedDate) {
            return "Tomorrow's Schedule"
        } else {
            return "\(selectedDate.formatted(.dateTime.month(.abbreviated).day())) Schedule"
        }
    }

    private func doseRow(_ dose: ScheduledDose) -> some View {
        let isTaken = doseLogs.contains {
            $0.medicationID == dose.medication.id &&
            $0.doseTime == dose.time &&
            Calendar.current.isDate($0.takenAt, inSameDayAs: selectedDate)
        }

        return Button {
            toggleDose(dose, currentlyTaken: isTaken)
        } label: {
            HStack(spacing: 16) {
                Button {
                    toggleDose(dose, currentlyTaken: isTaken)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isTaken ? Color.mint : Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                        if isTaken {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isTaken ? "Mark dose as not taken" : "Mark dose as taken")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(dose.medication.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(isTaken ? .white.opacity(0.55) : .white)
                            .strikethrough(isTaken, color: .white.opacity(0.55))

                        if dose.medication.isACAPreventive {
                            HStack(spacing: 3) {
                                Image(systemName: "shield.checkmark.fill")
                                    .font(.system(size: 8))
                                Text("$0 ACA")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.mint.opacity(0.2), in: Capsule())
                            .foregroundStyle(.mint)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: dose.time.symbol)
                            .font(.caption2)
                        Text("\(dose.time.title) • \(dose.time.displayTime)")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                }

                Spacer()

                Button {
                    selectedMedication = dose.medication
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(dose.medication.name)")
            }
            .padding(16)
            .background(isTaken ? .white.opacity(0.04) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isTaken ? .white.opacity(0.05) : .white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }

    private func toggleDose(_ dose: ScheduledDose, currentlyTaken: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if currentlyTaken {
                doseLogs.removeAll {
                    $0.medicationID == dose.medication.id &&
                    $0.doseTime == dose.time &&
                    Calendar.current.isDate($0.takenAt, inSameDayAs: selectedDate)
                }
            } else {
                let takenDate: Date
                if Calendar.current.isDateInToday(selectedDate) {
                    takenDate = Date.now
                } else {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                    components.hour = dose.time.hour
                    components.minute = dose.time.minute
                    takenDate = Calendar.current.date(from: components) ?? selectedDate
                }

                doseLogs.append(
                    DoseLog(
                        id: UUID(),
                        medicationID: dose.medication.id,
                        doseTime: dose.time,
                        takenAt: takenDate
                    )
                )
            }
        }
    }

    private func changeMonth(by offset: Int) {
        let calendar = Calendar.current
        guard let newDate = calendar.date(byAdding: .month, value: offset, to: selectedDate) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = calendar.startOfDay(for: newDate)
        }
    }

    private func changeDay(by offset: Int) {
        let calendar = Calendar.current
        guard let newDate = calendar.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = calendar.startOfDay(for: newDate)
        }
    }

    private func adherenceStatus(for date: Date) -> DayAdherenceStatus {
        let weekday = Weekday.from(date: date)
        let scheduledDosesForDay = medications.filter { $0.days.contains(weekday) }.reduce(0) { $0 + $1.times.count }
        guard scheduledDosesForDay > 0 else { return .noneScheduled }

        let takenCount = doseLogs.filter { Calendar.current.isDate($0.takenAt, inSameDayAs: date) }.count

        if takenCount >= scheduledDosesForDay {
            return .complete
        } else if takenCount > 0 {
            return .partial
        } else {
            let startOfToday = Calendar.current.startOfDay(for: .now)
            let startOfTarget = Calendar.current.startOfDay(for: date)
            if startOfTarget > startOfToday {
                return .upcoming
            } else {
                return .noneTaken
            }
        }
    }

    private func statusColor(for status: DayAdherenceStatus, isSelected: Bool) -> Color {
        if isSelected {
            switch status {
            case .complete: return Color(red: 0.04, green: 0.08, blue: 0.12)
            case .partial: return Color(red: 0.85, green: 0.45, blue: 0.1)
            case .noneTaken: return Color(red: 0.75, green: 0.15, blue: 0.15)
            case .upcoming, .noneScheduled: return Color(red: 0.04, green: 0.08, blue: 0.12).opacity(0.4)
            }
        } else {
            switch status {
            case .complete: return Color.mint
            case .partial: return Color.orange
            case .noneTaken: return Color.red.opacity(0.85)
            case .upcoming: return Color.white.opacity(0.3)
            case .noneScheduled: return Color.clear
            }
        }
    }

    private func addMedication(_ medication: Medication) {
        medications.append(medication)
        scheduleNotifications()
    }

    private func updateMedication(_ medication: Medication) {
        if let index = medications.firstIndex(where: { $0.id == medication.id }) {
            medications[index] = medication
            scheduleNotifications()
        }
    }

    private func deleteMedication(_ medication: Medication) {
        medications.removeAll { $0.id == medication.id }
        doseLogs.removeAll { $0.medicationID == medication.id }
        scheduleNotifications()
    }

    private func scheduleNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self.notificationStatus = "Reminders updated"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.notificationStatus = ""
                    }
                }
            }
        }
    }
}

// MARK: - Medications Management View

private struct MedicationsManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var medications: [Medication]
    let onAddMedication: (Medication) -> Void
    let onUpdateMedication: (Medication) -> Void
    let onDeleteMedication: (Medication) -> Void

    @State private var searchText = ""
    @State private var selectedMedicationToEdit: Medication?
    @State private var isShowingAddMedication = false
    @State private var isShowingACAList = false
    @State private var prefilledACAMed: ACAPreventiveMedication?
    @State private var isShowingAddFromACA = false

    private var filteredMedications: [Medication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return medications }
        return medications.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var totalDailyDoses: Int {
        medications.reduce(0) { $0 + $1.times.count }
    }

    private var totalMonthlyCost: Double {
        medications.reduce(0.0) { $0 + $1.monthlyCost }
    }

    private var acaCoveredCount: Int {
        medications.filter { $0.isACAPreventive }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        acaBrowseCard

                        if !medications.isEmpty {
                            statsBanner
                        }

                        if medications.isEmpty {
                            emptyStateView
                        } else if filteredMedications.isEmpty {
                            noSearchResultsView
                        } else {
                            medicationsList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .searchable(text: $searchText, prompt: "Search medications")
            }
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddMedication = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                            .frame(width: 32, height: 32)
                            .background(Color.mint, in: Circle())
                    }
                    .accessibilityLabel("Add medication")
                }
            }
            .sheet(item: $selectedMedicationToEdit) { medication in
                MedicationEditorView(
                    medication: medication,
                    onSave: { updated in
                        onUpdateMedication(updated)
                    },
                    onDelete: { deleted in
                        onDeleteMedication(deleted)
                    }
                )
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $isShowingAddMedication) {
                AddMedicationSheet { newMed in
                    onAddMedication(newMed)
                }
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $isShowingACAList) {
                ACAPreventiveListView { selectedMed in
                    prefilledACAMed = selectedMed
                    isShowingAddFromACA = true
                }
            }
            .sheet(isPresented: $isShowingAddFromACA) {
                AddMedicationSheet(
                    initialName: prefilledACAMed?.name ?? "",
                    initialCost: 0.0
                ) { newMed in
                    onAddMedication(newMed)
                }
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
        }
        .tint(.mint)
        .preferredColorScheme(.dark)
    }

    private var acaBrowseCard: some View {
        Button {
            isShowingACAList = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shield.checkmark.fill")
                    .font(.title2)
                    .foregroundStyle(.mint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ACA $0 Copay Preventive Drug List")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Search 340+ federally mandated $0 copay medications.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
            }
            .padding(14)
            .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.mint.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var statsBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(medications.count) Active \(medications.count == 1 ? "Medication" : "Medications")")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(totalDailyDoses) scheduled daily \(totalDailyDoses == 1 ? "dose" : "doses")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                }

                Spacer()

                Image(systemName: "cross.vial.fill")
                    .font(.title2)
                    .foregroundStyle(.mint)
                    .frame(width: 48, height: 48)
                    .background(.mint.opacity(0.2), in: Circle())
            }

            Divider()
                .background(.white.opacity(0.12))

            HStack {
                Label {
                    Text("Monthly Medication Cost:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                } icon: {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(.mint)
                }

                Spacer()

                Text(totalMonthlyCost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")) + "/mo")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(totalMonthlyCost == 0 ? Color.mint : .white)

                if acaCoveredCount > 0 {
                    Text("(\(acaCoveredCount) $0 ACA)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.mint)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.25, blue: 0.28), Color(red: 0.08, green: 0.15, blue: 0.21)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.mint.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: "pills.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.mint)
            }
            .padding(.top, 40)

            VStack(spacing: 6) {
                Text("No Medications Yet")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Add your medications to receive reminders, track daily doses, and monitor monthly costs.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                isShowingAddMedication = true
            } label: {
                Label("Add Your First Medication", systemImage: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 32)
            Text("No medications match '\(searchText)'")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text("Check the spelling or tap '+' to add this medication.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var medicationsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("All Medications")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(filteredMedications.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.mint, in: Capsule())
            }
            .padding(.horizontal, 4)

            ForEach(filteredMedications) { medication in
                medicationCard(medication)
            }

            Button {
                isShowingAddMedication = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add another medication")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.mint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.mint.opacity(0.35), lineWidth: 1)
                )
            }
            .padding(.top, 8)
        }
    }

    private func medicationCard(_ medication: Medication) -> some View {
        Button {
            selectedMedicationToEdit = medication
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "pill.fill")
                        .font(.title3)
                        .foregroundStyle(.mint)
                        .frame(width: 44, height: 44)
                        .background(.mint.opacity(0.18), in: Circle())
                        .overlay(Circle().stroke(.mint.opacity(0.3), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(medication.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            Label(medication.frequencyLabel, systemImage: "clock")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))

                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))

                            Label(medication.daysLabel, systemImage: "calendar")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Text("Edit")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.mint, in: Capsule())
                }

                HStack(spacing: 8) {
                    ForEach(DoseTime.allCases.filter { medication.times.contains($0) }) { time in
                        HStack(spacing: 5) {
                            Image(systemName: time.symbol)
                                .font(.caption2)
                            Text("\(time.title) (\(time.displayTime))")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                    }

                    Spacer()

                    // Cost Pill & ACA Badge
                    HStack(spacing: 6) {
                        if medication.isACAPreventive {
                            HStack(spacing: 3) {
                                Image(systemName: "shield.checkmark.fill")
                                    .font(.system(size: 9))
                                Text("ACA $0")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.mint.opacity(0.2), in: Capsule())
                            .foregroundStyle(.mint)
                        }

                        Text(medication.formattedMonthlyCost + "/mo")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(medication.monthlyCost == 0 ? .mint : .white)
                    }
                }
            }
            .padding(16)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                selectedMedicationToEdit = medication
            } label: {
                Label("Edit Medication", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDeleteMedication(medication)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(medication.name), \(medication.frequencyLabel), \(medication.daysLabel), monthly cost \(medication.formattedMonthlyCost)")
    }
}

// MARK: - Add Medication Sheet

private struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Medication) -> Void

    @State private var medicationName: String
    @State private var monthlyCost: Double
    @State private var selectedFrequency = 1
    @State private var selectedDays = Set(Weekday.allCases)
    @State private var selectedTimes: Set<DoseTime> = [.morning]

    init(
        initialName: String = "",
        initialCost: Double = 0.0,
        onSave: @escaping (Medication) -> Void
    ) {
        self.onSave = onSave
        _medicationName = State(initialValue: initialName)
        _monthlyCost = State(initialValue: initialCost)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.mint)
                                .frame(width: 52, height: 52)
                                .background(.mint.opacity(0.18), in: Circle())
                                .overlay(Circle().stroke(.mint.opacity(0.3), lineWidth: 1))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("New Medication")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                Text("Add to your daily schedule and reminders.")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .padding(.bottom, 4)

                        // Name Editor with In-line predictive suggestions
                        MedicationNameEditor(name: $medicationName) { suggested in
                            medicationName = suggested.name
                            monthlyCost = 0.0
                        }

                        // Monthly Cost Editor (defaults to $0.00)
                        MedicationCostEditor(monthlyCost: $monthlyCost, medicationName: medicationName)

                        // Daily frequency
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Daily frequency", systemImage: "repeat")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            Picker("Times per day", selection: $selectedFrequency) {
                                ForEach(1...3, id: \.self) { count in
                                    Text("\(count)x daily").tag(count)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedFrequency) { _, count in
                                selectedTimes = Set(DoseTime.allCases.prefix(count))
                            }

                            Text("Reminder times")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.top, 4)

                            HStack(spacing: 8) {
                                ForEach(DoseTime.allCases) { time in
                                    Button {
                                        toggleTime(time)
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: time.symbol)
                                                .font(.subheadline)
                                            Text(time.title)
                                                .font(.caption.weight(.bold))
                                            Text(time.displayTime)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedTimes.contains(time) ? Color.mint : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .foregroundStyle(selectedTimes.contains(time) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(selectedTimes.contains(time) ? Color.mint : Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        // Days of week
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Days of the week", systemImage: "calendar")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            Text("Select the days you need to take this medication.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))

                            HStack(spacing: 6) {
                                ForEach(Weekday.allCases) { day in
                                    Button(day.shortName) {
                                        if selectedDays.contains(day) {
                                            guard selectedDays.count > 1 else { return }
                                            selectedDays.remove(day)
                                        } else {
                                            selectedDays.insert(day)
                                        }
                                    }
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(selectedDays.contains(day) ? Color.mint : Color.white.opacity(0.12), in: Circle())
                                    .foregroundStyle(selectedDays.contains(day) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedDays.contains(day) ? Color.mint : Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .accessibilityLabel(day.accessibilityName)
                                    .accessibilityValue(selectedDays.contains(day) ? "Selected" : "Not selected")
                                }
                            }
                        }
                        .padding(18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let medication = Medication(
                            id: UUID(),
                            name: medicationName.trimmingCharacters(in: .whitespacesAndNewlines),
                            days: selectedDays,
                            times: selectedTimes,
                            monthlyCost: monthlyCost
                        )
                        onSave(medication)
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(.mint)
                    .disabled(medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDays.isEmpty || selectedTimes.isEmpty)
                }
            }
            .tint(.mint)
        }
    }

    private func toggleTime(_ time: DoseTime) {
        if selectedTimes.contains(time) {
            guard selectedTimes.count > 1 else { return }
            selectedTimes.remove(time)
        } else {
            selectedTimes.insert(time)
        }
        selectedFrequency = min(selectedTimes.count, 3)
    }
}

// MARK: - Medication Editor View

private struct MedicationEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let medication: Medication
    let onSave: (Medication) -> Void
    let onDelete: (Medication) -> Void

    @State private var name: String
    @State private var monthlyCost: Double
    @State private var selectedTimes: Set<DoseTime>
    @State private var selectedDays: Set<Weekday>
    @State private var isShowingDeleteConfirmation = false

    init(
        medication: Medication,
        onSave: @escaping (Medication) -> Void,
        onDelete: @escaping (Medication) -> Void
    ) {
        self.medication = medication
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: medication.name)
        _monthlyCost = State(initialValue: medication.monthlyCost)
        _selectedTimes = State(initialValue: medication.times)
        _selectedDays = State(initialValue: medication.days)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedTimes.isEmpty &&
        !selectedDays.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MedicationEditorHeader(name: medication.name)

                        // In-line predictive name editor
                        MedicationNameEditor(name: $name) { suggested in
                            name = suggested.name
                            monthlyCost = 0.0
                        }

                        // Monthly Cost Section (shows $0 default or ACA benefit)
                        MedicationCostEditor(monthlyCost: $monthlyCost, medicationName: name)

                        MedicationScheduleEditor(selectedTimes: $selectedTimes)
                        MedicationDaysEditor(selectedDays: $selectedDays)

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete medication", systemImage: "trash")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Medication(
                                id: medication.id,
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                days: selectedDays,
                                times: selectedTimes,
                                monthlyCost: monthlyCost
                            )
                        )
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(.mint)
                    .disabled(!canSave)
                }
            }
            .tint(.mint)
            .alert("Delete \(medication.name)?", isPresented: $isShowingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    onDelete(medication)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the medication, its reminders, and its dose history.")
            }
        }
    }
}

private struct MedicationEditorHeader: View {
    let name: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "pills.fill")
                .font(.title2)
                .foregroundStyle(.mint)
                .frame(width: 56, height: 56)
                .background(.mint.opacity(0.18), in: Circle())
                .overlay(Circle().stroke(.mint.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("Medication details")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Keep your treatment plan up to date.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Editing \(name)")
    }
}

// MARK: - In-line Predictive Medication Name Editor

private struct MedicationNameEditor: View {
    @Binding var name: String
    var onSelectSuggestedMedication: ((ACAPreventiveMedication) -> Void)?

    @State private var isShowingSuggestions = true

    private var suggestions: [ACAPreventiveMedication] {
        guard isShowingSuggestions else { return [] }
        return ACAPreventiveDatabase.suggestions(for: name, limit: 4)
    }

    private var matchedACAMed: ACAPreventiveMedication? {
        ACAPreventiveDatabase.findMatch(for: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Medication name", systemImage: "text.cursor")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            TextField("e.g. Aspirin, Truvada, Descovy, Lovastatin", text: $name)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(matchedACAMed != nil ? Color.mint : .white.opacity(0.15), lineWidth: 1)
                )
                .onChange(of: name) { _, _ in
                    isShowingSuggestions = true
                }

            if let matched = matchedACAMed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.mint)
                        .font(.caption)
                    Text("Guaranteed $0 Copay (ACA Preventive Care • \(matched.category))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.mint)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }

            // In-line predictive suggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("ACA $0 COPAY SUGGESTIONS", systemImage: "sparkles")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.mint)
                        Spacer()
                        Button("Dismiss") {
                            withAnimation { isShowingSuggestions = false }
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 4)

                    VStack(spacing: 6) {
                        ForEach(suggestions) { med in
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    name = med.name
                                    isShowingSuggestions = false
                                    onSelectSuggestedMedication?(med)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "shield.checkmark.fill")
                                        .font(.caption)
                                        .foregroundStyle(.mint)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(med.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.leading)
                                        Text("\(med.category) • \(med.subcategory)")
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.65))
                                    }

                                    Spacer(minLength: 4)

                                    Text("$0 Copay")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.mint.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.mint)
                                }
                                .padding(10)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Monthly Cost Editor Section

private struct MedicationCostEditor: View {
    @Binding var monthlyCost: Double
    let medicationName: String

    @State private var isEditingCustomCost = false
    @State private var customCostString = ""

    private var isACAPreventive: Bool {
        ACAPreventiveDatabase.isACAPreventive(name: medicationName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Monthly cost", systemImage: "dollarsign.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(monthlyCost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(monthlyCost == 0 ? Color.mint : .white)
            }

            if isACAPreventive {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield.checkmark.fill")
                        .font(.title3)
                        .foregroundStyle(.mint)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACA $0 Copay Mandate")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.mint)
                        Text("Under the Affordable Care Act, non-grandfathered health plans must provide this preventive medication with $0 out-of-pocket copay.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(2)
                    }
                }
                .padding(14)
                .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.mint.opacity(0.3), lineWidth: 1)
                )
            } else {
                Text("All medications default to $0.00 unless set otherwise. Enter your actual out-of-pocket monthly copay below if applicable.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            // Quick Presets
            HStack(spacing: 8) {
                costPresetButton(title: "$0 (Free)", amount: 0.0)
                costPresetButton(title: "$5", amount: 5.0)
                costPresetButton(title: "$10", amount: 10.0)
                costPresetButton(title: "$20", amount: 20.0)
                costPresetButton(title: "Custom", isCustom: true)
            }

            if isEditingCustomCost {
                HStack {
                    Text("$")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                    TextField("0.00", text: $customCostString)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(.white)
                        .onChange(of: customCostString) { _, newVal in
                            if let val = Double(newVal.filter { "0123456789.".contains($0) }) {
                                monthlyCost = max(0, val)
                            }
                        }
                    if monthlyCost > 0 {
                        Button("Reset to $0") {
                            monthlyCost = 0.0
                            customCostString = ""
                            isEditingCustomCost = false
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.mint)
                    }
                }
                .padding(12)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear {
            if monthlyCost > 0 {
                customCostString = String(format: "%.2f", monthlyCost)
                if ![0.0, 5.0, 10.0, 20.0].contains(monthlyCost) {
                    isEditingCustomCost = true
                }
            }
        }
    }

    private func costPresetButton(title: String, amount: Double = 0.0, isCustom: Bool = false) -> some View {
        let isSelected = isCustom ? isEditingCustomCost : (monthlyCost == amount && !isEditingCustomCost)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if isCustom {
                    isEditingCustomCost = true
                } else {
                    isEditingCustomCost = false
                    monthlyCost = amount
                }
            }
        } label: {
            Text(title)
                .font(.caption.weight(isSelected ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.mint : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .foregroundStyle(isSelected ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
        }
        .buttonStyle(.plain)
    }
}

private struct MedicationScheduleEditor: View {
    @Binding var selectedTimes: Set<DoseTime>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Daily reminders", systemImage: "clock.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text("Choose when you take this medication.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 10) {
                ForEach(DoseTime.allCases) { time in
                    Button {
                        toggle(time)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: time.symbol)
                                .font(.headline)
                            Text(time.title)
                                .font(.caption.weight(.bold))
                            Text(time.displayTime)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedTimes.contains(time) ? Color.mint : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(selectedTimes.contains(time) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selectedTimes.contains(time) ? Color.mint : Color.white.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(time.title) dose at \(time.displayTime)")
                    .accessibilityValue(selectedTimes.contains(time) ? "Selected" : "Not selected")
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func toggle(_ time: DoseTime) {
        if selectedTimes.contains(time) {
            guard selectedTimes.count > 1 else { return }
            selectedTimes.remove(time)
        } else {
            selectedTimes.insert(time)
        }
    }
}

private struct MedicationDaysEditor: View {
    @Binding var selectedDays: Set<Weekday>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Days of the week", systemImage: "calendar")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text("Select which days to take this medication.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    Button(day.shortName) {
                        toggle(day)
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(selectedDays.contains(day) ? Color.mint : Color.white.opacity(0.12), in: Circle())
                    .foregroundStyle(selectedDays.contains(day) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                    .overlay(
                        Circle()
                            .stroke(selectedDays.contains(day) ? Color.mint : Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .accessibilityLabel(day.accessibilityName)
                    .accessibilityValue(selectedDays.contains(day) ? "Selected" : "Not selected")
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            guard selectedDays.count > 1 else { return }
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}

// MARK: - Models and Persistence

struct Medication: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var days: Set<Weekday>
    var times: Set<DoseTime>
    var monthlyCost: Double

    init(
        id: UUID = UUID(),
        name: String,
        days: Set<Weekday>,
        times: Set<DoseTime>,
        monthlyCost: Double = 0.0
    ) {
        self.id = id
        self.name = name
        self.days = days
        self.times = times
        self.monthlyCost = monthlyCost
    }

    enum CodingKeys: String, CodingKey {
        case id, name, days, times, monthlyCost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        days = try container.decode(Set<Weekday>.self, forKey: .days)
        times = try container.decode(Set<DoseTime>.self, forKey: .times)
        monthlyCost = try container.decodeIfPresent(Double.self, forKey: .monthlyCost) ?? 0.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(days, forKey: .days)
        try container.encode(times, forKey: .times)
        try container.encode(monthlyCost, forKey: .monthlyCost)
    }

    var frequencyLabel: String {
        "\(times.count)x daily"
    }

    var daysLabel: String {
        days.count == Weekday.allCases.count ? "Every day" : days.sorted { $0.calendarValue < $1.calendarValue }.map(\.shortName).joined(separator: " · ")
    }

    var formattedMonthlyCost: String {
        monthlyCost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    var isACAPreventive: Bool {
        ACAPreventiveDatabase.isACAPreventive(name: name)
    }
}

struct DoseLog: Identifiable, Codable, Equatable {
    let id: UUID
    let medicationID: UUID
    let doseTime: DoseTime
    let takenAt: Date
}

struct ScheduledDose: Identifiable {
    let medication: Medication
    let time: DoseTime

    var id: String {
        "\(medication.id.uuidString)-\(time.rawValue)"
    }
}

enum DoseTime: String, CaseIterable, Identifiable, Hashable, Codable {
    case morning
    case afternoon
    case night

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .night: "moon.stars.fill"
        }
    }

    var hour: Int {
        switch self {
        case .morning: 8
        case .afternoon: 13
        case .night: 20
        }
    }

    var minute: Int { 0 }

    var sortOrder: Int { hour }

    var displayTime: String {
        DateComponents(hour: hour, minute: minute).date?.formatted(date: .omitted, time: .shortened) ?? ""
    }
}

enum Weekday: Int, CaseIterable, Identifiable, Hashable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }
    var calendarValue: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        }
    }

    var accessibilityName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    static var today: Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: .now)) ?? .monday
    }

    static func from(date: Date) -> Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? .monday
    }
}

enum MedicationStore {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T where T: RangeReplaceableCollection {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return T()
        }
        return value
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

#Preview {
    ContentView()
}
