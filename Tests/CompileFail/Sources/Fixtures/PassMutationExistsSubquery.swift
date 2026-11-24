import DBKit

// `update()` and `delete()` take a correlated `EXISTS` subquery.

@Model(table: "teams")
class TeamModel {
    @Key @AutoIncrement var id: Int64
    var ownerID: Int64
    var state: String
}

@Model(table: "team_members")
class TeamMemberModel {
    @Key @AutoIncrement var id: Int64
    var teamID: Int64
    var role: String
}

private func mutationExistsSubqueries() {
    _ = TeamMemberModel.delete()
        .whereExists(
            TeamModel.query()
                .select(TeamModel.id)
                .filter(TeamModel.id == TeamMemberModel.teamID)
                .filter(TeamModel.state == "active")
        )
        .render()

    _ = TeamModel.update()
        .set(TeamModel.state, to: "inactive")
        .whereNotExists(
            TeamMemberModel.query()
                .select(TeamMemberModel.id)
                .filter(TeamMemberModel.teamID == TeamModel.id)
                .filter(TeamMemberModel.role == "lead")
        )
        .render()
}
