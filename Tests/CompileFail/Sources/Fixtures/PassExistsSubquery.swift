import DBKit

// A model query and a projection take a correlated `EXISTS` subquery, which is a model query or a projection.

/// rust-dbkit's `Organization` of this fixture, renamed since `PassModelSuffixPreservedAPI.swift` declares one.
@Model(table: "organizations")
class SlugOrganizationModel {
    @Key @AutoIncrement var id: Int64
    var slug: String
}

@Model(table: "projects")
class ProjectModel {
    @Key @AutoIncrement var id: Int64
    var organizationID: Int64
    var state: String
}

private func existsSubqueries() {
    _ = SlugOrganizationModel.query()
        .whereExists(
            ProjectModel.query()
                .select(ProjectModel.id)
                .filter(ProjectModel.organizationID == SlugOrganizationModel.id)
                .filter(ProjectModel.state == "active")
        )
        .orderBy(SlugOrganizationModel.id.asc)
        .render()

    _ = SlugOrganizationModel.query()
        .whereNotExists(
            ProjectModel.query()
                .select(ProjectModel.id)
                .filter(ProjectModel.organizationID == SlugOrganizationModel.id)
                .filter(ProjectModel.state == "archived")
        )
        .render()

    _ = SlugOrganizationModel.query()
        .select(SlugOrganizationModel.slug)
        .whereExists(ProjectModel.query().filter(ProjectModel.organizationID == SlugOrganizationModel.id))
        .render()
}
