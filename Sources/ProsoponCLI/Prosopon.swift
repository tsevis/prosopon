import ArgumentParser

@main
struct Prosopon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prosopon",
        abstract: "Align portraits onto a fixed 2048 x 2048 face grid.",
        discussion: """
            Every portrait is mapped so the eyes land on (512, 512) and (1536, 512) and \
            the mouth on (1024, 1664). The eyes are pinned exactly; the mouth is brought \
            onto target by a vertical stretch and shear about the eye line, both capped \
            so no face is distorted by more than the allowed percentage.
            """,
        version: "0.1.0",
        subcommands: [Align.self, Calibrate.self, Stack.self, QA.self],
        defaultSubcommand: Align.self
    )
}
