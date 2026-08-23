import Foundation
import ProsoponPipeline
import Testing
@testable import ProsoponReview

/// The toolbar's wording and its dimmed controls, checked without a window.
///
/// This is the whole reason the chrome is a function of a value: what a stage badge says,
/// which action is filled, and what the banner reads are the parts that can be wrong in a
/// way nobody notices, and they are all decided here rather than in a SwiftUI file.
@Suite("Chrome")
struct ChromeTests {

    // MARK: Stages

    @Test("the stages read left to right as the work")
    func stageOrder() {
        #expect(Stage.allCases == [.importPortraits, .analyze, .fineTune])
        #expect(Stage.allCases.map(\.label) == ["Import", "Analyze", "Fine Tune"])
    }

    @Test("a stage with nothing in it carries no badge")
    func emptyStagesHaveNoBadge() {
        let empty = ChromeState()
        #expect(Stage.allCases.allSatisfy { $0.badge(empty) == nil })
    }

    @Test("Fine Tune counts what needs attention, not the whole queue")
    func fineTuneBadgeCountsTrouble() {
        // Three hundred good tiles is not a number anybody is tracking; the three bad
        // ones are the entire reason the stage exists.
        let state = ChromeState(tileCount: 300, acceptedCount: 297, attentionCount: 3)
        #expect(Stage.fineTune.badge(state) == 3)
        #expect(Stage.analyze.badge(state) == 300)
        #expect(Stage.fineTune.help(state).contains("3 of 300"))
    }

    @Test("a run on the command line opens in Fine Tune, and nothing loaded opens in Import")
    func openingStage() {
        // `review.sh ~/aligned` means there is work waiting; opening at Import would be a
        // step backwards from where the user asked to be.
        #expect(Stage.opening(hasRun: true) == .fineTune)
        #expect(Stage.opening(hasRun: false) == .importPortraits)
    }

    // MARK: The subject chip

    @Test("the chip names the run and how far along it is")
    func chipNamesTheRun() {
        let state = ChromeState(
            sourceCount: 1, imageCount: 16, runName: "test16", tileCount: 16, acceptedCount: 13
        )
        #expect(SubjectChip.title(state) == "test16")
        #expect(SubjectChip.detail(state) == "13/16 aligned")
    }

    @Test("unsaved corrections show in the chip")
    func chipShowsEdits() {
        let state = ChromeState(runName: "test16", tileCount: 16, acceptedCount: 13, editCount: 2)
        #expect(SubjectChip.detail(state) == "13/16 aligned \u{00B7} 2 edited")
    }

    @Test("before any analysis the chip describes what was imported")
    func chipBeforeAnalysis() {
        #expect(SubjectChip.title(ChromeState()) == "No portraits")
        #expect(SubjectChip.detail(ChromeState()) == nil)

        let imported = ChromeState(sourceCount: 2, imageCount: 40)
        #expect(SubjectChip.title(imported) == "Not analysed yet")
        #expect(SubjectChip.detail(imported) == "40 portraits from 2 sources")
    }

    @Test("a run in progress says so in the chip")
    func chipDuringAnalysis() {
        let state = ChromeState(
            imageCount: 160, isAnalysing: true,
            progress: BatchRunner.Progress(completed: 42, total: 160)
        )
        #expect(SubjectChip.detail(state) == "analysing 42/160")
    }

    @Test("singular and plural are both written out")
    func chipCountsAgree() {
        let one = ChromeState(sourceCount: 1, imageCount: 1)
        #expect(SubjectChip.detail(one) == "1 portrait from 1 source")
    }

    // MARK: Commands

    @Test("every stage offers exactly one filled control")
    func oneFilledControlPerStage() {
        // An accent used twice is an accent used nowhere, and the toolbar's whole job is
        // to say which action is the one to take.
        let states = [
            ChromeState(),
            ChromeState(sourceCount: 1, imageCount: 16),
            ChromeState(sourceCount: 1, imageCount: 16, runName: "r", tileCount: 16, acceptedCount: 13),
            ChromeState(runName: "r", tileCount: 16, acceptedCount: 13, attentionCount: 3, editCount: 2),
            ChromeState(imageCount: 9, isAnalysing: true,
                        progress: BatchRunner.Progress(completed: 3, total: 9)),
            ChromeState(runName: "r", tileCount: 4, acceptedCount: 4, isSaving: true),
        ]
        for state in states {
            for stage in Stage.allCases {
                let primaries = CommandSet.commands(for: stage, state: state)
                    .filter { $0.weight == .primary }
                #expect(primaries.count == 1,
                        "\(stage) had \(primaries.count) filled controls for \(state)")
            }
        }
    }

    @Test("an unavailable action is dimmed rather than taken away")
    func unavailableActionsStay() {
        // A control that disappears takes with it the knowledge that it exists, and then
        // the question is not "why is Save grey" but "where has Save gone".
        let nothing = ChromeState()
        let save = CommandSet.commands(for: .fineTune, state: nothing)
            .first { $0.action == .saveCorrections }
        #expect(save != nil)
        #expect(save?.isEnabled == false)

        let analyse = CommandSet.commands(for: .importPortraits, state: nothing)
            .first { $0.action == .analyse }
        #expect(analyse != nil)
        #expect(analyse?.isEnabled == false)
    }

    @Test("the primary control counts what it is about to do")
    func primaryNamesItsWork() {
        let ready = ChromeState(sourceCount: 1, imageCount: 16)
        let analyse = CommandSet.commands(for: .importPortraits, state: ready)
            .first { $0.action == .analyse }
        #expect(analyse?.title == "Analyse 16 Portraits")
        #expect(analyse?.isEnabled == true)

        let edited = ChromeState(runName: "r", tileCount: 16, acceptedCount: 16, editCount: 1)
        let save = CommandSet.commands(for: .fineTune, state: edited)
            .first { $0.action == .saveCorrections }
        #expect(save?.title == "Save 1 Correction")
        #expect(save?.isEnabled == true)
    }

    @Test("analysing what is already analysed is not offered")
    func nothingOutstanding() {
        // Every imported photograph is already in the run, so there is nothing to do and
        // the button says so rather than silently doing the work twice.
        let done = ChromeState(sourceCount: 1, imageCount: 16, alreadyAlignedCount: 16,
                               runName: "r", tileCount: 16, acceptedCount: 16)
        let analyse = CommandSet.commands(for: .importPortraits, state: done)
            .first { $0.action == .analyse }
        #expect(analyse?.isEnabled == false)
        #expect(analyse?.title == "All Analysed")
    }

    @Test("a run in flight can be stopped and cannot be started again")
    func analysisInFlight() {
        let running = ChromeState(
            sourceCount: 1, imageCount: 20, isAnalysing: true,
            progress: BatchRunner.Progress(completed: 4, total: 20)
        )
        let commands = CommandSet.commands(for: .analyze, state: running)
        #expect(commands.first { $0.action == .cancelAnalysis }?.isEnabled == true)
        #expect(commands.first { $0.action == .analyse }?.isEnabled == false)

        // Nothing anywhere may start a second run over the top of the first.
        for stage in Stage.allCases {
            let starts = CommandSet.commands(for: stage, state: running)
                .filter { $0.action == .analyse && $0.isEnabled }
            #expect(starts.isEmpty, "\(stage) would let a second analysis start")
        }
    }

    @Test("saving is not offered twice")
    func savingIsNotReentrant() {
        let saving = ChromeState(runName: "r", tileCount: 4, acceptedCount: 4,
                                 editCount: 2, isSaving: true)
        let save = CommandSet.commands(for: .fineTune, state: saving)
            .first { $0.action == .saveCorrections }
        #expect(save?.title == "Saving\u{2026}")
        #expect(save?.isEnabled == false)
    }

    @Test("every command explains itself")
    func everyCommandHasHelp() {
        let states = [ChromeState(), ChromeState(sourceCount: 2, imageCount: 8,
                                                 runName: "r", tileCount: 8, acceptedCount: 6)]
        for state in states {
            for stage in Stage.allCases {
                for command in CommandSet.commands(for: stage, state: state) {
                    #expect(!command.help.isEmpty, "\(command.action) has no help")
                    #expect(!command.title.isEmpty, "\(command.action) has no title")
                    #expect(!command.symbol.isEmpty, "\(command.action) has no symbol")
                }
            }
        }
    }

    // MARK: The banner

    @Test("an empty window says how to begin")
    func emptyBanner() {
        let banner = StatusBanner.message(for: .importPortraits, state: ChromeState())
        #expect(banner.kind == .notice)
        #expect(banner.text.contains("Add a folder"))
    }

    @Test("the import banner counts what is found against what is already done")
    func importCounts() {
        let state = ChromeState(sourceCount: 2, imageCount: 2560, alreadyAlignedCount: 1204)
        let banner = StatusBanner.message(for: .importPortraits, state: state)
        #expect(banner.text.contains("2560 portraits found"))
        #expect(banner.text.contains("1204 already aligned"))
        #expect(banner.text.contains("1356 still to do"))
    }

    @Test("declined tiles are reported as a number, not passed over")
    func rejectionsAreReported() {
        // A declined tile is the gates working rather than a failure, but it is a figure
        // somebody should see before committing to a stack.
        let state = ChromeState(runName: "r", tileCount: 16, acceptedCount: 13)
        let banner = StatusBanner.message(for: .analyze, state: state)
        #expect(banner.kind == .caution)
        #expect(banner.text.contains("13 of 16 aligned"))
        #expect(banner.text.contains("3 could not be used"))
    }

    @Test("a clean batch says so")
    func cleanBatch() {
        let state = ChromeState(runName: "r", tileCount: 16, acceptedCount: 16)
        #expect(StatusBanner.message(for: .analyze, state: state).kind == .notice)
        #expect(StatusBanner.message(for: .fineTune, state: state).kind == .notice)
        #expect(StatusBanner.message(for: .fineTune, state: state).text.contains("cleared"))
    }

    @Test("unsaved corrections outrank a queue that needs attention")
    func unsavedWinsOverAttention() {
        // Both are true at once and there is one line. Work that would be lost by closing
        // the window matters more than work still to do.
        let state = ChromeState(runName: "r", tileCount: 16, acceptedCount: 13,
                                attentionCount: 3, editCount: 2)
        let banner = StatusBanner.message(for: .fineTune, state: state)
        #expect(banner.text.contains("2 corrections not yet saved"))
    }

    @Test("a source that cannot be read interrupts whatever else the stage was saying")
    func unreadableSourceWins() {
        // A folder on an unmounted volume reports no images rather than an error, so the
        // count silently becomes wrong. That outranks every other message, on every stage.
        let state = ChromeState(sourceCount: 3, imageCount: 900, unreadableSourceCount: 1,
                                runName: "r", tileCount: 900, acceptedCount: 900)
        for stage in Stage.allCases {
            let banner = StatusBanner.message(for: stage, state: state)
            #expect(banner.kind == .caution)
            #expect(banner.text.contains("could not be read"), "\(stage): \(banner.text)")
        }
    }

    @Test("an unreadable QA report is said out loud, with the reason behind it")
    func qaProblemIsSurfaced() {
        let state = ChromeState(runName: "r", tileCount: 8, acceptedCount: 8,
                                qaReportProblem: "qa.json: dataCorrupted")
        let banner = StatusBanner.message(for: .fineTune, state: state)
        #expect(banner.kind == .caution)
        #expect(banner.extra == ["qa.json: dataCorrupted"])
    }

    @Test("a run in flight reports its progress on every stage")
    func progressBanner() {
        let state = ChromeState(imageCount: 160, isAnalysing: true,
                                progress: BatchRunner.Progress(completed: 42, total: 160))
        for stage in Stage.allCases {
            #expect(StatusBanner.message(for: stage, state: state).text.contains("42 of 160"))
        }
    }

    @Test("sources holding nothing readable suggest the reason")
    func noImagesFound() {
        let state = ChromeState(sourceCount: 1, imageCount: 0)
        let banner = StatusBanner.message(for: .importPortraits, state: state)
        #expect(banner.kind == .caution)
        #expect(banner.text.contains("Look Inside Folders"))
    }

    @Test("every banner is a sentence, and every state produces one")
    func everyStateHasABanner() {
        let states = [
            ChromeState(),
            ChromeState(sourceCount: 1),
            ChromeState(sourceCount: 1, imageCount: 5),
            ChromeState(sourceCount: 1, imageCount: 5, alreadyAlignedCount: 5),
            ChromeState(runName: "r", tileCount: 5, acceptedCount: 5),
            ChromeState(runName: "r", tileCount: 5, acceptedCount: 2, attentionCount: 3),
            ChromeState(runName: "r", tileCount: 5, acceptedCount: 5, isSaving: true),
            ChromeState(runName: "r", tileCount: 5, acceptedCount: 5,
                        lastSaveSummary: "2 tiles rewritten"),
        ]
        for state in states {
            for stage in Stage.allCases {
                let banner = StatusBanner.message(for: stage, state: state)
                #expect(!banner.text.isEmpty)
                #expect(banner.text.hasSuffix(".") || banner.text.hasSuffix("\u{2026}"),
                        "not a sentence: \(banner.text)")
                #expect(!banner.symbol.isEmpty)
            }
        }
    }
}
