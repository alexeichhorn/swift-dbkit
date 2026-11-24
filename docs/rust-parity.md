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
- `SQL.sum` of intervals
- Comparisons on nullable columns typed as `Bool?`
- Row-value tuples take each column's own type, so integer literals, optional values and `nil` for nullable columns, and `SQL.row(…).in(…)` is `Bool?` when a column is nullable
- Parentheses around a comparison used inside another comparison
- `exists(subquery)` as a `Bool` expression
- Table aliases, `Model.as(_:)`, so a subquery on the outer query's own table correlates with the outer row
- Streaming of projections, grouping and aggregates
- Schema-qualified tables, as an optional `schema:` argument on `@Model`
- Property names starting with `__dbkit_` are reserved for generated code and rejected by `@Model`, so a property such as `_name` no longer clashes with the generated storage
- `SQL.power` with any numeric type on either side, required or nullable; two `Decimal`s give `Decimal`
- `hasPrefix` and `SQL.startsWith` with a nullable prefix, giving `Bool?`
- `SQL.coalesce` with a required first argument
- `SQL.least` and `SQL.greatest` with one required and one nullable expression, giving a required result
- Text functions take nullable arguments in every position (patterns, fills, character sets, replacements, delimiters, counts), and the result is nullable when any argument is
- Counts, starts, lengths and indexes of text functions take any `Int32` expression, not only a literal, and values and expressions mix
- `SQL.split` with a nullable delimiter, which splits into characters and stays non-null
- `SQL.concat()` and `SQL.concatWithSeparator(separator)` without values render valid SQL
- A relation path inside a subquery joins under its own alias when an enclosing query already uses the table's name, so it no longer hides the outer row it is compared with
- A column of a model that an enclosing query reaches through a relation join binds to the nearest such join, as rust-dbkit resolves it
- A join added by a relation path is placed before a custom `join(_:on:)` whose condition refers to it
- Vector distances take a nullable vector on either side, giving a nullable distance
- `HalfVector` rounds its values to half precision when it is created, so a value equals the row read back, and rejects dimensions outside 1 to 16000
- The text decoders of the vector types reject input without its brackets

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

- **Regex flags.** `SQL.regexReplace` and `SQL.regexSplit` default their flags to none, so a call without flags replaces the first match and splits case-sensitively. rust-dbkit requires the flags argument.
- **Lock scope with joins.** A lock on a query with any join is scoped to the query's own table (`FOR UPDATE OF "users"`), so joined rows stay unlocked. rust-dbkit scopes the lock only when the query has a left join; with inner joins it locks the joined rows too.
- **Page numbers.** `paginate(page:perPage:on:)` traps for page 0 or `perPage` 0, which are programmer errors. rust-dbkit treats 0 as 1.
- **Counting a query with joins.** rust-dbkit counts the rows of the joined query, so a user with three joined todos counts three times. `count`, `exists` and `paginate` here count distinct rows of the query's own model.
- **Updating an active model with nothing assigned.** `update(on:)` sends no query and returns the row unchanged. rust-dbkit returns an error.
- **Changing a key column on an active model.** The update filters by the key the row was loaded with, so assigning a primary key column moves the row to the new key. rust-dbkit never writes key columns and filters by the assigned key, so it reports the row as not found.
- **Updating or deleting a new active model.** `update(on:)` and `delete(on:)` need a loaded row; calling them on `ActiveModel()` is a programmer error and traps. rust-dbkit returns an error when a key column is unset.
- **Arithmetic result types.** They follow PostgreSQL. Arithmetic on two `smallint`s stays `Int16`, where rust-dbkit types it `Int32`, and `+`, `-` and `*` accept mixed numeric types, which rust-dbkit accepts only in `/`.
- **`SUM` result types.** They follow PostgreSQL: a sum of `Int16` or `Int32` is `Int64?`, and of `Int64` is `Decimal?`, since PostgreSQL sums `bigint` as `numeric`. rust-dbkit types a sum as its input type, though its integration tests decode `bigint` sums as `BigDecimal`.
- **Interval units.** `SQL.interval(days:|hours:|minutes:)` takes any numeric type, such as `SQL.interval(hours: 1.5)`, where rust-dbkit takes only 32-bit integers. rust-dbkit renders PostgreSQL's `MAKE_INTERVAL`, which takes integers for these units; this port renders `(x * INTERVAL '1 hour')`, which PostgreSQL defines for any number.
- **A condition's predicate.** `Condition.all` and `.any` take `Bool` and `Bool?` predicates, and `predicate` is always `Expr<Bool?>`. rust-dbkit keeps it `bool` until a nullable predicate is added, but Swift can't change a variable's type when `add(_:)` mutates it.
- **Repeated values.** Every occurrence of a value gets its own bind. rust-dbkit binds an identical value once and repeats its placeholder.
- **Migrations.** rust-dbkit delegates to sqlx and its `_sqlx_migrations` table. `db.migrate(_:)` reads `.sql` files at runtime and records them in `_dbkit_migrations`.

## API Changes From The Kit

Changes to the public API of the kit at `0600cd20`, for code that moves from the kit to this package.

| Change | Reason |
| --- | --- |
| Comparisons, `between`, `like`, `ilike`, `in`, `notIn`, `&&`, `\|\|` and `!` return `Expr<Bool?>` when an operand is nullable, instead of `Expr<Bool>`. A predicate stored as `Expr<Bool>`, such as `let isToday: Expr<Bool> = TodoModel.note == "today"`, is now declared `Expr<Bool?>`; `filter` takes both. | A comparison with NULL is NULL, as rust-dbkit types it. Nullable columns also gain ordered comparisons with an optional value and optional arguments to `between`, `like`, `ilike`, `in` and `notIn`. |
| `??` between two nullable expressions of the same type, such as `email ?? backupEmail`, renders `COALESCE`. | The kit's overloads lost to the standard library's `??`, which returned the left column and dropped the fallback. |
| `cast(to:)` accepts only the casts PostgreSQL has: between the numeric types, from `String` to `Bool`, `UUID`, `Date`, `Interval`, `String` and the numeric types and from each of these to `String`, between `Int32` and `Bool`, and from `Date` to `Date`. | The kit accepted any pair, such as `Date` to `Double`, which PostgreSQL rejects at run time. rust-dbkit accepts the same casts. |
| `+`, `-`, `*` and `/` accept operands of different numeric types and give PostgreSQL's result type, such as `Expr<Int64>` for `Int32` with `Int64`. | The kit required both operands to have the same type; see "Ported Beyond The Kit". |
| `Condition.predicate` is `Expr<Bool?>?` instead of `Expr<Bool>?`. Code that stored it as `Expr<Bool>?` changes the annotation. | See "A condition's predicate" under "Different On Purpose". |
| `SQL.row` takes two to six columns, one overload per arity, instead of any number through a parameter pack. Its tuples take each column's own type, and `in` is `Expr<Bool?>` when a column is nullable. | With a parameter pack, Swift types an integer literal in `SQL.row(…).in([(7, 8)])` as `Int` before it resolves the pack, so the tuple doesn't match `Int64` columns. |
| An aggregate's `filter` returns `Expr<Value>` instead of `AggregateExpr<Value>`, so a filtered aggregate has no `filter`. Code that stored a filtered aggregate as `AggregateExpr`, such as `let usCount: AggregateExpr<Int64> = SQL.count(SaleModel.id).filter(usSale)`, changes the annotation to `Expr<Int64>`. | The kit rendered a second filter as `… FILTER (WHERE a) FILTER (WHERE b)`, which PostgreSQL rejects. rust-dbkit returns a plain expression too. |
| `SQL.power` with a `Double` base and a `Decimal` exponent doesn't compile; cast the exponent with `cast(to: Double.self)`. | `Decimal` takes a power only with a `Decimal`, as it combines only with `Decimal` in arithmetic; two `Decimal`s now give `Decimal`. See "Ported Beyond The Kit". |
| `count(on:)` and `exists(on:)` ignore the query's `orderBy`, `limit`, `offset` and `forUpdate`, as `paginate` already ignored its ordering and pagination. Code that counted a limited query, such as `query.limit(10).count(on: db)`, got at most the limit and now gets every matching row. | rust-dbkit counts without them too. PostgreSQL rejects `FOR UPDATE` together with the `DISTINCT` of a count with joins, see "Counting a query with joins" under "Different On Purpose". |
| A loaded relation's storage on the generated `Loaded` subclass and its `_<Name>Slot` protocol is `__dbkit_<relation>` instead of `_<relation>`, such as `row.__dbkit_user` for `row._user`. Read the relation by its own name, `row.user`. | Names starting with `__dbkit_` are reserved for generated code, so a model with relations `user` and `_user` doesn't clash; see "Ported Beyond The Kit". |
| `HalfVector.values` are rounded to half precision, so `HalfVector<1>([0.1]).values` is `[0.099975586]`. `HalfVector<0>` and more than 16000 dimensions throw `DBKitError.invalidVector`. | The values equal what PostgreSQL stores, so a vector equals the row read back; pgvector rejects the other dimensions. See "Ported Beyond The Kit". |

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
| `dbkit-core/vector_support.rs::value_from_pgvector` | A value becomes a bind when a query uses it; `selectBindsPgvectorEqAndNullFilters` binds a vector. |
| `dbkit/vector_support.rs::build_arguments_accepts_pgvector` | PostgresNIO binds every `SQLValue`; `pgvectorRoundtripEqFilterAndActiveModelNulling` sends vectors to PostgreSQL. |
| `extended_vector_support.rs::half_vector_try_from_native_vec_validates_lengths_dimensions_and_finite_values` | `HalfVector` takes `Float` values only, so there is no conversion from native half values to validate; `halfVectorTryFromF32VecRejectsWrongLengthsNonFiniteValuesAndOverflow` checks the same lengths, dimensions and non-finite values. |
| `ui/fail_nullable_model_field_type_alias.rs` | rust-dbkit's macro tells nullable fields by their syntax and rejects an alias of `Option`. Swift's type checker resolves `typealias OptionalText = String?`, so `@Model` accepts the alias as a nullable column. |
| `bitwise_sql.rs::compiles_custom_integer_backed_type_without_exposing_its_storage_type` | Custom integer-backed types in bitwise expressions are left out. |
| `bitwise_integration.rs::custom_integer_backed_type_filters_and_roundtrips` | Custom integer-backed types in bitwise expressions are left out. |
| `ui/pass_bitwise_custom_integer_types.rs` | Custom integer-backed types in bitwise expressions are left out. |
| `ui/fail_interval_float_hours.rs` | `SQL.interval(hours:)` takes fractions, see "Interval units" under "Different On Purpose". |
| `sql_compiler.rs::condition_preserves_required_predicate_type` | A condition's predicate is always `Bool?`, see "A condition's predicate" under "Different On Purpose". |
| `sql_compiler.rs::compiles_order_by_alias` | Ordering by a select alias is planned, see "Planned". |
| `expr_methods_sql.rs::unwrap_or_default_preserves_literal_types` | `unwrap_or_default()` is left out; `??` with an explicit fallback covers it. |
| `expr_methods_sql.rs::unwrap_or_default_uses_the_types_default_without_requiring_clone` | `unwrap_or_default()` is left out; `??` with an explicit fallback covers it. |
| `ui/fail_regex_transform_flags_required.rs` | The flags default to none, see "Regex flags" under "Different On Purpose". |
| `relation_state_into.rs::unloaded_model_keeps_standard_identity_conversion` | Converting a loaded row to a type with fewer loaded relations is left out; a loaded row passes as the plain model and as any `With…` type, as `selectInLoadsSelfReferencesAndPassesAsWithTypes` checks. |
| `relation_state_into.rs::each_loaded_relation_kind_converts_into_unloaded_model` | Converting a loaded row to a type with fewer loaded relations is left out; a loaded row passes as the plain model and as any `With…` type, as `selectInLoadsSelfReferencesAndPassesAsWithTypes` checks. |
| `relation_state_into.rs::every_loaded_and_unloaded_relation_combination_converts` | Converting a loaded row to a type with fewer loaded relations is left out; a loaded row passes as the plain model and as any `With…` type, as `selectInLoadsSelfReferencesAndPassesAsWithTypes` checks. |
| `relation_state_into.rs::nested_loaded_relation_models_also_convert` | Converting a loaded row to a type with fewer loaded relations is left out; a loaded row passes as the plain model and as any `With…` type, as `selectInLoadsSelfReferencesAndPassesAsWithTypes` checks. |
| `relation_state_into.rs::loaded_models_can_be_passed_to_unloaded_parameters_with_into` | Converting a loaded row to a type with fewer loaded relations is left out; a loaded row passes as the plain model and as any `With…` type, as `selectInLoadsSelfReferencesAndPassesAsWithTypes` checks. |
| `relation_state_into.rs::every_partial_relation_unload_converts_and_preserves_retained_relations` | Converting a loaded row to a type with fewer loaded relations is left out; a loaded row passes as the plain model and as any `With…` type, as `selectInLoadsSelfReferencesAndPassesAsWithTypes` checks. |
| `relation_state_into.rs::partial_unload_preserves_nested_loaded_relation_types` | Converting a loaded row to a type with fewer loaded relations is left out; a loaded row passes as the plain model and as any `With…` type, as `selectInLoadsSelfReferencesAndPassesAsWithTypes` checks. |
| `ui/pass_relation_state_into_generic_names.rs` | Its relation names would clash with the generated conversion to fewer loaded relations, which is left out. |
| `ui/pass_relation_state_into_shadowed_traits.rs` | Its types named `From` and `Into` would shadow the traits of the generated conversion to fewer loaded relations, which is left out. |
| `subquery_sql.rs::exists_subquery_does_not_treat_dollar_digits_inside_quoted_identifier_as_bind_token` | rust-dbkit takes an alias as SQL text, which may be a quoted identifier, and rewrites a subquery's placeholders in that text. This port takes an alias as a name it quotes itself and renders a subquery's binds with the outer query's renderer, so no SQL text is scanned for placeholders. `existsSubqueryDoesNotTreatDollarSuffixInAliasAsBindToken` covers an alias with `$1`. |
| `ui/fail_distinct_after_for_update.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_distinct_after_for_update_nowait.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_distinct_after_for_update_skip_locked.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_for_update_after_distinct.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_for_update_nowait_after_distinct.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_for_update_skip_locked_after_distinct.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_for_update_after_group_by.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_for_update_after_group_by_having.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_group_by_after_for_update.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_group_by_having_after_for_update.rs` | Rejecting `FOR UPDATE` with `DISTINCT` or `GROUP BY` at compile time is planned, see "Planned". |
| `ui/fail_nowait_without_for_update.rs` | The waiting behaviour is the argument of `forUpdate(_:)`, as in `forUpdate(.noWait)`, so there is no `NOWAIT` without a lock. |
| `ui/fail_skip_locked_without_for_update.rs` | The waiting behaviour is the argument of `forUpdate(_:)`, as in `forUpdate(.skipLocked)`, so there is no `SKIP LOCKED` without a lock. |
| `integration_streaming.rs::exhausted_pool_error_is_reported_during_iteration` | `PostgresClient` waits for a free connection without a time limit, so a stream on an exhausted pool waits instead of failing. `aStreamOnAnExhaustedPoolWaitsForAConnectionWhenIterated` checks that it waits on its first row, not in `stream(on:)`. |
| `integration_streaming.rs::standard_stream_combinators_preserve_errors_and_release_connections` | It tests Rust's `Stream` combinators. A stream here is an `AsyncSequence` read with `for try await`; `leavingAStreamEarlyStopsTheServerAndFreesTheConnection` leaves the loop by `break`, `throw` and cancellation. |
| `migrations.rs::migrate_applies_reversible_up_down_migrations` | Migrations are forward-only, see "Migrations" under "Different On Purpose". An `.up.sql` and a `.down.sql` file share their version, which `db.migrate` rejects, as `migrationFilesNeedAVersionOfTheirOwn` checks. |
| `ui/fail_streaming_executor_lifetime.rs` | Swift has no borrow checker. A stream keeps its `Database` alive, and a `Transaction` exists only inside the closure of `db.transaction`. |
