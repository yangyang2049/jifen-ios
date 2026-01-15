//
//  DateTimeToolView.swift
//  jifen
//
//  Date and time tool
//

import SwiftUI

struct DateTimeToolView: View {
    @State private var currentDate = Date()
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 40) {
                    // Date Display
                    VStack(spacing: 20) {
                        Text(currentDate, style: .date)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        
                        Text(currentDate, style: .time)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(Theme.accentColor)
                    }
                    .padding(.top, 60)
                    
                    // Weekday
                    Text(weekdayString)
                        .font(.title2)
                        .foregroundColor(Theme.textSecondary)
                    
                Spacer()
            }
        }
        .navigationTitle("时间工具")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .preferredColorScheme(.dark)
    }
    
    private var weekdayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: currentDate)
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentDate = Date()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    DateTimeToolView()
}

