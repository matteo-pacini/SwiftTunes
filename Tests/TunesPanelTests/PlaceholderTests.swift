import Foundation
import Testing
import TunesContract
@testable import TunesPanel

@Test func fixturesAreBundled() throws {
    let dir = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files.contains("01-not-set-up.jsonl"))
}
