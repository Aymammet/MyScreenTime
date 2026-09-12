import Foundation

enum DurationCalculationError: Error, Equatable {
    case endNotAfterStart
}

enum DurationCalculator {
    static func minutes(from start: Date, to end: Date) throws -> Int {
        let seconds = end.timeIntervalSince(start)

        guard seconds > 0 else {
            throw DurationCalculationError.endNotAfterStart
        }

        return Int(ceil(seconds / 60))
    }
}
