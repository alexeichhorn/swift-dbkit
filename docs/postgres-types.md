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
| `Vector<N>`, `HalfVector<N>`, `SparseVector<N>` | pgvector `vector`, `halfvec`, `sparsevec` |
| `BitVector<N>` | `bit(n)` |
| enums conforming to `DatabaseEnum` | PostgreSQL enums |
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

## pgvector Embeddings

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

```swift
@Model(table: "embedding_rows")
class EmbeddingRowModel {
    @Key @AutoIncrement var id: Int64
    var label: String
    var embedding: Vector<3>
    var embeddingOptional: Vector<3>?
    var compact: HalfVector<3>?
    var keywords: SparseVector<30000>?
    var fingerprint: BitVector<64>?
}
```

```swift
let query = try Vector<3>([1, 0, 0])

// Index-friendly top-k retrieval:
let nearest = try await EmbeddingRowModel.query()
    .filter(EmbeddingRowModel.embeddingOptional != nil)
    .orderBy(EmbeddingRowModel.embeddingOptional.innerProductDistance(to: query).asc)
    .limit(5)
    .all(on: db)

// True inner product score (higher is better); may not use an ANN index:
let ranked = try await EmbeddingRowModel.query()
    .filter(EmbeddingRowModel.embeddingOptional != nil)
    .orderBy(EmbeddingRowModel.embeddingOptional.innerProduct(with: query).desc)
    .limit(5)
    .all(on: db)

let similar = try await EmbeddingRowModel.query()
    .filter(EmbeddingRowModel.embedding.cosineDistance(to: query) < 0.1)
    .orderBy(EmbeddingRowModel.embedding.cosineDistance(to: query).asc)
    .all(on: db)

let halfQuery = try HalfVector<3>([1, 0, 0])
let compactNearest = try await EmbeddingRowModel.query()
    .orderBy(EmbeddingRowModel.compact.l2Distance(to: halfQuery).asc)
    .limit(5)
    .all(on: db)

// Zero-based (index, value) pairs; zeros are dropped:
let keywordQuery = try SparseVector<30000>([(42, 0.8), (1337, 0.3)])
let keywordMatches = try await EmbeddingRowModel.query()
    .orderBy(EmbeddingRowModel.keywords.innerProductDistance(to: keywordQuery).asc)
    .limit(5)
    .all(on: db)

let fingerprint = try BitVector<64>(Array(repeating: false, count: 32) + Array(repeating: true, count: 32))
let nearDuplicates = try await EmbeddingRowModel.query()
    .filter(EmbeddingRowModel.fingerprint.hammingDistance(to: fingerprint) < 4)
    .all(on: db)
```

| DBKit | pgvector | Notes |
| --- | --- | --- |
| `l2Distance(to:)` | `<->` | Euclidean distance. |
| `innerProductDistance(to:)` | `<#>` | Negative inner product. |
| `cosineDistance(to:)` | `<=>` | Lower is more similar. |
| `l1Distance(to:)` | `<+>` | Taxicab distance. |
| `innerProduct(with:)` | `inner_product(a, b)` | Higher is more similar; not ANN-index friendly. |
| `hammingDistance(to:)` | `<~>` | Bit strings only: the number of differing bits. |
| `jaccardDistance(to:)` | `<%>` | Bit strings only. |

- The dimension is part of the type: comparing `Vector<1536>` with `Vector<3>` doesn't compile, and neither does a
  distance between two kinds of vector. The first five distances take `Vector`, `HalfVector` and `SparseVector`; the
  last two take `BitVector` only.
- The initializers throw `DBKitError.invalidVector` for a wrong count or a non-finite value. `HalfVector` also
  rejects values outside ±65504 and more than 16000 dimensions, and rounds its values to half precision, so they
  equal the row read back.
- `SparseVector` takes zero-based `(index, value)` pairs in any order and keeps the nonzero ones in `indices` and
  `values`. It throws for an index out of bounds or given twice, and for more than 16000 nonzero values. Its
  `description` is PostgreSQL's text format, which counts from 1: `{43:0.8,1338:0.3}/30000`.
- Distances are `Double`, and `Double?` when either side is nullable: a nullable column, or a nullable expression as
  the argument (`embedding.l2Distance(to: EmbeddingRowModel.embeddingOptional)`).
- The operator-based helpers can use pgvector ANN indexes for `ORDER BY … LIMIT`. `inner_product > 0.9` matches
  `innerProductDistance < -0.9`.
- Vectors bind in pgvector's binary format with a `::vector`, `::halfvec` or `::sparsevec` placeholder cast, since
  their OIDs differ per database, and bit strings with their length, `::bit(64)`. `halfvec` and `sparsevec` need
  pgvector 0.7+.

## Postgres Enums With DatabaseEnum

`@DatabaseEnum` conforms a plain enum to `DatabaseEnum`. Each label is the snake_case case name:

```swift
@DatabaseEnum("task_state")
enum TaskState { case pendingReview, inProgress, completed, failed }   // pending_review, in_progress, …

@Model(table: "tasks")
class TaskModel {
    @Key var id: Int64
    var title: String
    var state: TaskState
    var previousState: TaskState?
}
```

```swift
let open = try await TaskModel.query()
    .filter(TaskModel.state.in([.pendingReview, .inProgress]))
    .all(on: db)

let updated = try await TaskModel.update()
    .set(TaskModel.state, to: .completed)
    .set(TaskModel.previousState, to: .inProgress)
    .filter(TaskModel.id == 42)
    .returningAll()
    .first(on: db)

let upserted = try await TaskModel.insert(TaskModel.Insert(id: 42, title: "Ship enum support", state: .pendingReview))
    .onConflict(TaskModel.id, doUpdate: TaskModel.state, TaskModel.previousState)
    .returningAll()
    .first(on: db)
```

For other labels, write the conformance by hand as a `String`-backed enum whose raw values are the labels:

```swift
enum TaskState: String, DatabaseEnum {
    static let typeName = "task_state"
    case pendingReview = "pending-review"
    case inProgress = "in-progress"
}
```

Enum binds are typed placeholders (`$1::task_state`). Swift already rejects duplicate raw values; create the
PostgreSQL type (`CREATE TYPE task_state AS ENUM (…)`) in a migration. `typeName` may be schema-qualified.
