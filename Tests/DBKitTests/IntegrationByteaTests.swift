import DBKit
import Foundation
import Testing

@Suite struct IntegrationByteaTests {
    @Test func byteaRoundtripFilterAndActiveModelNulling() async throws {
        try await withRollback { tx in
            try await tx.query("CREATE TEMP TABLE blob_rows (id BIGSERIAL PRIMARY KEY, data BYTEA NOT NULL, data_optional BYTEA NULL)")
            let data = Data([0, 1, 2, 255])
            let optional = Data([3, 4, 5])

            let inserted = try #require(
                try await BlobRowModel.insert(BlobRowModel.Insert(data: data, dataOptional: optional)).returningAll().first(on: tx))
            #expect(inserted.data == data)
            #expect(inserted.dataOptional == optional)

            let found = try #require(try await BlobRowModel.query().filter(BlobRowModel.data == data).first(on: tx))
            #expect(found.id == inserted.id)

            var active = found.active()
            active.dataOptional = nil
            let cleared = try await active.update(on: tx)
            #expect(cleared.dataOptional == nil)

            let onlyNullOptional = try await BlobRowModel.query().filter(BlobRowModel.dataOptional == nil).all(on: tx)
            #expect(onlyNullOptional.map(\.id) == [inserted.id])
        }
    }
}
