# PlayerKit Roadmap

**Status:** historical planning baseline · **Basis:** commit `1fe0a49` on branch
`audit-fixes`, updated after Sprint 1 (`f26cc55`…`7921d5b`) and the August 2026
remediation pass · **Method:** nine parallel code investigations against this
repository, plus a prior full-codebase audit. Claims that could not be verified
from this repository are marked **[unverified]**.

> The phase estimates below describe the broader reusable/open-source library.
> They do not govern the current iTV delivery. The active, scoped execution plan
> is [iTV primary-player 30-day plan](ITV_PRIMARY_PLAYER_30_DAY_PLAN.md); its
> release gates come from the [Standard vs PlayerKit parity audit](ITV_STANDARD_VS_PLAYERKIT_PARITY_AUDIT.md).

> **August 2026 status.** The control plane is now main-actor isolated; the
> duplicate controller subscriptions and host-handler restoration defects are
> fixed; playback state setters are read-only outside the module; empty queues,
> stopped-player replay, stale async callbacks, Cast handoff failures, PiP
> restoration, capture shielding, gesture teardown and accessibility defects
> have regression coverage. Google Cast now resolves from Google's official
> archive. The custom VLCKit binary remains a release blocker until its source,
> licenses, privacy manifest, signature and reproducible-build evidence exist.
> The phase estimates below are retained as historical planning context rather
> than current defect status.

## Current execution status — 3 August 2026

The August hardening pass closes the actionable playback-state, recovery,
adaptive-layout, accessibility and platform-input defects found by the code
audit and the 1,000-persona simulation. It does **not** complete the product
roadmap: repository consolidation, host integration, multi-instance ownership,
the timeline model, composable chrome, live-channel modelling and public-release
evidence remain separate milestones.

| Track | Current state | Remaining exit work |
|---|---|---|
| Phase 0 · Consolidate | **Partial / externally blocked** | CI and deterministic package resolution are in place. Obtain the GitLab fork dossier, choose the canonical repository, move both iTV apps to it, and close the custom VLCKit provenance/license/privacy/signature evidence gap. |
| Phase 1 · Adoptable | **Late-stage** | Public state, background/Now Playing, live-window seeking and stock recovery are done. Add `PlayerConfiguration`, narrow/deprecate accidental API, integrate both real iTV apps, and prove network-drop recovery on production-shaped streams. |
| Phase 2a · Main actor | **Complete** | The control plane is main-actor isolated and macOS/iOS Swift 6 builds pass. |
| Phase 2b · Instances | **Not started; foundations landed** | `PlayerManager` remains a singleton. Add the session registry, arbitrate Cast callbacks and screen brightness, expose instance creation, and run the currently skipped multi-backend/multi-player cases. |
| Phase 3 · Timeline model | **Not started** | Live/DVR clamping defects are fixed, but there is no first-class VOD/live-DVR/pure-live/short-form timeline model. |
| Phase 4 · Chrome + theming | **Preliminary hardening complete** | Compact widths, Dynamic Type, capability truth and accessibility are hardened. Control slots, content profiles, theming, inline trailer mode and observation fan-out remain. |
| Phase 5 · Live TV | **Not started** | Requires the Phase 3 timeline and Phase 4 chrome seams plus decisions on DRM, DVR and tvOS scope. |
| Phase 6 · OSS readiness | **Groundwork only / release blocked** | CI, release checks, security guidance and notices exist. API review, DocC, sample app, migration guides, legal review and reproducible VLCKit evidence remain. |
| Continuous accessibility/localization | **Code pass complete; validation open** | Run VoiceOver, Voice Control, Switch Control, capture, PiP, AirPlay, Cast, brightness/volume and VLC paused-switch checks on physical devices. Supply target locales and approved translations. |

### Next milestone: primary-player integration candidate

Work in this order:

1. Resolve the two external Phase 0 blockers: the fork dossier/canonical repo and
   the custom VLCKit release evidence.
2. Run the physical-device matrix in `RELEASE.md` and integrate the package into
   both iTV apps across movie, episode, live/DVR and background playback.
3. Close Phase 1 with `PlayerConfiguration` and a deliberate public-API review;
   do not add more one-off manager flags while that configuration seam is open.
4. Start Phase 2b only after the host integration proves simultaneous players
   are a real requirement; otherwise keep the singleton and proceed to the
   Phase 3 timeline model.

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
`isPlaying`, `duration`, `isBuffering` and `availableAudioTracks` were all
`internal` ([PlayerManager.swift:236-269](../Sources/PlayerKit/PlayerManager.swift#L236);
note that range is not homogeneous — it also holds 5 already-public properties
and 6 UI-chrome ones that must not be promoted). Sprint 1 promoted the
read-only playback state; the rest of this finding stands. There is no
configuration type in the package at all. 305 declarations are
`public`, but the *deliberate* surface is perhaps 60 symbols and the rest is
leakage. The `Player.playerManager` escape hatch exists precisely because the
facade cannot do the job. A library you cannot ask "are you playing?" is not a
library you promote to primary.

**c. There was no background or lock-screen support whatsoever.** `grep` for
`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, `scenePhase` and
`didEnterBackground` returned **zero hits across ~23,000 lines**. For a primary
video player this is table stakes, and it was missing entirely.

> **Closed.** `NowPlayingCoordinator` publishes lock-screen / Control Center
> metadata and installs the system transport controls, refcounted through
> `SharedResourceOwnership` like the other three process-global resources —
> `MPRemoteCommandCenter` is the same hazard as `GCController`, with the added
> trap that `removeTarget(nil)` would remove the *host's* targets, so every
> token is retained and removed individually. Both `isNowPlayingEnabled` and
> `isBackgroundPlaybackEnabled` are opt-in and default off. Background audio
> additionally needs `audio` in the host app's `UIBackgroundModes`, which a
> package cannot declare — documented in the README rather than worked around.

**d. Live TV is greenfield, and last week's live-seek fix was one layer of
five.** There is no channel, EPG, programme or DVR concept anywhere. The fix to
`PlayerManager.seek` did not reach its callers: the slider bound
`0...max(duration, 0.01)`, so on live the scrubber range was `0...0.01`;
`scrubForward`/`scrubBackward` bypassed the clamp entirely; `GestureManager`
clamped with `min(duration, …)`, which on live clamps to zero, so double-tap
skip jumped to the start; and — missed by the original survey — the VoiceOver
adjustable action bailed on `guard duration > 0`, so swipe-to-scrub was dead on
live too and `accessibilityValue` announced every position as "… of 00:00".

> **Closed.** All four callers now route through `PlayerManager.seekableRange`,
> with regression tests covering a live-shaped timeline (duration 0, non-nil
> seekable window) at each entry point. `GestureManager.durationProvider` is
> replaced by `seekableRangeProvider`. Where there is no seekable window the
> scrubber keeps its geometry but is disabled, rather than accepting drags that
> do nothing. The channel/EPG/DVR modelling in Phase 3 is untouched by this —
> only the clamping is fixed.

### Corrections to previously reported figures

| Claim | Corrected |
|---|---|
| 213 strict-concurrency diagnostics | **291** unique across macOS *and* iOS — 230 + 242, deduplicated by `file:line:col`. The 213 was the macOS slice, which compiles no UIKit, no VLCKit-iOS, no GoogleCast, *and* was itself undercounted. See the note below. |
| 3 skipped backend-switch tests | **4**, plus a 5th desktop-VLC skip ([PlayerKitTests.swift:51,80,107,142,230](../Tests/PlayerKitTests/PlayerKitTests.swift#L51)). |
| "Live seeking fixed" | Was fixed at the manager guard only; **four** downstream layers still assumed VOD, not three. All are fixed now — see (d). |
| "One VLC backend" | **Two, on different major versions of VLC** — iOS links VLCKit 4; macOS hand-binds libvlc 3 and explicitly refuses other majors. |

> **Counting the concurrency diagnostics.** An earlier figure of 417 appeared
> here and is not reproducible by any recipe; treat 291 as the number. The
> recipe that produced the low counts was
> `grep -oE '^/[^ ]+:[0-9]+:[0-9]+: warning:'`, whose `[^ ]+` cannot match a
> path containing a space — so it silently drops every diagnostic under
> `UI Controls`, `Player Controls` and `Media Options`, the three directories
> this repository is most known for. Use `'^/.+:[0-9]+:[0-9]+: warning:'`
> instead, and on iOS exclude the one clang warning from the vendored
> `VLCKit.framework` header, which is unfixable here and present regardless of
> the concurrency setting. Both slices must be measured: `swift build` sees
> only macOS.

### A defect in last week's fix

`PlayerManager.tearDown()`, added during the audit pass and called from
`PlayerView.onDisappear`, unconditionally deactivated the shared audio session,
dropped the wake lock and detached the process-wide `GCController` handlers.
That is correct for one player and **actively wrong for two**: dismissing an
inline trailer would deactivate the audio session out from under the main
player.

> **Closed.** All three are refcounted through `SharedResourceOwnership`, which
> tracks holders by object identity rather than as an integer count — both
> acquisition sites are deliberately idempotent (`configureIntegrationsIfNeeded`
> re-runs after a teardown, `tearDown()` is documented as safe to call
> repeatedly), so a counter would drift upwards on a repeated acquire and go
> negative on a repeated release. Each resource releases when the owner set
> empties *and* the resource is actually held, so a release by something that
> never acquired still works — `GameControllerManager.init` attaches handlers
> before anyone has acquired. `PlayerManager.init` remains private; making
> multiple instances possible is still Phase 2b.

### Defects found during Sprint 1 and closed in the remediation pass

**Duplicate game-controller subscriptions.** Session subscriptions are now
cancelled during teardown, repeated setup is idempotent, and the host's prior
controller handlers are restored instead of overwritten permanently.

**`currentTime` and `isMediaReady` were public read-write.** Both setters are now
module-internal, preventing hosts from fabricating readiness notifications or
desynchronizing the playhead. This is intentionally recorded as a source break
for the next major release.

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
- ~~**Fix `Package.swift`.**~~ *Done, and the finding was overstated.* The
  manifest picked its dependency graph from
  `FileManager.default.fileExists("Frameworks/VLCKit.xcframework")` — a
  `.gitignore`d path — so untracked state could change the resolved graph. That
  part was real and is fixed: selection is now an explicit
  `PLAYERKIT_LOCAL_VLCKIT=1` opt-in that fails loudly if the artifact is absent,
  so every clean checkout, CI runner and consumer resolves identically.

  VLCKit is now conditioned to iOS even when the explicit local override is
  used. The macOS implementation always uses its separate runtime bridge to a
  signature-checked `/Applications/VLC.app`; the preparation script no longer
  downloads or merges an unused macOS XCFramework slice.
- **Artifact supply chain.** Google Cast now resolves directly from Google's
  official 4.8.4 archive. VLCKit still resolves from a personal release asset
  and remains blocked from release by the evidence gaps recorded in
  `THIRD_PARTY_NOTICES.md`.
- **CI matrix** on whichever host becomes canonical; **repo hygiene**, including
  the Dubber `.mp4` resources that shipped in every consumer bundle for a
  feature that was switched off — done, 567 KB reclaimed.

**Exit:** one repository both iTV apps build from; CI builds and tests every
supported platform; a clean `swift package resolve` produces the same graph on
any machine.

### Phase 1 — Make it adoptable · ~6–8 weeks

*This is the phase that lets iTV promote PlayerKit to primary on iOS. It is
mostly API and platform integration, not architecture.*

- ~~**Expose playback state.**~~ *Done.* Sprint 1 promoted `isPlaying`,
  `isBuffering`, `duration`, `bufferedDuration`, the track lists and selections,
  `isPiPActive` and `isVideoEnded` to public read-only; `isMuted` and `autoplay`
  followed. Track *enumeration* was already public and this bullet was stale on
  that point — `selectAudioTrack(track:)` and `selectSubtitle(track:)` have
  always been public, and Sprint 1 made the lists they draw from public too.
- **Introduce `PlayerConfiguration`.** There is no configuration type today.
- ~~**Background, lock screen, remote commands.**~~ *Done* — now-playing
  metadata, the six remote commands, and an opt-in background-playback policy.
  Scene-phase transition handling is still open, but `AVPlayer`'s own
  background policy covers the case that mattered.
- ~~**Fix live end-to-end** — slider range, scrub paths, gesture clamping — so
  finding (d) is closed at every layer.~~ *Done in Sprint 1.* Note this closes
  the *clamping*, not live TV: the timeline model is still Phase 3 and channels
  are still Phase 5.
- ~~**Error and recovery UX.**~~ *Done for the stock player.* Terminal failures
  now present sanitized Retry/Close UI, recoverable external-playback failures
  remain non-blocking, and an optional async hook lets the host refresh a
  signed URL before retry. Automatic retry/backoff policy remains host-owned.
- **Narrow the accidental API** and start the deprecation clock on what has to go.

**Exit:** iTV iOS can drive every playback surface it needs through public API
without reaching into `Player.playerManager`; audio continues in background with
working lock-screen controls; a live stream is watchable, scrubbable within its
DVR window, and recoverable after a network drop.

### Phase 2 — Foundations: isolation and instances · ~8–10 weeks

*Two workstreams that must run in this order; each investigation independently
said so.*

1. ~~**`@MainActor` for the control plane.**~~ **Completed in August 2026.** It
   was recommended firmly over
   actor-per-player: `AVPlayer`, `AVPlayerItem`, `AVPlayerLayer`, `UIView` and
   `NSView` are all `@MainActor` in the current SDK, so an actor-isolated wrapper
   would hop to main for essentially every property access. CI now includes a
   Swift 6 language-mode build so new isolation regressions fail the build.
2. **Instantiable `PlayerManager` + resource arbitration.** `public init` is one
   line. The work is a `PlayerKitSession` registry arbitrating the audio session,
   the wake lock, the broadcast game-controller subject, cast callbacks and
   screen brightness. Sprint 1 already refcounted the first three via
   `SharedResourceOwnership` and fixed `tearDown()` per §2, so what remains here
   is cast callbacks, screen brightness, and the registry that owns them. The
   duplicate controller-subscription defect noted in §2 is closed.

**Exit:** `-strict-concurrency=complete` is clean or explicitly triaged; two
players can run simultaneously without corrupting each other's audio session,
wake lock or controller input; the 4 skipped backend-switch tests run.

### Phase 3 — The playback timeline model · ~8–10 weeks

The load-bearing modelling work. A timeline abstraction with VOD, live-with-DVR,
live-without-seek and short-form as first-class shapes.

> **Do not add a `.liveChannel` case to `PlayerContentType` and branch on it.**
> That enum is already consulted from six sites asking four different questions.
> A third case makes the sixth site ask a fifth question. This is precisely how
> the Dubber code grew to 2,394 lines inside `PlayerManager` — 58% of the file
> — before it was removed.

**Exit:** every timeline consumer — slider, gestures, scrub, diagnostics — reads
the model rather than `duration`; a live stream and a VOD asset drive the same
code paths with different timeline shapes.

### Phase 4 — Composable chrome and theming · ~10–12 weeks

Smaller than it looks, and smaller still now the Dubber views are deleted: of
what remains under `UI Controls/`, 2,244 lines are macOS-only diagnostics. The
chrome actually needing restructure is ~2,245 lines across 36 mostly-tiny
files.

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
3. ~~**Is Dubber coming back?**~~ **Answered: no — removed.** The actual
   figures were larger than estimated here: 4,458 lines deleted rather than
   ~1,770, 80 of `PlayerManager`'s 121 concurrency diagnostics rather than 53 of
   74, and 567 KB of bundled video. `PlayerManager` fell from 4,075 lines to
   1,681 — Dubber was 58% of it, not the ~1,900 lines estimated in §3 below.
   Combined complete-concurrency diagnostics fell from 291 to 202. This was the
   cheapest large win available, and it is taken.
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

Concrete, ordered, mostly unblocked. Items 3–6 and 8 landed in Sprint 1; 1, 2
and 7 still need a human and are the critical path.

1. ☐ **Request the fork dossier** (§6.1). Everything waits on it; ask today.
   Still outstanding — this repository's only remote is
   `github.com/jakhongir97/PlayerKit`, so the GitLab copy cannot be inspected
   from here at all.
2. ☑ **Answer the Dubber question** (§6.3). Answered: not coming back. Removed
   in full — see §6.3 for what it actually cost. Source-breaking for any host
   still calling the dub API, though never behaviour-breaking, since the feature
   flag already made every entry point a no-op.
3. ☑ **Delete dead code.** `CustomSlider.swift` had zero references anywhere and
   is gone.
4. ☑ **Fix live end-to-end** — slider range, `scrubForward`/`scrubBackward`,
   gesture clamping, *and* the VoiceOver adjustable action, which the original
   survey missed. See §2(d).
5. ☑ **Refcount the global resources** in `tearDown()`. See §2.
6. ☑ **Promote the read-only state API.** `isPlaying`, `isBuffering`,
   `duration`, `bufferedDuration`, the four track properties, plus `isPiPActive`
   and `isVideoEnded`, all as `public internal(set)`. `TrackInfo` gained
   `Identifiable`/`Equatable`/`Hashable`/`Sendable`, without which the track
   lists are visible but unusable from a host.
7. ☑ **The gesture layer was rewritten, and the writes were the real bug.**
   The arbitration suspicion was correct but minor; the reason users reported
   that "swipes do nothing" was three separate defects underneath it.
   `FeedbackView` had been deleted with nothing replacing it, so volume and
   brightness produced *no on-screen feedback whatsoever*. The swipe region was
   the middle third of the height intersected with the outer thirds of the
   width — about a fifth of the surface — while taps used a different partition
   entirely, so the two disagreed between x=0.33w and x=0.40w. And the volume
   write went through an `MPVolumeView` that was never added to a view
   hierarchy, which reaches nothing *and* leaves iOS drawing its own HUD over
   the video.

   The layer is now `Sources/PlayerKit/Gestures/`: a `TouchClassifier` that
   resolves a touch once at the slop threshold and owns it to completion, a
   `TapSeekMachine` extracted from the old manager with seven correctness
   fixes, effectors behind `OutputLevelControlling` with real iOS *and* macOS
   implementations, and a UIKit/AppKit touch host that receives the
   `touchesCancelled` a `DragGesture` never delivered. One `GestureGeometry`
   answers "where am I" for the classifier, the HUD, the affordance and the
   coach, so a hint can no longer point at a region the router does not honour.

   Still worth ten minutes on a device: the haptic grammar, the brightness
   two-segment mapping against real auto-brightness, and VLCKit's volume scale.
8. ☑ **Turn on `-strict-concurrency` as warnings** in `Package.swift` to stop
   the 291 growing while Phase 2 is scheduled. Verified against a real consumer
   package that `swiftSettings` do not inherit, so a host sees no new
   diagnostics in its own code.

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
