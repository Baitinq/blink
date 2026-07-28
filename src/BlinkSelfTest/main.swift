import Foundation

// A dependency-free test harness: XCTest is unavailable with bare Command Line
// Tools, and this way the exact same suite runs on macOS and Linux with
// `swift run blink-selftest`.

var failures: [String] = []
var checks = 0
var currentTest = ""

func expect(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    checks += 1
    guard !condition else { return }
    failures.append("\(currentTest): \(message)  (\(file):\(line))")
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ note: String = "",
                               file: String = #fileID, line: Int = #line) {
    expect(lhs == rhs, "expected \(rhs), got \(lhs)\(note.isEmpty ? "" : " — \(note)")",
           file: file, line: line)
}

func expectTrue(_ value: Bool, _ note: String = "", file: String = #fileID, line: Int = #line) {
    expect(value, "expected true\(note.isEmpty ? "" : " — \(note)")", file: file, line: line)
}

func expectFalse(_ value: Bool, _ note: String = "", file: String = #fileID, line: Int = #line) {
    expect(!value, "expected false\(note.isEmpty ? "" : " — \(note)")", file: file, line: line)
}

func expectNotNil<T>(_ value: T?, _ note: String = "", file: String = #fileID, line: Int = #line) {
    expect(value != nil, "expected non-nil\(note.isEmpty ? "" : " — \(note)")", file: file, line: line)
}

func expectLessThanOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, _ note: String = "",
                                          file: String = #fileID, line: Int = #line) {
    expect(lhs <= rhs, "expected \(lhs) <= \(rhs)\(note.isEmpty ? "" : " — \(note)")",
           file: file, line: line)
}

/// For assertions where a tick or two of real progress is expected.
func expectNear(_ value: Int, _ target: Int, tolerance: Int = 2,
                file: String = #fileID, line: Int = #line) {
    expect(abs(value - target) <= tolerance,
           "expected \(target) ± \(tolerance), got \(value)", file: file, line: line)
}

func run(_ name: String, _ body: () -> Void) {
    currentTest = name
    let before = failures.count
    body()
    let mark = failures.count == before ? "✓" : "✗"
    print("  \(mark) \(name)")
}

let suite = BreakEngineTests()
print("BlinkCore self-test")
for (name, body) in suite.allTests {
    suite.setUp()
    run(name, body)
}

print("")
if failures.isEmpty {
    print("\(suite.allTests.count) tests, \(checks) checks — all passed")
    exit(0)
} else {
    for failure in failures { print("FAIL  \(failure)") }
    print("\n\(failures.count) failure(s) in \(suite.allTests.count) tests")
    exit(1)
}
