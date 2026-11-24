import DBKit

// Models shared by the fixtures. This file has no marks, so it must compile.

@Model(table: "users")
class UserModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    var email: String
}
