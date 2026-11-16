import SwiftUI
import UserNotifications

struct ContentView: View {
    @State private var medications: [Medication] = MedicationStore.load([Medication].self, key: "medications")
    @State private var doseLogs: [DoseLog] = MedicationStore.load([DoseLog].self, key: "doseLogs")
    @State private var notificationStatus = ""
    @State private var selectedMedication: Medication?
    @State private var isShowingMedicationsList = false

    private var todaysDoses: [ScheduledDose] {
        let weekday = Weekday.today
        return medications.flatMap { medication in
            guard medication.days.contains(weekday) else { return [ScheduledDose]() }
            return medication.times.map { ScheduledDose(medication: medication, time: $0) }
        }
        .sorted { $0.time.sortOrder < $1.time.sortOrder }
    }

    private var takenTodayCount: Int {
        todaysDoses.filter { dose in
            doseLogs.contains { $0.medicationID == dose.medication.id && $0.doseTime == dose.time && Calendar.current.isDateInToday($0.takenAt) }
        }.count
    }

    private var adherencePercentage: Int {
        guard !todaysDoses.isEmpty else { return 0 }
        return Int((Double(takenTodayCount) / Double(todaysDoses.count) * 100).rounded())
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.08, blue: 0.12)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    progressCard
                    todaySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .tint(.mint)
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
        }
        .sheet(isPresented: $isShowingMedicationsList) {
            MedicationsManagementView(
                medications: $medications,
                onAddMedication: addMedication,
                onUpdateMedication: updateMedication,
                onDeleteMedication: deleteMedication
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good \(timeOfDayGreeting)")
                        .font(.title2.weight(.semibold))
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isShowingMedicationsList = true
                    }
                } label: {
                    Image(systemName: "pills.fill")
                        .font(.title2)
                        .foregroundStyle(.mint)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(.mint.opacity(0.16))
                                .overlay(
                                    Circle()
                                        .stroke(.mint.opacity(0.35), lineWidth: 1)
                                )
                        )
                        .scaleEffect(isShowingMedicationsList ? 0.96 : 1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isShowingMedicationsList)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Medications list")
            }

            Text("Your medicine, made simple.")
                .font(.title.weight(.bold))
        }
        .foregroundStyle(.white)
    }

    private var progressCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: Double(adherencePercentage) / 100)
                    .stroke(.mint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(adherencePercentage)%")
                    .font(.headline.weight(.bold))
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today’s progress")
                    .font(.headline)
                Text(todaysDoses.isEmpty ? "Add a medication to get started" : "\(takenTodayCount) of \(todaysDoses.count) doses taken")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 0.12, green: 0.25, blue: 0.28), Color(red: 0.08, green: 0.15, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            if todaysDoses.isEmpty {
                ContentUnavailableView {
                    Label("Nothing scheduled today", systemImage: "sun.max")
                        .foregroundStyle(.white)
                } description: {
                    Text("Add a medication and choose the days you take it.")
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(todaysDoses) { dose in
                    doseRow(dose)
                }
            }
        }
    }

    private func doseRow(_ dose: ScheduledDose) -> some View {
        let log = doseLogs.first {
            $0.medicationID == dose.medication.id && $0.doseTime == dose.time && Calendar.current.isDateInToday($0.takenAt)
        }

        return HStack(spacing: 14) {
            Button {
                selectedMedication = dose.medication
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: dose.time.symbol)
                        .font(.headline)
                        .foregroundStyle(.mint)
                        .frame(width: 42, height: 42)
                        .background(.mint.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(dose.medication.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(dose.time.title) · \(dose.time.displayTime)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                        if let log {
                            Text("Taken \(log.takenAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.mint)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                toggleDose(dose)
            } label: {
                Image(systemName: log == nil ? "checkmark" : "checkmark.circle.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(log == nil ? Color.white.opacity(0.1) : Color.mint, in: Circle())
                    .foregroundStyle(log == nil ? .white : Color(red: 0.04, green: 0.08, blue: 0.12))
            }
            .accessibilityLabel(log == nil ? "Mark \(dose.medication.name) \(dose.time.title) dose as taken" : "Undo \(dose.medication.name) \(dose.time.title) dose")
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        default: "evening"
        }
    }

    private func toggleDose(_ dose: ScheduledDose) {
        if let index = doseLogs.firstIndex(where: {
            $0.medicationID == dose.medication.id && $0.doseTime == dose.time && Calendar.current.isDateInToday($0.takenAt)
        }) {
            doseLogs.remove(at: index)
        } else {
            doseLogs.append(DoseLog(id: UUID(), medicationID: dose.medication.id, doseTime: dose.time, takenAt: .now))
        }
    }

    private func addMedication(_ medication: Medication) {
        medications.append(medication)
        Task {
            await scheduleNotifications(for: medication)
        }
    }

    private func updateMedication(_ medication: Medication) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        medications[index] = medication
        cancelNotifications(for: medication)
        Task {
            await scheduleNotifications(for: medication)
        }
    }

    private func deleteMedication(_ medication: Medication) {
        medications.removeAll { $0.id == medication.id }
        doseLogs.removeAll { $0.medicationID == medication.id }
        cancelNotifications(for: medication)
    }

    private func cancelNotifications(for medication: Medication) {
        let identifiers = Weekday.allCases.flatMap { day in
            DoseTime.allCases.map { time in
                "\(medication.id.uuidString)-\(day.calendarValue)-\(time.rawValue)"
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    @MainActor
    private func scheduleNotifications(for medication: Medication) async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                notificationStatus = "Notifications are off. You can enable them in Settings."
                return
            }

            for day in medication.days {
                for time in medication.times {
                    var components = DateComponents()
                    components.weekday = day.calendarValue
                    components.hour = time.hour
                    components.minute = time.minute

                    let content = UNMutableNotificationContent()
                    content.title = "Time for \(medication.name)"
                    content.body = "Mark your \(time.title.lowercased()) dose as taken."
                    content.sound = .default

                    let request = UNNotificationRequest(
                        identifier: "\(medication.id.uuidString)-\(day.calendarValue)-\(time.rawValue)",
                        content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    )
                    try await center.add(request)
                }
            }
            notificationStatus = "Reminders are set for \(medication.name)."
        } catch {
            notificationStatus = "Couldn’t set reminders. Please try again."
        }
    }
}

// MARK: - Modern Medication Management View

private struct MedicationsManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var medications: [Medication]
    let onAddMedication: (Medication) -> Void
    let onUpdateMedication: (Medication) -> Void
    let onDeleteMedication: (Medication) -> Void

    @State private var searchText = ""
    @State private var selectedMedicationToEdit: Medication?
    @State private var isShowingAddMedication = false

    private var filteredMedications: [Medication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return medications }
        return medications.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var totalDailyDoses: Int {
        medications.reduce(0) { $0 + $1.times.count }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.mint)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddMedication = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.mint)
                            .frame(width: 32, height: 32)
                            .background(.mint.opacity(0.15), in: Circle())
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
            }
            .sheet(isPresented: $isShowingAddMedication) {
                AddMedicationSheet(
                    onSave: { newMed in
                        onAddMedication(newMed)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .tint(.mint)
    }

    private var statsBanner: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(medications.count) Active \(medications.count == 1 ? "Medication" : "Medications")")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(totalDailyDoses) scheduled daily \(totalDailyDoses == 1 ? "dose" : "doses")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Image(systemName: "cross.vial.fill")
                .font(.title2)
                .foregroundStyle(.mint)
                .frame(width: 48, height: 48)
                .background(.mint.opacity(0.18), in: Circle())
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
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.mint.opacity(0.12))
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
                Text("Add your medications to receive reminders and easily track your daily doses.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                isShowingAddMedication = true
            } label: {
                Label("Add Your First Medication", systemImage: "plus")
                    .font(.headline.weight(.semibold))
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
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 24)
            Text("No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Check the spelling or try searching for another medication.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.mint.opacity(0.16), in: Capsule())
            }
            .padding(.horizontal, 4)

            ForEach(filteredMedications) { medication in
                medicationCard(medication)
            }

            Button {
                isShowingAddMedication = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add another medication")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.mint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.mint.opacity(0.25), lineWidth: 1)
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
                        .background(.mint.opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(medication.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            Label(medication.frequencyLabel, systemImage: "clock")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))

                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.4))

                            Label(medication.daysLabel, systemImage: "calendar")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Text("Edit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.mint)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.mint.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.mint.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 8) {
                    ForEach(DoseTime.allCases.filter { medication.times.contains($0) }) { time in
                        HStack(spacing: 5) {
                            Image(systemName: time.symbol)
                                .font(.caption2)
                            Text("\(time.title) (\(time.displayTime))")
                                .font(.caption2.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(16)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
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
        .accessibilityLabel("\(medication.name), \(medication.frequencyLabel), \(medication.daysLabel)")
        .accessibilityHint("Double tap to edit medication details")
    }
}

// MARK: - Add Medication Sheet

private struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Medication) -> Void

    @State private var medicationName = ""
    @State private var selectedFrequency = 1
    @State private var selectedDays = Set(Weekday.allCases)
    @State private var selectedTimes: Set<DoseTime> = [.morning]

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
                                .background(.mint.opacity(0.16), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text("New Medication")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                Text("Add to your daily schedule and reminders.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                        }
                        .padding(.bottom, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Medication name", systemImage: "text.cursor")
                                .font(.headline)
                                .foregroundStyle(.white)

                            TextField("e.g. Lisinopril, Vitamin D3", text: $medicationName)
                                .textInputAutocapitalization(.words)
                                .padding(14)
                                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.white)
                                .accessibilityLabel("Medication name")
                        }
                        .padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Daily frequency", systemImage: "repeat")
                                .font(.headline)
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
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.top, 4)

                            HStack(spacing: 8) {
                                ForEach(DoseTime.allCases) { time in
                                    Button {
                                        toggleTime(time)
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: time.symbol)
                                                .font(.headline)
                                            Text(time.title)
                                                .font(.caption.weight(.semibold))
                                            Text(time.displayTime)
                                                .font(.caption2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .foregroundStyle(selectedTimes.contains(time) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                                        .background(selectedTimes.contains(time) ? Color.mint : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!selectedTimes.contains(time) && selectedTimes.count >= selectedFrequency)
                                    .accessibilityLabel("\(time.title) reminder time")
                                    .accessibilityValue(selectedTimes.contains(time) ? "Selected" : "Not selected")
                                }
                            }
                        }
                        .padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Days of the week", systemImage: "calendar")
                                .font(.headline)
                                .foregroundStyle(.white)

                            Text("Select the days you need to take this medication.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.68))

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
                                    .background(selectedDays.contains(day) ? Color.mint : Color.white.opacity(0.1), in: Circle())
                                    .foregroundStyle(selectedDays.contains(day) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                                    .accessibilityLabel(day.accessibilityName)
                                    .accessibilityValue(selectedDays.contains(day) ? "Selected" : "Not selected")
                                }
                            }
                        }
                        .padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let medication = Medication(
                            id: UUID(),
                            name: medicationName.trimmingCharacters(in: .whitespacesAndNewlines),
                            days: selectedDays,
                            times: selectedTimes
                        )
                        onSave(medication)
                        dismiss()
                    }
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
        } else if selectedTimes.count < selectedFrequency {
            selectedTimes.insert(time)
        }
    }
}

// MARK: - Medication Editor View

private struct MedicationEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let medication: Medication
    let onSave: (Medication) -> Void
    let onDelete: (Medication) -> Void

    @State private var name: String
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
                        MedicationNameEditor(name: $name)
                        MedicationScheduleEditor(selectedTimes: $selectedTimes)
                        MedicationDaysEditor(selectedDays: $selectedDays)

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete medication", systemImage: "trash")
                                .font(.headline)
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
            .navigationTitle("Edit medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Medication(
                                id: medication.id,
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                days: selectedDays,
                                times: selectedTimes
                            )
                        )
                        dismiss()
                    }
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
                .background(.mint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Medication details")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Keep your treatment plan up to date.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Editing \(name)")
    }
}

private struct MedicationNameEditor: View {
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Medication name", systemImage: "text.cursor")
                .font(.headline)
                .foregroundStyle(.white)

            TextField("Medication name", text: $name)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct MedicationScheduleEditor: View {
    @Binding var selectedTimes: Set<DoseTime>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Daily reminders", systemImage: "clock.fill")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Choose when you take this medication.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))

            HStack(spacing: 10) {
                ForEach(DoseTime.allCases) { time in
                    Button {
                        toggle(time)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: time.symbol)
                                .font(.headline)
                            Text(time.title)
                                .font(.caption.weight(.semibold))
                            Text(time.displayTime)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(selectedTimes.contains(time) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                        .background(selectedTimes.contains(time) ? Color.mint : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(time.title), \(time.displayTime)")
                    .accessibilityValue(selectedTimes.contains(time) ? "Selected" : "Not selected")
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            Label("Schedule", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Select the days this medication is taken.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))

            HStack(spacing: 7) {
                ForEach(Weekday.allCases) { day in
                    Button(day.shortName) {
                        toggle(day)
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(selectedDays.contains(day) ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white)
                    .background(selectedDays.contains(day) ? Color.mint : Color.white.opacity(0.1), in: Circle())
                    .accessibilityLabel(day.accessibilityName)
                    .accessibilityValue(selectedDays.contains(day) ? "Selected" : "Not selected")
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

private struct Medication: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var days: Set<Weekday>
    var times: Set<DoseTime>

    var frequencyLabel: String {
        "\(times.count)x daily"
    }

    var daysLabel: String {
        days.count == Weekday.allCases.count ? "Every day" : days.sorted { $0.calendarValue < $1.calendarValue }.map(\.shortName).joined(separator: " · ")
    }
}

private struct DoseLog: Identifiable, Codable, Equatable {
    let id: UUID
    let medicationID: UUID
    let doseTime: DoseTime
    let takenAt: Date
}

private struct ScheduledDose: Identifiable {
    let medication: Medication
    let time: DoseTime

    var id: String {
        "\(medication.id.uuidString)-\(time.rawValue)"
    }
}

private enum DoseTime: String, CaseIterable, Identifiable, Hashable, Codable {
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

private enum Weekday: Int, CaseIterable, Identifiable, Hashable, Codable {
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
}

private enum MedicationStore {
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
