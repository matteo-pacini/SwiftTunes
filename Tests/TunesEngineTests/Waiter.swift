import Foundation

/// Waits on something outside the test's control (a real process, the real
/// player, a server) until a condition holds, or a time limit runs out. A
/// continuation alone cannot be cancelled, so a test's own time limit cannot
/// end such a wait; this one always ends.
final class Waiter {
    private struct Pending {
        let check: () -> Bool
        let cont: CheckedContinuation<Bool, Never>
        let deadline: Task<Void, Never>
    }

    private var pending: [Int: Pending] = [:]
    private var seq = 0

    /// True once `check` holds, re-checked on every `poke()`; false when
    /// `limit` passes first.
    func until(_ limit: Duration, _ check: @escaping () -> Bool) async -> Bool {
        if check() { return true }
        seq += 1
        let id = seq
        return await withCheckedContinuation { cont in
            let deadline = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                self?.expire(id)
            }
            pending[id] = Pending(check: check, cont: cont, deadline: deadline)
        }
    }

    /// Something changed: resume every wait whose condition now holds.
    func poke() {
        for (id, p) in pending where p.check() {
            pending[id] = nil
            p.deadline.cancel()
            p.cont.resume(returning: true)
        }
    }

    private func expire(_ id: Int) {
        guard let p = pending.removeValue(forKey: id) else { return }
        p.cont.resume(returning: false)
    }
}
