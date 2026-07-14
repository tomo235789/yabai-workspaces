import Foundation
import YWRCore

struct DoctorCommand: Command {
    let name = "doctor"
    let summary = "Check that yabai and the environment are ready"
    var usage: String { "ywr doctor" }

    private let doctor: Doctor

    init(doctor: Doctor) {
        self.doctor = doctor
    }

    func run(_ args: [String]) throws -> Int32 {
        let report = doctor.run()
        for result in report.results {
            print("\(icon(result.status)) \(result.name): \(result.message)")
        }
        if report.hasFailure {
            print("\nDoctor found problems that will prevent ywr from working.")
            return 1
        }
        print("\nAll required checks passed.")
        return 0
    }

    private func icon(_ status: CheckStatus) -> String {
        switch status {
        case .pass: return "✓"
        case .warn: return "!"
        case .fail: return "✗"
        }
    }
}
