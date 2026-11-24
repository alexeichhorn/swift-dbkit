import DBKit

@Model(table: "organizations")
class OrganizationModel {
    @Key @AutoIncrement var id: Int64
    var name: String
}

/// rust-dbkit's `UserModel` of this fixture, renamed since `Models.swift` declares one.
@Model(table: "accounts")
class AccountModel {
    @Key @AutoIncrement var id: Int64
    var organizationID: Int64
    @BelongsTo(key: "organizationID") var organization: OrganizationModel?
    var email: String
}

private func useSuffixedModel(loaded: AccountModel.Loaded<OrganizationModel?>) {
    _ = AccountModel.query().filter(AccountModel.email == "a@b.com")
    _ = AccountModel.insert(AccountModel.Insert(organizationID: 1, email: "a@b.com"))
    var active: ActiveModel<AccountModel> = AccountModel(id: 1, organizationID: 1, email: "a@b.com").active()
    active.email = "a@b.com"
    let _: OrganizationModel? = loaded.organization
}
