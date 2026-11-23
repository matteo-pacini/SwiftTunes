import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes

@Test func targetBuilds() {
    #expect(GenreRules.fieldError(GenreFieldsText(name: "", caption: "", turns: "", slowest: "", fastest: ""), others: []) == nil)
}
