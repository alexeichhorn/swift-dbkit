import DBKit
import Testing

/// rust-dbkit's `accounts` of `subquery_sql.rs`, with a key `@Model` requires.
@Model(table: "accounts")
class AccountModel {
    @Key var id: Int64
    var region: String
    var status: String
}

@Model(table: "invoices")
class InvoiceModel {
    @Key var id: Int64
    var accountID: Int64
    var status: String
}

@Model(table: "employees")
class EmployeeModel {
    @Key var id: Int64
    var name: String
    var managerID: Int64
}

/// This port renders `NOT EXISTS (…)` for `whereNotExists`, where rust-dbkit renders `NOT (EXISTS (…))`. It renders a
/// subquery with the outer query's renderer, so the subquery's placeholders are numbered as they are written and no
/// SQL text is rewritten afterwards. The tests of aliases containing `$1` keep rust-dbkit's cases all the same.
@Suite struct SubquerySQLTests {
    @Test func compilesWhereExistsWithCorrelatedSubqueryAndBinds() {
        let subquery = InvoiceModel.query()
            .select(InvoiceModel.id)
            .filter(InvoiceModel.accountID == AccountModel.id)
            .filter(InvoiceModel.status == "open")
        let rendered = AccountModel.query().filter(AccountModel.region == "eu").whereExists(subquery).render()
        #expect(
            rendered.sql
                == #"SELECT "accounts".* FROM "accounts" WHERE "accounts"."region" = $1 AND EXISTS (SELECT "invoices"."id" FROM "invoices" WHERE "invoices"."account_id" = "accounts"."id" AND "invoices"."status" = $2)"#
        )
        #expect(rendered.binds.map(\.description) == ["eu", "open"])
    }

    @Test func compilesWhereNotExistsWithCorrelatedSubqueryAndOrdering() {
        let subquery = InvoiceModel.query()
            .select(InvoiceModel.id)
            .filter(InvoiceModel.accountID == AccountModel.id)
            .filter(InvoiceModel.status == "void")
        let rendered = AccountModel.query()
            .filter(AccountModel.status == "active")
            .whereNotExists(subquery)
            .orderBy(AccountModel.id.asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "accounts".* FROM "accounts" WHERE "accounts"."status" = $1 AND NOT EXISTS (SELECT "invoices"."id" FROM "invoices" WHERE "invoices"."account_id" = "accounts"."id" AND "invoices"."status" = $2) ORDER BY "accounts"."id" ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["active", "void"])
    }

    @Test func compilesExistsExpressionViaFuncHelper() {
        let subquery = InvoiceModel.query()
            .select(InvoiceModel.id)
            .filter(InvoiceModel.accountID == AccountModel.id)
            .filter(InvoiceModel.status == "overdue")
        let rendered = AccountModel.query().filter(AccountModel.status == "active").filter(!SQL.exists(subquery)).render()
        #expect(
            rendered.sql
                == #"SELECT "accounts".* FROM "accounts" WHERE "accounts"."status" = $1 AND NOT (EXISTS (SELECT "invoices"."id" FROM "invoices" WHERE "invoices"."account_id" = "accounts"."id" AND "invoices"."status" = $2))"#
        )
        #expect(rendered.binds.map(\.description) == ["active", "overdue"])
    }

    /// A subquery on the outer query's own table aliases it, so `EmployeeModel.id` still means the outer row.
    @Test func compilesWhereExistsForSelfCorrelatedSubqueryWithAlias() {
        let reports = EmployeeModel.as("reports")
        let subquery = reports.query().select(reports.id).filter(reports.managerID == EmployeeModel.id)
        let rendered = EmployeeModel.query().filter(EmployeeModel.name == "Ava").whereExists(subquery).render()
        #expect(
            rendered.sql
                == #"SELECT "employees".* FROM "employees" WHERE "employees"."name" = $1 AND EXISTS (SELECT "reports"."id" FROM "employees" AS "reports" WHERE "reports"."manager_id" = "employees"."id")"#
        )
        #expect(rendered.binds.map(\.description) == ["Ava"])
    }

    @Test func existsSubqueryDoesNotTreatDollarSuffixInAliasAsBindToken() {
        let reports = EmployeeModel.as("reports$1")
        let subquery = reports.query().select(reports.id).filter(reports.managerID == EmployeeModel.id)
        let rendered = EmployeeModel.query().whereExists(subquery).render()
        #expect(
            rendered.sql
                == #"SELECT "employees".* FROM "employees" WHERE EXISTS (SELECT "reports$1"."id" FROM "employees" AS "reports$1" WHERE "reports$1"."manager_id" = "employees"."id")"#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func existsSubqueryPreservesUTF8AliasText() {
        let reports = EmployeeModel.as("caf\u{e9}")
        let subquery = reports.query().select(reports.id).filter(reports.managerID == EmployeeModel.id)
        let rendered = EmployeeModel.query().whereExists(subquery).render()
        #expect(
            rendered.sql
                == "SELECT \"employees\".* FROM \"employees\" WHERE EXISTS (SELECT \"caf\u{e9}\".\"id\" FROM \"employees\" AS \"caf\u{e9}\" WHERE \"caf\u{e9}\".\"manager_id\" = \"employees\".\"id\")"
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func existsSubqueryDoesNotTreatDollarSuffixInUTF8AliasAsBindToken() {
        let reports = EmployeeModel.as("caf\u{e9}$1")
        let subquery = reports.query().select(reports.id).filter(reports.managerID == EmployeeModel.id)
        let rendered = EmployeeModel.query().whereExists(subquery).render()
        #expect(
            rendered.sql
                == "SELECT \"employees\".* FROM \"employees\" WHERE EXISTS (SELECT \"caf\u{e9}$1\".\"id\" FROM \"employees\" AS \"caf\u{e9}$1\" WHERE \"caf\u{e9}$1\".\"manager_id\" = \"employees\".\"id\")"
        )
        #expect(rendered.binds.isEmpty)
    }
}
