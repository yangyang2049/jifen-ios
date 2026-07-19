//
//  AACalculatorView.swift
//  jifen
//
//  AA calculator - pixel perfect copy from HarmonyOS
//

import SwiftUI

struct AACalculatorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var totalAmount: String = ""
    @State private var participants: Int = 2
    @State private var amountPerPerson: Double = 0
    @State private var showResult = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @FocusState private var isAmountFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ScrollView {
                VStack(spacing: 24) {
                    // Total amount input
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("total_amount", comment: "Total Amount"))
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textPrimary)
                        
                        TextField(NSLocalizedString("enter_amount", comment: "Enter amount"), text: $totalAmount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textPrimary)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.controlBackground)
                            )
                            .focused($isAmountFocused)
                            .onChange(of: totalAmount) { _, _ in
                                showResult = false
                            }
                            .id("amount_input")
                        
                        // Quick amount buttons
                        VStack(spacing: 8) {
                            // First row
                            HStack(spacing: 8) {
                                ForEach([50, 100, 200], id: \.self) { amount in
                                    Button(action: {
                                        totalAmount = "\(amount)"
                                        showResult = false
                                        isAmountFocused = false
                                    }) {
                                        Text("¥\(amount)")
                                            .font(.system(size: 14))
                                            .foregroundColor(totalAmount == "\(amount)" ? .white : Theme.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(totalAmount == "\(amount)" ? Color(hex: "4CAF50") : Theme.controlBackground)
                                            )
                                    }
                                }
                            }
                            
                            // Second row
                            HStack(spacing: 8) {
                                ForEach([300, 500, 1000], id: \.self) { amount in
                                    Button(action: {
                                        totalAmount = "\(amount)"
                                        showResult = false
                                        isAmountFocused = false
                                    }) {
                                        Text("¥\(amount)")
                                            .font(.system(size: 14))
                                            .foregroundColor(totalAmount == "\(amount)" ? .white : Theme.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(totalAmount == "\(amount)" ? Color(hex: "4CAF50") : Theme.controlBackground)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Participants selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("participants", comment: "Participants"))
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textPrimary)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                if participants > 2 {
                                    participants -= 1
                                    showResult = false
                                }
                            }) {
                                Text("-")
                                    .font(.system(size: 28))
                                    .foregroundColor(Theme.textPrimary)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.controlBackground)
                                    )
                            }
                            .disabled(participants <= 2)
                            .opacity(participants > 2 ? 1 : 0.3)
                            
                            VStack(spacing: 4) {
                                Text("\(participants)")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(Theme.positiveText)
                                
                                Text(NSLocalizedString("person", comment: "person"))
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Button(action: {
                                if participants < 20 {
                                    participants += 1
                                    showResult = false
                                }
                            }) {
                                Text("+")
                                    .font(.system(size: 28))
                                    .foregroundColor(Theme.textPrimary)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.controlBackground)
                                    )
                            }
                            .disabled(participants >= 20)
                            .opacity(participants < 20 ? 1 : 0.3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Result display area
                    if showResult {
                        VStack(spacing: 16) {
                            Divider()
                                .overlay(Theme.divider)
                            
                            VStack(spacing: 8) {
                                Text(NSLocalizedString("each_pays", comment: "Each Pays"))
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textSecondary)
                                
                                Text("¥\(amountPerPerson, specifier: "%.2f")")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(Theme.goldText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(hex: "4CAF50").opacity(0.1))
                            )
                            
                            // Detail information
                            VStack(spacing: 8) {
                                HStack {
                                    Text(NSLocalizedString("total_amount", comment: "Total Amount"))
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    if let total = Double(totalAmount) {
                                        Text("¥\(total, specifier: "%.2f")")
                                            .font(.system(size: 14))
                                            .foregroundColor(Theme.textPrimary)
                                    }
                                }
                                
                                HStack {
                                    Text(NSLocalizedString("participants", comment: "Participants"))
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text("\(participants)")
                                            .font(.system(size: 14))
                                            .foregroundColor(Theme.textPrimary)
                                        Text(NSLocalizedString("person", comment: "person"))
                                            .font(.system(size: 14))
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                                
                                Divider()
                                    .overlay(Theme.divider)
                                    .padding(.vertical, 4)
                                
                                HStack {
                                    Text(NSLocalizedString("each_pays", comment: "Each Pays"))
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    Text("¥\(amountPerPerson, specifier: "%.2f")")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Theme.positiveText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.cardBackground)
                            )
                        }
                    }
                    
                    // Button group (1:2 ratio)
                    HStack(spacing: 12) {
                        Button(action: reset) {
                            Text(NSLocalizedString("reset", comment: "Reset"))
                                .font(.system(size: 16))
                                .foregroundColor(Theme.destructiveText)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(hex: "FF6B6B").opacity(0.15))
                                )
                        }
                        
                        Button(action: calculate) {
                            Text(NSLocalizedString("calculate", comment: "Calculate"))
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(hex: "4CAF50"))
                                )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 16)
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("aa_calculator_title", comment: "AA Calculator title"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(
            toastMessage.isEmpty ? nil :
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.8))
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 50)
                        .transition(.opacity)
                        .animation(.easeInOut, value: showToast)
                }
        )
    }
    
    private func calculate() {
        // Dismiss keyboard
        isAmountFocused = false

        guard let amount = Double(totalAmount), amount > 0 else {
            showToastMessage(NSLocalizedString("aa_enter_valid_amount", value: "请输入有效金额", comment: ""))
            return
        }

        amountPerPerson = amount / Double(participants)
        showResult = true
        VibrationManager.shared.vibrateLight()
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        // Auto-hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showToast = false
            }
            // Clear message after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                toastMessage = ""
            }
        }
    }
    
    private func reset() {
        totalAmount = ""
        participants = 2
        amountPerPerson = 0
        showResult = false
        isAmountFocused = false
    }
}

#Preview {
    NavigationStack {
        AACalculatorView()
    }
}
