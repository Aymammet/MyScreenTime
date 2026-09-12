import Foundation
import Testing
@testable import MyScreenTime

struct DurationCalculatorTests {
    @Test("A 30-minute session returns 30 minutes")
    func thirtyMinuteSession() throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(30 * 60)

        #expect(try DurationCalculator.minutes(from: start, to: end) == 30)
    }

    @Test("A partial minute rounds up")
    func partialMinuteRoundsUp() throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(61)

        #expect(try DurationCalculator.minutes(from: start, to: end) == 2)
    }

    @Test("An invalid time range is rejected")
    func invalidRange() {
        let start = Date(timeIntervalSince1970: 60)
        let end = Date(timeIntervalSince1970: 0)

        #expect(throws: DurationCalculationError.endNotAfterStart) {
            try DurationCalculator.minutes(from: start, to: end)
        }
    }
}
