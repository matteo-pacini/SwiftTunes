import Testing

@Suite struct WaiterTests {
    @Test func aWaitThatNeverHoldsEndsAtItsLimit() async {
        let waiter = Waiter()
        #expect(await waiter.until(.milliseconds(20)) { false } == false)
    }

    @Test func aPokeEndsTheWaitOnceItHolds() async {
        let waiter = Waiter()
        var done = false
        let poker = Task {
            await Task.yield()
            done = true
            waiter.poke()
        }
        #expect(await waiter.until(.seconds(30)) { done })
        await poker.value
    }
}
