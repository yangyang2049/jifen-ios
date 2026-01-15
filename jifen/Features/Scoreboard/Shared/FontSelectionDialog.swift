//
//  FontSelectionDialog.swift
//  jifen
//
//  Font selection dialog for scoreboard
//

import SwiftUI

struct FontOption {
    let code: String
    let name: String
}

struct FontSelectionDialog: View {
    let currentFont: String
    let onFontSelected: (String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    private let fonts: [FontOption] = [
        FontOption(code: "default", name: "默认"),
        FontOption(code: "digital", name: "数字"),
        FontOption(code: "harmony_digit", name: "鸿蒙数字"),
        FontOption(code: "seven_segment", name: "七段数码")
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Title
                Text("选择字体")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                
                // Font options list
                VStack(spacing: 0) {
                    ForEach(Array(fonts.enumerated()), id: \.element.code) { index, font in
                        Button(action: {
                            onFontSelected(font.code)
                            dismiss()
                        }) {
                            HStack {
                                // Font preview
                                Text("123")
                                    .font(fontPreview(for: font.code))
                                    .foregroundColor(.white)
                                    .frame(width: 44)
                                
                                // Font name
                                Text(font.name)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Check indicator
                                if font.code == currentFont {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Divider (except last item)
                        if index < fonts.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(hex: "222222"))
                .cornerRadius(12)
                
                // OK button
                Button("确定") {
                    dismiss()
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .medium))
                .cornerRadius(8)
                .padding(.top, 16)
                
                Spacer()
            }
            .padding(24)
            .background(Color(hex: "1A1A1A"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func fontPreview(for fontCode: String) -> Font {
        switch fontCode {
        case "default":
            return .system(size: 18, weight: .medium)
        case "digital":
            return .system(size: 18, weight: .medium, design: .monospaced)
        case "harmony_digit":
            return .system(size: 18, weight: .medium)
        case "seven_segment":
            // Try to use custom font, fallback to monospaced
            if let customFont = UIFont(name: "7segment", size: 18) {
                return Font(customFont)
            } else {
                return .system(size: 18, weight: .medium, design: .monospaced)
            }
        default:
            return .system(size: 18, weight: .medium)
        }
    }
}

