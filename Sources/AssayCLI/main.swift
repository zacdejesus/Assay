// assay: the command-line side of Assay.
//
//   assay drift <tape or directory>... [--update] [--report <file>] [--fail-on-change]
//   assay compare <baseline tape> <candidate tape> [--report <file>] [--fail-on-change]

import Assay
import Foundation

let usage = """
    assay drift <tape or directory>... [--update] [--report <file>] [--fail-on-change]
        Sends every request in the tapes to the on-device model again and reports what
        changed. Needs Apple Intelligence.
          --update           replace each tape with the new answers; if the model
                             changed, the old tape is kept under generations/
          --report <file>    also write the report, as Markdown, to a file
          --fail-on-change   exit with status 1 if any answer changed (changes to requests
                             recorded with random sampling and no seed don't count)

    assay compare <baseline tape> <candidate tape> [--report <file>] [--fail-on-change]
        Compares two tape files. Calls no model.

    Exit status: 0 nothing to report, 1 changes found with --fail-on-change, 2 usage or error.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("assay: \(message)\n".utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(2)
}
arguments.removeFirst()

var paths: [String] = []
var update = false
var failOnChange = false
var reportPath: String?
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--update": update = true
    case "--fail-on-change": failOnChange = true
    case "--report":
        guard !arguments.isEmpty else { fail("--report needs a file") }
        reportPath = arguments.removeFirst()
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        if argument.hasPrefix("-") { fail("unknown option \(argument)\n\n\(usage)") }
        paths.append(argument)
    }
}

let report: DriftReport
do {
    switch command {
    case "drift":
        guard !paths.isEmpty else { fail("drift needs at least one tape or directory\n\n\(usage)") }
        var tapes: [URL] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                fail("no such file or directory: \(path)")
            }
            tapes += isDirectory.boolValue ? try Drift.tapes(in: url) : [url]
        }
        guard !tapes.isEmpty else { fail("no tapes found") }
        var reports: [DriftReport] = []
        for tape in tapes {
            FileHandle.standardError.write(Data("checking \(tape.lastPathComponent)…\n".utf8))
            reports.append(try await Drift.check(tape: tape, update: update))
        }
        report = DriftReport.merged(reports)
    case "compare":
        guard paths.count == 2 else { fail("compare needs a baseline tape and a candidate tape\n\n\(usage)") }
        if update { fail("--update only applies to drift") }
        report = try Drift.compare(baseline: URL(fileURLWithPath: paths[0]), candidate: URL(fileURLWithPath: paths[1]))
    case "-h", "--help", "help":
        print(usage)
        exit(0)
    default:
        fail("unknown command \(command)\n\n\(usage)")
    }
} catch {
    fail(String(describing: error))
}

let markdown = report.markdown()
print(markdown)
if let reportPath {
    do {
        try markdown.write(toFile: reportPath, atomically: true, encoding: .utf8)
    } catch {
        fail("can't write \(reportPath): \(error.localizedDescription)")
    }
}

exit(failOnChange && report.changeCount > 0 ? 1 : 0)
