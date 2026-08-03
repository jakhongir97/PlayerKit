import XCTest
@testable import PlayerKit

/// `PlayerRenderingView` shows whatever `currentPlayer.getPlayerView()` returns,
/// and `PlayerView` keys that subtree on `playerGeneration`. If the generation
/// stops tracking player swaps, SwiftUI keeps the previous backend's view on
/// screen — a black rectangle once its own player is torn down, with audio
/// carrying on from the new one. These pin the signal to the swap.
@MainActor
final class PlayerRenderingIdentityTests: XCTestCase {

    override func tearDown() {
        PlayerManager.shared.tearDown()
        super.tearDown()
    }

    /// Building a player must move the generation, or the view has no reason to
    /// swap to the new backend's view.
    func testGenerationAdvancesWhenAPlayerIsCreated() {
        let manager = PlayerManager.shared
        manager.resetPlayer()

        let before = manager.playerGeneration
        manager.setPlayer(type: .avPlayer)

        XCTAssertGreaterThan(manager.playerGeneration, before)
        XCTAssertNotNil(manager.currentPlayer)
    }

    /// The case the old `.id(selectedPlayerType)` missed entirely: reconfiguring
    /// to the *same* backend still builds a new wrapper with a new player view,
    /// while the type — and so the old identity — never changes.
    func testGenerationAdvancesWhenReconfiguringToTheSameBackend() {
        let manager = PlayerManager.shared
        manager.setPlayer(type: .avPlayer)

        let typeBefore = manager.selectedPlayerType
        let generationBefore = manager.playerGeneration
        // Keep the old view alive so the allocator cannot reuse its address for
        // the replacement and make two distinct objects look identical.
        let viewBefore = manager.currentPlayer?.getPlayerView()

        manager.setPlayer(type: .avPlayer)

        let viewAfter = manager.currentPlayer?.getPlayerView()

        XCTAssertEqual(manager.selectedPlayerType, typeBefore, "the backend is deliberately unchanged")
        XCTAssertFalse(viewBefore === viewAfter, "a new wrapper brings a new player view")
        XCTAssertGreaterThan(
            manager.playerGeneration,
            generationBefore,
            "same type, new view — the generation is what has to move here"
        )
    }

    /// Tearing the player down has to move it too, so the view stops rendering a
    /// player that no longer exists.
    func testGenerationAdvancesWhenThePlayerIsTornDown() {
        let manager = PlayerManager.shared
        manager.setPlayer(type: .avPlayer)

        let before = manager.playerGeneration
        manager.resetPlayer()

        XCTAssertNil(manager.currentPlayer)
        XCTAssertGreaterThan(manager.playerGeneration, before)
    }

    /// The generation only ever moves forward, so a swap can never land back on
    /// a value SwiftUI has already seen and be treated as "no change".
    func testGenerationIsMonotonic() {
        let manager = PlayerManager.shared
        var seen: [Int] = []

        for _ in 0 ..< 4 {
            manager.setPlayer(type: .avPlayer)
            seen.append(manager.playerGeneration)
            manager.resetPlayer()
            seen.append(manager.playerGeneration)
        }

        XCTAssertEqual(seen, seen.sorted(), "generations went backwards: \(seen)")
        XCTAssertEqual(Set(seen).count, seen.count, "a generation repeated: \(seen)")
    }
}
