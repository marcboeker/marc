import Testing
@testable import Marcdown

struct ReloadPolicyTests {
    @Test func cleanBufferReloads() {
        #expect(ReloadPolicy.action(disk: "new", buffer: "old", lastKnownDisk: "old") == .reload)
    }

    @Test func dirtyBufferAsks() {
        #expect(ReloadPolicy.action(disk: "new", buffer: "old + mine", lastKnownDisk: "old") == .ask)
    }

    @Test func ownSaveIsIgnored() {
        #expect(ReloadPolicy.action(disk: "mine", buffer: "mine", lastKnownDisk: "old") == .ignore)
    }

    @Test func touchWithoutChangeIsIgnored() {
        #expect(ReloadPolicy.action(disk: "old", buffer: "old + mine", lastKnownDisk: "old") == .ignore)
    }
}
