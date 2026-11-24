# PostgreSQL String Functions

`SQL` provides typed PostgreSQL string functions. A text argument accepts a column, an expression or a Swift string,
and a count, start, length or index accepts an `Int32` value or an `Int32` expression. Any argument may be nullable,
and a nullable argument makes the result nullable, except where "NULL Handling And Collation" says otherwise. String
expressions also have `.lowercased()`, `.uppercased()`, `.trimmed()` and `.hasPrefix(_:)`, equivalent to
`SQL.lower`, `SQL.upper`, `SQL.trim` and `SQL.startsWith` (`hasPrefix` treats `%` and `_` literally).

## Practical Queries

```swift
@Model(table: "articles")
class ArticleModel {
    @Key @AutoIncrement var id: Int64
    var title: String
    var subtitle: String?
    var body: String
    var delimiter: String
    var pattern: String
    var replacement: String
    var codepoint: Int32
}
```

```swift
let normalizedTitle = ArticleModel.title.trimmed().lowercased()
let matching = try await ArticleModel.query()
    .filter(normalizedTitle.hasPrefix("swift"))
    .orderBy(normalizedTitle.asc)
    .all(on: db)

let cleanedBody = SQL.regexReplace(ArticleModel.body, ArticleModel.pattern, ArticleModel.replacement, [.global, .caseInsensitive])
let rows = try await ArticleModel.query()
    .select(
        SQL.titleCase(ArticleModel.title),
        SQL.concatWithSeparator(" - ", ArticleModel.title, ArticleModel.subtitle),
        SQL.split(ArticleModel.body, ArticleModel.delimiter),
        SQL.splitPart(ArticleModel.body, ArticleModel.delimiter, -1),
        SQL.left(ArticleModel.subtitle, 20),
        SQL.regexCaptures(ArticleModel.body, ArticleModel.pattern),
        SQL.regexSplit(cleanedBody, #"\s+"#),
        SQL.normalize(ArticleModel.title, .nfc),
        SQL.fromCodepoint(ArticleModel.codepoint)
    )
    .filter(SQL.regexIsMatch(ArticleModel.body, ArticleModel.pattern))
    .all(on: db)
// rows: [(String, String, [String], String, String?, RegexCaptures?, [String], String, String)]
```

Swift values in these calls become bind parameters, including regex patterns, replacements, separators, delimiters
and counts. Function names are fixed, regex flags come from `RegexReplaceFlags` / `RegexSplitFlags`, and
normalization forms from `NormalizationForm`. PostgreSQL validates regex syntax when the query runs.

## 1. Case Conversion And Trimming

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.upper(text)` | `UPPER(text)` | Uppercases using the database locale. |
| `SQL.lower(text)` | `LOWER(text)` | Lowercases using the database locale. |
| `SQL.trim(text)` | `TRIM(text)` | Removes spaces from both ends. |
| `SQL.trimChars(text, chars)` | `TRIM(BOTH chars FROM text)` | Removes the longest span made from the `chars` set at both ends. |
| `SQL.trimStart(text)` | `TRIM(LEADING FROM text)` | Removes leading spaces. |
| `SQL.trimStartChars(text, chars)` | `TRIM(LEADING chars FROM text)` | Removes a leading span made from the `chars` set. |
| `SQL.trimEnd(text)` | `TRIM(TRAILING FROM text)` | Removes trailing spaces. |
| `SQL.trimEndChars(text, chars)` | `TRIM(TRAILING chars FROM text)` | Removes a trailing span made from the `chars` set. |

`chars` is a set of characters, not a literal prefix or suffix.

## 2. Length And Search

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.charLength(text)` | `CHAR_LENGTH(text)` | Counts characters. |
| `SQL.byteLength(text)` | `OCTET_LENGTH(text)` | Counts encoded bytes. |
| `SQL.bitLength(text)` | `BIT_LENGTH(text)` | Eight times the byte length. |
| `SQL.position(text, substring)` | `STRPOS(text, substring)` | The first 1-based position, or 0. |
| `SQL.startsWith(text, prefix)` | `STARTS_WITH(text, prefix)` | Exact, case-sensitive prefix test. PostgreSQL 11+. |

## 3. Extraction And Sizing

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.left(text, count)` | `LEFT(text, count)` | The first `count` characters; a negative count omits from the end. |
| `SQL.right(text, count)` | `RIGHT(text, count)` | The last `count` characters; a negative count omits from the start. |
| `SQL.substring(text, start, count)` | `SUBSTRING(text, start, count)` | Up to `count` characters from the 1-based start. |
| `SQL.repeat(text, count)` | `REPEAT(text, count)` | Repeats text; a non-positive count returns `''`. |
| `SQL.padStart(text, length, fill)` | `LPAD(text, length, fill)` | Pads on the left by cycling `fill`, or truncates. |
| `SQL.padEnd(text, length, fill)` | `RPAD(text, length, fill)` | Pads on the right by cycling `fill`, or truncates. |

Counts are `Int32` values or `Int32` expressions, mixed in one call as needed: `SQL.substring(text, 2, lengthColumn)`.
PostgreSQL rejects a negative `substring` count when the query runs.

## 4. Text Transformation

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.titleCase(text)` | `INITCAP(text)` | Uppercases the first letter of each word, lowercases the rest. |
| `SQL.replace(text, from, to)` | `REPLACE(text, from, to)` | Replaces every exact occurrence of `from`. |
| `SQL.replaceRange(text, replacement, start, count)` | `OVERLAY(text, replacement, start, count)` | Replaces `count` characters from the 1-based start. |
| `SQL.translateChars(text, from, to)` | `TRANSLATE(text, from, to)` | Maps characters by position; extra `from` characters are deleted. |
| `SQL.reverse(text)` | `REVERSE(text)` | Reverses characters. |

PostgreSQL rejects a `replaceRange` start below 1 when the query runs.

## 5. Composition And Splitting

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.concat(values...)` | `CONCAT(values...)` | Concatenates and ignores NULL items; never NULL. |
| `SQL.concatWithSeparator(separator, values...)` | `CONCAT_WS(separator, values...)` | Ignores NULL items; NULL only for a NULL separator. |
| `SQL.split(text, delimiter)` | `STRING_TO_ARRAY(text, delimiter)` | Returns `[String]`; a NULL delimiter splits into characters. |
| `SQL.splitPart(text, delimiter, index)` | `SPLIT_PART(text, delimiter, index)` | The 1-based field; `''` when out of range, negative indexes count from the end (PostgreSQL 14+). |

`concat` and `concatWithSeparator` accept any mix of required and nullable text columns, expressions and strings, and
no values at all, which gives `''`. PostgreSQL rejects a `splitPart` index of 0 when the query runs.

## 6. Regex Inspection

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.regexIsMatch(text, pattern)` | `REGEXP_LIKE(text, pattern)` | Whether a POSIX regex matches. PostgreSQL 15+. |
| `SQL.regexCount(text, pattern)` | `REGEXP_COUNT(text, pattern)` | Non-overlapping match count. PostgreSQL 15+. |
| `SQL.regexPosition(text, pattern)` | `REGEXP_INSTR(text, pattern)` | The first 1-based match position, or 0. PostgreSQL 15+. |
| `SQL.regexCaptures(text, pattern)` | `REGEXP_MATCH(text, pattern)` | Captures of the first match as `RegexCaptures?`. |
| `SQL.regexExtract(text, pattern)` | `REGEXP_SUBSTR(text, pattern)` | The first whole match as `String?`. PostgreSQL 15+. |

`regexCaptures` is `nil` when nothing matches or the input is NULL. Without capture groups, `groups` holds the whole
match; with groups, one entry per group, `nil` for a group that didn't participate. An empty match gives `[""]`. Use
an inline ARE option like `(?i)` for case-insensitive inspection.

## 7. Regex Transformation

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.regexReplace(text, pattern, replacement, flags)` | `REGEXP_REPLACE(text, pattern, replacement, flags)` | Replaces the first match, or every match with `.global`. |
| `SQL.regexSplit(text, pattern, flags)` | `REGEXP_SPLIT_TO_ARRAY(text, pattern, flags)` | Splits around matches into `[String]`. |

Flags: `.caseInsensitive` (`i`) for both, `.global` (`g`) for `regexReplace`. They default to none, so
`SQL.regexReplace(text, "a", "x")` replaces the first match and `SQL.regexSplit(text, #"\s+"#)` splits
case-sensitively. Replacements support `\1`–`\9`, `\&` and `\\`.

## 8. Unicode And Code Points

| DBKit | PostgreSQL | Behavior |
| --- | --- | --- |
| `SQL.normalize(text, form)` | `NORMALIZE(text, NFC)` | Unicode normalization (`.nfc`, `.nfd`, `.nfkc`, `.nfkd`). PostgreSQL 13+, UTF8. |
| `SQL.firstCodepoint(text)` | `ASCII(text)` | The first character's code point, or 0 for `''`. |
| `SQL.fromCodepoint(value)` | `CHR(value)` | The character for an `Int32` code point. |
| `SQL.toASCII(text)` | `TO_ASCII(text)` | Removes accents; LATIN1, LATIN2, LATIN9 and WIN1250 databases only. |
| `SQL.caseFold(text)` | `CASEFOLD(text)` | Unicode case folding. PostgreSQL 18+, UTF8. |
| `SQL.isUnicodeAssigned(text)` | `UNICODE_ASSIGNED(text)` | Whether every character is assigned. PostgreSQL 18+, UTF8. |

The normalization form renders as a keyword, not a bind parameter. PostgreSQL rejects a code point of 0, a negative
one, a surrogate or one beyond U+10FFFF when the query runs.

## NULL Handling And Collation

PostgreSQL returns NULL when any argument is NULL, so a function's Swift result is optional when any argument is
nullable: `SQL.left(title, optionalCount)` is `Expr<String?>` even for a required `title`. The exceptions are `concat`
(never NULL), `concatWithSeparator` (NULL only for a NULL separator), `split` (NULL only for a NULL text, since a
NULL delimiter splits into characters) and `regexCaptures` / `regexExtract` (always optional, since no match is
NULL). A nullable pattern or replacement makes a regex result nullable too: `SQL.regexReplace(title, optionalPattern,
"x")` is `Expr<String?>`.

`upper`, `lower`, `titleCase` and `caseFold` depend on the locale or collation. POSIX regex classes and
case-insensitive matching can vary with collation, and regex functions don't support nondeterministic collations.
See PostgreSQL's [string functions](https://www.postgresql.org/docs/18/functions-string.html) and
[POSIX regular expressions](https://www.postgresql.org/docs/18/functions-matching.html#FUNCTIONS-POSIX-REGEXP).
