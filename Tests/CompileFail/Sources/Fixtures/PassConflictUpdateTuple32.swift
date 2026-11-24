import DBKit

@Model(table: "wide_jobs")
class WideJobModel {
    @Key var sourceID: String
    var c01: Int32
    var c02: Int32
    var c03: Int32
    var c04: Int32
    var c05: Int32
    var c06: Int32
    var c07: Int32
    var c08: Int32
    var c09: Int32
    var c10: Int32
    var c11: Int32
    var c12: Int32
    var c13: Int32
    var c14: Int32
    var c15: Int32
    var c16: Int32
    var c17: Int32
    var c18: Int32
    var c19: Int32
    var c20: Int32
    var c21: Int32
    var c22: Int32
    var c23: Int32
    var c24: Int32
    var c25: Int32
    var c26: Int32
    var c27: Int32
    var c28: Int32
    var c29: Int32
    var c30: Int32
    var c31: Int32
    var c32: Int32
}

private func upsertThirtyTwoColumns() {
    let job = WideJobModel.Insert(
        sourceID: "job-1",
        c01: 1,
        c02: 2,
        c03: 3,
        c04: 4,
        c05: 5,
        c06: 6,
        c07: 7,
        c08: 8,
        c09: 9,
        c10: 10,
        c11: 11,
        c12: 12,
        c13: 13,
        c14: 14,
        c15: 15,
        c16: 16,
        c17: 17,
        c18: 18,
        c19: 19,
        c20: 20,
        c21: 21,
        c22: 22,
        c23: 23,
        c24: 24,
        c25: 25,
        c26: 26,
        c27: 27,
        c28: 28,
        c29: 29,
        c30: 30,
        c31: 31,
        c32: 32
    )
    _ = WideJobModel.insert(job)
        .onConflict(
            WideJobModel.sourceID,
            doUpdate:
                WideJobModel.c01,
            WideJobModel.c02,
            WideJobModel.c03,
            WideJobModel.c04,
            WideJobModel.c05,
            WideJobModel.c06,
            WideJobModel.c07,
            WideJobModel.c08,
            WideJobModel.c09,
            WideJobModel.c10,
            WideJobModel.c11,
            WideJobModel.c12,
            WideJobModel.c13,
            WideJobModel.c14,
            WideJobModel.c15,
            WideJobModel.c16,
            WideJobModel.c17,
            WideJobModel.c18,
            WideJobModel.c19,
            WideJobModel.c20,
            WideJobModel.c21,
            WideJobModel.c22,
            WideJobModel.c23,
            WideJobModel.c24,
            WideJobModel.c25,
            WideJobModel.c26,
            WideJobModel.c27,
            WideJobModel.c28,
            WideJobModel.c29,
            WideJobModel.c30,
            WideJobModel.c31,
            WideJobModel.c32
        )
    let updates = (
        WideJobModel.c01,
        WideJobModel.c02,
        WideJobModel.c03,
        WideJobModel.c04,
        WideJobModel.c05,
        WideJobModel.c06,
        WideJobModel.c07,
        WideJobModel.c08,
        WideJobModel.c09,
        WideJobModel.c10,
        WideJobModel.c11,
        WideJobModel.c12,
        WideJobModel.c13,
        WideJobModel.c14,
        WideJobModel.c15,
        WideJobModel.c16,
        WideJobModel.c17,
        WideJobModel.c18,
        WideJobModel.c19,
        WideJobModel.c20,
        WideJobModel.c21,
        WideJobModel.c22,
        WideJobModel.c23,
        WideJobModel.c24,
        WideJobModel.c25,
        WideJobModel.c26,
        WideJobModel.c27,
        WideJobModel.c28,
        WideJobModel.c29,
        WideJobModel.c30,
        WideJobModel.c31,
        WideJobModel.c32
    )
    _ = WideJobModel.insert(job).onConflict(WideJobModel.sourceID, doUpdate: updates)
}
