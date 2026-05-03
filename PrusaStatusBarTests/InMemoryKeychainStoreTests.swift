@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `api-key-storage` Requirement: Reading the API key gracefully handles
///   missing items (the in-memory implementation is the test double for this
///   behavior).
struct InMemoryKeychainStoreTests {
    @Test
    func readReturnsNilWhenNothingStored() {
        let store = InMemoryKeychainStore()
        #expect(store.read() == nil)
    }

    @Test
    func writeThenReadRoundTrips() throws {
        let store = InMemoryKeychainStore()
        try store.write("super-secret")
        #expect(store.read() == "super-secret")
    }

    @Test
    func writeOverwritesPreviousValue() throws {
        let store = InMemoryKeychainStore()
        try store.write("first")
        try store.write("second")
        #expect(store.read() == "second")
    }

    @Test
    func deleteRemovesValue() throws {
        let store = InMemoryKeychainStore(initial: "abc")
        try store.delete()
        #expect(store.read() == nil)
    }

    @Test
    func deleteMissingItemDoesNotThrow() throws {
        let store = InMemoryKeychainStore()
        try store.delete()
        try store.delete()
    }
}
