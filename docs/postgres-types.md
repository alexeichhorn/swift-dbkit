# Postgres Types

## Supported Types

Model properties, filter values, inserts and updates support:

| Swift | PostgreSQL |
| --- | --- |
| `Bool` | `boolean` |
| `Int16`, `Int32`, `Int64` (`Int` maps to `bigint`) | `smallint`, `integer`, `bigint` |
| `Float`, `Double` | `real`, `double precision` |
| `Decimal` | `numeric` |
| `String` | `text`, `varchar` |
| `UUID` | `uuid` |
| `Date` | `timestamptz`; also decodes `timestamp` and `date` |
| `Interval` | `interval` |
| `Data` | `bytea` |
| `[Element]` for `Bool`, integers, floats, `String`, `UUID`, `Date` | arrays such as `text[]`, `bigint[]` |
| `Codable` types conforming to `DatabaseJSON` | `jsonb` |
| `Optional` of any of the above | nullable columns |

A `Date` is written rounded to the nearest microsecond, PostgreSQL's precision, so a timestamp read from a row is
written back unchanged. `[Date]` arrays and dates interpolated into raw SQL go through PostgresNIO, which rounds down.

A model property of any other type doesn't compile. For other types, conform them to `SQLValue` (PostgresNIO
encoding plus a type name) or use raw SQL.

## NULL Handling With Optional

```swift
@Model(table: "nullable_rows")
class NullableRowModel {
    @Key @AutoIncrement var id: Int64
    var note: String?
}
```

```swift
let row = try await NullableRowModel.insert(NullableRowModel.Insert(note: nil)).returningAll().first(on: db)
let empty = try await NullableRowModel.query().filter(NullableRowModel.note == nil).all(on: db)

// Plain values work on nullable columns, and dynamic optionals compile to `= $1` or `IS NULL`:
let note: String? = "present"
let matching = try await NullableRowModel.query().filter(NullableRowModel.note == note).all(on: db)
try await NullableRowModel.update().set(NullableRowModel.note, to: "updated").execute(on: db)
```

`nil` and optional values are accepted only for optional properties, in filters, inserts, updates and active models.
A comparison on a nullable column is an `Expr<Bool?>`; see [Expressions](expressions.md#nullability).

## JSON And Arrays

```swift
struct Preferences: Codable, DatabaseJSON {
    var theme: String
}

@Model(table: "profiles")
class ProfileModel {
    @Key @AutoIncrement var id: Int64
    var preferences: Preferences
    var labels: [String]
}
```

```swift
let dark = try await ProfileModel.query().filter(ProfileModel.preferences == Preferences(theme: "dark")).all(on: db)
try await ProfileModel.update().set(ProfileModel.labels, to: ["a", "b"]).filter(ProfileModel.id == 1).execute(on: db)
```

`DatabaseJSON` values encode with PostgresNIO's JSON coder as `jsonb`.
