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
    @FocusState private var isAmountFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ScrollView {
                VStack(spacing: 24) {
                    // Total amount input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("总金额")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                        
                        TextField("请输入金额", text: $totalAmount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
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
                                            .foregroundColor(totalAmount == "\(amount)" ? .white : .white.opacity(0.7))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(totalAmount == "\(amount)" ? Color(hex: "4CAF50") : Color.white.opacity(0.08))
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
                                            .foregroundColor(totalAmount == "\(amount)" ? .white : .white.opacity(0.7))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(totalAmount == "\(amount)" ? Color(hex: "4CAF50") : Color.white.opacity(0.08))
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Participants selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("参与人数")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                if participants > 2 {
                                    participants -= 1
                                    showResult = false
                                }
                            }) {
                                Text("-")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                    )
                            }
                            .disabled(participants <= 2)
                            .opacity(participants > 2 ? 1 : 0.3)
                            
                            VStack(spacing: 4) {
                                Text("\(participants)")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(Color(hex: "4CAF50"))
                                
                                Text("人")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
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
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
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
                                .background(Color.white.opacity(0.1))
                            
                            VStack(spacing: 8) {
                                Text("每人应付")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text("¥\(amountPerPerson, specifier: "%.2f")")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(Color(hex: "FFD700"))
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
                                    Text("总金额")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.6))
                                    Spacer()
                                    if let total = Double(totalAmount) {
                                        Text("¥\(total, specifier: "%.2f")")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                }
                                
                                HStack {
                                    Text("参与人数")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.6))
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text("\(participants)")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.9))
                                        Text("人")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                    .padding(.vertical, 4)
                                
                                HStack {
                                    Text("每人应付")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.6))
                                    Spacer()
                                    Text("¥\(amountPerPerson, specifier: "%.2f")")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "4CAF50"))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                    }
                    
                    // Button group (1:2 ratio)
                    HStack(spacing: 12) {
                        Button(action: reset) {
                            Text("重置")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "FF6B6B"))
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(hex: "FF6B6B").opacity(0.15))
                                )
                        }
                        
                        Button(action: calculate) {
                            Text("计算")
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
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("AA计算器")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func calculate() {
        // Dismiss keyboard
        isAmountFocused = false
        
        guard let amount = Double(totalAmount), amount > 0 else {
            // Show toast: "请输入有效金额"
            return
        }
        
        amountPerPerson = amount / Double(participants)
        showResult = true
        VibrationManager.shared.vibrateLight()
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
