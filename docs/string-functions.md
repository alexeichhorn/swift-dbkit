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
}
```

```swift
let normalizedTitle = ArticleModel.title.trimmed().lowercased()
let matching = try await ArticleModel.query()
    .filter(normalizedTitle.hasPrefix("swift"))
    .orderBy(normalizedTitle.asc)
    .all(on: db)

let rows = try await ArticleModel.query()
    .select(
        SQL.titleCase(ArticleModel.title),
        SQL.concatWithSeparator(" - ", ArticleModel.title, ArticleModel.subtitle),
        SQL.split(ArticleModel.body, ArticleModel.delimiter),
        SQL.splitPart(ArticleModel.body, ArticleModel.delimiter, -1),
        SQL.left(ArticleModel.subtitle, 20)
    )
    .filter(SQL.position(ArticleModel.body, ArticleModel.delimiter) > 0)
    .all(on: db)
// rows: [(String, String, [String], String, String?)]
```

Swift values in these calls become bind parameters, including separators, delimiters and counts. Function names are
fixed.

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

## NULL Handling And Collation

PostgreSQL returns NULL when any argument is NULL, so a function's Swift result is optional when any argument is
nullable: `SQL.left(title, optionalCount)` is `Expr<String?>` even for a required `title`. The exceptions are `concat`
(never NULL), `concatWithSeparator` (NULL only for a NULL separator) and `split` (NULL only for a NULL text, since a
NULL delimiter splits into characters).

`upper`, `lower` and `titleCase` depend on the locale or collation. See PostgreSQL's
[string functions](https://www.postgresql.org/docs/18/functions-string.html).
