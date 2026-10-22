import Foundation
import Testing
@testable import OMPCore

@Suite("Finding omp")
struct FindingOMPTests {
    @Test("an omp the reader chose is used before the usual places")
    func chosenComesFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-find-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("omp")
        try "#!/bin/sh\n".write(to: chosen, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: chosen.path)

        #expect(OMPBinary.resolve(chosen: chosen.path) == chosen.path)
    }

    @Test("a chosen omp that is gone is passed over")
    func goneIsPassedOver() {
        let gone = "/nonexistent/omp-ui/omp"
        #expect(OMPBinary.resolve(chosen: gone) != gone)
    }
}
