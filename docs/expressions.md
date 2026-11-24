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
