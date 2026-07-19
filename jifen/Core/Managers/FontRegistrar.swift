//
//  FontRegistrar.swift
//  jifen
//
//  Registers bundled custom fonts. iOS 原生支持外挂字体：
//  1) 将 .ttf/.otf 加入工程并勾选 Copy Bundle Resources；
//  2) Info.plist 增加 UIAppFonts（Fonts provided by application），数组里填字体文件名；
//  3) 启动时可在此处用 CTFontManagerRegisterFontsForURL 注册，或依赖 plist 自动加载；
//  4) 计分板 Template 的 fontFamily 传字体 PostScript 名即可（如鸿蒙用的数字体，把 .ttf 拷入后查真实名称用 UIFont 打印）。
//

import CoreText
import Foundation

enum FontRegistrar {
    static func registerFonts() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "7segment", withExtension: "ttf"),
            Bundle.main.url(forResource: "7segment", withExtension: "ttf", subdirectory: "Resources"),
            Bundle.main.url(forResource: "teko", withExtension: "ttf"),
            Bundle.main.url(forResource: "teko", withExtension: "ttf", subdirectory: "Resources"),
            Bundle.main.url(forResource: "roboto-mono", withExtension: "ttf"),
            Bundle.main.url(forResource: "roboto-mono", withExtension: "ttf", subdirectory: "Resources")
        ]

        for url in candidates.compactMap({ $0 }) {
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if registered {
                #if DEBUG
                print("[FontRegistrar] Successfully registered \(url.lastPathComponent)")
                #endif
            } else if let error = error?.takeRetainedValue() {
                #if DEBUG
                print("[FontRegistrar] Failed to register \(url.lastPathComponent): \(error)")
                #endif
            }
        }
    }
}
