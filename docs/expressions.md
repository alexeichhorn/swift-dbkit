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
let normalizedTitle = ArticleModel.title.lowercased()  // Expr<String>
let normalizedSubtitle = ArticleModel.subtitle.lowercased()  // Expr<String?>
let titled = normalizedTitle == "swift"  // Expr<Bool>
let subtitled = normalizedSubtitle == "swift"  // Expr<Bool?>, NULL where the subtitle is NULL
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
`!(ArticleModel.subtitle == "Swift")` skips articles without a subtitle. Functions keep their input's nullability
too, so `lowercased()` of a nullable column is `Expr<String?>`.

A nullable column takes its optional type wherever it takes a value: plain values, optionals and `nil`. `== nil` and
`!= nil` compile to `IS NULL` / `IS NOT NULL`, and so does `==` / `!=` with an optional that is `nil` at run time. The
other predicates bind `nil` as NULL, so `ArticleModel.subtitle < nil` matches no row. Required columns reject `nil`
and optionals at compile time.

`??` replaces only NULL, so empty strings and zeroes are kept. With a value or a required expression as fallback the
result is required; with a nullable fallback it stays nullable. `SQL.coalesce(value, fallback)` is the same and also
takes a required first argument: both arguments have one type, and the result is nullable only when both are.

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

`+`, `-`, `*` and `/` work on integers, floats and `Decimal` (`+`/`-` also on `Interval`). A nullable operand makes
the result nullable. Operands of different numeric types give PostgreSQL's result type, the same for all four
operators:

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
- from `String` to `Bool`, `UUID`, `Date`, `Interval`, `String` and the numeric types, and from each of these to
  `String`
- between `Int32` and `Bool`
- from `Date` to `Date`

Any other cast, such as `Date` to `Double`, doesn't compile.

`SQL.least` and `SQL.greatest` take two arguments of one type, and a literal takes the other argument's type.
PostgreSQL skips NULL arguments, so the result is nullable only when both arguments are:
`SQL.greatest(nullableColumn, 0)` is required. Numeric types don't mix here; cast one argument.

`SQL.power(base, exponent)` is `Double` for any mix of `Int16`, `Int32`, `Int64`, `Int`, `Float` and `Double`, and
`Decimal` for two `Decimal`s; `Decimal` takes no other type. A nullable argument makes the result nullable.

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

## Interval Expressions

```swift
@Model(table: "schedules")
class ScheduleModel {
    @Key @AutoIncrement var id: Int64
    var baseIntervalHours: Int32
    var leaseWindow: Interval
    var backoffMinutes: Int32?
    var attempts: Int32
    var updatedAt: Date
}
```

```swift
let rows = try await ScheduleModel.query()
    .filter(SQL.interval(hours: ScheduleModel.baseIntervalHours) == ScheduleModel.leaseWindow)
    .orderBy(SQL.interval(minutes: ScheduleModel.backoffMinutes ?? 15).asc)
    .all(on: db)

let expired = try await ScheduleModel.query()
    .filter(ScheduleModel.updatedAt + ScheduleModel.leaseWindow <= Date())
    .all(on: db)

// Exponential backoff, capped at an hour:
let retrySeconds = SQL.least(3600.0, SQL.power(2.0, ScheduleModel.attempts - 1) * 60.0)
let due = try await ScheduleModel.query()
    .filter(ScheduleModel.updatedAt <= Date() - SQL.interval(seconds: retrySeconds))
    .all(on: db)
```

`SQL.interval(days:|hours:|minutes:|seconds:)` scales a numeric value or expression, fractions included:
`SQL.interval(hours: 1.5)` is an hour and a half. Timestamps support `± Interval` values and interval expressions,
and intervals add to and subtract from each other. A nullable operand makes the result nullable. `SQL.now()` is the
transaction's start time, an `Expr<Date>`.

An `Interval` value keeps PostgreSQL's months, days and microseconds; `.days(_:)`, `.hours(_:)`, `.minutes(_:)` and
`.seconds(_:)` build one.

## Aggregation And Projections

`select(…)` switches from models to expressions. Results decode as a typed tuple whose element types follow the
expressions, or into a `Decodable` type matched by alias (exact name or snake_case):

```swift
@Model(table: "sales")
class SaleModel {
    @Key @AutoIncrement var id: Int64
    var region: String
    var amount: Int64
    var discount: Int64?
    var createdAt: Date
}

struct SaleSummary: Decodable {
    let region: String
    let netAmount: Int64?
    let isDiscounted: Bool?
}

struct RegionTotal: Decodable {
    let region: String
    let total: Decimal?
}
```

```swift
let rows: [(String, Int64?)] = try await SaleModel.query()
    .select(SaleModel.region, SaleModel.amount - SaleModel.discount)
    .filter(SaleModel.amount > 0)
    .all(on: db)

let summaries = try await SaleModel.query()
    .select(
        SaleModel.region.as("region"),
        (SaleModel.amount - SaleModel.discount).as("net_amount"),
        (SaleModel.discount > 0).as("isDiscounted")
    )
    .all(as: SaleSummary.self, on: db)

let regionTotals: [(String, Decimal?)] = try await SaleModel.query()
    .select(SaleModel.region, SQL.sum(SaleModel.amount))
    .groupBy(SaleModel.region)
    .having(SQL.sum(SaleModel.amount) > 0)
    .all(on: db)

let totals = try await SaleModel.query()
    .select(SaleModel.region.as("region"), SQL.sum(SaleModel.amount).as("total"))
    .groupBy(SaleModel.region)
    .all(as: RegionTotal.self, on: db)
```

A selected expression keeps its nullability. A comparison on a nullable operand is `Bool?` and decodes NULL as
`nil`, so `SaleModel.discount > 0` is `nil` for a sale without a discount. A `Decodable` type isn't checked against
the select list: give such a property an optional type, and a property without a matching alias fails with
`DBKitError.missingColumn`.

Aggregates: `SQL.count`, `SQL.countAll`, `SQL.sum`, `SQL.min`, `SQL.max`. Their result types follow PostgreSQL:

| Aggregate | Result |
| --- | --- |
| `SQL.count(x)`, `SQL.countAll()` | `Int64` |
| `SQL.sum` of `Int16` or `Int32` | `Int64?` |
| `SQL.sum` of `Int64`, `Int` or `Decimal` | `Decimal?` |
| `SQL.sum` of `Float`, `Double` or `Interval` | the input's type, optional |
| `SQL.min`, `SQL.max` | the input's type, optional |

`SUM`, `MIN` and `MAX` return NULL without input rows, so they are optional even over a required column; a nullable
input doesn't nest the optional. A sum over an expression follows the expression's type, so
`SQL.sum(int32Column * 2)` is `Int64?`. `SUM` of text, timestamps or booleans doesn't compile. `COUNT` is never NULL.

Comparing an aggregate follows the nullability rules: `SQL.count(SaleModel.id) > 1` is `Expr<Bool>`, and
`SQL.sum(SaleModel.amount) > 100` is `Expr<Bool?>`. `having` filters groups after aggregation and takes both; several
`having` predicates combine with `AND`. `groupBy` takes one or more expressions.

Use either all aliased or all unaliased expressions in one `select`. A projection takes `filter`, `distinct`,
`groupBy`, `having`, `orderBy`, `limit` and `offset` like a model query, and keeps what was built before `select`.
`first(on:)` and `first(as:on:)` fetch one row.

## Typed Projections

`@Projection` names the result columns in code, with no aliases. It generates `columns(…)` on the struct, with one
labelled parameter per stored property:

```swift
@Projection
struct SaleLine {
    let region: String
    let netAmount: Int64
    let isDiscounted: Bool?
}

let lines = try await SaleModel.query()
    .select(
        SaleLine.columns(
            region: SaleModel.region,
            netAmount: SaleModel.amount - (SaleModel.discount ?? 0),
            isDiscounted: SaleModel.discount > 0
        )
    )
    .orderBy(SaleModel.region.asc)
    .all(on: db)  // [SaleLine]
```

A missing property, a misspelled label and an expression of another type are compile errors. The types must match
exactly, so a nullable expression, such as `SQL.max` or a comparison on a nullable column, needs an Optional property
or `??`. The
struct can be declared inside the function that runs the query. It needs its memberwise initializer and must be
`Sendable`, which a public struct has to declare itself.

## Filtered Aggregates

```swift
struct SalesOverview: Decodable {
    let saleCount: Int64
    let usSaleCount: Int64
    let firstUSSaleAt: Date?
}
```

```swift
let usSale = SaleModel.region == "us"
let overview = try await SaleModel.query()
    .select(
        SQL.count(SaleModel.id).as("sale_count"),
        SQL.count(SaleModel.id).filter(usSale).as("us_sale_count"),
        SQL.min(SaleModel.createdAt).filter(usSale).as("first_us_sale_at")
    )
    .filter(SaleModel.amount > 0)
    .first(as: SalesOverview.self, on: db)
```

A query filter limits every aggregate's input; an aggregate's `.filter(…)` limits only that aggregate
(`FILTER (WHERE …)`) and keeps its type. It takes a `Bool` or `Bool?` predicate. PostgreSQL takes one filter, right
after the aggregate call, so only the aggregates have `.filter`, and it returns a plain `Expr` without one. Filter once,
before wrapping: `SQL.sum(SaleModel.amount).filter(usSale) ?? 0` or
`SQL.sum(SaleModel.amount).filter(usSale).cast(to: Double.self)`. Aggregates without `GROUP BY` return one row.

## SQL Functions And Expression-Based Grouping

```swift
let buckets: [(Date, Decimal?)] = try await SaleModel.query()
    .select(SQL.dateTrunc(.day, SaleModel.createdAt), SQL.sum(SaleModel.amount))
    .groupBy(SQL.dateTrunc(.day, SaleModel.createdAt))
    .orderBy(SQL.dateTrunc(.day, SaleModel.createdAt).asc)
    .all(on: db)

let amountBuckets: [(Int64, Int64)] = try await SaleModel.query()
    .select(SaleModel.amount / 100, SQL.countAll())
    .groupBy(SaleModel.amount / 100)
    .orderBy(SQL.countAll().desc)
    .all(on: db)
```

`SQL.dateTrunc(unit, timestamp)` takes a `Date` and keeps its nullability. The `DateTruncUnit` renders as a literal,
`DATE_TRUNC('day', …)`, so the same expression in `select` and `groupBy` matches. PostgreSQL truncates a
`timestamptz` in the session's time zone.

`groupBy` takes any expression, and `orderBy` takes any expression, including aggregates. Aggregates take computed
values too: `SQL.max(SaleModel.discount ?? 0)`.
