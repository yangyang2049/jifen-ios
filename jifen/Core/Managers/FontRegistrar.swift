//
//  FontRegistrar.swift
//  jifen
//
//  Registers bundled custom fonts.
//

import CoreText
import Foundation

enum FontRegistrar {
    static func registerFonts() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "7segment", withExtension: "ttf"),
            Bundle.main.url(forResource: "7segment", withExtension: "ttf", subdirectory: "Resources")
        ]

        for url in candidates.compactMap({ $0 }) {
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !registered, let error = error?.takeRetainedValue() {
                print("[FontRegistrar] Failed to register \(url.lastPathComponent): \(error)")
            }
        }
    }
}
