import Foundation

@inline(__always)
func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@inline(__always)
func assertEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String) {
    let left = lhs()
    let right = rhs()
    if left != right {
        fputs("FAIL: \(message). expected=\(right) actual=\(left)\n", stderr)
        exit(1)
    }
}

func assertApprox(_ lhs: Double, _ rhs: Double, tolerance: Double, _ message: String) {
    if abs(lhs - rhs) > tolerance {
        fputs("FAIL: \(message). expected~\(rhs) actual=\(lhs) tolerance=\(tolerance)\n", stderr)
        exit(1)
    }
}

func testDestructivePresetRequiresConfirmation() {
    let vm = PlexTVEditorViewModel()
    let preset = PlexSectionActionPreset(
        id: UUID(),
        name: "Full Cleanup",
        sectionType: "show",
        includeRefresh: true,
        includeAnalyze: true,
        includeEmptyTrash: true,
        runOnAllSections: true
    )

    vm.plexActionPresets = [preset]
    vm.selectedPlexPresetId = preset.id.uuidString

    vm.runSelectedPreset()

    assertTrue(vm.statusMessage.contains("Confirm before running"), "Destructive preset should require explicit confirmation")
    assertTrue(vm.selectedPresetRequiresDestructiveConfirmation(), "Preset with Empty Trash should be flagged destructive")
}

func testNonDestructivePresetNeedsSections() {
    let vm = PlexTVEditorViewModel()
    let preset = PlexSectionActionPreset(
        id: UUID(),
        name: "Safe TV",
        sectionType: "show",
        includeRefresh: true,
        includeAnalyze: true,
        includeEmptyTrash: false,
        runOnAllSections: true
    )

    vm.plexActionPresets = [preset]
    vm.selectedPlexPresetId = preset.id.uuidString
    vm.plexLibrarySections = []

    vm.runSelectedPreset()

    assertEqual(vm.statusMessage, "Load sections first before running preset", "Non-destructive preset should require loaded sections")
    assertTrue(!vm.selectedPresetRequiresDestructiveConfirmation(), "Non-destructive preset should not require confirmation")
}

func testSettingsRoundTripKeepsReliabilityFields() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let next = now.addingTimeInterval(86_400)

    let settings = Settings(
        tmdbApiKey: "abc",
        plexSqlitePath: "/tmp/sqlite",
        plexDbPath: "/tmp/db",
        plexServerURL: "http://127.0.0.1:32400",
        plexToken: "token",
        selectedPlexTVSectionKey: "8",
        selectedPlexMovieSectionKey: "9",
        plexServerProfiles: [
            PlexServerProfile(id: UUID(), name: "Local", serverURL: "http://127.0.0.1:32400", token: "token")
        ],
        selectedPlexProfileId: "profile-id",
        plexActionPresets: [
            PlexSectionActionPreset(id: UUID(), name: "Preset", sectionType: "show", includeRefresh: true, includeAnalyze: true, includeEmptyTrash: false, runOnAllSections: false)
        ],
        selectedPlexPresetId: "preset-id",
        sectionActionMaxRetries: 3,
        sectionActionRetryDelaySeconds: 1.25,
        schedulerEnabled: true,
        schedulerFrequency: SchedulerFrequency.weekly.rawValue,
        schedulerScope: SchedulerScope.both.rawValue,
        schedulerLastRunAt: now,
        schedulerNextRunAt: next,
        notificationsEnabled: true,
        plexCapabilities: PlexCapabilities(
            canRefreshSection: false,
            canAnalyzeSection: true,
            canEmptyTrashSection: false,
            canCancelSectionJob: true,
            canAnalyzeItem: true
        ),
        capabilitySummary: "Refresh: No"
    )

    let encoded = try! JSONEncoder().encode(settings)
    let decoded = try! JSONDecoder().decode(Settings.self, from: encoded)

    assertEqual(decoded.sectionActionMaxRetries, 3, "Retry count should round-trip")
    assertEqual(decoded.sectionActionRetryDelaySeconds, 1.25, "Retry delay should round-trip")
    assertEqual(decoded.schedulerEnabled, true, "Scheduler enabled should round-trip")
    assertEqual(decoded.schedulerFrequency, SchedulerFrequency.weekly.rawValue, "Scheduler frequency should round-trip")
    assertEqual(decoded.schedulerScope, SchedulerScope.both.rawValue, "Scheduler scope should round-trip")
    assertEqual(decoded.notificationsEnabled, true, "Notification setting should round-trip")
    assertEqual(decoded.plexCapabilities?.canAnalyzeSection, true, "Capabilities should round-trip")
    assertEqual(decoded.capabilitySummary, "Refresh: No", "Capability summary should round-trip")
}

func testSchedulerPreviewDates() {
    let vm = PlexTVEditorViewModel()
    let baseline = Date(timeIntervalSince1970: 1_700_000_000)

    vm.schedulerFrequency = .daily
    let daily = vm.previewNextSchedulerRunDate(from: baseline)
    let dailyDiff = daily.timeIntervalSince(baseline)
    assertApprox(dailyDiff, 86_400, tolerance: 120, "Daily scheduler interval should be ~1 day")

    vm.schedulerFrequency = .weekly
    let weekly = vm.previewNextSchedulerRunDate(from: baseline)
    let weeklyDiff = weekly.timeIntervalSince(baseline)
    assertApprox(weeklyDiff, 604_800, tolerance: 120, "Weekly scheduler interval should be ~7 days")
}

func testAdvisoryCapabilityResolution() {
    assertTrue(PlexTVEditorViewModel.resolveAdvisoryCapability(probeSupported: true, previousCapability: false), "Probe success should enable capability")
    assertTrue(PlexTVEditorViewModel.resolveAdvisoryCapability(probeSupported: false, previousCapability: true), "Previous true capability should remain enabled on inconclusive probe")
    assertTrue(!PlexTVEditorViewModel.resolveAdvisoryCapability(probeSupported: false, previousCapability: false), "Capability should remain disabled only when both probe and previous are false")
}

func testParseTMDBShowIdVariants() {
    assertEqual(PlexTVEditorViewModel.parseTMDBShowId("12345"), 12345, "Direct TMDB show ID should parse")
    assertEqual(PlexTVEditorViewModel.parseTMDBShowId("https://www.themoviedb.org/tv/1396-breaking-bad"), 1396, "TMDB show URL should parse show ID")
    assertTrue(PlexTVEditorViewModel.parseTMDBShowId("not-a-show-id") == nil, "Invalid TMDB show reference should return nil")
}

func testRunSelectedPresetRequiresSelection() {
    let vm = PlexTVEditorViewModel()
    vm.selectedPlexPresetId = ""
    vm.runSelectedPreset()
    assertEqual(vm.statusMessage, "Select a preset to run", "Running preset with no selection should be blocked")
}

func testRunSelectedPresetNeedsSpecificSectionWhenNotAllSections() {
    let vm = PlexTVEditorViewModel()
    let preset = PlexSectionActionPreset(
        id: UUID(),
        name: "Single TV",
        sectionType: "show",
        includeRefresh: true,
        includeAnalyze: false,
        includeEmptyTrash: false,
        runOnAllSections: false
    )

    vm.plexActionPresets = [preset]
    vm.selectedPlexPresetId = preset.id.uuidString
    vm.plexLibrarySections = [
        PlexLibrarySection(id: "8", key: "8", title: "TV Programmes", type: "show")
    ]
    vm.selectedPlexTVSectionKey = ""

    vm.runSelectedPreset()

    assertEqual(vm.statusMessage, "Preset requires a selected section", "Single-section preset should require selected section key")
}

func testSelectedPresetNameAndFallback() {
    let vm = PlexTVEditorViewModel()
    let preset = PlexSectionActionPreset(
        id: UUID(),
        name: "Nightly Safe",
        sectionType: "movie",
        includeRefresh: true,
        includeAnalyze: true,
        includeEmptyTrash: false,
        runOnAllSections: true
    )

    vm.plexActionPresets = [preset]
    vm.selectedPlexPresetId = preset.id.uuidString
    assertEqual(vm.selectedPresetName(), "Nightly Safe", "Selected preset name should return active preset name")

    vm.selectedPlexPresetId = "invalid-id"
    assertEqual(vm.selectedPresetName(), "selected preset", "Invalid selected preset should return fallback name")
}

func testUnknownCapabilitiesDefaultToEnabled() {
    let unknown = PlexCapabilities.unknown
    assertTrue(unknown.canRefreshSection, "Unknown capabilities should default refresh=true")
    assertTrue(unknown.canAnalyzeSection, "Unknown capabilities should default analyze=true")
    assertTrue(unknown.canEmptyTrashSection, "Unknown capabilities should default emptyTrash=true")
    assertTrue(unknown.canCancelSectionJob, "Unknown capabilities should default cancel=true")
    assertTrue(unknown.canAnalyzeItem, "Unknown capabilities should default analyzeItem=true")
}

@main
struct Stage2ReliabilityTestRunner {
    static func main() {
        testDestructivePresetRequiresConfirmation()
        testNonDestructivePresetNeedsSections()
        testSettingsRoundTripKeepsReliabilityFields()
        testSchedulerPreviewDates()
        testAdvisoryCapabilityResolution()
        testParseTMDBShowIdVariants()
        testRunSelectedPresetRequiresSelection()
        testRunSelectedPresetNeedsSpecificSectionWhenNotAllSections()
        testSelectedPresetNameAndFallback()
        testUnknownCapabilitiesDefaultToEnabled()
        print("PASS: Stage 2 reliability tests")
    }
}
