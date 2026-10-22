import Foundation

/// Minimal ULID (Crockford base32, 48-bit ms timestamp + 80 random bits),
/// matching the `id TEXT ... DEFAULT(ULID())` keys Raycast uses for notes.
nonisolated enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func make(date: Date = .now) -> String {
        var timestamp = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        var timeChars = [Character](repeating: "0", count: 10)
        for i in stride(from: 9, through: 0, by: -1) {
            timeChars[i] = alphabet[Int(timestamp & 31)]
            timestamp >>= 5
        }
        var generator = SystemRandomNumberGenerator()
        let randomChars = (0..<16).map { _ in alphabet[Int(generator.next() & 31)] }
        return String(timeChars + randomChars)
    }
}
