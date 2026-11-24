import DBKit

// Two enum columns compare only when they hold the same enum type, even when their labels overlap.

@DatabaseEnum("build_stage")
enum BuildStage { case planned, built }

@DatabaseEnum("deploy_stage")
enum DeployStage { case planned, deployed }

@Model(table: "builds")
class BuildModel {
    @Key var id: Int64
    var stage: BuildStage
}

@Model(table: "deployments")
class DeploymentModel {
    @Key var id: Int64
    var stage: DeployStage
}

private func columnsOfDifferentEnums() {
    _ = BuildModel.stage == DeploymentModel.stage  // error: requires the types
}
