import DBKit

// A conflict target takes typed columns of the model, not column names.
private func conflictOnColumnNames() {
    let insert = RunPayloadModel.insert(RunPayloadModel.Insert(targetID: 1, runID: 2, payload: "p", source: "s", version: 1))
    let (targetID, runID) = (RunPayloadModel.targetID.name, RunPayloadModel.runID.name)
    _ = insert.onConflictDoNothing(targetID, runID)  // error: cannot convert value of type 'String' // error: could not infer pack element
}
