#if os(iOS)
import SwiftUI
import EventKit

struct CalendarSchedulerSheet: View {
    let goalId: UUID?
    let goalTitle: String
    let goalNotes: String
    let goalTargetDate: Date?
    let onScheduled: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let calendarService = CalendarService.shared

    @State private var startDate = Date()
    @State private var durationMinutes: Double = 60
    @State private var isRecurring = false
    @State private var recurrence: RecurrenceFrequency = .weekly
    @State private var hasEndDate = true
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    @State private var permissionDenied = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text(goalTitle.isEmpty ? "Untitled Goal" : goalTitle)
                            .fontWeight(.semibold)
                    }
                }

                Section("When") {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Slider(value: $durationMinutes, in: 15...240, step: 15)
                            Text("\(Int(durationMinutes))m")
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }

                Section("Recurrence") {
                    Toggle("Repeat", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Frequency", selection: $recurrence) {
                            ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                                Text(freq.label).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Set end date", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("Until", selection: $endDate, in: startDate..., displayedComponents: .date)
                        }
                    }
                }

                if let target = goalTargetDate {
                    Section {
                        HStack {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.orange)
                            Text("Goal target date")
                                .font(.caption)
                            Spacer()
                            Text(target.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }

                if permissionDenied {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Calendar access denied", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("To schedule work blocks, enable Calendar access for MortalLoom in Settings > Privacy & Security > Calendars.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .macGroupedFormStyle()
            .navigationTitle("Schedule Work Block")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .macSheetFrame(minHeight: 480, idealHeight: 560)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { schedule() }
                        .disabled(goalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func schedule() {
        Task {
            if !calendarService.isAuthorized {
                let granted = await calendarService.requestAccess()
                if !granted {
                    permissionDenied = true
                    return
                }
            }

            let title = goalTitle.trimmingCharacters(in: .whitespaces)
            let result: String?
            if isRecurring {
                result = calendarService.scheduleRecurringWorkBlock(
                    goalId: goalId,
                    goalTitle: title,
                    notes: goalNotes,
                    startDate: startDate,
                    durationMinutes: Int(durationMinutes),
                    recurrence: recurrence,
                    endDate: hasEndDate ? endDate : nil
                )
            } else {
                result = calendarService.scheduleWorkBlock(
                    goalId: goalId,
                    goalTitle: title,
                    notes: goalNotes,
                    startDate: startDate,
                    durationMinutes: Int(durationMinutes)
                )
            }

            if result != nil {
                let msg = isRecurring
                    ? "Added \(recurrence.label.lowercased()) \(Int(durationMinutes))-minute blocks to your calendar"
                    : "Added \(Int(durationMinutes))-minute block to your calendar"
                onScheduled(msg)
                dismiss()
            } else {
                errorMessage = "Could not create the calendar event. Please try again."
            }
        }
    }
}
#endif
