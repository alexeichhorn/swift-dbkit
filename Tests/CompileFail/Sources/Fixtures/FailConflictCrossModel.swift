import DBKit

@Model(table: "other_rows")
class OtherRowModel {
    @Key var id: Int64
    var value: String
}

private func updateAColumnOfAnotherModel() {
    _ = RunPayloadModel.insert(RunPayloadModel.Insert(targetID: 1, runID: 2, payload: "p", source: "s", version: 1))
        .onConflict(
            RunPayloadModel.targetID, RunPayloadModel.runID,
            doUpdate: RunPayloadModel.payload, OtherRowModel.value  // error: cannot convert value of type 'Column<
        )
}
