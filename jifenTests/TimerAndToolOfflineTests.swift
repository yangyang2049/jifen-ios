import XCTest
import WebKit
import AVFoundation
@testable import jifen

final class TimerAndToolOfflineTests: XCTestCase {
    @MainActor
    func testToolPlaybackIgnoresSilentModeAndMixesWithOtherAudio() throws {
        let session = AVAudioSession.sharedInstance()
        let original = (session.category, session.mode, session.categoryOptions)
        defer {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(original.0, mode: original.1, options: original.2)
        }
        try session.setCategory(.ambient)
        try AppAudioPlaybackSession.activate()
        XCTAssertEqual(session.category, .playback)
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers))
    }

    @MainActor
    func testPlaybackRestoresCategoryAfterVoiceNoteRecording() throws {
        let session = AVAudioSession.sharedInstance()
        let original = (session.category, session.mode, session.categoryOptions)
        defer {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(original.0, mode: original.1, options: original.2)
        }
        // The shared session retains playAndRecord when a voice note ends.
        XCTAssertFalse(RecordNoteAudioManager.shared.isRecording)
        try session.setCategory(.playAndRecord, options: .defaultToSpeaker)
        try AppAudioPlaybackSession.activate()
        XCTAssertEqual(session.category, .playback)
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers))
    }

    @MainActor
    func testDisabledToolSoundDoesNotActivatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        let original = (session.category, session.mode, session.categoryOptions)
        let wasEnabled = PreferencesManager.shared.soundEnabled
        defer {
            PreferencesManager.shared.soundEnabled = wasEnabled
            try? session.setCategory(original.0, mode: original.1, options: original.2)
        }
        PreferencesManager.shared.soundEnabled = false
        try session.setCategory(.ambient)
        for name in ["whistle", "buzzer", "dice", "flip_coin"] {
            SoundManager.shared.playSound(name)
            XCTAssertEqual(session.category, .ambient, name)
        }
        BoardTimerVoiceAnnouncer.shared.playControl(.start)
        BoardTimerVoiceAnnouncer.shared.playByoyomiPhrase(periodsRemaining: 3)
        BoardTimerVoiceAnnouncer.shared.playCountdownCompletion()
        XCTAssertEqual(session.category, .ambient)
    }

    @MainActor
    func testSoundManagerPlayToggleAndStopOutcomes() {
        let wasEnabled = PreferencesManager.shared.soundEnabled
        defer {
            SoundManager.shared.stopSound()
            PreferencesManager.shared.soundEnabled = wasEnabled
        }
        PreferencesManager.shared.soundEnabled = true

        XCTAssertEqual(SoundManager.shared.playSound("whistle"), .started)
        XCTAssertEqual(SoundManager.shared.activeSoundName, "whistle")

        XCTAssertEqual(SoundManager.shared.toggleSound("whistle"), .stopped)
        XCTAssertNil(SoundManager.shared.activeSoundName)

        XCTAssertEqual(SoundManager.shared.toggleSound("buzzer"), .started)
        XCTAssertEqual(SoundManager.shared.activeSoundName, "buzzer")

        XCTAssertEqual(SoundManager.shared.toggleSound("whistle"), .started)
        XCTAssertEqual(SoundManager.shared.activeSoundName, "whistle")

        SoundManager.shared.stopIfPlaying(["buzzer"])
        XCTAssertEqual(SoundManager.shared.activeSoundName, "whistle")

        SoundManager.shared.stopIfPlaying(["whistle", "buzzer"])
        XCTAssertNil(SoundManager.shared.activeSoundName)
    }

    @MainActor
    func testDisabledToggleSoundDoesNotActivatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        let original = (session.category, session.mode, session.categoryOptions)
        let wasEnabled = PreferencesManager.shared.soundEnabled
        defer {
            SoundManager.shared.stopSound()
            PreferencesManager.shared.soundEnabled = wasEnabled
            try? session.setCategory(original.0, mode: original.1, options: original.2)
        }
        PreferencesManager.shared.soundEnabled = false
        try session.setCategory(.ambient)

        XCTAssertEqual(SoundManager.shared.toggleSound("whistle"), .disabledBySettings)
        XCTAssertNil(SoundManager.shared.activeSoundName)
        XCTAssertEqual(session.category, .ambient)

        XCTAssertEqual(SoundManager.shared.toggleSound("buzzer"), .disabledBySettings)
        XCTAssertNil(SoundManager.shared.activeSoundName)
        XCTAssertEqual(session.category, .ambient)
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TimerAndToolOfflineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStopwatchPersistsRunningStateAcrossBackgroundAndCapsLapsAt99() {
        let now = Date(timeIntervalSince1970: 10_000)
        let state = StopwatchPersistedState(
            phase: .running,
            baseMilliseconds: 1_250,
            runStartedAt: now.timeIntervalSince1970 * 1_000 - 2_000,
            lapCumulativeMilliseconds: Array(repeating: 1, count: StopwatchPolicy.maximumLapCount)
        )

        TimerToolStateStore.saveStopwatch(state, defaults: defaults)
        let restored = TimerToolStateStore.loadStopwatch(defaults: defaults)

        XCTAssertEqual(StopwatchPolicy.maximumLapCount, 99)
        XCTAssertEqual(restored.phase, .running)
        XCTAssertEqual(restored.lapCumulativeMilliseconds.count, 99)
        XCTAssertEqual(restored.elapsedMilliseconds(at: now), 3_250, accuracy: 0.001)
    }

    func testCountdownPersistsAndResetClearsBothTimerTools() {
        let state = CountdownPersistedState(
            phase: .paused,
            durationSeconds: 180,
            lastDurationSeconds: 180,
            endAt: 0,
            remainingMilliseconds: 42_500
        )
        TimerToolStateStore.saveCountdown(state, defaults: defaults)
        XCTAssertEqual(
            TimerToolStateStore.loadCountdown(defaults: defaults).remainingMilliseconds,
            42_500
        )

        TimerToolStateStore.clear(defaults: defaults)

        XCTAssertEqual(TimerToolStateStore.loadStopwatch(defaults: defaults).phase, .idle)
        XCTAssertEqual(TimerToolStateStore.loadCountdown(defaults: defaults).phase, .idle)
    }

    func testPointsTablePersistsAndCanBeCompletelyCleared() {
        let record = PointsTableRecord(
            id: "league",
            name: "周末联赛",
            teams: [PointsTableTeam(name: "A", win: 2, draw: 1)]
        )
        PointsTableStorage.save([record], defaults: defaults)
        XCTAssertEqual(PointsTableStorage.load(defaults: defaults), [record])

        PointsTableStorage.clear(defaults: defaults)
        XCTAssertTrue(PointsTableStorage.load(defaults: defaults).isEmpty)
    }

    func testAACalculationRejectsInvalidBoundaryValues() {
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "0", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "-1", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "nan", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "100", participants: 1))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "100", participants: 21))
        XCTAssertEqual(
            AACalculationPolicy.amountPerPerson(totalText: "100", participants: 3)!,
            100.0 / 3.0,
            accuracy: 0.000_001
        )
    }

    func testAACalculationAcceptsLocalizedKeyboardAmounts() {
        for (input, identifier) in [("12,50", "de_DE"), ("12,50", "fr_FR"), ("١٢٫٥٠", "ar_SA"), ("१२.५०", "hi_IN"), ("１２.５０", "ja_JP")] {
            XCTAssertEqual(
                AACalculationPolicy.amountPerPerson(totalText: input, participants: 2, locale: Locale(identifier: identifier)),
                6.25,
                "\(identifier): \(input)"
            )
        }
        XCTAssertEqual(AACalculationPolicy.totalAmount(from: "12.50", locale: Locale(identifier: "de_DE")), 12.5)
        XCTAssertNil(AACalculationPolicy.totalAmount(from: "12,50junk", locale: Locale(identifier: "de_DE")))
        XCTAssertNil(AACalculationPolicy.totalAmount(from: "1.234,50", locale: Locale(identifier: "de_DE")))
        XCTAssertNil(AACalculationPolicy.totalAmount(from: "١٢٫٫٥٠", locale: Locale(identifier: "ar_SA")))
    }

    func testTenSecondChallengeDifferencePolicy() {
        XCTAssertEqual(TenSecondChallengePolicy.presetSeconds, [1, 3, 5, 10])
        XCTAssertEqual(TenSecondChallengePolicy.defaultTargetSeconds, 10)
        for preset in TenSecondChallengePolicy.presetSeconds {
            XCTAssertEqual(TenSecondChallengePolicy.normalizedTargetSeconds(preset), preset)
            XCTAssertEqual(
                TenSecondChallengePolicy.targetMilliseconds(for: preset),
                TimeInterval(preset * 1_000)
            )
        }
        for invalid in [0, 2, 7, -5] {
            XCTAssertEqual(TenSecondChallengePolicy.normalizedTargetSeconds(invalid), 10)
            XCTAssertEqual(TenSecondChallengePolicy.targetMilliseconds(for: invalid), 10_000)
        }

        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 10_000), 0)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 9_950), 50)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 10_125), 125)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: -10), 10_000)
        XCTAssertEqual(TenSecondChallengePolicy.automaticStopMilliseconds, 59_990)

        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 1_000, targetSeconds: 1), 0)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 920, targetSeconds: 1), 80)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 1_045, targetSeconds: 1), 45)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: -10, targetSeconds: 1), 1_000)

        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 3_000, targetSeconds: 3), 0)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 2_950, targetSeconds: 3), 50)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 3_110, targetSeconds: 3), 110)

        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 5_000, targetSeconds: 5), 0)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 4_880, targetSeconds: 5), 120)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 5_060, targetSeconds: 5), 60)
    }

    func testCubeRequiresHalfSecondHoldAndDoesNotCreateHistory() {
        XCTAssertEqual(CubeTimerPolicy.readinessHoldDuration, 0.5)
        XCTAssertFalse(CubeTimerPolicy.createsHistoryRecord)
    }

    @MainActor
    func testDiceResetCancelsStaleRollCallbacksBeforeWebViewReuse() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let htmlURL = repositoryRoot.appendingPathComponent("jifen/Resources/dice.html")
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                window.__diceTestTimers = [];
                window.setTimeout = function(callback, delay) {
                    var timer = { callback: callback, delay: delay, cancelled: false };
                    window.__diceTestTimers.push(timer);
                    return timer;
                };
                window.clearTimeout = function(timer) {
                    timer.cancelled = true;
                };
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(html, baseURL: htmlURL.deletingLastPathComponent())

        var didLoadDice = false
        for _ in 0..<100 {
            if let count = try? await webView.evaluateJavaScript(
                "document.querySelectorAll('.dice-unit .dice').length"
            ) as? NSNumber, count.intValue == 3 {
                didLoadDice = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(didLoadDice, "dice.html did not finish initializing")

        let snapshotJSON = try await webView.evaluateJavaScript(
            """
            rollDice();
            var staleTimer = window.__diceTestTimers[0];
            window.resetDiceState();
            staleTimer.callback();
            JSON.stringify({
                timerWasCancelled: staleTimer.cancelled,
                result: document.getElementById('result').textContent,
                rollingDice: document.querySelectorAll('.dice.rolling').length,
                settlingDice: document.querySelectorAll('.dice.settling').length,
                rollingPlatforms: document.querySelectorAll('.platform.rolling').length,
                settlingPlatforms: document.querySelectorAll('.platform.settling').length,
                transform: document.querySelector('.dice').style.transform
            });
            """
        ) as? String
        let snapshotData = try XCTUnwrap(snapshotJSON?.data(using: .utf8))
        let snapshot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: snapshotData) as? [String: Any]
        )

        XCTAssertEqual(snapshot["timerWasCancelled"] as? Bool, true)
        XCTAssertEqual(snapshot["result"] as? String, "")
        XCTAssertEqual(snapshot["rollingDice"] as? Int, 0)
        XCTAssertEqual(snapshot["settlingDice"] as? Int, 0)
        XCTAssertEqual(snapshot["rollingPlatforms"] as? Int, 0)
        XCTAssertEqual(snapshot["settlingPlatforms"] as? Int, 0)
        XCTAssertTrue((snapshot["transform"] as? String)?.contains("rotateX(0deg)") == true)

        let rollingDice = try await webView.evaluateJavaScript(
            "rollDice(); document.querySelectorAll('.dice.rolling').length"
        ) as? NSNumber
        XCTAssertEqual(rollingDice?.intValue, 1, "reset must permit a fresh roll immediately")
    }
}
