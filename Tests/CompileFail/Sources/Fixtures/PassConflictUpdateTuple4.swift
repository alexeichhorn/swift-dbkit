import DBKit
import Foundation

@Model(table: "jobs")
class JobModel {
    @Key var sourceID: String
    var title: String
    var company: String
    var location: String
    var contentHash: String
    var removedAt: Date?
    var updatedAt: Date
}

private func upsertFourColumns() {
    // 2026-01-01 00:00:00 UTC.
    let now = Date(timeIntervalSince1970: 1_767_225_600)
    let job = JobModel.Insert(
        sourceID: "job-1", title: "Senior Rust Engineer", company: "Acme", location: "Zurich", contentHash: "hash-1", removedAt: nil,
        updatedAt: now)
    _ = JobModel.insert(job)
        .onConflict(JobModel.sourceID, doUpdate: JobModel.title, JobModel.company, JobModel.location, JobModel.contentHash)
    let updates = (JobModel.title, JobModel.company, JobModel.location, JobModel.contentHash)
    _ = JobModel.insert(job).onConflict(JobModel.sourceID, doUpdate: updates)
}
