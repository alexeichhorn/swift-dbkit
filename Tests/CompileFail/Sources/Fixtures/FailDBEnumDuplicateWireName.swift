import DBKit

// Two cases with one label would save alike, and reading would always give back the first. `@DatabaseEnum` rejects
// case names with the same snake_case label, and Swift rejects a raw value given twice.

@DatabaseEnum("job_state")  // error: both get the label 'in_review'
enum JobState {
    case inReview
    case in_review
}

enum HandWrittenJobState: String, DatabaseEnum {
    static let typeName = "job_state"
    case planned
    case active = "planned"  // error: raw value for enum case is not unique
}
