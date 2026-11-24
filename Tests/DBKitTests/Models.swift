import DBKit

@Model(table: "users")
class UserModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    @Unique var email: String
    var region: String?
}

@Model(table: "todos")
class TodoModel {
    @Key @AutoIncrement var id: Int64
    @Index var userID: Int64
    var title: String
    var note: String?
    var isComplete: Bool = false
}
