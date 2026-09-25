import Testing
@testable import MedicationAdherenceCore

private actor ReminderGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor ReminderSystem {
    var pending: [String: String] = [:]
    var events: [String] = []
    var observedCancellation = false

    func add(_ id: String, value: String) {
        pending[id] = value
        events.append(id)
        observedCancellation = observedCancellation || Task.isCancelled
    }

    func remove(_ ids: [String]) {
        for id in ids { pending[id] = nil }
    }
}

struct ReminderOperationQueueTests {
    @Test(arguments: [false, true])
    func replacementWaitsForInFlightAdd(cancelOnly: Bool) async {
        let queue = ReminderOperationQueue()
        let entered = ReminderGate()
        let release = ReminderGate()
        let system = ReminderSystem()
        let old = queue.enqueue {
            await entered.open()
            await release.wait()
            await system.add("A", value: "old")
            await system.add("B", value: "old")
        }
        await entered.wait()
        let latest = queue.enqueue {
            await system.remove(["A", "B"])
            if !cancelOnly { await system.add("C", value: "latest") }
        }
        old.cancel()
        #expect(await system.events.isEmpty)
        await release.open()
        await latest.value
        #expect(await system.pending == (cancelOnly ? [:] : ["C": "latest"]))
        #expect(await system.observedCancellation == false)
    }

    @Test
    func successiveSavesPreserveOtherMedication() async {
        let queue = ReminderOperationQueue()
        let entered = ReminderGate()
        let release = ReminderGate()
        let system = ReminderSystem()
        queue.enqueue {
            await entered.open()
            await release.wait()
            await system.add("A", value: "v1")
        }
        await entered.wait()
        queue.enqueue { await system.add("B", value: "b1") }
        queue.enqueue { await system.add("A", value: "v2") }
        let last = queue.enqueue { await system.add("A", value: "v3") }
        await release.open()
        await last.value
        #expect(await system.pending == ["A": "v3", "B": "b1"])
        #expect(await system.events == ["A", "B", "A", "A"])
    }
}
