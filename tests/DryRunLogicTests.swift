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

func testSeasonEpisodeCodeParsing() {
    let parsed1 = PlexTVEditorViewModel.parseSeasonEpisodeCode("S2E8")
    assertEqual(parsed1?.season, 2, "S2E8 season parse")
    assertEqual(parsed1?.episode, 8, "S2E8 episode parse")

    let parsed2 = PlexTVEditorViewModel.parseSeasonEpisodeCode(" 3x14 ")
    assertEqual(parsed2?.season, 3, "3x14 season parse")
    assertEqual(parsed2?.episode, 14, "3x14 episode parse")

    let parsed3 = PlexTVEditorViewModel.parseSeasonEpisodeCode("s01e02")
    assertEqual(parsed3?.season, 1, "s01e02 season parse")
    assertEqual(parsed3?.episode, 2, "s01e02 episode parse")

    assertTrue(PlexTVEditorViewModel.parseSeasonEpisodeCode("abc") == nil, "Invalid code should return nil")
    assertTrue(PlexTVEditorViewModel.parseSeasonEpisodeCode("S0E1") == nil, "Season 0 should return nil")
    assertTrue(PlexTVEditorViewModel.parseSeasonEpisodeCode("S1E0") == nil, "Episode 0 should return nil")
}

func testDryRunMeaningfulChangeDetection() {
    let vm = PlexTVEditorViewModel()

    let same = DryRunDiffRow(
        episodeId: 1,
        currentCode: "S1E1",
        mappedCode: "S1E1",
        currentTitle: "Pilot",
        mappedTitle: "Pilot",
        currentAirDate: "2024-01-01",
        mappedAirDate: "2024-01-01",
        note: "TMDB match found"
    )
    assertTrue(!vm.isDryRunMeaningfulChange(same), "Unchanged row should not be marked meaningful")

    let titleChanged = DryRunDiffRow(
        episodeId: 2,
        currentCode: "S1E2",
        mappedCode: "S1E2",
        currentTitle: "Old Title",
        mappedTitle: "New Title",
        currentAirDate: "2024-01-02",
        mappedAirDate: "2024-01-02",
        note: "TMDB match found"
    )
    assertTrue(vm.isDryRunMeaningfulChange(titleChanged), "Title change should be marked meaningful")

    let skipped = DryRunDiffRow(
        episodeId: 3,
        currentCode: "S1E3",
        mappedCode: "Skipped",
        currentTitle: "Name",
        mappedTitle: "Name",
        currentAirDate: "2024-01-03",
        mappedAirDate: "2024-01-03",
        note: "No TMDB match found"
    )
    assertTrue(vm.isDryRunMeaningfulChange(skipped), "Skipped row should be marked meaningful")

    let missing = DryRunDiffRow(
        episodeId: 4,
        currentCode: "S1E4",
        mappedCode: "S1E4",
        currentTitle: "Name",
        mappedTitle: "Name",
        currentAirDate: "2024-01-04",
        mappedAirDate: "2024-01-04",
        note: "TMDB image missing"
    )
    assertTrue(vm.isDryRunMeaningfulChange(missing), "Missing note should be marked meaningful")
}

@main
struct DryRunLogicTestRunner {
    static func main() {
        testSeasonEpisodeCodeParsing()
        testDryRunMeaningfulChangeDetection()
        print("PASS: Dry run logic tests")
    }
}
