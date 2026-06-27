import Darwin
import Foundation

struct MacPulseTestCase {
    let name: String
    let body: () throws -> Void

    init(_ name: String, _ body: @escaping () throws -> Void) {
        self.name = name
        self.body = body
    }
}

struct MacPulseTestFailure: Error, CustomStringConvertible {
    let message: String
    let file: StaticString
    let line: UInt

    var description: String {
        "\(file):\(line): \(message)"
    }
}

func expect(_ condition: @autoclosure () -> Bool,
            _ message: String = "expectation failed",
            file: StaticString = #filePath,
            line: UInt = #line) throws {
    if !condition() {
        throw MacPulseTestFailure(message: message, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(_ actual: @autoclosure () -> T,
                               _ expected: @autoclosure () -> T,
                               file: StaticString = #filePath,
                               line: UInt = #line) throws {
    let actualValue = actual()
    let expectedValue = expected()
    if actualValue != expectedValue {
        throw MacPulseTestFailure(
            message: "expected \(String(describing: expectedValue)), got \(String(describing: actualValue))",
            file: file,
            line: line
        )
    }
}

func expectClose(_ actual: @autoclosure () -> Double,
                 _ expected: @autoclosure () -> Double,
                 accuracy: Double = 0.001,
                 file: StaticString = #filePath,
                 line: UInt = #line) throws {
    let actualValue = actual()
    let expectedValue = expected()
    if abs(actualValue - expectedValue) > accuracy {
        throw MacPulseTestFailure(
            message: "expected \(expectedValue) +/- \(accuracy), got \(actualValue)",
            file: file,
            line: line
        )
    }
}

private enum MacPulseTestRunner {
    static func run() {
        let tests = [
            ByteFormatterTests.tests,
            UpdaterTests.tests,
            ProcessMonitorTests.tests,
            SettingsTests.tests
        ].flatMap { $0 }

        var failures: [String] = []
        for test in tests {
            do {
                try test.body()
            } catch {
                failures.append("\(test.name): \(error)")
            }
        }

        if failures.isEmpty {
            print("MacPulseTests: \(tests.count) tests passed")
        } else {
            fputs("MacPulseTests: \(failures.count) failed out of \(tests.count)\n", stderr)
            for failure in failures {
                fputs("\(failure)\n", stderr)
            }
            exit(1)
        }
    }
}

@used
@section("__DATA,__mod_init_func")
private let runMacPulseTestsOnLoad: @convention(c) () -> Void = {
    MacPulseTestRunner.run()
}
