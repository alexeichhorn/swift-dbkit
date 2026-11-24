import Foundation
import Testing

/// Builds the fixture package in `Tests/CompileFail` and compares the compiler's errors with the fixtures'
/// `// error: <part of the message>` marks. A marked line must fail with an error containing the mark, and every
/// error must be on a line whose mark it contains, so a fixture without marks must compile.
@Suite struct CompileFailTests {
    private struct Line: Hashable {
        /// The fixture's file name, or the whole path of an error outside the fixtures.
        let file: String
        let number: Int
    }

    @Test func fixturesFailOnlyWhereMarked() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CompileFail")
        let fixtures = package.appendingPathComponent("Sources/Fixtures")

        var marks: [Line: [String]] = [:]
        for file in try FileManager.default.contentsOfDirectory(atPath: fixtures.path) where file.hasSuffix(".swift") {
            let source = try String(contentsOf: fixtures.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let texts = line.components(separatedBy: "// error: ").dropFirst()
                if !texts.isEmpty { marks[Line(file: file, number: index + 1)] = texts.map { $0.trimmingCharacters(in: .whitespaces) } }
            }
        }

        let (output, succeeded) = try build(package)
        let lines = output.replacing(/\u{1B}\[[0-9;]*m/, with: "").split(separator: "\n")
        var errors: [Line: Set<String>] = [:]
        for (index, line) in lines.enumerated() {
            guard let error = line.wholeMatch(of: /(.+):(\d+):\d+: error: (.*)/) else { continue }
            var (path, number) = (String(error.1), Int(error.2)!)
            // An error in macro-generated code counts on the line its expansion comes from.
            if path.hasPrefix("macro expansion"), index + 1 < lines.count,
                let origin = lines[index + 1].firstMatch(of: /`- (.+):(\d+):\d+: note: expanded code originates here/)
            {
                (path, number) = (String(origin.1), Int(origin.2)!)
            }
            let file = path.contains("/Sources/Fixtures/") ? URL(fileURLWithPath: path).lastPathComponent : path
            errors[Line(file: file, number: number), default: []].insert(String(error.3))
        }
        if !succeeded && errors.isEmpty {
            Issue.record("The fixture build failed without a compiler error:\n\(output.suffix(3000))")
        }

        for (line, texts) in marks {
            let found = errors[line] ?? []
            for text in texts where !found.contains(where: { $0.contains(text) }) {
                Issue.record("\(line.file):\(line.number): expected an error containing \"\(text)\", got \(found.sorted())")
            }
        }
        for (line, messages) in errors {
            let texts = marks[line] ?? []
            for message in messages.sorted() where !texts.contains(where: { message.contains($0) }) {
                Issue.record("\(line.file):\(line.number): unexpected error: \(message)")
            }
        }
    }

    private func build(_ package: URL) throws -> (output: String, succeeded: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // The default build system fails without the separate emit-module job that the fixture package turns off.
        // Indexing a whole-module build fails with "index output filenames do not match input source files".
        process.arguments = ["swift", "build", "--build-system", "native", "--disable-index-store", "--package-path", package.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: output, as: UTF8.self), process.terminationStatus == 0)
    }
}
