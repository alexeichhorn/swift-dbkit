# Expressions And Aggregation

## Nullability

Expressions follow the nullability of the columns they use:

```swift
@Model(table: "articles")
class ArticleModel {
    @Key @AutoIncrement var id: Int64
    var title: String
    var subtitle: String?
}
```

```swift
let titled = ArticleModel.title == "Swift"  // Expr<Bool>
let subtitled = ArticleModel.subtitle == "Swift"  // Expr<Bool?>, NULL where the subtitle is NULL
let subtitleWithFallback = ArticleModel.subtitle ?? "No subtitle"  // Expr<String>, COALESCE

let articles = try await ArticleModel.query()
    .filter(titled || subtitled)  // Expr<Bool?>
    .filter(ArticleModel.subtitle != nil)
    .orderBy(subtitleWithFallback.asc)
    .all(on: db)
```

A comparison is nullable when an operand is, as in PostgreSQL, where comparing with NULL gives NULL. On a nullable
column, `==`, `!=`, `<`, `<=`, `>`, `>=`, `between`, `like`, `ilike`, `in` and `notIn` are `Expr<Bool?>`; on a
required column they are `Expr<Bool>`. Between two expressions, a comparison is `Expr<Bool?>` when either one is
nullable. `&&` and `||` are `Expr<Bool?>` when either operand is, and `!` keeps its operand's type. Only `isNull`,
`isNotNull`, `isDistinct(from:)` and `isNotDistinct(from:)` are never NULL, so they stay `Expr<Bool>`. `filter`
takes both kinds and keeps the rows where the predicate is true, so a NULL drops the row:
`!(ArticleModel.subtitle == "Swift")` skips articles without a subtitle.

A nullable column takes its optional type wherever it takes a value: plain values, optionals and `nil`. `== nil` and
`!= nil` compile to `IS NULL` / `IS NOT NULL`, and so does `==` / `!=` with an optional that is `nil` at run time. The
other predicates bind `nil` as NULL, so `ArticleModel.subtitle < nil` matches no row. Required columns reject `nil`
and optionals at compile time.

`??` replaces only NULL, so empty strings and zeroes are kept. With a value or a required expression as fallback the
result is required; with a nullable fallback it stays nullable.

## Arithmetic Expressions

```swift
@Model(table: "records")
class RecordModel {
    @Key @AutoIncrement var id: Int64
    var leftValue: Int64
    var rightValue: Int64
    var baselineValue: Int64
    var bookmarkCount: Int64
    var playCount: Int32
}
```

```swift
let rows = try await RecordModel.query()
    .filter(RecordModel.leftValue + 1 < RecordModel.baselineValue)
    .filter(RecordModel.rightValue - RecordModel.leftValue > 0)
    .orderBy((RecordModel.baselineValue + RecordModel.leftValue).desc)
    .all(on: db)

// Integer division keeps PostgreSQL's integer semantics; cast for fractions:
let rate = RecordModel.bookmarkCount.cast(to: Double.self) / RecordModel.playCount  // Expr<Double>
```

`+`, `-`, `*` and `/` work on integers, floats and `Decimal`. A nullable operand makes the result nullable. Operands
of different numeric types give PostgreSQL's result type, the same for all four operators:

| Operands | Result |
| --- | --- |
| `Int16` and `Int16` | `Int16` |
| `Int16` and `Int32` | `Int32` |
| `Int16` or `Int32` and `Int64` | `Int64` |
| an integer and `Float` or `Double` | `Double` |
| `Float` and `Float` | `Float` |
| `Float` and `Double` | `Double` |
| `Decimal` and `Decimal` | `Decimal` |

`Decimal` combines with `Decimal` only; cast the other operand. Swift's `Int` is `bigint`: `Int` with `Int` stays
`Int`, and with another integer type the result is `Int64`. A literal takes the other operand's type, so
`smallintColumn + 1` is `Expr<Int16>`, while a typed value follows the table: `int32Column + Int64(1)` is
`Expr<Int64>`.

`cast(to:)` compiles to `CAST(… AS …)` and keeps nullability: `Expr<T>` from a required expression, `Expr<T?>` from a
nullable one. It accepts the casts PostgreSQL has:

- between `Int16`, `Int32`, `Int64`, `Int`, `Float`, `Double` and `Decimal`
- from `String` to `Bool`, `UUID`, `Date`, `String` and the numeric types, and from each of these to `String`
- between `Int32` and `Bool`
- from `Date` to `Date`

Any other cast, such as `Date` to `Double`, doesn't compile.

## Bitwise Expressions

| Swift | PostgreSQL |
| --- | --- |
| `left & right` | `left & right` |
| `left \| right` | `left \| right` |
| `left ^ right` | `left # right` |
| `~value` | `~value` |
| `value << count` | `value << count` |
| `value >> count` | `value >> count` |

```swift
@Model(table: "accounts")
class AccountModel {
    @Key @AutoIncrement var id: Int64
    var accessMask: Int64
    var roleBits: Int16
}
```

```swift
let editors = try await AccountModel.query()
    .filter((AccountModel.accessMask & 0b0010) != 0)
    .orderBy((AccountModel.accessMask >> 1).desc)
    .all(on: db)

let combined = AccountModel.accessMask | AccountModel.roleBits  // Expr<Int64>
```

Bitwise operators work on `Int16`, `Int32`, `Int64` and `Int`. A nullable operand makes the result nullable.

`&`, `|` and `^` give PostgreSQL's result type, as arithmetic does:

| Operands | Result |
| --- | --- |
| the same type | that type |
| `Int16` and `Int32` | `Int32` |
| `Int16` or `Int32` and `Int64` | `Int64` |
| `Int` and another integer type | `Int64` |

An untyped literal takes the other operand's type on either side, so `AccountModel.roleBits & 1` is `Expr<Int16>`.
A typed value next to an expression of another integer type must be `Int16`, `Int32` or `Int64`; an `Int` value
combines only with an `Int` expression.

`~` keeps its operand's type. `<<` and `>>` keep the left operand's type, which may also be a value:
`Int64(1) << count`. The count is `Int32` or `Int16`, required or nullable, and a literal count is `Int32`.
PostgreSQL doesn't narrow a `bigint` count, so an `Int64` or `Int` count doesn't compile; `cast(to: Int32.self)` it.
