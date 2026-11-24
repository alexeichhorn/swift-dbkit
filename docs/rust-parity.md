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
- Mixed integer widths in arithmetic and bitwise operators, producing the wider type
- `Int16` shift counts besides `Int32`
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
- **Migrations.** rust-dbkit delegates to sqlx and its `_sqlx_migrations` table. `db.migrate(_:)` reads `.sql` files at runtime and records them in `_dbkit_migrations`.

## API Changes From The Kit

Changes to the public API of the kit at `0600cd20`, for code that moves from the kit to this package.

| Change | Reason |
| --- | --- |

## Rust Tests Without A Swift Counterpart

`scripts/check-rust-parity.py` reads this table. A row names one Rust test as `<file>::<function>`, or one fixture as `ui/<file>`.

| Rust test | Reason |
| --- | --- |
| `ui/fail_appended_model_type.rs` | `@Model` adds members and extensions only, so it can't declare a type under another name, such as `UserModel` for `User`. |
| `ui/fail_derive_model_with_dbkit_field_attr.rs` | Swift has no derive macros; `@Model` is the only way to declare a model. |
| `ui/fail_model_suffix_double_model_type.rs` | `@Model` can't declare a type under another name, such as `UserModelModel` for `UserModel`. |
| `ui/fail_nullable_model_field_type_alias.rs` | rust-dbkit's macro tells nullable fields by their syntax and rejects an alias of `Option`. Swift's type checker resolves `typealias OptionalText = String?`, so `@Model` accepts the alias as a nullable column. |
