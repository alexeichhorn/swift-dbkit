import DBKit

// Columns of two models holding the same enum compare with each other.

@DatabaseEnum("workflow_stage")
enum WorkflowStage { case queued, running, finished }

/// rust-dbkit's `Task` of this fixture, renamed since `FailDBEnumValueMismatch.swift` declares one.
@Model(table: "tasks")
class StagedTaskModel {
    @Key var id: Int64
    var stage: WorkflowStage
}

@Model(table: "task_snapshots")
class TaskSnapshotModel {
    @Key var id: Int64
    var taskID: Int64
    var stage: WorkflowStage
}

private func oneEnumAcrossModels() {
    _ = StagedTaskModel.query().filter(StagedTaskModel.stage == TaskSnapshotModel.stage)

    _ = StagedTaskModel.query().filter(StagedTaskModel.stage.in([.queued, .running]))

    _ = TaskSnapshotModel.insert(TaskSnapshotModel.Insert(id: 10, taskID: 1, stage: .queued))

    _ = TaskSnapshotModel.update()
        .set(TaskSnapshotModel.stage, to: .finished)
        .filter(TaskSnapshotModel.taskID == 1)
}
