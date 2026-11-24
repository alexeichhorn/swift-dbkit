# swift-dbkit

A Postgres-first ORM for Swift, the port of [rust-dbkit](https://github.com/alexeichhorn/rust-dbkit). It is built test-first.

## Test first

Every change lands as commits in this order:

1. `Test <feature>`: the tests alone. Run them and confirm they are red for the reason you expect. A missing API fails the build; a behaviour gap fails an assertion.
2. `Implement <feature>` or `Fix <bug>`: the code that turns them green, with the whole suite passing.
3. `Document <feature>`: its part of `README.md` and `docs/`.

A committed test changes only when the test itself was wrong. That is its own commit, `Fix test <name>`, and the message says what was wrong.

## Porting from rust-dbkit

rust-dbkit's tests are the spec. A ported test keeps its name in camelCase, in a file named after the Rust file:

| rust-dbkit | swift-dbkit |
| --- | --- |
| `crates/dbkit/tests/joined_sql.rs` | `Tests/DBKitTests/JoinedSQLTests.swift`, suite `JoinedSQLTests` |
| `fn select_binds_utc_datetime` | `func selectBindsUTCDatetime()` |
| `crates/dbkit/tests/ui/fail_sum_non_numeric.rs` | `Tests/CompileFail/Sources/Fixtures/FailSumNonNumeric.swift` |

`type_support.rs` and `vector_support.rs` exist in both Rust crates. The `dbkit-core` one becomes `CoreTypeSupportTests.swift` and `CoreVectorSupportTests.swift`.

Translate what a test checks into Swift's API and keep its cases and edge values. Expected SQL follows this library's rendering: quoted identifiers, `$n` binds.

A Rust test is either ported or listed with its reason in `docs/rust-parity.md`, which also holds the features this port leaves out. `scripts/check-rust-parity.py <path to rust-dbkit>` reports every test that is neither.

## The kit baseline

Until `0.1.0`, the repo is rebuilt from an existing implementation, the kit. Its snapshot is the untracked folder `.reference/kit`.

- Bring its code over as it is. Its public API is the baseline.
- Change a signature only where `docs/rust-parity.md` names the change, and record the change there under "API changes from the kit".
- An improvement you notice becomes a GitHub issue.

## Tests

- `swift test` runs everything: unit tests, integration tests and compile-fail fixtures.
- Integration tests read `DATABASE_URL` from the environment or from `.env`, and fail without it. They need PostgreSQL 16 or newer with pgvector 0.7 or newer.
- Point `DATABASE_URL` only at a throwaway database. The tests create the `vector` extension, create and drop real tables named for their tests, and the migration tests drop `_dbkit_migrations`.
- An integration test creates its tables as `TEMP` tables inside one transaction, so tests run in parallel and leave nothing behind. A test that needs several connections uses real tables named for that test and drops them.
- A compile-fail fixture marks each line that must fail with `// error: <part of the message>`. `CompileFailTests` builds the fixture package once and fails on a marked line without that error and on an error without a mark. A fixture without marks must compile.
- Test models carry the `Model` suffix (`UserModel`), as the docs do.

## Checks

- Format before committing: `swift format --in-place --recursive Sources Tests Package.swift`. CI lints the same paths with `--strict`.
- CI builds and tests on Linux, where the library deploys. Use Foundation and the NIO libraries; Apple-only frameworks do not build there.
