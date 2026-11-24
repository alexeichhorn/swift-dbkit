import NIOCore
import PostgresNIO

// PostgreSQL string functions. A NULL argument makes the result NULL, except where a function says otherwise. Swift
// values become bind parameters, never SQL text.
//
// The overloads of a function never overlap, so each call matches exactly one; overlapping overloads, even disfavored
// ones, make a projection of many calls take the type checker exponential time. One overload takes every argument
// besides the text required and keeps the text's nullability. The others give a nullable result, one per argument
// that can be nullable: that argument is a nullable expression, the arguments before it are required, and the ones
// after it may be nullable.
//
// A count, start, length or index is an `Int32` value or expression. A generic parameter would type an integer literal
// as Swift's `Int`, so a value is a plain `Int32` parameter, with a separate overload for an expression in its place.
// Required and nullable expressions are existentials rather than generic parameters, so that a literal fails them at
// once rather than after the type checker has chosen the overloads of every other call in the expression.

extension SQL {
    // MARK: Case conversion and trimming

    public static func upper<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("UPPER", text) }
    public static func lower<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("LOWER", text) }
    /// Removes spaces from both ends.
    public static func trim<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("TRIM", text) }
    public static func trimStart<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String {
        Expr(.sequence([.raw("TRIM(LEADING FROM "), text.sqlNode, .raw(")")]))
    }
    public static func trimEnd<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String {
        Expr(.sequence([.raw("TRIM(TRAILING FROM "), text.sqlNode, .raw(")")]))
    }
    /// Removes the longest span made from the `characters` set (not a literal prefix) at both ends.
    public static func trimChars<T: SQLArgument>(_ text: T, _ characters: some SQLArgument<String>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        trimming("BOTH", text, characters)
    }
    public static func trimChars<T: SQLArgument>(_ text: T, _ characters: any SQLExpression<String?>) -> Expr<String?>
    where T.Value.NonNull == String {
        trimming("BOTH", text, characters)
    }
    public static func trimStartChars<T: SQLArgument>(_ text: T, _ characters: some SQLArgument<String>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        trimming("LEADING", text, characters)
    }
    public static func trimStartChars<T: SQLArgument>(_ text: T, _ characters: any SQLExpression<String?>) -> Expr<String?>
    where T.Value.NonNull == String {
        trimming("LEADING", text, characters)
    }
    public static func trimEndChars<T: SQLArgument>(_ text: T, _ characters: some SQLArgument<String>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        trimming("TRAILING", text, characters)
    }
    public static func trimEndChars<T: SQLArgument>(_ text: T, _ characters: any SQLExpression<String?>) -> Expr<String?>
    where T.Value.NonNull == String {
        trimming("TRAILING", text, characters)
    }

    private static func trimming<Result>(_ side: String, _ text: any SQLArgument, _ characters: any SQLArgument) -> Expr<Result> {
        Expr(.sequence([.raw("TRIM(\(side) "), characters.sqlNode, .raw(" FROM "), text.sqlNode, .raw(")")]))
    }

    // MARK: Length and search

    public static func charLength<T: SQLArgument>(_ text: T) -> Expr<T.Value.AsInt32> where T.Value.NonNull == String {
        call("CHAR_LENGTH", text)
    }
    public static func byteLength<T: SQLArgument>(_ text: T) -> Expr<T.Value.AsInt32> where T.Value.NonNull == String {
        call("OCTET_LENGTH", text)
    }
    public static func bitLength<T: SQLArgument>(_ text: T) -> Expr<T.Value.AsInt32> where T.Value.NonNull == String {
        call("BIT_LENGTH", text)
    }
    /// The first 1-based position of `substring`, or 0.
    public static func position<T: SQLArgument>(_ text: T, _ substring: some SQLArgument<String>) -> Expr<T.Value.AsInt32>
    where T.Value.NonNull == String {
        call("STRPOS", text, substring)
    }
    public static func position<T: SQLArgument>(_ text: T, _ substring: any SQLExpression<String?>) -> Expr<Int32?>
    where T.Value.NonNull == String {
        call("STRPOS", text, substring)
    }

    // The two overloads of `startsWith` split on the prefix's nullability, as comparisons do, and require
    // `P.Value.NonNull == String` in both, so that a prefix of another type is reported by its type.

    /// Exact, case-sensitive prefix test. PostgreSQL 11+.
    public static func startsWith<T: SQLArgument, P: SQLArgument>(_ text: T, _ prefix: P) -> Expr<T.Value.AsBool>
    where T.Value.NonNull == String, P.Value.NonNull == String, P.Value.AsBool: SQLValue {
        call("STARTS_WITH", text, prefix)
    }
    public static func startsWith<T: SQLArgument, P: SQLArgument>(_ text: T, _ prefix: P) -> Expr<Bool?>
    where T.Value.NonNull == String, P.Value: ExpressibleByNilLiteral, P.Value.NonNull == String {
        call("STARTS_WITH", text, prefix)
    }

    // MARK: Extraction and sizing

    public static func left<T: SQLArgument>(_ text: T, _ count: Int32) -> Expr<T.Value> where T.Value.NonNull == String {
        call("LEFT", text, count)
    }
    public static func left<T: SQLArgument>(_ text: T, _ count: any SQLExpression<Int32>) -> Expr<T.Value> where T.Value.NonNull == String {
        call("LEFT", text, count)
    }
    public static func left<T: SQLArgument>(_ text: T, _ count: any SQLExpression<Int32?>) -> Expr<String?>
    where T.Value.NonNull == String {
        call("LEFT", text, count)
    }
    public static func right<T: SQLArgument>(_ text: T, _ count: Int32) -> Expr<T.Value> where T.Value.NonNull == String {
        call("RIGHT", text, count)
    }
    public static func right<T: SQLArgument>(_ text: T, _ count: any SQLExpression<Int32>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("RIGHT", text, count)
    }
    public static func right<T: SQLArgument>(_ text: T, _ count: any SQLExpression<Int32?>) -> Expr<String?>
    where T.Value.NonNull == String {
        call("RIGHT", text, count)
    }

    /// Up to `count` characters from the 1-based `start`.
    public static func substring<T: SQLArgument>(_ text: T, _ start: Int32, _ count: Int32) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("SUBSTRING", text, start, count)
    }
    public static func substring<T: SQLArgument>(_ text: T, _ start: Int32, _ count: any SQLExpression<Int32>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("SUBSTRING", text, start, count)
    }
    public static func substring<T: SQLArgument>(_ text: T, _ start: any SQLExpression<Int32>, _ count: Int32) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("SUBSTRING", text, start, count)
    }
    public static func substring<T: SQLArgument>(_ text: T, _ start: any SQLExpression<Int32>, _ count: any SQLExpression<Int32>)
        -> Expr<T.Value> where T.Value.NonNull == String
    {
        call("SUBSTRING", text, start, count)
    }
    public static func substring<T: SQLArgument>(_ text: T, _ start: any SQLExpression<Int32?>, _ count: Int32) -> Expr<String?>
    where T.Value.NonNull == String {
        call("SUBSTRING", text, start, count)
    }
    public static func substring<T: SQLArgument, C: SQLExpression>(_ text: T, _ start: any SQLExpression<Int32?>, _ count: C)
        -> Expr<String?> where T.Value.NonNull == String, C.Value.NonNull == Int32
    {
        call("SUBSTRING", text, start, count)
    }
    public static func substring<T: SQLArgument>(_ text: T, _ start: Int32, _ count: any SQLExpression<Int32?>) -> Expr<String?>
    where T.Value.NonNull == String {
        call("SUBSTRING", text, start, count)
    }
    public static func substring<T: SQLArgument>(_ text: T, _ start: any SQLExpression<Int32>, _ count: any SQLExpression<Int32?>)
        -> Expr<String?> where T.Value.NonNull == String
    {
        call("SUBSTRING", text, start, count)
    }

    public static func `repeat`<T: SQLArgument>(_ text: T, _ count: Int32) -> Expr<T.Value> where T.Value.NonNull == String {
        call("REPEAT", text, count)
    }
    public static func `repeat`<T: SQLArgument>(_ text: T, _ count: any SQLExpression<Int32>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("REPEAT", text, count)
    }
    public static func `repeat`<T: SQLArgument>(_ text: T, _ count: any SQLExpression<Int32?>) -> Expr<String?>
    where T.Value.NonNull == String {
        call("REPEAT", text, count)
    }

    /// `LPAD`: pads on the left by cycling `fill`, or truncates on the right.
    public static func padStart<T: SQLArgument>(_ text: T, _ length: Int32, _ fill: some SQLArgument<String>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("LPAD", text, length, fill)
    }
    public static func padStart<T: SQLArgument>(_ text: T, _ length: any SQLExpression<Int32>, _ fill: some SQLArgument<String>)
        -> Expr<T.Value> where T.Value.NonNull == String
    {
        call("LPAD", text, length, fill)
    }
    public static func padStart<T: SQLArgument, F: SQLArgument>(_ text: T, _ length: any SQLExpression<Int32?>, _ fill: F)
        -> Expr<String?> where T.Value.NonNull == String, F.Value.NonNull == String
    {
        call("LPAD", text, length, fill)
    }
    public static func padStart<T: SQLArgument>(_ text: T, _ length: Int32, _ fill: any SQLExpression<String?>) -> Expr<String?>
    where T.Value.NonNull == String {
        call("LPAD", text, length, fill)
    }
    public static func padStart<T: SQLArgument>(_ text: T, _ length: any SQLExpression<Int32>, _ fill: any SQLExpression<String?>)
        -> Expr<String?> where T.Value.NonNull == String
    {
        call("LPAD", text, length, fill)
    }
    /// `RPAD`: pads on the right by cycling `fill`, or truncates on the right.
    public static func padEnd<T: SQLArgument>(_ text: T, _ length: Int32, _ fill: some SQLArgument<String>) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("RPAD", text, length, fill)
    }
    public static func padEnd<T: SQLArgument>(_ text: T, _ length: any SQLExpression<Int32>, _ fill: some SQLArgument<String>)
        -> Expr<T.Value> where T.Value.NonNull == String
    {
        call("RPAD", text, length, fill)
    }
    public static func padEnd<T: SQLArgument, F: SQLArgument>(_ text: T, _ length: any SQLExpression<Int32?>, _ fill: F)
        -> Expr<String?> where T.Value.NonNull == String, F.Value.NonNull == String
    {
        call("RPAD", text, length, fill)
    }
    public static func padEnd<T: SQLArgument>(_ text: T, _ length: Int32, _ fill: any SQLExpression<String?>) -> Expr<String?>
    where T.Value.NonNull == String {
        call("RPAD", text, length, fill)
    }
    public static func padEnd<T: SQLArgument>(_ text: T, _ length: any SQLExpression<Int32>, _ fill: any SQLExpression<String?>)
        -> Expr<String?> where T.Value.NonNull == String
    {
        call("RPAD", text, length, fill)
    }

    // MARK: Transformation

    /// `INITCAP`: uppercases the first letter of each word.
    public static func titleCase<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("INITCAP", text) }
    public static func replace<T: SQLArgument>(_ text: T, _ from: some SQLArgument<String>, _ to: some SQLArgument<String>)
        -> Expr<T.Value> where T.Value.NonNull == String
    {
        call("REPLACE", text, from, to)
    }
    public static func replace<T: SQLArgument, To: SQLArgument>(_ text: T, _ from: any SQLExpression<String?>, _ to: To) -> Expr<String?>
    where T.Value.NonNull == String, To.Value.NonNull == String {
        call("REPLACE", text, from, to)
    }
    public static func replace<T: SQLArgument>(_ text: T, _ from: some SQLArgument<String>, _ to: any SQLExpression<String?>)
        -> Expr<String?> where T.Value.NonNull == String
    {
        call("REPLACE", text, from, to)
    }

    /// `OVERLAY`: replaces `count` characters from the 1-based `start`.
    public static func replaceRange<T: SQLArgument>(_ text: T, _ replacement: some SQLArgument<String>, _ start: Int32, _ count: Int32)
        -> Expr<T.Value> where T.Value.NonNull == String
    {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument>(
        _ text: T,
        _ replacement: some SQLArgument<String>,
        _ start: Int32,
        _ count: any SQLExpression<Int32>
    ) -> Expr<T.Value> where T.Value.NonNull == String {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument>(
        _ text: T,
        _ replacement: some SQLArgument<String>,
        _ start: any SQLExpression<Int32>,
        _ count: Int32
    ) -> Expr<T.Value> where T.Value.NonNull == String {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument>(
        _ text: T,
        _ replacement: some SQLArgument<String>,
        _ start: any SQLExpression<Int32>,
        _ count: any SQLExpression<Int32>
    ) -> Expr<T.Value> where T.Value.NonNull == String {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument>(_ text: T, _ replacement: any SQLExpression<String?>, _ start: Int32, _ count: Int32)
        -> Expr<String?> where T.Value.NonNull == String
    {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument, C: SQLExpression>(
        _ text: T,
        _ replacement: any SQLExpression<String?>,
        _ start: Int32,
        _ count: C
    ) -> Expr<String?> where T.Value.NonNull == String, C.Value.NonNull == Int32 {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument, S: SQLExpression>(
        _ text: T,
        _ replacement: any SQLExpression<String?>,
        _ start: S,
        _ count: Int32
    ) -> Expr<String?> where T.Value.NonNull == String, S.Value.NonNull == Int32 {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument, S: SQLExpression, C: SQLExpression>(
        _ text: T,
        _ replacement: any SQLExpression<String?>,
        _ start: S,
        _ count: C
    ) -> Expr<String?> where T.Value.NonNull == String, S.Value.NonNull == Int32, C.Value.NonNull == Int32 {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument>(
        _ text: T,
        _ replacement: some SQLArgument<String>,
        _ start: any SQLExpression<Int32?>,
        _ count: Int32
    ) -> Expr<String?> where T.Value.NonNull == String {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument, C: SQLExpression>(
        _ text: T,
        _ replacement: some SQLArgument<String>,
        _ start: any SQLExpression<Int32?>,
        _ count: C
    ) -> Expr<String?> where T.Value.NonNull == String, C.Value.NonNull == Int32 {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument>(
        _ text: T,
        _ replacement: some SQLArgument<String>,
        _ start: Int32,
        _ count: any SQLExpression<Int32?>
    ) -> Expr<String?> where T.Value.NonNull == String {
        call("OVERLAY", text, replacement, start, count)
    }
    public static func replaceRange<T: SQLArgument>(
        _ text: T,
        _ replacement: some SQLArgument<String>,
        _ start: any SQLExpression<Int32>,
        _ count: any SQLExpression<Int32?>
    ) -> Expr<String?> where T.Value.NonNull == String {
        call("OVERLAY", text, replacement, start, count)
    }

    /// `TRANSLATE`: maps characters by position; extra characters in `from` are deleted.
    public static func translateChars<T: SQLArgument>(_ text: T, _ from: some SQLArgument<String>, _ to: some SQLArgument<String>)
        -> Expr<T.Value> where T.Value.NonNull == String
    {
        call("TRANSLATE", text, from, to)
    }
    public static func translateChars<T: SQLArgument, To: SQLArgument>(_ text: T, _ from: any SQLExpression<String?>, _ to: To)
        -> Expr<String?> where T.Value.NonNull == String, To.Value.NonNull == String
    {
        call("TRANSLATE", text, from, to)
    }
    public static func translateChars<T: SQLArgument>(_ text: T, _ from: some SQLArgument<String>, _ to: any SQLExpression<String?>)
        -> Expr<String?> where T.Value.NonNull == String
    {
        call("TRANSLATE", text, from, to)
    }
    public static func reverse<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("REVERSE", text) }

    // MARK: Composition and splitting

    /// `CONCAT(…)`: concatenates text values and ignores NULL items, so the result is never NULL.
    public static func concat<each A: SQLTextArgument>(_ items: repeat each A) -> Expr<String> {
        Expr(.function("CONCAT", textItems(repeat each items)))
    }

    /// `CONCAT_WS(separator, …)`: ignores NULL items; NULL only when the separator is NULL.
    public static func concatWithSeparator<S: SQLArgument, each A: SQLTextArgument>(_ separator: S, _ items: repeat each A) -> Expr<S.Value>
    where S.Value.NonNull == String {
        Expr(.function("CONCAT_WS", [separator.sqlNode] + textItems(repeat each items)))
    }

    /// PostgreSQL has no `CONCAT()` without arguments, so no items become an empty `VARIADIC` array.
    private static func textItems<each A: SQLTextArgument>(_ items: repeat each A) -> [SQLNode] {
        var nodes: [SQLNode] = []
        for item in repeat each items { nodes.append(item.sqlNode) }
        return nodes.isEmpty ? [.raw("VARIADIC ARRAY[]::TEXT[]")] : nodes
    }

    /// `STRING_TO_ARRAY(text, delimiter)`. A NULL delimiter splits into characters, so only a NULL text gives NULL.
    public static func split<T: SQLArgument, D: SQLArgument>(_ text: T, _ delimiter: D) -> Expr<T.Value.AsStringArray>
    where T.Value.NonNull == String, D.Value.NonNull == String {
        call("STRING_TO_ARRAY", text, delimiter)
    }
    /// `SPLIT_PART`: the 1-based field; negative indexes count from the end (PostgreSQL 14+).
    public static func splitPart<T: SQLArgument>(_ text: T, _ delimiter: some SQLArgument<String>, _ index: Int32) -> Expr<T.Value>
    where T.Value.NonNull == String {
        call("SPLIT_PART", text, delimiter, index)
    }
    public static func splitPart<T: SQLArgument>(_ text: T, _ delimiter: some SQLArgument<String>, _ index: any SQLExpression<Int32>)
        -> Expr<T.Value> where T.Value.NonNull == String
    {
        call("SPLIT_PART", text, delimiter, index)
    }
    public static func splitPart<T: SQLArgument>(_ text: T, _ delimiter: any SQLExpression<String?>, _ index: Int32) -> Expr<String?>
    where T.Value.NonNull == String {
        call("SPLIT_PART", text, delimiter, index)
    }
    public static func splitPart<T: SQLArgument, I: SQLExpression>(_ text: T, _ delimiter: any SQLExpression<String?>, _ index: I)
        -> Expr<String?> where T.Value.NonNull == String, I.Value.NonNull == Int32
    {
        call("SPLIT_PART", text, delimiter, index)
    }
    public static func splitPart<T: SQLArgument>(_ text: T, _ delimiter: some SQLArgument<String>, _ index: any SQLExpression<Int32?>)
        -> Expr<String?> where T.Value.NonNull == String
    {
        call("SPLIT_PART", text, delimiter, index)
    }

    // MARK: Regex inspection

    /// `REGEXP_LIKE`. PostgreSQL 15+.
    public static func regexIsMatch<T: SQLArgument>(_ text: T, _ pattern: some SQLArgument<String>) -> Expr<T.Value.AsBool>
    where T.Value.NonNull == String {
        call("REGEXP_LIKE", text, pattern)
    }
    public static func regexIsMatch<T: SQLArgument>(_ text: T, _ pattern: any SQLExpression<String?>) -> Expr<Bool?>
    where T.Value.NonNull == String {
        call("REGEXP_LIKE", text, pattern)
    }
    /// `REGEXP_COUNT`. PostgreSQL 15+.
    public static func regexCount<T: SQLArgument>(_ text: T, _ pattern: some SQLArgument<String>) -> Expr<T.Value.AsInt32>
    where T.Value.NonNull == String {
        call("REGEXP_COUNT", text, pattern)
    }
    public static func regexCount<T: SQLArgument>(_ text: T, _ pattern: any SQLExpression<String?>) -> Expr<Int32?>
    where T.Value.NonNull == String {
        call("REGEXP_COUNT", text, pattern)
    }
    /// `REGEXP_INSTR`: the first 1-based match position, or 0. PostgreSQL 15+.
    public static func regexPosition<T: SQLArgument>(_ text: T, _ pattern: some SQLArgument<String>) -> Expr<T.Value.AsInt32>
    where T.Value.NonNull == String {
        call("REGEXP_INSTR", text, pattern)
    }
    public static func regexPosition<T: SQLArgument>(_ text: T, _ pattern: any SQLExpression<String?>) -> Expr<Int32?>
    where T.Value.NonNull == String {
        call("REGEXP_INSTR", text, pattern)
    }
    /// `REGEXP_MATCH`: the capture groups of the first match; NULL when nothing matches.
    public static func regexCaptures<T: SQLArgument, P: SQLArgument>(_ text: T, _ pattern: P) -> Expr<RegexCaptures?>
    where T.Value.NonNull == String, P.Value.NonNull == String {
        call("REGEXP_MATCH", text, pattern)
    }
    /// `REGEXP_SUBSTR`: the first whole match; NULL when nothing matches. PostgreSQL 15+.
    public static func regexExtract<T: SQLArgument, P: SQLArgument>(_ text: T, _ pattern: P) -> Expr<String?>
    where T.Value.NonNull == String, P.Value.NonNull == String {
        call("REGEXP_SUBSTR", text, pattern)
    }

    // MARK: Regex transformation

    public static func regexReplace<T: SQLArgument>(
        _ text: T,
        _ pattern: some SQLArgument<String>,
        _ replacement: some SQLArgument<String>,
        _ flags: RegexReplaceFlags = []
    ) -> Expr<T.Value> where T.Value.NonNull == String {
        call("REGEXP_REPLACE", text, pattern, replacement, flags.sql)
    }
    public static func regexReplace<T: SQLArgument, R: SQLArgument>(
        _ text: T,
        _ pattern: any SQLExpression<String?>,
        _ replacement: R,
        _ flags: RegexReplaceFlags = []
    ) -> Expr<String?> where T.Value.NonNull == String, R.Value.NonNull == String {
        call("REGEXP_REPLACE", text, pattern, replacement, flags.sql)
    }
    public static func regexReplace<T: SQLArgument>(
        _ text: T,
        _ pattern: some SQLArgument<String>,
        _ replacement: any SQLExpression<String?>,
        _ flags: RegexReplaceFlags = []
    ) -> Expr<String?> where T.Value.NonNull == String {
        call("REGEXP_REPLACE", text, pattern, replacement, flags.sql)
    }

    public static func regexSplit<T: SQLArgument>(_ text: T, _ pattern: some SQLArgument<String>, _ flags: RegexSplitFlags = [])
        -> Expr<T.Value.AsStringArray> where T.Value.NonNull == String
    {
        call("REGEXP_SPLIT_TO_ARRAY", text, pattern, flags.contains(.caseInsensitive) ? "i" : "")
    }
    public static func regexSplit<T: SQLArgument>(_ text: T, _ pattern: any SQLExpression<String?>, _ flags: RegexSplitFlags = [])
        -> Expr<[String]?> where T.Value.NonNull == String
    {
        call("REGEXP_SPLIT_TO_ARRAY", text, pattern, flags.contains(.caseInsensitive) ? "i" : "")
    }

    // MARK: Unicode and code points

    /// `NORMALIZE`. PostgreSQL 13+, UTF8 databases.
    public static func normalize<T: SQLArgument>(_ text: T, _ form: NormalizationForm) -> Expr<T.Value> where T.Value.NonNull == String {
        Expr(.sequence([.raw("NORMALIZE("), text.sqlNode, .raw(", \(form.rawValue))")]))
    }
    /// `ASCII`: the first character's code point, or 0 for empty text.
    public static func firstCodepoint<T: SQLArgument>(_ text: T) -> Expr<T.Value.AsInt32> where T.Value.NonNull == String {
        call("ASCII", text)
    }
    /// `CHR`: the character for a code point.
    public static func fromCodepoint<C: SQLArgument>(_ codepoint: C) -> Expr<C.Value.AsString> where C.Value.NonNull == Int32 {
        call("CHR", codepoint)
    }
    /// `TO_ASCII`: removes accents. Only LATIN1, LATIN2, LATIN9 and WIN1250 databases.
    public static func toASCII<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("TO_ASCII", text) }
    /// `CASEFOLD`. PostgreSQL 18+, UTF8 databases.
    public static func caseFold<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("CASEFOLD", text) }
    /// `UNICODE_ASSIGNED`. PostgreSQL 18+, UTF8 databases.
    public static func isUnicodeAssigned<T: SQLArgument>(_ text: T) -> Expr<T.Value.AsBool> where T.Value.NonNull == String {
        call("UNICODE_ASSIGNED", text)
    }

    private static func call<Result>(_ name: String, _ arguments: any SQLArgument...) -> Expr<Result> {
        Expr(.function(name, arguments.map(\.sqlNode)))
    }
}

/// A required or nullable text value or expression, for variadic text functions like `SQL.concat`.
public protocol SQLTextArgument: SQLArgument {}
extension Column: SQLTextArgument where Value.NonNull == String {}
extension Expr: SQLTextArgument where Value: SQLType, Value.NonNull == String {}
extension AggregateExpr: SQLTextArgument where Value.NonNull == String {}

public struct RegexReplaceFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let caseInsensitive = RegexReplaceFlags(rawValue: 1 << 0)
    /// Replace every match instead of only the first.
    public static let global = RegexReplaceFlags(rawValue: 1 << 1)

    var sql: String { (contains(.global) ? "g" : "") + (contains(.caseInsensitive) ? "i" : "") }
}

public struct RegexSplitFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let caseInsensitive = RegexSplitFlags(rawValue: 1 << 0)
}

public enum NormalizationForm: String, Sendable {
    case nfc = "NFC", nfd = "NFD", nfkc = "NFKC", nfkd = "NFKD"
}

/// The result of `SQL.regexCaptures`: one entry per capture group (or the whole match without groups);
/// `nil` for a group that didn't participate.
public struct RegexCaptures: SQLValue, Hashable {
    public let groups: [String?]

    public init(_ groups: [String?]) { self.groups = groups }

    public static var sqlTypeName: String { "text[]" }
    public static var psqlType: PostgresDataType { .textArray }
    public static var psqlFormat: PostgresFormat { .binary }

    public func encode<JSONEncoder: PostgresJSONEncoder>(into buffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        buffer.writeInteger(Int32(1))  // dimensions
        buffer.writeInteger(Int32(groups.contains(nil) ? 1 : 0))
        buffer.writeInteger(PostgresDataType.text.rawValue)
        buffer.writeInteger(Int32(groups.count))
        buffer.writeInteger(Int32(1))  // lower bound
        for group in groups {
            guard let group else {
                buffer.writeInteger(Int32(-1))
                continue
            }
            buffer.writeInteger(Int32(group.utf8.count))
            buffer.writeString(group)
        }
    }

    // Binary array layout: dimensions, has-null flag, element OID, then per dimension (length, lower bound),
    // then per element a length (-1 for NULL) and its bytes.
    public init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        guard format == .binary, let dimensions = buffer.readInteger(as: Int32.self), buffer.readInteger(as: Int32.self) != nil,
            buffer.readInteger(as: UInt32.self) != nil
        else { throw PostgresDecodingError.Code.failure }
        guard dimensions > 0 else {
            self.init([])
            return
        }
        guard dimensions == 1, let count = buffer.readInteger(as: Int32.self), buffer.readInteger(as: Int32.self) != nil else {
            throw PostgresDecodingError.Code.failure
        }
        var groups: [String?] = []
        for _ in 0..<count {
            guard let length = buffer.readInteger(as: Int32.self) else { throw PostgresDecodingError.Code.failure }
            groups.append(length < 0 ? nil : buffer.readString(length: Int(length)))
        }
        self.init(groups)
    }
}
