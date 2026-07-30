# PlayerKit Roadmap

**Status:** draft for review · **Basis:** commit `1fe0a49` on branch `audit-fixes`
· **Method:** nine parallel code investigations against this repository, plus a
prior full-codebase audit. Every factual claim below cites the code. Claims that
could not be verified from this repository are marked **[unverified]**.

---

## 1. Where this is going

Two outcomes, in priority order.

**Near-term — the one that matters.** One library, consumed over SPM by both iTV
apps, covering every player surface they need: live TV channels, movies,
episodic series, general streaming, and trailers. Good enough on iOS to be the
*primary* player rather than a secondary option.

**Later — the aspiration.** A public open-source player library with polished,
ready-to-use UI that other teams would adopt on merit.

## 2. What we found that changes the plan

Nine investigations produced four findings that reorder the obvious plan.

**a. The singleton is not the problem it appears to be.** `PlayerManager.shared`
is referenced **zero times** inside `Sources/`. The library's own logic is
already instance-based; both backends are instantiable and hold no static state.
The singleton survives only through `private init` at
[PlayerManager.swift:432](../Sources/PlayerKit/PlayerManager.swift#L432) and 26
`= .shared` default arguments — 21 of which are on internal types a host cannot
see. **Making `init` public is a one-line change that breaks nothing.** The real
work is arbitrating five process-global resources that currently have
last-writer-wins semantics.

**b. The thing actually blocking iOS adoption is probably the API, not the
architecture.** A host application **cannot read whether the player is playing.**
`isPlaying`, `duration`, `isBuffering` and `availableAudioTracks` are all
`internal` ([PlayerManager.swift:236-268](../Sources/PlayerKit/PlayerManager.swift#L236)).
There is no configuration type in the package at all. 305 declarations are
`public`, but the *deliberate* surface is perhaps 60 symbols and the rest is
leakage. The `Player.playerManager` escape hatch exists precisely because the
facade cannot do the job. A library you cannot ask "are you playing?" is not a
library you promote to primary.

**c. There is no background or lock-screen support whatsoever.** `grep` for
`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, `scenePhase` and
`didEnterBackground` returns **zero hits across ~23,000 lines**. No now-playing
metadata, no lock-screen controls, no remote commands, no background transition
handling. For a primary video player this is table stakes, and it is missing
entirely.

**d. Live TV is greenfield, and last week's live-seek fix is one layer of four.**
There is no channel, EPG, programme or DVR concept anywhere. And the recent fix
to `PlayerManager.seek` did not reach its callers: the slider still binds
`0...max(duration, 0.01)`
([PlaybackSliderView.swift:47](../Sources/PlayerKit/UI%20Controls/Views/PlaybackSliderView.swift#L47)),
so on live the scrubber range is `0...0.01`; `scrubForward`/`scrubBackward`
([PlayerManager.swift:1321](../Sources/PlayerKit/PlayerManager.swift#L1321))
bypass the clamp entirely; and
[GestureManager.swift:201](../Sources/PlayerKit/Managers/GestureManager.swift#L201)
clamps with `min(duration, …)`, which on live clamps to zero — double-tap skip
jumps to the start. **Live seeking does not work end-to-end today.**

### Corrections to previously reported figures

| Claim | Corrected |
|---|---|
| 213 strict-concurrency diagnostics | **417** unique across macOS *and* iOS. The 213 was the macOS slice, which compiles no UIKit, no VLCKit-iOS, no GoogleCast. |
| 3 skipped backend-switch tests | **4**, plus a 5th desktop-VLC skip ([PlayerKitTests.swift:51,80,107,142,230](../Tests/PlayerKitTests/PlayerKitTests.swift#L51)). |
| "Live seeking fixed" | Fixed at the manager guard only. Three downstream layers still assume VOD. |
| "One VLC backend" | **Two, on different major versions of VLC** — iOS links VLCKit 4; macOS hand-binds libvlc 3 and explicitly refuses other majors. |

### A defect in last week's fix

`PlayerManager.tearDown()`
([PlayerManager.swift:3685](../Sources/PlayerKit/PlayerManager.swift#L3685)),
added during the audit pass and called from `PlayerView.onDisappear`,
unconditionally calls `AudioSessionManager.shared.deactivateAudioSession()`,
`PlaybackWakeLockCoordinator.shared.setPlaybackActive(false)` and
`GameControllerManager.shared.releaseControllerHandlers()`. That is correct for
one player and **actively wrong for two**: dismissing an inline trailer would
deactivate the audio session out from under the main player. This must be
refcounted before any multi-instance work ships. It is not a bug today, because
multiple instances are impossible today.

## 3. Phases

Each phase states its exit criterion as something checkable.

### Phase 0 — Consolidate and stabilise the pipeline · ~4–5 weeks

*Start immediately. Independent of every other decision.*

Nothing else is safe while three divergent copies exist: this repo, the GitLab
copy iTV iOS consumes, and the local copy iTV macOS uses. Every workstream below
independently concluded that landing changes into one copy and hand-merging into
two others will not survive.

- **Fork reconciliation.** Requires a human-supplied dossier (see §6); cannot be
  sized without it. **[unverified — no GitLab access from this repo; the only
  remote configured is `github.com/jakhongir97/PlayerKit`]**
- **Fix `Package.swift`.** The manifest picks its dependency graph from
  `FileManager.default.fileExists("Frameworks/VLCKit.xcframework")` at evaluation
  time. This is worse than non-reproducible: combined with
  `#if canImport(VLCKit)` it decides *which of two entirely different macOS VLC
  backends compiles*, and the `public typealias VLCPlayerWrapper` makes that a
  public API difference. CI has only ever built one of the two configurations.
- **Artifact supply chain.** VLCKit and GoogleCast resolve from release assets on
  a personal GitHub account even when the package is consumed from GitLab.
- **CI matrix** on whichever host becomes canonical; **repo hygiene**, including
  the 572 KB of Dubber `.mp4` resources still shipping in every consumer bundle
  for a feature that is switched off.

**Exit:** one repository both iTV apps build from; CI builds and tests every
supported platform *and both VLC configurations*; a clean `swift package resolve`
produces the same graph on any machine.

### Phase 1 — Make it adoptable · ~6–8 weeks

*This is the phase that lets iTV promote PlayerKit to primary on iOS. It is
mostly API and platform integration, not architecture.*

- **Expose playback state.** Promote `isPlaying`, `duration`, `isBuffering`,
  track lists to public read-only. Add the missing `mute`, autoplay control, and
  track enumeration.
- **Introduce `PlayerConfiguration`.** There is no configuration type today.
- **Background, lock screen, remote commands.** `MPNowPlayingInfoCenter`,
  `MPRemoteCommandCenter`, background audio session handling, scene-phase
  transitions. Entirely absent today.
- **Fix live end-to-end** — slider range, scrub paths, gesture clamping — so
  finding (d) is closed at every layer.
- **Error and recovery UX.** A signed-URL refresh hook, retry policy, and a
  user-visible error state. Today a mid-stream 403 has no recovery path.
- **Narrow the accidental API** and start the deprecation clock on what has to go.

**Exit:** iTV iOS can drive every playback surface it needs through public API
without reaching into `Player.playerManager`; audio continues in background with
working lock-screen controls; a live stream is watchable, scrubbable within its
DVR window, and recoverable after a network drop.

### Phase 2 — Foundations: isolation and instances · ~8–10 weeks

*Two workstreams that must run in this order; each investigation independently
said so.*

1. **`@MainActor` for the control plane.** Recommended firmly over
   actor-per-player: `AVPlayer`, `AVPlayerItem`, `AVPlayerLayer`, `UIView` and
   `NSView` are all `@MainActor` in the current SDK, so an actor-isolated wrapper
   would hop to main for essentially every property access. This also deletes the
   ~21 hand-written `Thread.isMainThread` prologues.
2. **Instantiable `PlayerManager` + resource arbitration.** `public init` is one
   line. The work is a `PlayerKitSession` registry arbitrating the audio session,
   the wake lock (currently a boolean, not a refcount), the broadcast game-
   controller subject, cast callbacks and screen brightness — plus fixing
   `tearDown()` per §2.

**Exit:** `-strict-concurrency=complete` is clean or explicitly triaged; two
players can run simultaneously without corrupting each other's audio session,
wake lock or controller input; the 4 skipped backend-switch tests run.

### Phase 3 — The playback timeline model · ~8–10 weeks

The load-bearing modelling work. A timeline abstraction with VOD, live-with-DVR,
live-without-seek and short-form as first-class shapes.

> **Do not add a `.liveChannel` case to `PlayerContentType` and branch on it.**
> That enum is already consulted from six sites asking four different questions.
> A third case makes the sixth site ask a fifth question. This is precisely how
> the Dubber code grew to ~1,900 lines inside `PlayerManager`.

**Exit:** every timeline consumer — slider, gestures, scrub, diagnostics — reads
the model rather than `duration`; a live stream and a VOD asset drive the same
code paths with different timeline shapes.

### Phase 4 — Composable chrome and theming · ~10–12 weeks

Smaller than it looks: of ~6,400 lines under `UI Controls/`, 2,244 are macOS-only
diagnostics and 1,437 are disabled Dubber views. The chrome actually needing
restructure is ~2,245 lines across 36 mostly-tiny files.

Control-slot protocol, per-content-kind chrome profiles, a theme seam, inline
(non-fullscreen) mode for trailers, and the observation rework that stops 18
views re-rendering at 2 Hz.

**Exit:** TV, VOD and inline-trailer chrome differ without `if contentType ==`
branches; an integrator restyles without forking; inline playback works in a
scroll view.

### Phase 5 — Live TV channels · ~12 weeks

*Only after Phases 3 and 4.* Channel model and switching, programme boundaries,
live-specific chrome, broadcast track handling, DVR scrubbing. Preloaded zapping
requires Phase 2.

**tvOS is a separate ~6–8 week option**, not included above — see §6.

### Phase 6 — Open-source readiness · ~8–10 weeks

Public API review, DocC, sample app, migration guides, and the licensing work in
§5. Not startable until the API stops moving.

## 4. Dependency graph

```
Phase 0 (consolidate) ──────────► everything
        │
        └─► Phase 1 (adoptable) ──► iTV iOS primary  ◄── the near-term goal
                    │
                    ├─► Phase 2a (@MainActor) ──► Phase 2b (instances)
                    │                                   │
                    │                                   ├─► inline trailers (feed)
                    │                                   └─► channel preload
                    │
                    └─► Phase 3 (timeline) ──┬─► Phase 4 (chrome) ──► Phase 5 (TV)
                                             └─────────────────────────► ▲
Backend parity ─── threads through 3 and 5 ──────────────────────────────┘
Phase 6 (OSS) ◄── after the API stops moving
```

**Genuinely parallel:** Phase 0 infrastructure runs alongside Phase 1. Backend
parity can start any time after Phase 0. Localization and accessibility can run
as a continuous track rather than a phase.

**Hard blockers:** Phase 2b needs 2a (or expect rework). Phase 5 needs 3 and 4.
Feed-of-N trailers need 2b.

## 5. Backend strategy — a straight answer

**VLC is a fallback, not a peer. Stop implying otherwise in the API.**

Peer parity is not expensive, it is *impossible*. VLC cannot do FairPlay (no CDM
path on iOS), cannot do AirPlay video, cannot report a buffered range, and cannot
feed the AVMetrics-based diagnostics. Those cells are permanently red at any
budget.

Recommendation: a declared-capability model so the UI hides what a backend cannot
do instead of offering controls that silently no-op — which is what shipped — and
move the backend picker behind a debug flag. Also resolve that "the VLC backend"
is currently two backends on different major versions of VLC.

**Licensing needs a lawyer, not an engineer.** VLCKit is LGPL and is redistributed
as a binary from a personal GitHub release with no license file. The GoogleCast
redistribution question should go first — it is proprietary redistribution rather
than a compliance detail. **[unverified — requires legal review]**

## 6. Decisions needed before work starts

Ordered by how much they move the plan.

1. **The fork dossier.** Merge-base SHA, both-sides diffstat, the overlapping file
   list, GitLab's `Package.swift`, how iTV iOS pins the dependency, whether a
   `.gitlab-ci.yml` exists. *If the merge base is tag 1.1.0 with a handful of
   commits, reconciliation is ~3 days. If it is 1.0.8 with a year of iOS
   production fixes in `PlayerManager.swift`, it is 4+ weeks.*
2. **DRM.** Which key system do iTV's live channels use? If FairPlay, it is a
   prerequisite for Phase 5 and permanently excludes VLC for live. If the streams
   are clear HLS behind signed URLs, DRM drops out entirely (~14 days saved) and
   the URL-refresh hook becomes the most valuable item in Phase 1.
3. **Is Dubber coming back?** Deleting it is ~1 day and removes ~1,770 lines, 53
   of `PlayerManager`'s 74 concurrency diagnostics, 12 of 23 public `@Published`
   properties, and 572 KB of bundled video. Extracting it as a separate product
   is ~5 days. It is currently switched off with its tests skipped. **This is the
   cheapest large win available.**
4. **"TV player" — live channels, or tvOS?** This roadmap assumes live linear
   content. tvOS is a further ~6–8 weeks of focus-engine and UI work that would
   largely replace Phase 5's UI rather than extend it.
5. **Do the channels have a DVR window, and how long?** Pure-live collapses much
   of Phase 3's timeline work to "hide the slider, show a LIVE badge".
6. **Does either iTV app call PlayerKit off the main thread?** Half a day of
   grepping two codebases; moves the Phase 2a integration task between 1 and 8
   days and determines whether `@MainActor` is a source break for the host.
7. **Can the deployment target move to iOS 17?** iOS 15 rules out `@Observable`
   and forces hand-rolled Combine projections in Phase 4.

## 7. What we are not doing

- **Not** rewriting from scratch. The audit found specific, findable defects, not
  diffuse rot. The wrappers' observer hygiene and the diagnostics subsystem are
  genuinely good.
- **Not** pursuing AVPlayer/VLC peer parity (§5).
- **Not** building an EPG. Channel lists and programme metadata stay host data
  that PlayerKit renders. `configureExternalEpisodeNavigation`
  ([PlayerManager.swift:1004](../Sources/PlayerKit/PlayerManager.swift#L1004)) is
  the right precedent. Without this boundary, scope expands indefinitely.
- **Not** shipping tvOS unless §6.4 says so.
- **Not** open-sourcing before the API settles. Publishing an API mid-migration
  buys the deprecation burden without the adoption benefit.
- **Not** keeping the macOS `dlopen`-libvlc backend if iTV macOS must be sandboxed
  — sandboxing already makes it non-functional.

## 8. First two weeks

Concrete, ordered, mostly unblocked.

1. **Request the fork dossier** (§6.1). Everything waits on it; ask today.
2. **Answer the Dubber question** (§6.3). One conversation; unlocks the single
   largest cheap reduction in the codebase.
3. **Delete dead code.** `CustomSlider.swift` has zero references anywhere.
4. **Fix live end-to-end** — slider range, `scrubForward`/`scrubBackward`,
   gesture clamping. Small, contained, and closes a defect that is live today.
5. **Refcount the global resources** in `tearDown()` (§2), before anything makes
   multiple instances possible.
6. **Promote the read-only state API** — `isPlaying`, `duration`, `isBuffering`.
   Additive, non-breaking, and probably unblocks iTV iOS immediately.
7. **Ten minutes on a device**: confirm whether the volume/brightness swipe fires
   at all. [GestureView.swift:12-14](../Sources/PlayerKit/UI%20Controls/Views/GestureView.swift#L12)
   chains three `.gesture()` modifiers on one view; this cannot be settled by
   reading.
8. **Turn on `-strict-concurrency` as warnings** in `Package.swift` to stop the
   417 growing while Phase 2 is scheduled.

## 9. Effort summary

| Phase | Weeks | Confidence |
|---|---:|---|
| 0 · Consolidate | 4–5 | medium — reconciliation unsized |
| 1 · Adoptable | 6–8 | medium |
| 2 · Isolation + instances | 8–10 | medium |
| 3 · Timeline model | 8–10 | high |
| 4 · Chrome + theming | 10–12 | medium |
| 5 · Live TV | 12 | medium |
| 6 · OSS readiness | 8–10 | medium |
| **Total** | **56–67** | one engineer |

Plus optional: tvOS ~6–8 weeks; DRM/FairPlay ~14 days if required.

Read that as **13–16 months for one engineer**, or roughly **6–8 months with
three** on the parallel tracks in §4 — *if* fork reconciliation lands at the
optimistic end. The near-term goal (iTV iOS primary) is **Phases 0–1 only:
10–13 weeks**, and that is the number worth planning around first.

These are estimates by engineers who read the code but have not shipped it. Apply
your own multiplier.
