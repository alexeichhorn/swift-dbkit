import DBKit
import Testing

/// The `users` table of rust-dbkit's `sql_compiler.rs`, with nullable `email` and `score`.
@Model(table: "users")
class CompilerUserModel {
    @Key var id: Int64
    var email: String?
    var backupEmail: String?
    var score: Int64?
}

@Suite struct SQLCompilerTests {
    @Test func compilesBasicFilter() {
        let rendered = CompilerUserModel.query().filter(CompilerUserModel.email == "a@b.com").render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" = $1"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    @Test func compilesBoolComposition() {
        let rendered = CompilerUserModel.query()
            .filter(CompilerUserModel.id > 10 && CompilerUserModel.email.ilike("%test%"))
            .render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE ("users"."id" > $1 AND "users"."email" ILIKE $2)"#)
        #expect(rendered.binds.map(\.description) == ["10", "%test%"])
    }

    @Test func compilesInExpression() {
        let rendered = CompilerUserModel.query().filter(CompilerUserModel.id.in([1, 2, 3])).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."id" IN ($1, $2, $3)"#)
        #expect(rendered.binds.map(\.description) == ["1", "2", "3"])
    }

    @Test func compilesIsNullExpression() {
        let predicate: Expr<Bool> = CompilerUserModel.email.isNull
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" IS NULL"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesEqNoneAsIsNull() {
        let predicate: Expr<Bool?> = CompilerUserModel.email == nil
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" IS NULL"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesEqSomeOnNullableColumnAsBoundValue() {
        let email: String? = "a@b.com"
        let predicate: Expr<Bool?> = CompilerUserModel.email == email
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" = $1"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    @Test func compilesNeNoneAsIsNotNull() {
        let predicate: Expr<Bool?> = CompilerUserModel.email != nil
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" IS NOT NULL"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesNullableOrderedComparisonsWithOptionalValues() {
        let five: Int64? = 5
        let some: Expr<Bool?> = CompilerUserModel.score < five
        let someRendered = CompilerUserModel.query().filter(some).render()
        #expect(someRendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."score" < $1"#)
        #expect(someRendered.binds.map(\.description) == ["5"])

        let missing: Int64? = nil
        let none: Expr<Bool?> = CompilerUserModel.score >= missing
        let noneRendered = CompilerUserModel.query().filter(none).render()
        #expect(noneRendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."score" >= NULL"#)
        #expect(noneRendered.binds.isEmpty)
    }

    @Test func compilesCoalesceFunctionFilter() {
        let predicate: Expr<Bool> = (CompilerUserModel.email ?? "unknown") == "ALPHA"
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE COALESCE("users"."email", $1) = $2"#)
        #expect(rendered.binds.map(\.description) == ["unknown", "ALPHA"])
    }

    @Test func compilesCoalesceTwoColumns() {
        let predicate: Expr<Bool?> = (CompilerUserModel.email ?? CompilerUserModel.backupEmail) == "alpha@db.com"
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE COALESCE("users"."email", "users"."backup_email") = $1"#)
        #expect(rendered.binds.map(\.description) == ["alpha@db.com"])
    }

    @Test func compilesSelectQuery() {
        let rendered = CompilerUserModel.query()
            .filter(CompilerUserModel.email.like("%example%"))
            .limit(5)
            .offset(10)
            .render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" LIKE $1 LIMIT 5 OFFSET 10"#)
        #expect(rendered.binds.map(\.description) == ["%example%"])
    }

    @Test func compilesBetweenExpression() {
        let rendered = CompilerUserModel.query().filter(CompilerUserModel.id.between(1, 5)).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."id" BETWEEN $1 AND $2"#)
        #expect(rendered.binds.map(\.description) == ["1", "5"])
    }
}
