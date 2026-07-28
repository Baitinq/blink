import Foundation
import BlinkCore

/// Every test gets a fresh engine driven by a fake clock, so the whole suite
/// runs in milliseconds and is bit-for-bit deterministic.
final class BreakEngineTests {
    private var platform: FakePlatform!
    private var settings: BlinkSettings!
    private var engine: BreakEngine!

    func setUp() {
        platform = FakePlatform()
        settings = BlinkSettings(store: platform.settingsStore)
        settings.workIntervalMinutes = 20
        settings.breakDurationSeconds = 20
        settings.warningLeadSeconds = 10
        settings.idleResetEnabled = false
        engine = BreakEngine(settings: settings, platform: platform)
        engine.start()
    }

    // MARK: - Cycle

    func testFullCycleWarnsThenRestsThenReturnsToWork() {
        expectEqual(engine.phase, .working)

        platform.advance(19 * 60 + 45)   // 15s before the break
        expectEqual(engine.phase, .working)
        expectFalse(platform.recordingHUD.isVisible)

        platform.advance(6)              // inside the 10s heads-up window
        expectEqual(engine.phase, .warning)
        expectTrue(platform.recordingHUD.isVisible)
        expectEqual(platform.recordingHUD.lastSecondsLeft, 9)

        platform.advance(10)             // break starts
        expectEqual(engine.phase, .resting)
        expectTrue(platform.recordingOverlay.isVisible)
        expectFalse(platform.recordingHUD.isVisible)
        expectEqual(platform.recordingSound.cues, [.breakStart])

        platform.advance(20)             // break ends
        expectEqual(engine.phase, .working)
        expectFalse(platform.recordingOverlay.isVisible)
        expectEqual(platform.recordingSound.cues, [.breakStart, .breakEnd])
        expectEqual(settings.breaksToday, 1)
        expectNear(engine.secondsUntilBreak, 20 * 60)
    }

    func testCompletedBreaksAccumulate() {
        for _ in 0..<3 { platform.advance(20 * 60 + 20) }
        expectEqual(settings.breaksToday, 3)
    }

    // MARK: - Escape hatches

    func testSkipEndsBreakWithoutCreditOrChime() {
        engine.takeBreakNow()
        expectTrue(platform.recordingOverlay.isVisible)

        engine.skipCurrentCycle()
        expectEqual(engine.phase, .working)
        expectFalse(platform.recordingOverlay.isVisible)
        expectEqual(settings.breaksToday, 0)
        expectEqual(platform.recordingSound.cues, [.breakStart])
        expectEqual(engine.secondsUntilBreak, 20 * 60)
    }

    func testPostponePushesTheDeadlineOut() {
        engine.takeBreakNow()
        engine.postpone(minutes: 5)
        expectEqual(engine.phase, .working)
        expectFalse(platform.recordingOverlay.isVisible)
        expectEqual(engine.secondsUntilBreak, 5 * 60)
        expectEqual(settings.breaksToday, 0)
    }

    func testOverlayContextCarriesTheEscapeHatches() {
        engine.takeBreakNow()
        platform.recordingOverlay.context?.onSkip()
        expectEqual(engine.phase, .working)
        expectFalse(platform.recordingOverlay.isVisible)
    }

    func testStrictModeWithholdsSkipFromTheOverlay() {
        settings.strictMode = true
        engine.takeBreakNow()
        expectEqual(platform.recordingOverlay.context?.allowsSkip, false)

        settings.strictMode = false
        engine.skipCurrentCycle()
        engine.takeBreakNow()
        expectEqual(platform.recordingOverlay.context?.allowsSkip, true)
    }

    // MARK: - Pause

    func testTimedPauseExpiresOnItsOwn() {
        engine.pause(until: platform.fakeClock.now.addingTimeInterval(60))
        expectTrue(engine.phase.isPaused)

        platform.advance(59)
        expectTrue(engine.phase.isPaused)

        platform.advance(2)
        expectEqual(engine.phase, .working)
        expectNear(engine.secondsUntilBreak, 20 * 60)
    }

    func testIndefinitePauseNeverFiresABreak() {
        engine.pause(until: nil)
        platform.advance(6 * 60 * 60)
        expectTrue(engine.phase.isPaused)
        expectEqual(platform.recordingOverlay.presentCount, 0)

        engine.resume()
        expectEqual(engine.phase, .working)
    }

    func testPausingDuringABreakTearsDownTheOverlay() {
        engine.takeBreakNow()
        engine.pause(until: nil)
        expectFalse(platform.recordingOverlay.isVisible)
        expectEqual(settings.breaksToday, 0)
    }

    // MARK: - Idle credit

    func testTimeAwayCountsAsABreak() {
        settings.idleResetEnabled = true
        platform.advance(19 * 60)
        platform.fakeIdle.idle = Double(settings.breakDurationSeconds)

        platform.advance(60)   // would have broken without idle credit
        expectEqual(engine.phase, .working)
        expectEqual(platform.recordingOverlay.presentCount, 0)
        expectEqual(engine.secondsUntilBreak, 20 * 60)
    }

    func testIdleCreditIgnoredWhenDisabled() {
        settings.idleResetEnabled = false
        platform.fakeIdle.idle = 600
        platform.advance(20 * 60)
        expectEqual(engine.phase, .resting)
    }

    func testShortIdleDoesNotEarnCredit() {
        settings.idleResetEnabled = true
        platform.fakeIdle.idle = Double(settings.breakDurationSeconds) - 1
        platform.advance(20 * 60)
        expectEqual(engine.phase, .resting)
    }

    func testIdleCreditHidesAWarningAlreadyOnScreen() {
        settings.idleResetEnabled = true
        platform.advance(19 * 60 + 55)
        expectEqual(engine.phase, .warning)

        platform.fakeIdle.idle = 30
        platform.advance(1)
        expectEqual(engine.phase, .working)
        expectFalse(platform.recordingHUD.isVisible)
    }

    // MARK: - System events

    func testWakeReArmsAFullInterval() {
        platform.advance(19 * 60)
        platform.manualEvents.fireWake()
        expectEqual(engine.phase, .working)
        expectEqual(engine.secondsUntilBreak, 20 * 60)
    }

    func testWakeDoesNotResumeAPausedEngine() {
        engine.pause(until: nil)
        platform.manualEvents.fireWake()
        expectTrue(engine.phase.isPaused)
    }

    func testDisplayChangeRelaysOutOnlyDuringABreak() {
        platform.manualEvents.fireDisplayChange()
        expectEqual(platform.recordingOverlay.relayoutCount, 0)

        engine.takeBreakNow()
        platform.manualEvents.fireDisplayChange()
        expectEqual(platform.recordingOverlay.relayoutCount, 1)
        expectEqual(platform.recordingOverlay.presentCount, 1, "relayout must not re-present or re-chime")
        expectEqual(platform.recordingSound.cues, [.breakStart])
    }

    // MARK: - Settings reactivity

    func testShorteningTheIntervalPullsTheNextBreakIn() {
        platform.advance(60)
        settings.workIntervalMinutes = 5
        expectEqual(engine.secondsUntilBreak, 5 * 60)
    }

    func testLengtheningTheIntervalDoesNotDelayTheCurrentCycle() {
        platform.advance(60)
        settings.workIntervalMinutes = 60
        expectEqual(engine.secondsUntilBreak, 19 * 60)
    }

    func testWarningDisabledGoesStraightToTheBreak() {
        settings.showPreBreakWarning = false
        platform.advance(20 * 60)
        expectEqual(engine.phase, .resting)
        expectEqual(platform.recordingHUD.showCount, 0)
    }

    // MARK: - Status surface

    func testStatusSurfaceReceivesSnapshotsAndCommands() {
        expectNotNil(platform.recordingStatus.commands)
        platform.advance(1)
        let last = platform.recordingStatus.snapshots.last
        expectEqual(last?.phase, .working)
        expectEqual(last?.workIntervalMinutes, 20)
        expectEqual(last?.breakDurationSeconds, 20)

        platform.recordingStatus.commands?.breakNow()
        expectEqual(engine.phase, .resting)
        platform.recordingStatus.commands?.pause(nil)
        expectTrue(engine.phase.isPaused)
        platform.recordingStatus.commands?.resume()
        expectEqual(engine.phase, .working)
    }

    func testSnapshotsAreDeduplicated() {
        let before = platform.recordingStatus.snapshots.count
        platform.advance(0.5)   // same whole second, nothing user-visible changed
        platform.advance(0.5)
        let after = platform.recordingStatus.snapshots.count
        expectLessThanOrEqual(after - before, 2)
    }

    func testStopHaltsTheTicker() {
        engine.stop()
        expectTrue(platform.manualScheduler.cancelled)
    }

    // MARK: - Shared presentation rules

    /// Both renderers ask BreakVisuals for these, so the macOS and Linux overlays
    /// cannot drift apart.
    func testFadeCurveIsVisibleAtBothEndsAndDarkInTheMiddle() {
        expectEqual(BreakVisuals.contentAlpha(progress: 0, fadeToBlack: true), 1)
        expectEqual(BreakVisuals.contentAlpha(progress: 0.17, fadeToBlack: true), 1)
        expectTrue(BreakVisuals.contentAlpha(progress: 0.5, fadeToBlack: true) < 0.15)
        expectEqual(BreakVisuals.contentAlpha(progress: 0.9, fadeToBlack: true), 1)
        expectEqual(BreakVisuals.contentAlpha(progress: 0.5, fadeToBlack: false), 1)
    }

    func testProgressIsClampedAndSafeAtZeroTotal() {
        expectEqual(BreakVisuals.progress(secondsLeft: 20, total: 20), 0)
        expectEqual(BreakVisuals.progress(secondsLeft: 5, total: 20), 0.75)
        expectEqual(BreakVisuals.progress(secondsLeft: -3, total: 20), 1)
        expectEqual(BreakVisuals.progress(secondsLeft: 5, total: 0), 1)
    }

    func testPauseDurationGrammar() {
        expectEqual(PauseDuration("20m"), .seconds(1200))
        expectEqual(PauseDuration("1h"), .seconds(3600))
        expectEqual(PauseDuration("90s"), .seconds(90))
        expectEqual(PauseDuration("inf"), .indefinite)
        expectEqual(PauseDuration("forever"), .indefinite)
        expectEqual(PauseDuration("20"), .invalid, "a bare number is ambiguous")
        expectEqual(PauseDuration("nonsense"), .invalid)
        expectEqual(PauseDuration("0m"), .invalid)
    }

    func testInvalidPauseDurationYieldsNoDeadline() {
        let now = Date()
        expectTrue(PauseDuration("nonsense").deadline(from: now) == nil, "must not pause at all")
        expectTrue(PauseDuration("inf").deadline(from: now) == .some(nil), "must pause indefinitely")
    }

    // MARK: - Settings observers

    /// Two subsystems legitimately watch settings; one must not displace the other.
    func testSettingsObserversAreAdditive() {
        var first = 0
        var second = 0
        settings.onChange { first += 1 }
        settings.onChange { second += 1 }
        settings.strictMode = true
        expectEqual(first, 1)
        expectEqual(second, 1)
    }

    func testBreakOnDemandOverridesAPause() {
        engine.pause(until: nil)
        engine.takeBreakNow()
        expectEqual(engine.phase, .resting)
        platform.advance(20)
        expectEqual(engine.phase, .working, "an explicit break ends the pause")
        expectEqual(settings.breaksToday, 1)
    }

    // MARK: - Formatting

    func testFormatting() {
        expectEqual(Format.clock(seconds: 725), "12:05")
        expectEqual(Format.clock(seconds: 9), "0:09")
        expectEqual(Format.compact(seconds: 725), "13m")
        expectEqual(Format.compact(seconds: 45), "45s")
    }

    // MARK: - Registry

    var allTests: [(String, () -> Void)] {
        [
        ("testFullCycleWarnsThenRestsThenReturnsToWork", testFullCycleWarnsThenRestsThenReturnsToWork),
        ("testCompletedBreaksAccumulate", testCompletedBreaksAccumulate),
        ("testSkipEndsBreakWithoutCreditOrChime", testSkipEndsBreakWithoutCreditOrChime),
        ("testPostponePushesTheDeadlineOut", testPostponePushesTheDeadlineOut),
        ("testOverlayContextCarriesTheEscapeHatches", testOverlayContextCarriesTheEscapeHatches),
        ("testStrictModeWithholdsSkipFromTheOverlay", testStrictModeWithholdsSkipFromTheOverlay),
        ("testTimedPauseExpiresOnItsOwn", testTimedPauseExpiresOnItsOwn),
        ("testIndefinitePauseNeverFiresABreak", testIndefinitePauseNeverFiresABreak),
        ("testPausingDuringABreakTearsDownTheOverlay", testPausingDuringABreakTearsDownTheOverlay),
        ("testTimeAwayCountsAsABreak", testTimeAwayCountsAsABreak),
        ("testIdleCreditIgnoredWhenDisabled", testIdleCreditIgnoredWhenDisabled),
        ("testShortIdleDoesNotEarnCredit", testShortIdleDoesNotEarnCredit),
        ("testIdleCreditHidesAWarningAlreadyOnScreen", testIdleCreditHidesAWarningAlreadyOnScreen),
        ("testWakeReArmsAFullInterval", testWakeReArmsAFullInterval),
        ("testWakeDoesNotResumeAPausedEngine", testWakeDoesNotResumeAPausedEngine),
        ("testDisplayChangeRelaysOutOnlyDuringABreak", testDisplayChangeRelaysOutOnlyDuringABreak),
        ("testShorteningTheIntervalPullsTheNextBreakIn", testShorteningTheIntervalPullsTheNextBreakIn),
        ("testLengtheningTheIntervalDoesNotDelayTheCurrentCycle", testLengtheningTheIntervalDoesNotDelayTheCurrentCycle),
        ("testWarningDisabledGoesStraightToTheBreak", testWarningDisabledGoesStraightToTheBreak),
        ("testStatusSurfaceReceivesSnapshotsAndCommands", testStatusSurfaceReceivesSnapshotsAndCommands),
        ("testSnapshotsAreDeduplicated", testSnapshotsAreDeduplicated),
        ("testStopHaltsTheTicker", testStopHaltsTheTicker),
        ("testFadeCurveIsVisibleAtBothEndsAndDarkInTheMiddle", testFadeCurveIsVisibleAtBothEndsAndDarkInTheMiddle),
        ("testProgressIsClampedAndSafeAtZeroTotal", testProgressIsClampedAndSafeAtZeroTotal),
        ("testPauseDurationGrammar", testPauseDurationGrammar),
        ("testInvalidPauseDurationYieldsNoDeadline", testInvalidPauseDurationYieldsNoDeadline),
        ("testSettingsObserversAreAdditive", testSettingsObserversAreAdditive),
        ("testBreakOnDemandOverridesAPause", testBreakOnDemandOverridesAPause),
        ("testFormatting", testFormatting)
        ]
    }
}
