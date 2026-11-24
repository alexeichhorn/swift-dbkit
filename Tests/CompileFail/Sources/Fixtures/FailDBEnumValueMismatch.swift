import DBKit

// An enum column takes values of its own enum only: not another enum with the same labels, and not a string.

@DatabaseEnum("task_state")
enum TaskState { case queued, running }

@DatabaseEnum("delivery_state")
enum DeliveryState { case queued, running }

@Model(table: "tasks")
class TaskModel {
    @Key var id: Int64
    var state: TaskState
}

private func valuesOfAnotherType() {
    let label = "queued"
    _ = TaskModel.query().filter(TaskModel.state == DeliveryState.queued)  // error: requires the types
    _ = TaskModel.query().filter(TaskModel.state == "queued")  // error: requires the types
    _ = TaskModel.query().filter(TaskModel.state == label)  // error: requires the types
}
