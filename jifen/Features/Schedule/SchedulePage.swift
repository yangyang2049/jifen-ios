import SwiftUI

struct SchedulePage: View {
    var onStartGame: ((GameType) -> Void)? = nil
    var onChanged: (() -> Void)? = nil

    @State private var selectedStatus: BookingStatus = .pending
    @State private var bookings: [LocalBooking] = []
    @State private var selectedBooking: LocalBooking?
    @State private var showCreatePage = false

    var body: some View {
        List {
            if filteredBookings.isEmpty {
                VStack(spacing: 16) {
                    EmptyStateCourtIcon(size: 48, color: Theme.textSecondary)
                    Text(emptyStateText)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredBookings) { booking in
                    Button {
                        selectedBooking = booking
                    } label: {
                        bookingRow(booking)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .frame(maxWidth: scheduleMaxContentWidth)
        .frame(maxWidth: .infinity)
        .scrollIndicators(.hidden)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("schedule_title", value: "我的球局", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            scheduleContentWidth {
                Button {
                    showCreatePage = true
                } label: {
                    Text(NSLocalizedString("schedule_create_title", value: "预约新球局", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.accentColor)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, Theme.lg)
            }
            .padding(.top, Theme.sm)
            .padding(.bottom, Theme.sm)
            .background(Theme.backgroundColor)
        }
        .safeAreaInset(edge: .top) {
            scheduleContentWidth {
                statusPicker
                    .padding(.horizontal, Theme.lg)
            }
            .padding(.top, Theme.sm)
            .padding(.bottom, Theme.sm)
            .background(Theme.backgroundColor)
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showCreatePage) {
            CreateBookingPage {
                reload()
                onChanged?()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $selectedBooking) { booking in
            BookingDetailPage(
                bookingId: booking.id,
                onStartGame: { gameType in
                    onStartGame?(gameType)
                },
                onChanged: {
                    reload()
                    onChanged?()
                }
            )
        }
    }

    private let scheduleMaxContentWidth: CGFloat = 600

    @ViewBuilder
    private func scheduleContentWidth<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: scheduleMaxContentWidth)
            .frame(maxWidth: .infinity)
    }

    private var filteredBookings: [LocalBooking] {
        bookings.filter { $0.status == selectedStatus }
    }

    private var emptyStateText: String {
        switch selectedStatus {
        case .pending:
            return NSLocalizedString("schedule_empty_pending", value: "暂无待进行球局", comment: "")
        case .completed:
            return NSLocalizedString("schedule_empty_completed", value: "暂无已完成球局", comment: "")
        case .cancelled:
            return NSLocalizedString("schedule_empty_cancelled", value: "暂无已取消球局", comment: "")
        }
    }

    private var statusPicker: some View {
        Picker("", selection: $selectedStatus) {
            Text(NSLocalizedString("schedule_status_pending", value: "待进行", comment: "")).tag(BookingStatus.pending)
            Text(NSLocalizedString("schedule_status_completed", value: "已完成", comment: "")).tag(BookingStatus.completed)
            Text(NSLocalizedString("schedule_status_cancelled", value: "已取消", comment: "")).tag(BookingStatus.cancelled)
        }
        .pickerStyle(.segmented)
    }

    private func reload() {
        bookings = LocalBookingManager.shared.getAllBookings()
    }

    private func bookingRow(_ booking: LocalBooking) -> some View {
        HStack(spacing: 10) {
            Text(booking.sportType.icon)
                .font(.system(size: 22))
                .opacity(0.8)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(formatDateTime(booking.dateTime))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Text(booking.sportType.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.textPrimary.opacity(0.86))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                if !booking.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 6) {
                        Text("📍")
                            .font(.system(size: 12))
                            .opacity(0.72)
                        Text(booking.location)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if selectedStatus == .pending {
                    scheduleTimeStatusTag(for: booking.dateTime)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatDateTime(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "\(NSLocalizedString("today", value: "今天", comment: "")) \(time)"
        }
        if calendar.isDateInTomorrow(date) {
            return "\(NSLocalizedString("tomorrow", value: "明天", comment: "")) \(time)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func scheduleTimeStatusTag(for date: Date) -> some View {
        let status = getScheduleTimeStatus(scheduledAt: date)
        let style = status.style

        Text(status.localizedLabel)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(style.textColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(style.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style.borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
