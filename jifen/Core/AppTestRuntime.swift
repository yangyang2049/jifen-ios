import Foundation

/// Default app dependencies must never reuse an installed user's credentials
/// when Xcode hosts tests or launches an explicitly marked UI fixture.
/// Explicitly injected stores and transports keep their own behavior.
nonisolated enum AppTestRuntime {
    enum Mode: Equatable, Sendable {
        case application
        case hostedUnitTests
        case uiTests
    }

    static let normalAuthService = "com.douhua.jifen.ios.secure"
    private static let processNamespace = UUID().uuidString
    static let mode: Mode = {
        #if DEBUG
        return detect(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment,
                      xctestLoaded: NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest.XCTestCase") != nil,
                      debugBuild: true)
        #else
        return .application
        #endif
    }()
    static let authService = authService(for: mode, processNamespace: processNamespace)
    static var isolatesDefaultPrivateSync: Bool { mode != .application }
    static let storageRootURL: URL? = {
        switch mode {
        case .application: return nil
        case .hostedUnitTests:
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("jifen-hosted-tests-" + processNamespace, isDirectory: true)
        case .uiTests:
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UITestFixtures-v1", isDirectory: true)
        }
    }()
    static let defaultsSuiteName: String? = {
        switch mode {
        case .application: return nil
        case .hostedUnitTests: return "com.douhua.jifen.tests.unit." + processNamespace
        case .uiTests: return "com.douhua.jifen.tests.ui"
        }
    }()
    static var persistenceDefaults: UserDefaults {
        guard let name = defaultsSuiteName else { return .standard }
        guard let defaults = UserDefaults(suiteName: name) else {
            // Falling back to standard here would expose installed user data.
            preconditionFailure("Unable to create isolated test defaults")
        }
        return defaults
    }

    static func detect(arguments: [String], environment: [String: String], xctestLoaded: Bool,
                       debugBuild: Bool) -> Mode {
        guard debugBuild else { return .application }
        if arguments.contains(where: { $0.hasPrefix("-UITest") }) { return .uiTests }
        let hostedKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier", "XCInjectBundleInto", "XCInjectBundle"]
        if xctestLoaded || hostedKeys.contains(where: { environment[$0]?.isEmpty == false }) { return .hostedUnitTests }
        return .application
    }

    static func authService(for mode: Mode, processNamespace: String) -> String {
        switch mode {
        case .application: return normalAuthService
        case .hostedUnitTests: return normalAuthService + ".tests.unit." + processNamespace
        case .uiTests: return normalAuthService + ".tests.ui"
        }
    }
}
