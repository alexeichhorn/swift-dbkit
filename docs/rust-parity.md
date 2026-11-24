# Parity With rust-dbkit

swift-dbkit ports [rust-dbkit](https://github.com/alexeichhorn/rust-dbkit) and its tests. This page records where the two differ and why.

## Sources

| Source | Commit |
| --- | --- |
| rust-dbkit | `1b97d31` |
| The kit this repo is rebuilt from: `platform-swift/Kits/swift-dbkit` in the job-scraper repository | `0600cd20` |

## Ported Beyond The Kit

The kit lacked these rust-dbkit features. They are part of this port:

- `sparsevec` with the five distance functions
- `bit` with Hamming and Jaccard distance
- Arithmetic on mixed numeric types, following PostgreSQL's promotion: the wider integer, and `Double` for an integer with `Float` or `Double`
- Mixed integer widths in bitwise operators, producing the wider type
- `Int16` shift counts besides `Int32`
- Bitwise operators with one required and one nullable operand, a nullable shift count, and a value on the left
- A timestamp plus or minus a nullable interval, giving a nullable timestamp
- Comparisons on nullable columns typed as `Bool?`
- Parentheses around a comparison used inside another comparison
- `exists(subquery)` as a `Bool` expression
- Streaming of projections, grouping and aggregates
- Schema-qualified tables, as an optional `schema:` argument on `@Model`
- Property names starting with `__dbkit_` are reserved for generated code and rejected by `@Model`, so a property such as `_name` no longer clashes with the generated storage

## Left Out

| rust-dbkit feature | Why it is left out |
| --- | --- |
| Separate types for `timestamp`, `date` and `time` | Swift has no such types. `Date` maps to `timestamptz` and also reads `timestamp` and `date`. |
| Untyped JSON value and `json` columns | Any `Codable` type conforming to `DatabaseJSON` is stored as `jsonb`, including an untyped JSON value of your own. |
| Custom integer-backed types in bitwise expressions | Not needed so far. |
| `unwrap_or_default()` | `??` with an explicit fallback covers it. |
| `returning(columns)` | `returningAll()` covers it. |
| Converting a loaded row to a type with fewer loaded relations | A loaded row already passes as the plain model and as any `With…` type. |
| Enum label styles other than snake_case, and per-case renames | A hand-written `String`-backed enum takes any labels. |
| Transaction handles (`begin`, `commit`, `rollback`) | `db.transaction { }` commits and rolls back by itself. |

## Planned

| rust-dbkit feature | Issue |
| --- | --- |
| `FOR UPDATE` with `DISTINCT` or `GROUP BY` rejected at compile time | [#1](https://github.com/alexeichhorn/swift-dbkit/issues/1) |
| Order by a select alias | [#2](https://github.com/alexeichhorn/swift-dbkit/issues/2) |

## Different On Purpose

- **Counting a query with joins.** rust-dbkit counts the rows of the joined query, so a user with three joined todos counts three times. `count`, `exists` and `paginate` here count distinct rows of the query's own model.
- **Updating an active model with nothing assigned.** `update(on:)` sends no query and returns the row unchanged. rust-dbkit returns an error.
- **Changing a key column on an active model.** The update filters by the key the row was loaded with, so assigning a primary key column moves the row to the new key. rust-dbkit never writes key columns and filters by the assigned key, so it reports the row as not found.
- **Updating or deleting a new active model.** `update(on:)` and `delete(on:)` need a loaded row; calling them on `ActiveModel()` is a programmer error and traps. rust-dbkit returns an error when a key column is unset.
- **Arithmetic result types.** They follow PostgreSQL. Arithmetic on two `smallint`s stays `Int16`, where rust-dbkit types it `Int32`, and `+`, `-` and `*` accept mixed numeric types, which rust-dbkit accepts only in `/`.
- **Interval units.** `SQL.interval(days:|hours:|minutes:)` takes any numeric type, such as `SQL.interval(hours: 1.5)`, where rust-dbkit takes only 32-bit integers. rust-dbkit renders PostgreSQL's `MAKE_INTERVAL`, which takes integers for these units; this port renders `(x * INTERVAL '1 hour')`, which PostgreSQL defines for any number.
- **Migrations.** rust-dbkit delegates to sqlx and its `_sqlx_migrations` table. `db.migrate(_:)` reads `.sql` files at runtime and records them in `_dbkit_migrations`.

## API Changes From The Kit

Changes to the public API of the kit at `0600cd20`, for code that moves from the kit to this package.

| Change | Reason |
| --- | --- |
| Comparisons, `between`, `like`, `ilike`, `in`, `notIn`, `&&`, `\|\|` and `!` return `Expr<Bool?>` when an operand is nullable, instead of `Expr<Bool>`. A predicate stored as `Expr<Bool>`, such as `let isToday: Expr<Bool> = TodoModel.note == "today"`, is now declared `Expr<Bool?>`; `filter` takes both. | A comparison with NULL is NULL, as rust-dbkit types it. Nullable columns also gain ordered comparisons with an optional value and optional arguments to `between`, `like`, `ilike`, `in` and `notIn`. |
| `??` between two nullable expressions of the same type, such as `email ?? backupEmail`, renders `COALESCE`. | The kit's overloads lost to the standard library's `??`, which returned the left column and dropped the fallback. |
| `cast(to:)` accepts only the casts PostgreSQL has: between the numeric types, from `String` to `Bool`, `UUID`, `Date`, `Interval`, `String` and the numeric types and from each of these to `String`, between `Int32` and `Bool`, and from `Date` to `Date`. | The kit accepted any pair, such as `Date` to `Double`, which PostgreSQL rejects at run time. rust-dbkit accepts the same casts. |
| `+`, `-`, `*` and `/` accept operands of different numeric types and give PostgreSQL's result type, such as `Expr<Int64>` for `Int32` with `Int64`. | The kit required both operands to have the same type; see "Ported Beyond The Kit". |

## Rust Tests Without A Swift Counterpart

`scripts/check-rust-parity.py` reads this table. A row names one Rust test as `<file>::<function>`, or one fixture as `ui/<file>`.

| Rust test | Reason |
| --- | --- |
| `integration_postgres.rs::active_save_composite_changing_key_returns_not_found` | Changing a key column on an active model moves the row, see "Different On Purpose"; `activeSaveChangingACompositeKeyColumnMovesTheRow` covers it. |
| `integration_postgres.rs::active_insert_missing_required_field_errors` | `ActiveModel` inserts only through `save(on:)`, so this is `active_save_missing_required_fields_errors_on_insert`. |
| `ui/fail_appended_model_type.rs` | `@Model` adds members and extensions only, so it can't declare a type under another name, such as `UserModel` for `User`. |
| `ui/fail_derive_model_with_dbkit_field_attr.rs` | Swift has no derive macros; `@Model` is the only way to declare a model. |
| `ui/fail_model_suffix_double_model_type.rs` | `@Model` can't declare a type under another name, such as `UserModelModel` for `UserModel`. |
| `dbkit-core/type_support.rs::value_from_uuid` | A value becomes a bind when a query uses it; `selectBindsUUIDDatetimeDateTime` binds the same UUID. |
| `dbkit-core/type_support.rs::value_from_datetime_date_time` | A value becomes a bind when a query uses it; `selectBindsUUIDDatetimeDateTime` binds the same `Date`s. Swift has no time-of-day type. |
| `dbkit-core/type_support.rs::value_from_utc_datetime` | A value becomes a bind when a query uses it; `selectBindsUTCDatetime` binds the same `Date`. |
| `dbkit-core/type_support.rs::value_from_json` | A value becomes a bind when a query uses it; `selectBindsJSON` binds the same payload. |
| `dbkit-core/type_support.rs::value_from_string_array` | A value becomes a bind when a query uses it; `selectBindsStringArray` binds the same array. |
| `dbkit-core/type_support.rs::value_from_bytes` | A value becomes a bind when a query uses it; `selectBindsBytes` binds the same bytes. |
| `dbkit/type_support.rs::build_arguments_accepts_uuid_datetime_date_time` | PostgresNIO binds every `SQLValue`; `uuidDateTimeRoundtrip` sends the same UUID and dates to PostgreSQL. |
| `dbkit/type_support.rs::build_arguments_accepts_utc_datetime` | PostgresNIO binds every `SQLValue`; `timestamptzNullFilterAndActiveUpdateRoundtrip` sends the same `Date` to PostgreSQL. |
| `dbkit/type_support.rs::build_arguments_accepts_json` | PostgresNIO binds every `SQLValue`; `jsonColumnRoundtrip` sends a payload of the same shape to PostgreSQL. |
| `dbkit/type_support.rs::build_arguments_accepts_bytea` | PostgresNIO binds every `SQLValue`; `byteaRoundtripFilterAndActiveModelNulling` sends the same bytes to PostgreSQL. |
| `dbkit/type_support.rs::build_arguments_accepts_interval` | PostgresNIO binds every `SQLValue`; `intervalRoundtripsThroughInsertFilterAndUpdate` sends the same interval to PostgreSQL. |
| `ui/fail_nullable_model_field_type_alias.rs` | rust-dbkit's macro tells nullable fields by their syntax and rejects an alias of `Option`. Swift's type checker resolves `typealias OptionalText = String?`, so `@Model` accepts the alias as a nullable column. |
| `bitwise_sql.rs::compiles_custom_integer_backed_type_without_exposing_its_storage_type` | Custom integer-backed types in bitwise expressions are left out. |
| `bitwise_integration.rs::custom_integer_backed_type_filters_and_roundtrips` | Custom integer-backed types in bitwise expressions are left out. |
| `ui/pass_bitwise_custom_integer_types.rs` | Custom integer-backed types in bitwise expressions are left out. |
| `ui/fail_interval_float_hours.rs` | `SQL.interval(hours:)` takes fractions, see "Interval units" under "Different On Purpose". |
