# iTV Standard Player vs PlayerKit parity audit

**Audit snapshot:** 3 August 2026

**Repositories:** `PlayerKit` and sibling `../itv-ios` on `codex/itv-playerkit-month1`

**Decision scope:** iTV iOS production replacement. tvOS and Reels are reported
because they affect the phrase “replace totally”, but they are not hidden inside
the one-month iOS VOD scope.

## Executive decision

PlayerKit is **not safe to make the global production default today**, and the
Standard implementation is **not removable today**. The current candidate does
compile inside iTV and is much closer on VOD/episode fundamentals than the old
“Test Player”, but compilation does not prove the production contract.

The shortest credible one-month outcome is:

1. PlayerKit becomes the measured, rollback-safe default for iOS movie, trailer,
   and episode cohorts.
2. Offline, generic live, and linear TV gain PlayerKit-capable routes behind
   flags while the existing iTV product shells remain.
3. Standard stays available until a sustained 100% non-inferiority gate. Its
   deletion is a later, small, separately reviewed change.

“Perfect total replacement in one month” is not an engineering claim this audit
can support if it means iOS VOD + offline + live + TV + tvOS + deletion with no
production measurement. The calendar risk is not mainly writing the engine; it
is proving ads, entitlement, persistence, devices, external routes, and QoE
against production-shaped assets. Four parallel lanes can remove the code gap in
one month. Evidence gates cannot honestly be skipped.

The current go/no-go status is:

| Decision | Status now | What must become true |
| --- | --- | --- |
| Make PlayerKit default for selectable iOS VOD | **NO-GO** | The new host-owned IMA and signed-URL candidates pass their production-shaped runtime matrices; VOD product gaps close; iOS 14 dependency policy is resolved; golden device and QoE gates pass. |
| Route every current iOS Standard entry to PlayerKit | **NO-GO** | The VOD gate passes, then offline `AVURLAsset`, catalog live, and TV transport routes are integrated and tested. |
| Remove `VideoPlayerViewController` | **NO-GO** | Every caller is migrated, a rollback cohort has reached sustained 100%, and production non-inferiority is demonstrated. |
| Remove embedded VersaPlayer sources | **NO-GO** | Removing the VOD controller is insufficient: `TVVideoPlayerViewController` still owns VersaPlayer. TV must migrate first. |
| Replace every iTV player on every Apple platform | **OUT OF MONTH SCOPE** | PlayerKit currently declares iOS/macOS, not tvOS; tvOS has a separate player. Reels is also a separate surface. |

## How to read this audit

This is a semantic diff, not a raw line diff. Standard is one app-owned UIKit
controller plus embedded VersaPlayer, IMA, Cast, persistence, and business
callbacks. PlayerKit is a reusable SwiftUI library with an iTV adapter. Comparing
filenames would miss most regressions; the tables compare the user and business
contract at each production route.

Statuses:

- **Ready-code** — an equivalent implementation exists, but the route still
  needs runtime/device proof before a no-regression claim.
- **Partial** — useful code exists but some production behavior, host wiring, or
  proof is missing.
- **Missing** — no equivalent exists on the audited path.
- **Blocked** — implementation or proof depends on an unresolved product,
  dependency, asset, or device decision.

Gate labels:

- **D** — blocks PlayerKit becoming the default for selectable VOD.
- **R** — blocks routing every current iOS Standard surface to PlayerKit.
- **X** — blocks deleting Standard/VersaPlayer.
- **T** — blocks the broader all-platform “total replacement” claim.

Change labels:

- **Existing** — present in the PlayerKit/iTV `HEAD` baseline before this month's
  uncommitted candidate work.
- **Candidate** — present only in the current worktree diff and not yet a released
  PlayerKit/iTV production behavior.
- **Standard** — current default implementation, not modified by this audit.

## Production ownership and route diff

The default is unambiguous in code. `UserDefaults.getPlayerType()` falls back to
`PlayerTypes.old`, whose label is “Standard Player”
(`../itv-ios/Shared/Extensions/UserDefaults.swift:392-394` and
`../itv-ios/Shared/Models/Player/PlayerType.swift:19-24`). Git history traces the
VOD controller to 1 February 2022 (136 commits following the file) and the TV
controller to 28 February 2022 (78 commits). That longevity raises regression
risk; commit count itself is not proof of quality.

| Route / user flow | Current production owner and exact entry | PlayerKit candidate | Status / regression risk | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Movie/VOD fetched by IDs | `MainCoordinator.pushToVideoPlayerVC(paymentModuleId:itemId:fileId:...)` selects Standard or New by persisted setting (`MainCoordinator.swift:323-350`). Standard owns URL fetch, paywall, ads, playback, persistence, reports, sharing, and analytics. | `NewPlayerViewController` fetches through the same `FileViewModel`, maps metadata/resume/markers, hosts PlayerKit, gates ad-bearing content behind app-owned IMA, and refetches expired playback URLs. | **Partial, critical.** The two highest-risk code gaps now have candidate implementations, but ads/expiry have compile and deterministic-state evidence only; several product controls and all runtime proof remain open. | Run the IMA and expiry matrices, close the remaining D blockers, then canary this route only. | D, X |
| Direct `PlayerItem` movie/card/search route | The same setting selects Standard/New (`MainCoordinator.swift:385-411`). | Candidate maps a valid HTTP(S) item or refetches by IDs. Non-empty top-level or nested `adUrl` is normalized and held behind the same IMA gate; `thumbnailUrl` remains app metadata only. | **Partial, critical.** Silent preroll bypass is closed in candidate code; thumbnail/product parity and runtime proof remain open. | Prove ad success/no-fill/error/lifecycle for both direct and fetched items; add thumbnails and retry-expiry fixtures. | D, X |
| Trailer | Routed through the same selector with `.trailer`. Standard hides settings/episode behavior and applies trailer-specific resume (`VideoPlayerViewController.swift:230-233,987-1010`). | Candidate preserves trailer resume threshold/rewind, but configures PlayerKit as movie and exposes the generic control set. | **Partial, high.** UI/product policy regression. | Add a small host playback policy for hidden controls, speed/quality/share rules, and test trailer resume/end. | D, X |
| Episode from series/history/list | Same selector; Standard owns availability, ascending/descending navigation, previous-season fallback, end-to-next, and series sheet. | Candidate now has cancellation-safe async next/previous availability, sort direction, previous-season fallback, exact metadata and save-before-switch (`NewPlayerViewController.swift:367-707`). | **Partial, high.** Navigation is code-complete enough to test; series catalog sheet/round-trip is missing. | Add integration tests for rapid switching/stale responses and expose the existing iTV series catalog from the host overlay. | D, X |
| Download/offline from main coordinator | Always Standard with the downloaded `AVURLAsset` and `.download` (`MainCoordinator.swift:374-383`). | No route. Generic PlayerKit URL loading may handle a simple `file://`, but the current direct mapper accepts only HTTP(S) and cannot preserve an app-supplied `AVURLAsset`/resource loader. | **Missing, critical.** Offline playback and Core Data progress would regress. | Accept a local/asset source without inventing a new download system; route behind a flag; preserve offline Core Data and airplane-mode behavior. | R, X |
| Download list | Always constructs Standard with `AVURLAsset` (`DownloadListViewController.swift:107-115`). | No route. | **Missing, critical.** A second caller must be migrated; changing only MainCoordinator is insufficient. | Consolidate both offline entries onto the same tested adapter. | R, X |
| Generic catalog live/stream | `StreamDetailViewController` creates a live `PlayerItem`, then `CatalogCoordinator` always constructs Standard with no player toggle (`StreamDetailViewController.swift:86-90`; `CatalogCoordinator.swift:179-190`). | PlayerKit has seekable-range/live mechanics, but no app route or pure-live/DVR product policy. | **Missing integration, critical.** | Route under a flag; introduce only VOD / seekable-live / pure-live distinctions and a go-live action. | R, X |
| Linear TV, EPG, catch-up, channel switching | Three iOS constructors always open `TVPlayerViewController`: main/story/notification (`MainCoordinator.swift:353-366`), channel catalog (`ChannelCoordinator.swift:30-43`), and sport playback after its gate (`SportCoordinator.swift:202-219`). The shell owns channel auth/paywall, favorites, channel list, pagination, EPG, timeshift and URL changes; `TVVideoPlayerViewController` owns VersaPlayer, IMA, Cast, PiP, tracks/quality/reporting. | No PlayerKit route. Engine primitives exist, but PlayerKit must not absorb iTV EPG/business models. | **Missing integration, highest complexity.** Migrating only MainCoordinator would leave channel and sport entries on the old transport. | Put PlayerKit transport inside the shared existing TV shell so all three callers migrate together; preserve shell callbacks; test boundaries, clock skew, stale responses and 100 rapid zaps. | R, X |
| Reels | Separate `ReelsPlayerViewController`, not Standard/New. | Not in this replacement seam. | **Out of scope.** Replacing Standard does not replace Reels. | Keep separate unless product explicitly asks for consolidation. | T |
| tvOS | Separate target/controllers under `itv_tvOS`. | `Package.swift` declares iOS and macOS only; no tvOS platform/product validation. | **Missing / out of month scope.** | Run a separate tvOS product/remote/focus audit before claiming all-platform replacement. | T |

## Stop-ship blocker register

These are outcome blockers, not an estimate in vague months. Default cannot flip
while any applicable D blocker is red.

| ID | Blocker and evidence | Consequence | Smallest closure / proof | Gate |
| --- | --- | --- | --- | --- |
| B1 | **IMA moved from a missing-code blocker to an unproved candidate.** `NewPlayerViewController` now holds each ad-bearing item behind a generation-keyed app-owned gate, owns IMA loader/manager/playhead and secure overlay, rejects stale callbacks, pauses across covered/background states, fails open only after an IMA result or a 15-second foreground timeout, and releases content exactly once. A pure Swift reducer check covers stale/duplicate/exit transitions. | The previous silent ad bypass is closed in code, but a real SDK/tag/runtime mismatch could still regress revenue, lifecycle, accessibility or playback. VMAP post-roll is deliberately not claimed: Standard never calls `contentComplete`, and episode auto-next needs a product handoff before adding it. | Run preroll success, no-fill, load/play error, timeout, background/foreground, covered navigation, episode switch and teardown using real test tags. Confirm whether post-roll inventory exists; if it does, add completion deferral before claiming full VMAP. | D, R, X |
| B2 | **The source platform says iOS 14, but shipped binary dependencies do not.** `Package.swift:43-58` now declares iOS 14. `vtool` reports Google Cast 4.8.4 arm64 `minos 15.0`; iTV IMA 3.28.10 arm64 also `minos 15.0`; VLCKit arm64 reports iOS 9.0. iTV target settings include 14.0. | A successful compile cannot establish launch/runtime support on iOS 14. | Product-data decision: prove the existing combination on a real iOS 14 device, select compatible binaries, weak/isolate unavailable features safely, or raise the app minimum deliberately. | D, R, X |
| B3 | **Signed/expired URL refresh is wired in candidate code but lacks service proof.** iTV now owns `PlayerManager.onPlaybackRetryRequested`, refetches the current movie/file through `FileViewModel`, validates response/status/item identity, rejects stale/unchanged URLs, preserves all PlayerKit metadata, and lets PlayerManager perform one reload at the current position. Owner, cancellation, generation, exit and covered-navigation guards prevent late autoplay. | The stale-URL loop is closed structurally, but actual gateway 401/403/expiry/auth/network behavior has not run. | Execute an expiring signed-stream fixture plus 401, 403, unchanged URL, payment 402, network loss, dismissal and episode-switch races; retain sanitized logs proving one refetch and one reload. | D |
| B4 | **No current runtime proof.** PlayerKit unit/compile and current iTV simulator compile are green, but the simulator remained shut down. | Playback, layout, lifecycle and framework errors remain possible despite compilation. | Boot simulator; run movie/trailer/episode golden flows on production-shaped fixtures; archive screenshots/logs and one small automated host smoke. | D |
| B5 | **No physical-device/system integration proof.** PiP, Cast, AirPlay, interruption, background audio, route changes, capture and assistive technologies depend on hardware/system services. | “No regression” cannot be claimed for high-risk OS integrations. | Execute the named supported iPhone/iPad/iOS matrix, including real Cast/AirPlay receivers and iOS 14 policy resolution. | D, R, X |
| B6 | **VOD UI/product parity gaps remain, but rates and quality now have candidate implementations.** WebVTT scrub thumbnails, issue reporting, series catalog, trailer policy and full approved RU/UZ copy are still absent. PlayerKit now exposes all eight Standard rates and an Auto/Maximum/Optimal/Minimum adaptive-cap menu; iTV supplies sanitized, identity-guarded HLS master bitrates and localized menu copy. | The previous rate/quality code gaps are closed, but unrun manifests/layouts and the remaining product surfaces can still cause visible regression. | Runtime-test multi-variant/single/malformed/failed/stale manifests and layouts; then reuse host services for thumbnails/report/series/trailer and complete all PlayerStrings copy. | D, X |
| B7 | **QoE baseline, canary and rollback proof do not exist yet.** Candidate events exist, but iTV consumes only load for watch analytics and pause/completion/fatal for persistence. | Stability/optimization claims are opinions; rollout failure may be invisible. | Capture Standard and PlayerKit startup, start failure, fatal, stall and crash-free baselines by the same definitions; enable server cohort rollback. | D, X |
| B8 | **Offline routes bypass PlayerKit and require an `AVURLAsset` contract.** | Cannot replace all Standard routes or delete it. | Add local/asset input and offline progress parity; verify airplane mode, expiry and relaunch. | R, X |
| B9 | **Generic live and TV always bypass PlayerKit.** TV also owns IMA, EPG, entitlement, timeshift and channel state. | Cannot claim route completeness; VersaPlayer remains live. | Integrate PlayerKit only as transport under existing app shells; do not rewrite business UI. | R, X |
| B10 | **Release dependency state is not reproducible enough.** Candidate iTV uses a local `../PlayerKit` reference; production previously used 1.1.0. IMA is now pinned exactly to 3.28.10 instead of moving `main`, but VLCKit remains a checksum-pinned binary from a personal PlayerKit release (`Package.swift:32-40`). | The IMA drift risk is closed, but a clean release still cannot reproduce the local PlayerKit candidate and the supply-chain/license/privacy/signing review is incomplete. | Publish a reviewed PlayerKit version/commit; record vendor provenance, license, privacy manifest and signature/hash for every binary. | D, X |
| B11 | **Protected/header/FairPlay asset requirements are unconfirmed.** Public `PlayerItem` is URL-centric and has no explicit headers, resource-loader or DRM seam. | A protected production class could fail only after rollout. | App owner supplies a redacted asset inventory. If any active asset needs FairPlay/headers/resource loading, promote that exact contract into scope with a fixture. | D or R if present |

## Detailed capability diff

### VOD, trailer and episode playback

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| URL acquisition and authorization | App `FileViewModel` fetches URLs and calls `CheckAuthorization` on API errors. Standard reacts to the same delegate callbacks. | Candidate deliberately keeps URL/auth in iTV and uses the same view model. | **Ready-code**, runtime 200/401/402/invalid-data matrix open. | Add host integration tests with stubbed result shapes and one redacted service smoke. | D |
| Initial playback / teardown | Standard installs VersaPlayer after item resolution and owns dismissal cleanup. | Existing PlayerKit has AVPlayer load/play/teardown. Candidate now mounts a host-managed `PlayerView`, pauses for temporary child navigation, tears down only when leaving the player presentation, rejects late media/payment installation after exit, and cleans singleton callback ownership (`NewPlayerViewController.swift:98-149,221-289`). | **Ready-code after candidate lifecycle fix.** Compile and focused ownership checks are green; paid-next/back, double load, dismiss-during-load and playback-after-dismissal still need runtime proof. | Run presentation/dismiss/reopen plus “episode end -> paid next -> back”; assert terminal state is preserved temporarily and no audio/session/callback survives real dismissal. | D |
| Exact resume | Standard honors `exactStartPosition`, thresholds history, and rewinds non-trailers (`VideoPlayerViewController.swift:987-1010`). | Candidate maps the same exact position, trailer threshold and non-trailer rewind (`NewPlayerViewController.swift:853-864`). | **Ready-code**, edge fixtures open. | Test exact 0, below threshold, normal history, near end and trailer values. | D |
| Metadata / title art / Cast | Standard maps title/detail/poster and Cast URL. | Candidate maps title image, title, description, poster, Cast/external URL, content type and duration (`NewPlayerViewController.swift:296-310,692-707,830-850`). | **Ready-code**, receiver/runtime proof open. iOS 14 title art has a text fallback. | Golden metadata assertions plus Cast receiver inspection. | D |
| Exact intro/credits markers | Standard evaluates backend segments; credits can become next episode and the button pulses/auto-hides (`VideoPlayerViewController.swift:1137-1227`). | Candidate adds exact typed `PlayerSkipSegment` mapping and suppresses duration heuristics; focused tests exist. | **Partial.** Timing/target semantics are covered in unit tests; Standard's 10-second presentation/pulse behavior is not identical. | Device/UI test boundary times, overlap, episode credits, seek target and accessibility announcement; decide whether auto-hide is contract. | D |
| Episode next/previous/end | Standard handles order, availability, previous season and end-to-next (`VideoPlayerViewController.swift:832-985,1050-1111,1240-1242`). | Candidate adds async availability, stale request identity, previous-season fallback, save-before-switch and external episode navigation (`NewPlayerViewController.swift:367-707`). | **Partial, improved candidate.** No current app-level runtime/regression suite. | Stub asc/desc, first/last, missing file, paywall and 20 rapid switch cases. | D |
| Series catalog sheet | Standard exposes an app sheet and receives its delegate; coordinator assigns a delegate only when source is Standard (`MainCoordinator.swift:246-257`; `VideoPlayerViewController.swift:1410-1462`). | No PlayerKit/New equivalent. | **Missing.** | Add a host overlay/button that opens existing `SeriesCatalogViewController` and can request an episode switch through the same adapter. | D, X |
| Trailer product policy | Standard hides selected controls and avoids normal rewind semantics. | Resume semantics are mapped; generic movie controls remain visible. | **Partial.** | Add a simple host policy value; no trailer-specific engine abstraction. | D |
| Playback end behavior | Standard calls next action; movie delegates/channel contexts can differ. | PlayerKit emits completion and existing episode navigation, but product-specific movie/trailer end has no golden proof. | **Partial.** | Record expected end result for each type and test completion once, no replay/duplicate analytics. | D |

### Ads, entitlement, auth and purchase

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| IMA preroll | Standard owns IMA loader/manager/display/playhead; pauses content, resumes on completion/no-fill/error, and handles lifecycle (`VideoPlayerViewController.swift:1583-1761`). Standard's fresh failure path calls `play()` without installing the held item, so the candidate must preserve policy rather than copy that bug. | Candidate keeps all IMA types/models in iTV, not PlayerKit. A UUID gate holds direct, fetched and switched items; a secure accessible overlay, KVO-compatible playhead, lifecycle pause/resume, stale-callback guards and exact-once fail-open release are implemented. | **Ready-code, still stop-ship on runtime evidence.** Pure reducer/static checks are green; no real tag ran. Post-roll is explicitly outside claimed parity until inventory and auto-next policy are confirmed. | Execute the B1 matrix with real test tags and capture content-not-started assertions before every release condition. | D, R, X |
| VOD tariff/free/ADVOD/content purchase | Standard branches on `PaymentType`, opens tariff suggestion or content detail (`VideoPlayerViewController.swift:491-516`). | Candidate mirrors the same branch (`NewPlayerViewController.swift:781-815`). | **Ready-code**, runtime navigation/status matrix open. ADVOD still depends on B1. | Test every payment type and no-module/invalid payload; assert content never starts on 402. | D |
| Child restriction | Standard refuses payment path under child restriction. | Candidate uses the same `ChildProfileAccessPolicy` guard. | **Ready-code**, UI outcome open. | Verify restricted asset cannot play or open an inappropriate purchase screen. | D |
| Auth expiry | Both use `FileViewModel`/`CheckAuthorization`; bridge dismisses after auth state is consumed. | Same app ownership is retained, and manual PlayerKit recovery now asks the gateway for a fresh URL with current identity before reloading. | **Ready-code / runtime-red.** Initial auth and mid-play expiry remain unproved against the service. | Run initial 401, mid-play expiry, re-auth, cancel, payment and stale-response cases. | D |
| VPN/StoreKit subscription path | Standard implements `didRequireStoreKitSubscriptions`. | Candidate implements the same callback (`NewPlayerViewController.swift:730-733`). | **Ready-code**, device/store environment proof open. | Verify the exact service response opens StoreKit once and returns safely. | D |
| TV entitlement | `TVPlayerViewController` stores channel context and handles channel payment/tariff (`TVPlayerViewController.swift:190-235`). | No PlayerKit TV route. | **Missing integration.** | Preserve this shell unchanged while replacing only transport. | R, X |

### History, state and analytics

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Watch position / widget | Standard writes widget state, backend seconds and watch-history refresh; saves on pause and switches (`VideoPlayerViewController.swift:1013-1038,1273-1275`). | Candidate writes widget/backend/history on exit, PlayerKit pause/completion/fatal, and episode switches. Close funnels through one exit save, and its network write is no longer canceled when the controller deinitializes (`NewPlayerViewController.swift:117-128,263-273,345-367`; `VideoPlayerViewModel.swift:18-47`). | **Ready-code after candidate change**, runtime cadence/open interruption cases remain. The write is best effort rather than an offline-durable queue. | Assert values after pause, home/background, kill, close, fatal, completion and switch; add a durable sync queue only if measured offline delivery requires it. | D |
| Offline progress | Standard additionally writes Core Data and posts download update (`VideoPlayerViewController.swift:1023-1025`). | No offline route or equivalent write. | **Missing.** | Reuse the existing Core Data call from the offline host adapter. | R, X |
| Selected audio/subtitle/rate persistence | Standard sends selected languages and speed; carries preferences across episodes. | Existing PlayerKit exposes selections/rate and attempts episode persistence; candidate sends language/id and speed in `userViewsSet` (`NewPlayerViewController.swift:354-364`). | **Partial.** App-locale default selection and cross-episode manifest matching need fixtures. | Test relaunch and episode switch with reordered/absent/default/forced tracks. | D |
| Watch analytics | Standard sends AppsFlyer and Firebase watch events (`VideoPlayerViewController.swift:1124-1127`). | Candidate sends them on PlayerKit `.loadRequested` (`NewPlayerViewController.swift:262-294`). | **Partial.** Item reload/retry can duplicate load events; item context can be zero/stale if ordering changes. | Introduce a host session/item identity and assert exactly once per real item start, not per retry/reload. | D |
| QoE telemetry | Standard has no comparable typed lifecycle stream in this controller. | Candidate PlayerKit adds privacy-safe load/play/pause/ready/active-playback/stall/seek/fatal/completed/exited events (`PlayerQoEEvent.swift`). `playbackStarted` explicitly is not decoded-first-frame. iTV currently consumes only a subset. | **Partial, net improvement potential.** No dashboard, timings, item/session correlation or Standard baseline. | Add monotonic timestamps/session ID in host analytics, a real first-frame signal if required, and common dashboards/tolerances. | D, X |

### Tracks, speed, quality, thumbnails and controls

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Audio tracks | Standard enumerates Versa tracks, applies app-localization fallback and persists the choice across episodes (`VideoPlayerViewController.swift:760-835,1244-1254`). | Existing AVPlayer wrapper enumerates/selects media groups with an iOS 14 fallback; candidate persists selected ID/language. Default fallback follows device preferred languages rather than the app's selected locale. | **Partial.** | Supply host preferred language or map app locale; test HLS alternate/default/unknown-language and episode reorder. | D |
| Subtitles | Standard supports off/selection and persistence. | Existing PlayerKit supports off/selection and state. | **Ready-code**, forced/default/SDH and relaunch proof open. | Production-shaped manifests plus VoiceOver checks. | D |
| Playback rates | Standard exposes 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 (`VideoPlayerViewController.swift:273-280`). | Candidate PlayerKit exposes the same eight rates from one native SwiftUI menu list. Focused tests assert the set and verify 0.75/1.75 reach and survive backend replacement. | **Ready-code**, runtime menu/layout, pause/seek/item-switch and persistence proof remain. | Run the rate matrix on small phone/iPad and across a real episode switch. | D |
| Manual HLS quality | Standard derives variants and maps Auto/min/mid/max to `preferredPeakBitRate` (`VideoPlayerViewController.swift:1312-1398`), but its fallback parser misses normal `#EXT-X-STREAM-INF:BANDWIDTH` syntax, lacks stale-item guards and can silently do nothing on iOS 14. | Candidate fixes the host parser, filters positive values without logging signed URLs, probes only explicit `.m3u8` content after ad release, and generation/owner/URL-guards responses. PlayerKit sorts/deduplicates raw bitrates, retains the semantic selection across episodes, maps lower-median Optimal, hides single-rendition controls and applies an adaptive cap to current/new AVPlayer items. | **Ready-code / runtime-red.** Parser, policy, semantic remap and replacement-item checks pass; no real multi-variant fixture or menu interaction ran. Extensionless HLS intentionally stays Auto until the host supplies an explicit media-kind signal. | Run Auto/Max/Optimal/Min, single/malformed/failure, episode switch, stale result and signed refresh on a production-shaped HLS fixture. | D |
| WebVTT scrub thumbnails | Standard/Versa loads WebVTT, supports sprite cropping, cancellation, cue lookup and bounded caches (`VersaPlayerControls.swift:124,482-497,753-756,994-1320`). | No thumbnail/VTT implementation or bridge mapping. | **Missing, visible regression.** | Add one bounded loader/cache driven by the existing `thumbnailUrl`; test malformed VTT, sprites, cancellation, memory and offline/no-network. | D, X |
| Issue reporting | Standard fetches report choices and sends selected error (`VideoPlayerViewController.swift:519-529,1113-1122,1294-1353`). | No production issue-report action in PlayerKit/New. | **Missing.** | Keep service and presentation app-owned; expose a host action in PlayerKit's options or overlay. | D, X |
| Timestamp sharing | Standard constructs the app share URL with current seconds. | Candidate retains an app-owned accessible share button and timestamp (`NewPlayerViewController.swift:313-340`). | **Ready-code**, iPad popover/share-sheet runtime proof open. | Test URL, hidden controls, zero/NaN and iPad presentation. | D |
| Gestures / lock / rotation | Versa supports pinch, double-tap seek, long-press speed, vertical volume/brightness and orientation locking. | Existing PlayerKit has richer gesture routing, coach/HUD, lock notifications, scrub, aspect controls and focused tests; candidate connects app orientation ownership. | **Ready-code with likely UX improvement**, but touch conflict/haptics/real brightness need devices. | Run gesture conflict matrix on small iPhone/iPad with VoiceOver/Voice Control on and off. | D |

### Recovery, lifecycle and system integrations

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Playback failure UX | Standard's `playbackDidFailed` callback is empty (`VideoPlayerViewController.swift:1231-1234`). | Existing PlayerKit has safe blocking/non-blocking recovery UI, retry/close/end decisions and regression tests. Candidate iTV retry now refetches a fresh URL, preserves metadata and reloads once at the current position. | **Ready-code / improvement**, service/runtime proof remains B3. | Test transient/fatal/close/duplicate retry, expiry/payment/stale identity and sanitized user copy. | D |
| Automatic recovery/backoff | Standard does not provide a robust controller-level strategy. | PlayerKit recovery exists, but no app policy for retries/backoff/refetch. | **Partial.** | Define bounded retry policy around network vs authorization; never loop or bypass paywall. | D |
| PiP | Standard embeds native PiP and restoration/orientation handling (`VersaPlayerView.swift:198-345`). | Existing PlayerKit supports PiP. Candidate callback currently only returns whether the view has a window (`NewPlayerViewController.swift:255-261`); it does not re-present a dismissed controller. | **Partial, device-critical.** | Implement actual host restoration and test start, home, dismiss, return, item end and failure. | D, R |
| AirPlay | Standard has route picker/external playback behavior. | Existing PlayerKit supports AirPlay; candidate enables external playback. | **Ready-code**, real route/device/capture-policy proof open. | Test route connect/disconnect, seek, background, lock screen and protected-output policy. | D |
| Google Cast | Standard distinguishes buffered VOD vs live and sends metadata/start time (`VideoPlayerViewController.swift:1465-1580`). | Existing PlayerKit supports Cast metadata/session state, but always builds `.buffered` (`CastManager.swift:153-184`). | **Partial.** VOD receiver proof open; live semantics are wrong. | Verify current receiver/app ID for VOD; add explicit stream type before live routing; test disconnect/reconnect/error. | D for VOD, R for live |
| Background audio / Now Playing / remote commands | Standard app already declares background audio. | Existing PlayerKit supports opt-in background/Now Playing; candidate enables both (`NewPlayerViewController.swift:240-244`). Info.plist contains audio background mode and Cast Bonjour services. | **Ready-code**, interruption/route/command/history proof open. | Device-test phone calls/Siri/headphones/Control Center/lock screen and ensure teardown clears metadata. | D |
| Orientation / iPad / multitasking | Standard has years of app-owned rotation and layout behavior. | Candidate retains app orientation locking around PlayerKit; SwiftUI layout differs. | **Partial.** | Snapshot and interaction matrix across smallest phone, notched phone, iPad portrait/landscape/split view. | D |
| Singleton ownership | Standard controller owns a player instance. | PlayerKit uses `PlayerManager.shared`; candidate adds a callback owner UUID, host-managed view teardown, pause for child navigation, explicit teardown on true exit, and callback cleanup on deinit. | **Ready-code mitigation, architecture risk remains.** | Stress paid-next/back, sequential presentations, PiP restoration, rapid dismiss/reopen and any concurrent preview; prove stale controllers cannot receive events. | D |

### Offline, live and TV specifics

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Downloaded `AVURLAsset` | App passes the asset directly; this can preserve local/resource-loader configuration. | Public item is URL-centric; direct app mapper rejects non-HTTP(S). | **Missing contract.** | Accept an app-owned local asset/source or prove every download is a plain file URL; keep API minimal. | R, X |
| Pure live vs DVR | Standard hides VOD controls for live and exposes live-edge behavior. TV shell constructs catch-up/time URLs. | Existing PlayerKit has live seekable-range clamping/tests, but no first-class host policy or routed live UI. | **Partial engine, missing integration.** | One content/timeline policy with pure-live and seekable-live; all seek paths share the same range. | R, X |
| Live edge / go live | Standard delegates `playbackCheckLive` and `playbackBackToLive` (`VideoPlayerViewController.swift:1264-1270`). | No iTV PlayerKit go-live bridge. | **Missing.** | Expose current live-edge state and one host action; test moving windows. | R |
| EPG/timeshift/catch-up | Existing TV shell owns guide/current/previous/next, `{START_AT}`/time construction and selected guide. | No PlayerKit integration; these should remain app-owned. | **Missing integration, not a library rewrite.** | Adapt resolved URL + timeline mode into PlayerKit; leave EPG state in `TVPlayerViewController`. | R, X |
| Channel navigation/zapping | TV shell owns list, pagination, favorites, next/previous and stale channel identity. | No route. PlayerKit item-load cancellation must be validated. | **Missing integration.** | Add transport adapter, identity/cancellation, then a deterministic 100-zap stress check. | R, X |
| TV ads/tracks/quality/report | `TVVideoPlayerViewController` independently implements IMA, Cast, tracks, quality and reports (`TVVideoPlayerViewController.swift:49-152,789-990`). | VOD bridge work does not cover it. | **Missing.** | Reuse the same host seams after VOD proves them; do not create a second PlayerKit business layer. | R, X |

### Localization, accessibility, capture and security

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| English/Russian/Uzbek chrome | Standard uses app localization in many menus but also contains hard-coded strings (including Russian-only normal speed). | Candidate injects app-owned copy for quality, speed/normal, audio, subtitles, retry, close, buffering and exact markers; all new keys exist in EN/RU/UZ and the Russian quality typo is corrected. The remaining PlayerStrings defaults—including recovery, PiP/Cast, gesture and many accessibility sentences—are still English. | **Partial.** The new menu slice avoids mixed-language labels, but full approved RU/UZ copy and layout/plural proof remain a release blocker. | Add namespaced app copy for every rendered scalar/formatter, obtain native-language approval, then test truncation, VoiceOver and number grammar. | D |
| VoiceOver / Dynamic Type | Standard has UIKit controls but little code-level evidence of a complete audit. | Existing PlayerKit has labels, identifiers, accessibility actions/proxies, live slider semantics and regression tests. | **Ready-code / likely improvement**, physical screen-reader proof open. | Full VoiceOver traversal/action matrix at accessibility text sizes on phone/iPad. | D |
| Voice Control / Switch Control | No strong Standard automated evidence. | PlayerKit includes touch-routing/accessibility-aware behavior. | **Partial proof.** | Physical Voice Control names, Switch Control scan order and locked-player tests. | D |
| Screenshot/screen recording protection | Standard wraps rendering with `SnapshotSafeView` (`VideoPlayerViewController.swift:551`). | PlayerKit has a best-effort secure-text-field shield plus capture-state cover; candidate also wraps its hosting view in the app's `SnapshotSafeView` (`NewPlayerViewController.swift:217-230`). | **Ready-code, security proof open.** Secure canvas discovery is best effort and OS-sensitive. | Physical screenshot, recording, app switcher, mirroring, AirPlay and Cast matrix on every supported OS. | D, R |
| Privacy-safe telemetry | Standard analytics attaches content identifiers. | PlayerKit QoE enum deliberately carries no URL/title/token/user identifier; host adds context. | **Ready-code.** Host logging still needs review. | Assert logs/events never contain signed URL/query/header data. | D |
| DRM/request headers | Not explicit in audited VOD path; offline asset may hide resource loading. | No explicit public seam. | **Blocked on catalog inventory.** | Close B11; implement only a verified requirement. | D/R if present |

### Performance, stability, dependencies and operations

| Capability | Standard baseline | PlayerKit candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Startup time / first frame | No captured baseline in this audit. | QoE has load/ready/active playback, but active playback is not decoded first frame. | **Blocked on measurement.** | Add one monotonic first-frame measure, capture p50/p95 on identical assets/devices for both. | D, X |
| Rebuffering / failures | No common Standard dashboard evidence supplied. | PlayerKit emits stall start/end and fatal; host does not yet publish a comparison. | **Partial instrumentation.** | Common session definition and non-inferiority thresholds before canary. | D, X |
| CPU/memory/energy/leaks | No current Standard Instruments baseline. | PlayerKit has substantial unit/state coverage, but SwiftUI update cost, framework memory and long-session behavior are unmeasured on iOS. | **Blocked on profiles.** | Instruments launch/seek/menu/2-hour VOD and TV zap profiles; compare, fix measured hotspots only. | D for obvious regressions, X for removal |
| Automated library regression | N/A as app monolith. | Full PlayerKit `swift test` executes 321 tests with 5 environment skips and 0 failures; exact markers, quality policy/remapping, eight-rate menu/backend behavior, QoE reducer, strings, recovery and host teardown selection have focused tests. | **Good code evidence, not app proof.** Skips need explicit disposition. | Keep suite green; document every skip; add smallest iTV host tests for business seams. | D |
| iTV integration compile | Standard app is existing build target. | Final current candidate built `itv-new`, Debug, iPhone 16 Pro simulator in 23.8s after the host lifecycle change, with no bridge errors. | **Compile proof only.** Simulator stayed shut down. | Clean-checkout build plus booted runtime smoke. | D |
| iOS 14 source compatibility | Standard app target includes iOS 14. | PlayerKit source was lowered to iOS 14 with availability fallbacks and generic simulator/device slices compile. | **Source compile ready; binary runtime blocked by B2.** | Resolve vendor binary floor and run actual iOS 14 device launch/playback. | D, R |
| Dependency reproducibility | App previously resolved IMA from moving `main`; candidate pins it exactly to 3.28.10. | PlayerKit binary checksums are pinned; Google Cast is an official archive; VLCKit artifact provenance is project-owned/personal release. Candidate app still uses a local PlayerKit path. | **Partial / release blocker.** IMA drift is closed; PlayerKit publication and full binary provenance remain. | Publish immutable PlayerKit, then perform a clean-machine resolve/build/sign/privacy/license record. | D, X |
| Rollback | Persisted Standard/Test selector exists, but it is a local setting rather than proven server cohort rollback. | Candidate can coexist with Standard on selected VOD routes. | **Partial.** Routes that bypass toggle are unaffected; emergency remote control is unproved. | One server-controlled flag with instant fallback; rehearse during canary without App Store release. | D, X |

## What was already in PlayerKit vs what changed this month

This distinction prevents candidate work from being reported as established
production behavior.

| Area | Existing before current worktree | Current candidate change | Still not delivered |
| --- | --- | --- | --- |
| Playback engine | AVPlayer and iOS VLC backends; playback state/control, tracks, speed, queue, seek ranges, recovery UI. | iOS 14 availability fallbacks; persisted quality cap applied to AVPlayer items; recovery copy/safety refinements; opt-in host ownership of `PlayerView` teardown with a focused default/override test. | iTV runtime proof and DRM/header contract if required. |
| Product metadata | Title, description, poster, Cast/external URL, last position, episode index. | Exact typed skip segments added to `PlayerItem`. | Thumbnail VTT, ad contract, explicit content/timeline/control policy. |
| System integrations | PiP, AirPlay, Google Cast, background audio, Now Playing, remote commands, capture shield. | iOS 14-compatible UI fallbacks and additional localized/accessibility copy. | Real device proof; correct live Cast type; complete host PiP restoration. |
| UX/accessibility | SwiftUI controls, menus, gestures, lock, scrub, accessibility labels/actions and tests. | Injectable `PlayerStrings`; exact marker UI; iOS 14 visual fallbacks; all eight rates; accessible adaptive-quality menu with localized iTV tier labels. | Approved full RU/UZ injection, thumbnails, report/series actions and real quality/layout proof. |
| Observability | Internal diagnostics and state. | Public privacy-safe QoE lifecycle/stall/seek/fatal/completion stream with reducer tests. | Host session timing/dashboard, true first frame, common Standard baseline and rollout thresholds. |
| iTV adapter | Basic New player, close/share/history, simple URL fetch/episode switching, basic paywall and metadata mapping. | Local candidate pin; stale package-reference cleanup; exact resume/metadata/markers; robust entitlement and async episode navigation; callback ownership; host-managed pause/exit teardown; late-response rejection; single exit-progress write lifetime; PiP/background/Now Playing options; selected track/rate history; pause/end/fatal persistence; watch analytics/QoE bridge; deterministic app-owned IMA gate; identity-safe signed-URL refresh; stale-safe host quality discovery and localized tier injection. | Real ad/expiry/quality proof, thumbnails, report/series/trailer policy, full locales, offline/live/TV routes and runtime/device proof. |

## Verification ledger: compile proof is not runtime proof

### Verified in this audit/current work

| Evidence | Result | What it proves | What it does not prove |
| --- | --- | --- | --- |
| Full PlayerKit `swift test` | 321 executed, 5 skipped, 0 failed after the quality/rate slice. | Library logic in the active host environment; focused candidate contracts, including quality semantic remapping, all Standard rates and host-managed teardown selection, remain green. | iOS frameworks, real media, iTV business flows, skipped environments or devices. |
| App-owned IMA gate harness | `xcrun swiftc` compiled the pure gate plus assertion program; stale token, duplicate release, fail-open, direct-start, finish and exit checks passed. | The content-release reducer is deterministic and exact-once without needing the ad SDK. | IMA SDK callbacks, rendering, real VAST/VMAP tags, networking or lifecycle on a device. |
| Signed-URL bridge contract check | The repository static check passed after final wiring. It asserts owner/item/generation/cancellation guards, unchanged-URL rejection, full item-field preservation, one reload owner and completion paths. | The intended host safety invariants remain present in the compiled source. | Real service status/auth behavior or actual expiring media. |
| HLS quality host checks | The standalone master-playlist harness passes normal `BANDWIDTH`, `AVERAGE-BANDWIDTH`, quoted-codec, zero and media-tag cases. EN/RU/UZ property lists and the app-owned PlayerKit key contract pass. | The corrected parser and new menu-key inventory are deterministic; signed manifest fetches use a no-cache ephemeral session. | CDN behavior, extensionless HLS, real variants, menu layout or native-language approval. |
| Generic iOS Simulator PlayerKit build | Succeeded. | Candidate source compiles for simulator. | App launch/playback or iOS 14 runtime. |
| Generic iOS device PlayerKit build | Succeeded. | Candidate source/device slice can compile/link in that build context. | Installation, vendor binary load, signing, hardware/system behavior. |
| iTV Xcode simulator build | `itv-new`, Debug, iPhone 16 Pro simulator, succeeded in 23.8s after the host-managed teardown change. Subsequent generic Debug builds resolved the exact IMA lock and compiled/linked the final IMA, retry, quality, rate and localized-menu candidate for both arm64 and x86_64 with zero errors. | The audited adapter/API/app source compile together across both simulator architectures; the lockfile matches exact IMA 3.28.10. | Runtime; every installed simulator remained shut down and UI/media/SDK behavior was not exercised. |
| `vtool` on arm64 binaries | Cast 4.8.4: iOS 15.0; IMA 3.28.10: iOS 15.0; VLCKit: iOS 9.0. | The binary deployment metadata actually embedded in the inspected artifacts. | Whether an older/different vendor build is acceptable or whether product can raise the target. |
| Static route/capability audit | Every known Standard/New/TV/offline/catalog entry and requested capability category was traced. | Current ownership, bypasses, code gaps and smallest next actions. | Hidden server/catalog behavior, production frequency, actual QoE, unprovided DRM/header requirements. |

### Explicitly unverified and therefore still red

- No current PlayerKit iTV playback session was launched on a simulator.
- No iOS 14 physical device launch or playback was run.
- No production-shaped VOD/ad/episode/offline/live/DVR/TV fixture matrix ran.
- No real IMA success/no-fill/error/background flow ran through the new
  host-owned gate; only its deterministic reducer and compile path were checked.
- No real signed URL expiry/refetch flow ran; only structural/static and compile
  checks exist.
- No real multi-variant HLS quality switch, stale-manifest race or eight-rate UI
  matrix ran; only parser/policy/backend tests and compile evidence exist.
- No PiP, AirPlay, Cast, background interruption, route change, Now Playing,
  capture or assistive-technology physical matrix ran.
- No Standard-vs-PlayerKit p50/p95 startup, failure, stall, crash-free, memory,
  energy, leak or long-session comparison exists.
- No clean-checkout remote PlayerKit release resolution exists; the app currently
  points at a sibling local package.

## One-month audit-driven execution plan

The detailed daily board lives in
`docs/ITV_PRIMARY_PLAYER_30_DAY_PLAN.md`. This section is the blocker-ordered
critical path produced by this audit. Work proceeds in parallel lanes; a failed
gate stops rollout, not unrelated implementation.

### Week 1: make one VOD flow production-shaped

**Exit:** ad-bearing and non-ad movie flows work through the real iTV adapter;
expired URLs refresh; persistence is asserted; simulator runtime is green.

1. Ads lane: B1 host-owned IMA handoff and deterministic content installation.
2. Recovery lane: B3 signed URL refresh with cancellation/item identity.
3. Host contract lane: app tests for entitlement, resume, history/tracks/rate,
   analytics exactly-once and dismissal teardown.
4. Evidence lane: boot simulator immediately; capture Standard baseline and same
   PlayerKit golden movie rather than waiting for week 4.
5. Release lane: resolve B2 product decision and immutable dependency plan.

### Week 2: close visible VOD/episode regressions

**Exit:** movie, trailer and episode pass the golden matrix with Standard as an
instant fallback.

1. Runtime-prove the candidate Auto/Maximum/Optimal/Minimum menu and all eight rates.
2. Add bounded WebVTT/sprite thumbnails.
3. Reuse iTV report and series catalog surfaces through host actions.
4. Apply trailer control policy and inject complete English/Russian/Uzbek copy.
5. Prove rapid episode navigation, stale responses, previous season, paywall,
   marker boundaries, network loss and ad failure.
6. Publish common QoE session definitions and provisional non-inferiority
   thresholds from measured Standard data.

### Week 3: route completeness without rewriting product shells

**Exit:** offline, catalog live and TV transport can select PlayerKit behind
independent flags.

1. Accept downloaded/local assets and preserve offline Core Data/widget state.
2. Route generic pure-live/DVR with unified seek range and go-live behavior.
3. Put PlayerKit transport under existing TV EPG/channel/entitlement UI.
4. Reuse VOD ad/report/track/quality seams; correct live Cast/Now Playing.
5. Run airplane-mode, live-window, programme boundary, clock-skew, stale-response
   and 100-zap stress checks.

### Week 4: device proof and reversible rollout

**Exit:** a measured cohort uses PlayerKit by default; rollback is rehearsed and
instant. Standard removal receives a go/no-go, not an automatic deadline.

1. Run supported iPhone/iPad/iOS hardware, accessibility and external-route
   matrices.
2. Profile both players on the same assets for startup, CPU, memory, energy,
   leaks, stalls and two-hour stability.
3. Create a clean remote PlayerKit release pin; archive dependency provenance,
   build/test/device evidence and known limitations.
4. Roll out internal -> 1% -> 5% -> 25% -> 100% only while written tolerances
   remain green; rollback on any stop-ship condition.
5. After sustained 100%, remove the selector and Standard controller in a
   separate diff. Remove VersaPlayer only after TV no longer references it.

## Release and deletion gates

PlayerKit may become VOD default only when all of the following are evidenced:

- no ad obligation, entitlement, child restriction or protected-output bypass;
- every VOD type starts, seeks, resumes, completes and tears down correctly;
- history, widget, tracks, rate, sharing, reports and analytics persist exactly
  as defined across pause/background/relaunch/switch;
- startup success/time, fatal errors, rebuffering and crash-free sessions are
  non-inferior to Standard using written tolerances;
- PiP, AirPlay, Cast, background/interruption and capture pass real devices;
- English/Russian/Uzbek and supported assistive technologies pass phone/iPad;
- the selected iOS 14/minimum-OS policy is true for source and every embedded
  binary on an actual supported device;
- a clean checkout resolves immutable dependencies and builds the release;
- server rollback is exercised without an App Store update.

Standard may be deleted only after every route row is green, the 100% cohort is
sustained for the agreed observation window, and production metrics remain
inside tolerance. A date alone is never deletion evidence.

## Evidence map

Primary Standard sources:

- `../itv-ios/itv-new/Main/Player/VideoPlayer/View Controller/VideoPlayerViewController.swift`
- `../itv-ios/Shared/Classes/VersaPlayer/Classes/Source/VersaPlayerView.swift`
- `../itv-ios/Shared/Classes/VersaPlayer/Classes/Source/VersaPlayerControls/VersaPlayerControls.swift`
- `../itv-ios/itv-new/Main/Player/TVPlayer/TVPlayer/View Controller/TVPlayerViewController.swift`
- `../itv-ios/itv-new/Main/Player/TVPlayer/TVVideoPlayer/View Controller/TVVideoPlayerViewController.swift`
- `../itv-ios/itv-new/Main/MainCoordinator.swift`
- `../itv-ios/itv-new/Channel/ChannelCoordinator.swift`
- `../itv-ios/itv-new/Sport/SportCoordinator.swift`
- `../itv-ios/itv-new/Catalog/CatalogCoordinator.swift`
- `../itv-ios/itv-new/Library/Download/View Controller/DownloadListViewController.swift`

Primary PlayerKit/candidate sources:

- `Package.swift`
- `Sources/PlayerKit/Model/PlayerItem.swift`
- `Sources/PlayerKit/PlayerManager.swift`
- `Sources/PlayerKit/PlayerQoEEvent.swift`
- `Sources/PlayerKit/PlayerStrings.swift`
- `Sources/PlayerKit/AVPlayerWrapper.swift`
- `Sources/PlayerKit/Managers/CastManager.swift`
- `Sources/PlayerKit/UI Controls/Views/PlayerKitProtectedContentView.swift`
- `../itv-ios/itv-new/Main/Player/NewPlayer/NewPlayerViewController.swift`
- `../itv-ios/itv-new/Main/CardInfo/View Model/FileViewModel.swift`

Focused candidate tests include
`PlaybackQualityPolicyTests.swift`, `PlayerQoEEventReducerTests.swift`,
`PlayerStringsTests.swift`, `SkipSegmentContractTests.swift`, and
`PlaybackRecoveryRegressionTests.swift`. Those tests are necessary code evidence;
they do not substitute for the red runtime/device items above.
