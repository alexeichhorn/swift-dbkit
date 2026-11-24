import DBKit

@Model(table: "jobs")
class JobModel {
    @Key var sourceID: String
    var title: String
    var company: String
    var location: String
    var contentHash: String
    // Waits for slice 7: `var removedAt: Date?` and `var updatedAt: Date`, set to 2026-01-01 00:00:00 in the insert.
}

private func upsertFourColumns() {
    let job = JobModel.Insert(sourceID: "job-1", title: "Senior Rust Engineer", company: "Acme", location: "Zurich", contentHash: "hash-1")
    _ = JobModel.insert(job)
        .onConflict(JobModel.sourceID, doUpdate: JobModel.title, JobModel.company, JobModel.location, JobModel.contentHash)
    let updates = (JobModel.title, JobModel.company, JobModel.location, JobModel.contentHash)
    _ = JobModel.insert(job).onConflict(JobModel.sourceID, doUpdate: updates)
}
