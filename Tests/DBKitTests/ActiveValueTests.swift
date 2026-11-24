import DBKit
import Testing

/// rust-dbkit tracks each column in an `ActiveValue`; here `ActiveModel` tracks the columns you assign.
@Suite struct ActiveValueTests {
    @Test func setAcceptsRequiredValues() {
        var active = ActiveModel<UserModel>()

        active.name = "required"

        #expect(active.name == "required")
    }

    @Test func setAcceptsDirectOptionalAndNullValuesForNullableFields() {
        var active = ActiveModel<UserModel>()

        active.region = "direct"
        #expect(active.region == "direct")

        let optional: String? = "optional"
        active.region = optional
        #expect(active.region == "optional")

        active.region = nil
        #expect(active.region == nil)
    }
}
