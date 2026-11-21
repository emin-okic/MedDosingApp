//
//  ACAPreventiveListView.swift
//  MedDosingApp
//
//  Browsing and searching ACA $0 Preventive Care Medications
//

import SwiftUI

struct ACAPreventiveListView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelectMedication: ((ACAPreventiveMedication) -> Void)?

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedMedication: ACAPreventiveMedication?
    @State private var isShowingInfoSheet = false

    private var filteredMedications: [ACAPreventiveMedication] {
        var list = ACAPreventiveDatabase.medications

        if selectedCategory != "All" {
            list = list.filter { $0.category == selectedCategory }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter { $0.matches(query: query) }
        }

        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerBanner
                        categoryFilterBar
                        resultsHeader

                        if filteredMedications.isEmpty {
                            emptyResultsView
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredMedications) { med in
                                    medicationRow(med)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .searchable(text: $searchText, prompt: "Search by medication, brand, or generic name")
            }
            .navigationTitle("ACA $0 Copay Meds")
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

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundStyle(.mint)
                    }
                    .accessibilityLabel("ACA Coverage Information")
                }
            }
            .sheet(item: $selectedMedication) { med in
                ACAMedicationDetailSheet(medication: med) {
                    onSelectMedication?(med)
                    dismiss()
                }
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $isShowingInfoSheet) {
                ACAInfoExplainerSheet()
                    .presentationDetents([.medium, .large])
                    .preferredColorScheme(.dark)
            }
        }
        .tint(.mint)
        .preferredColorScheme(.dark)
    }

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkmark.fill")
                            .foregroundStyle(.mint)
                            .font(.subheadline)
                        Text("FEDERAL ACA MANDATE")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.mint)
                    }

                    Text("Guaranteed $0 Out-of-Pocket")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(.mint.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Text("$0")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.mint)
                }
            }

            Text("Most private health insurance plans must provide these preventive medications at $0 copay without cost-sharing under the Affordable Care Act.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(2)

            Link(destination: ACAPreventiveDatabase.pdfSourceURL) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                    Text("Official 2026 ACA Drug List (PDF)")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.22, blue: 0.25), Color(red: 0.06, green: 0.12, blue: 0.17)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.mint.opacity(0.3), lineWidth: 1)
        )
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ACAPreventiveDatabase.allCategories, id: \.self) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category)
                            .font(.caption.weight(isSelected ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? Color.mint : Color.white.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                isSelected ? Color(red: 0.04, green: 0.08, blue: 0.12) : .white
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var resultsHeader: some View {
        HStack {
            Text("\(filteredMedications.count) medications eligible for $0 copay")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))

            Spacer()

            if !searchText.isEmpty || selectedCategory != "All" {
                Button("Reset filters") {
                    withAnimation {
                        searchText = ""
                        selectedCategory = "All"
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.mint)
            }
        }
        .padding(.horizontal, 4)
    }

    private func medicationRow(_ med: ACAPreventiveMedication) -> some View {
        Button {
            selectedMedication = med
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconForCategory(med.category))
                        .font(.headline)
                        .foregroundStyle(.mint)
                        .frame(width: 38, height: 38)
                        .background(.mint.opacity(0.18), in: Circle())
                        .overlay(Circle().stroke(.mint.opacity(0.3), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(med.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(med.category)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white.opacity(0.9))

                            if med.subcategory != med.category {
                                Text(med.subcategory)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.mint.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.mint)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$0")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.mint)
                        Text("out of pocket")
                            .font(.system(size: 9).weight(.bold))
                            .foregroundStyle(.mint.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.mint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if !med.details.isEmpty && med.details != med.name {
                    Text(med.details)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 24)
            Text("No medications found")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text("Try checking the spelling or selecting a different category filter.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Aspirin": return "heart.fill"
        case "Bowel Preparation": return "cross.case.fill"
        case "Breast Cancer Prevention": return "ribbon"
        case "Contraceptives": return "figure.2.arms.open"
        case "Fluoride": return "mouth.fill"
        case "Folic Acid Supplements": return "leaf.fill"
        case "HIV PrEP": return "shield.lefthalf.filled"
        case "Iron Supplements": return "drop.fill"
        case "Statins": return "waveform.path.ecg"
        case "Tobacco Cessation": return "lungs.fill"
        case "Vaccines": return "syringe.fill"
        default: return "pill.fill"
        }
    }
}

// MARK: - Medication Detail Sheet

private struct ACAMedicationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let medication: ACAPreventiveMedication
    let onAddToMyMeds: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) {
                            Image(systemName: "shield.checkmark.fill")
                                .font(.title)
                                .foregroundStyle(.mint)
                                .frame(width: 52, height: 52)
                                .background(.mint.opacity(0.18), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(medication.name)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                Text(medication.category)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.mint)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Monthly Copay", systemImage: "dollarsign.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("$0.00 (100% Covered)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.mint)
                            }

                            Divider()
                                .background(.white.opacity(0.15))

                            HStack {
                                Label("Subcategory", systemImage: "tag.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text(medication.subcategory)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                            }

                            if let brand = medication.brandName {
                                Divider()
                                    .background(.white.opacity(0.15))

                                HStack {
                                    Label("Brand Name", systemImage: "trademark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                    Spacer()
                                    Text(brand)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }

                            Divider()
                                .background(.white.opacity(0.15))

                            VStack(alignment: .leading, spacing: 6) {
                                Label("Generic / Formulation", systemImage: "cross.vial")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(medication.genericName)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .padding(18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Federal ACA Guidelines")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            Text("Under Section 2713 of the Public Health Service Act (enacted under the Affordable Care Act), non-grandfathered group health plans and health insurance issuers offering group or individual health insurance must provide coverage without cost sharing for evidence-based preventive medications.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineSpacing(2)
                        }
                        .padding(18)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Button {
                            onAddToMyMeds()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to My Medications Schedule")
                            }
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Coverage Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }
}

// MARK: - Informational Explainer Sheet

private struct ACAInfoExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(spacing: 12) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 48))
                                .foregroundStyle(.mint)

                            Text("ACA $0 Copay Mandate")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)

                            Text("Affordable Care Act Preventive Services")
                                .font(.subheadline)
                                .foregroundStyle(.mint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("What is the ACA $0 Drug Mandate?")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            Text("The Affordable Care Act requires most private health insurance plans to cover specific preventive services and medications with **$0 cost sharing**—meaning no copayment, no coinsurance, and no deductible when received from in-network providers.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineSpacing(2)
                        }
                        .padding(16)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Who recommends these medications?")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            VStack(alignment: .leading, spacing: 8) {
                                bulletPoint(title: "USPSTF", text: "U.S. Preventive Services Task Force (Grade A and B recommendations)")
                                bulletPoint(title: "HRSA", text: "Health Resources and Services Administration (women's preventive services, including contraception)")
                                bulletPoint(title: "ACIP / CDC", text: "Advisory Committee on Immunization Practices (routine adult and child vaccines)")
                            }
                        }
                        .padding(16)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Link(destination: ACAPreventiveDatabase.pdfSourceURL) {
                            HStack {
                                Image(systemName: "arrow.down.doc.fill")
                                Text("View Official 2026 ACA Drug List (PDF)")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.mint)
                            .padding(16)
                            .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.mint.opacity(0.35), lineWidth: 1)
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("ACA Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func bulletPoint(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.headline)
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
