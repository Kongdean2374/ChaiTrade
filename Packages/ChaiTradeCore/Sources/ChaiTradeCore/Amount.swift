import Foundation

public enum TradeError: Error, LocalizedError, Sendable, Equatable {
    case invalid(String), insufficient(String), unavailable(String), corrupt(String), wrongAccount
    public var errorDescription: String? {
        switch self {
        case .invalid(let s), .insufficient(let s), .unavailable(let s), .corrupt(let s): s
        case .wrongAccount: "帳戶或工作階段不符，已拒絕此操作"
        }
    }
}

/// Bounded exact decimal. Encoding is always a base-10 string; no financial Double inputs.
public struct Amount: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let decimal: Decimal
    public static let zero = Amount(unchecked: 0)
    public static let one = Amount(unchecked: 1)
    public static let max = Amount(unchecked: Decimal(string: "1000000000000000")!)
    private init(unchecked value: Decimal) { decimal = value }
    public init(_ text: String) throws {
        guard text.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]{1,12})?$"#, options: .regularExpression) != nil,
              let d = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !d.isNaN, d <= Self.max.decimal, d >= -Self.max.decimal else {
            throw TradeError.invalid("數值格式、精度或範圍不合法（最多 12 位小數／10¹⁵）")
        }
        decimal = d
    }
    public init(_ integer: Int) throws { try self.init(String(integer)) }
    public var description: String { var d = decimal; return NSDecimalString(&d, Locale(identifier: "en_US_POSIX")) }
    public var displayDouble: Double { NSDecimalNumber(decimal: decimal).doubleValue }
    public static func < (a: Self, b: Self) -> Bool { a.decimal < b.decimal }
    public var magnitude: Self { Self(unchecked: abs(decimal)) }
    public var negated: Self { Self(unchecked: -decimal) }
    public var sign: Int { decimal == 0 ? 0 : (decimal > 0 ? 1 : -1) }
    private static func calculate(_ a: Self, _ b: Self, _ op: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError) throws -> Self {
        var left = a.decimal, right = b.decimal, result = Decimal()
        let error = op(&result, &left, &right, .plain)
        guard error == .noError, !result.isNaN, abs(result) <= Self.max.decimal else {
            throw TradeError.invalid("十進位運算溢位、除零或精度不足")
        }
        return Self(unchecked: result)
    }
    public static func + (a: Self, b: Self) throws -> Self { try calculate(a, b, NSDecimalAdd) }
    public static func - (a: Self, b: Self) throws -> Self { try calculate(a, b, NSDecimalSubtract) }
    public static func * (a: Self, b: Self) throws -> Self { try calculate(a, b, NSDecimalMultiply) }
    public static func / (a: Self, b: Self) throws -> Self {
        // Recurring division has a documented 12-decimal settlement boundary.
        guard b != .zero else { throw TradeError.invalid("不可除以零") }
        var l = a.decimal, r = b.decimal, out = Decimal()
        let error = NSDecimalDivide(&out, &l, &r, .plain)
        guard error == .noError || error == .lossOfPrecision, !out.isNaN, abs(out) <= Self.max.decimal else { throw TradeError.invalid("除法溢位") }
        var rounded = Decimal(); NSDecimalRound(&rounded, &out, 12, .plain)
        return Self(unchecked: rounded)
    }
    public func rounded(_ scale: Int, _ mode: Decimal.RoundingMode = .plain) -> Self {
        var value = decimal, result = Decimal(); NSDecimalRound(&result, &value, scale, mode)
        return Self(unchecked: result)
    }
    public func isMultiple(of step: Self) throws -> Bool {
        guard step > .zero else { return false }
        let ratio = try self / step
        return ratio == ratio.rounded(0)
    }
    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(description) }
}

public typealias Money = Amount
public typealias Price = Amount
public typealias Quantity = Amount

public func sum<S: Sequence>(_ values: S) throws -> Amount where S.Element == Amount {
    try values.reduce(.zero) { try $0 + $1 }
}
