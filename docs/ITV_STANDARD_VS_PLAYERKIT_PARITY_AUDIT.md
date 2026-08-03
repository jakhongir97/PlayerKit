# iTV Standard Player vs PlayerKit parity audit

**Audit snapshot:** 3 August 2026

**Repositories:** `PlayerKit` and sibling `../itv-ios` on `codex/itv-playerkit-month1`

**Decision scope:** iTV iOS production replacement. tvOS and Reels are reported
because they affect the phrase “replace totally”, but they are not hidden inside
the one-month iOS VOD scope. PlayerKit's macOS-only diagnostics console is also
outside this iTV/iOS localization decision and must not be counted as globally
localized PlayerKit UI.

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
| Route every current iOS Standard entry to PlayerKit | **NO-GO** | The VOD gate passes; offline, catalog-live and TV candidates pass their runtime/device matrices; the catch-up timeline is proven against production-shaped templates; and Standard rollback is proven. |
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
- **Candidate** — present on the current integration branches and not yet a
  released PlayerKit/iTV production behavior.
- **Standard** — current default implementation, not modified by this audit.

## Production ownership and route diff

The default is unambiguous in code. iTV `74f45e8b` makes the exact stored value
`Test Player` the only PlayerKit opt-in across all five route selectors. Nil,
`Standard Player`, unknown, empty and case variants fail closed to
`Standard Player`; no permissive string fallback remains. This is a device-local
setting, not a server cohort or kill switch. Git history traces the
VOD controller to 1 February 2022 (136 commits following the file) and the TV
controller to 28 February 2022 (78 commits). That longevity raises regression
risk; commit count itself is not proof of quality.

| Route / user flow | Current production owner and exact entry | PlayerKit candidate | Status / regression risk | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Movie/VOD fetched by IDs | `MainCoordinator.pushToVideoPlayerVC(paymentModuleId:itemId:fileId:...)` selects Standard or New by persisted setting (`MainCoordinator.swift:323-350`). Standard owns URL fetch, paywall, ads, playback, persistence, reports, sharing, and analytics. | `NewPlayerViewController` fetches through the same `FileViewModel`, maps metadata/resume/markers, hosts PlayerKit, gates ad-bearing content behind app-owned IMA, refetches expired playback URLs, exposes app-owned report/timestamp actions, and injects complete candidate EN/RU/UZ iTV/iOS copy. | **Partial, critical.** The known VOD host seams have candidate implementations, but ads, expiry, report/share UI, native-language approval and all runtime proof remain open. | Run the IMA, expiry and host-action matrices, finish native copy approval, then canary this route only after the device/QoE gates. | D, X |
| Direct `PlayerItem` movie/card/search route | The same setting selects Standard/New (`MainCoordinator.swift:385-411`). | Candidate maps a valid HTTP(S) item or refetches by IDs. Non-empty top-level or nested `adUrl` is normalized and held behind the same IMA gate; `thumbnailUrl` is validated and bridged to PlayerKit's bounded WebVTT loader. | **Partial, critical.** Silent preroll bypass and the thumbnail code gap are closed in candidate code; real ad/thumbnail media and lifecycle proof remain open. | Prove ad success/no-fill/error/lifecycle for both direct and fetched items; run a representative WebVTT/sprite fixture and retry-expiry matrix. | D, X |
| Trailer | Routed through the same selector with `.trailer`. Standard hides settings/episode behavior and applies trailer-specific resume (`VideoPlayerViewController.swift:230-233,987-1010`). | Candidate keeps the exact trailer threshold/no-rewind rule and uses PlayerKit's host presentation policy to hide speed, quality and the generic ended overlay. iTV also suppresses quality probing, host report/share/series actions and progress writes while retaining the separate audio/subtitle and transport controls. | **Ready-code / runtime-red.** The previous visible policy regression is closed in `3949727` and `73acc8b5`; focused/static checks and dual-architecture builds pass, but no trailer media flow has run. | Run resume, seek, audio/subtitle, completion-last-frame, replay absence, close and analytics checks on representative trailer media. | D, X |
| Episode from series/history/list | Same selector; Standard owns availability, ascending/descending navigation, previous-season fallback, end-to-next, and series sheet. | Candidate has cancellation-safe async next/previous availability, sort direction, previous-season fallback, exact metadata and save-before-switch. The host now opens the existing series catalog and carries a typed episode selection back through the same fetch/install adapter with owner, request and source/target identity guards. | **Partial, high.** The series-sheet code gap is closed in `82446853`, and its static verifier/build pass; rapid-switch and real catalog round-trip behavior remain unproved. | Run the existing catalog with available/unavailable/paid episodes, dismissal and rapid competing selections, plus the next/previous stale-response matrix. | D, X |
| Download/offline from main coordinator | Standard remains the rollback path with the downloaded `AVURLAsset` and `.download` (`MainCoordinator.swift:374-383`). | PlayerKit `f179890` accepts a host-retained `AVURLAsset`; iTV `fbf7f80b` routes the downloaded item through PlayerKit only when the New-player flag is selected and the resolved asset is an existing local file. The host suppresses ads, signed-URL retry, HLS probing and online-only menus, and keeps widget/Core Data progress. | **Ready-code / runtime-red, critical.** The static contract, source parse and dual-architecture app build pass. Neither this entry nor its invalid/expired-download behavior has run in airplane mode or on a device. | Run valid, missing, expired and corrupted downloads through Standard rollback and PlayerKit in airplane mode; assert progress, relaunch and no network fallback. | R, X |
| Download list | Standard remains the rollback path with its `AVURLAsset` (`DownloadListViewController.swift:107-115`). | The same `fbf7f80b` flag split and local-asset mapper covers the direct download-list entry, including coordinator-less launch/error paths. | **Ready-code / runtime-red, critical.** Both entry shapes are statically checked and compile, but neither has been launched. | Run both direct-entry shapes, dismissal/relaunch and progress notification checks with networking disabled. | R, X |
| Generic catalog live/stream | `StreamDetailViewController` creates a live `PlayerItem`; Standard remains the selector default and rollback. | iTV `ebb9767b` routes the New-player selection through the existing coordinator seam, validates the stream URL and maps it to PlayerKit's explicit `.pureLive` timeline from `9e8d16a`. | **Ready-code / runtime-red, critical.** The static bridge and dual-architecture app build pass; no live fixture, transition, recovery or device flow ran. | Run valid/invalid URLs, live-edge UI, interruption, retry, Cast/AirPlay/PiP and teardown against a safe live fixture while retaining Standard fallback. | R, X |
| Linear TV, EPG, catch-up, channel switching | Three iOS constructors converge on `TVPlayerViewController`; the shell owns channel auth/paywall, favorites, channel list, pagination, EPG, timeshift and URL changes. Standard/VersaPlayer remains the default transport. | iTV `b5f8cec2` snapshots the existing selector in that shared shell and embeds the VOD-proven PlayerKit host only for the New route. It keeps EPG/business state app-owned, maps live to `.pureLive` and constructed catch-up URLs to `.onDemand`, preserves tracks via PlayerKit `7b72368`, and retains the Standard branch. Earlier `afdcc554` guards stale channel/guide/timeshift generations. | **Ready-code / catch-up-design-red, highest complexity.** Static/build gates pass, but Standard rebases logical programme time over each replacement asset while PlayerKit publishes backend time and several consumers read the backend directly. A URL-only seek interceptor would therefore be incomplete. No real catch-up fixture, 100-switch, boundary, clock-skew, ad or device matrix ran. | First run a redacted production-shaped template plus manifests at logical seconds 0, middle and live edge to determine whether native AVFoundation seek on one zero-second URL suffices. If not, add a token-scoped reloading-timeline projection plus host resolver with paused-intent, boundary and generation guards; then run the remaining matrices. | R, X |
| Reels | Separate `ReelsPlayerViewController`, not Standard/New. | Not in this replacement seam. | **Out of scope.** Replacing Standard does not replace Reels. | Keep separate unless product explicitly asks for consolidation. | T |
| tvOS | Separate target/controllers under `itv_tvOS`. | `Package.swift` declares iOS and macOS only; no tvOS platform/product validation. | **Missing / out of month scope.** | Run a separate tvOS product/remote/focus audit before claiming all-platform replacement. | T |

## Stop-ship blocker register

These are outcome blockers, not an estimate in vague months. Default cannot flip
while any applicable D blocker is red.

| ID | Blocker and evidence | Consequence | Smallest closure / proof | Gate |
| --- | --- | --- | --- | --- |
| B1 | **IMA moved from a missing-code blocker to an unproved candidate.** `NewPlayerViewController` now holds each ad-bearing item behind a generation-keyed app-owned gate, owns IMA loader/manager/playhead and secure overlay, rejects stale callbacks, pauses across covered/background states, fails open only after an IMA result or a 15-second foreground timeout, and releases content exactly once. A pure Swift reducer check covers stale/duplicate/exit transitions. | The previous silent ad bypass is closed in code, but a real SDK/tag/runtime mismatch could still regress revenue, lifecycle, accessibility or playback. VMAP post-roll remains absent because the host does not call `adsLoader.contentComplete()`; Standard also omits it. | Run preroll success, no-fill, load/play error, timeout, background/foreground, covered navigation, episode switch and teardown using real test tags. Add `contentComplete()` and completion deferral only if the product contract explicitly requires post-roll. | D, R, X |
| B2 | **The source platform says iOS 14, but shipped binary dependencies do not.** `Package.swift:43-58` and the app declare iOS 14, while `LC_BUILD_VERSION` reports `minos 15.0` for Google Cast 4.8.4 and IMA 3.28.10; VLCKit reports iOS 9.0. | A compile or iOS 14 runtime smoke cannot override the embedded binary floor or establish iOS 14 release compatibility. | Choose one release path: raise both app and PlayerKit minimums to iOS 15, or replace both IMA and Cast with reviewed binaries whose slices declare `minos <= 14.0`. | D, R, X |
| B3 | **Signed/expired URL refresh is wired in candidate code but lacks service proof.** iTV now owns `PlayerManager.onPlaybackRetryRequested`, refetches the current movie/file through `FileViewModel`, validates response/status/item identity, rejects stale/unchanged URLs, preserves all PlayerKit metadata, and lets PlayerManager perform one reload at the current position. Owner, cancellation, generation, exit and covered-navigation guards prevent late autoplay. | The stale-URL loop is closed structurally, but actual gateway 401/403/expiry/auth/network behavior has not run. | Execute an expiring signed-stream fixture plus 401, 403, unchanged URL, payment 402, network loss, dismissal and episode-switch races; retain sanitized logs proving one refetch and one reload. | D |
| B4 | **No current runtime proof.** PlayerKit unit/compile and current iTV simulator compile are green, but the simulator remained shut down. | Playback, layout, lifecycle and framework errors remain possible despite compilation. | Obtain explicit simulator-boot permission, then run movie/trailer/episode golden flows on production-shaped fixtures; archive screenshots/logs and one small automated host smoke. | D |
| B5 | **No physical-device/system integration proof.** PiP, Cast, AirPlay, interruption, background audio, route changes, capture and assistive technologies depend on hardware/system services. | “No regression” cannot be claimed for high-risk OS integrations. | Execute the named supported iPhone/iPad/iOS matrix, including real Cast/AirPlay receivers and iOS 14 policy resolution. | D, R, X |
| B6 | **The audited VOD UI/product seams now have candidates, but runtime and approved-language proof remain red.** PlayerKit exposes all eight Standard rates, adaptive quality, bounded WebVTT/sprites and a narrow host presentation policy. iTV reuses its report service and series catalog, timestamp-shares from an app-owned menu, and applies strict Standard trailer visibility/end/progress rules. PlayerKit `18cd8a7` and iTV `c3cbf3bc` route all 126 iTV/iOS `PlayerStrings` values through 125 matched EN/RU/UZ host keys or locale-aware numeric formatters, including recovery, gestures, accessibility, streaming values and the hidden backend-debug menu. None of the candidate locale bags has named native approval yet. | Static checks, 355 library tests and dual-architecture builds close the known implementation gaps, not the user-visible contract. Report POST/share-sheet/catalog selection/trailer media, representative quality/thumbnail media and complete localized layout remain unrun. The macOS-only diagnostics console is not part of the iTV/iOS claim and remains English. | Complete the native-review checklist and localized device/layout matrix, execute the VOD runtime matrices, and keep Standard available until the golden device/QoE gate passes. | D, X |
| B7 | **QoE baseline, schema and rollout control remain red.** PlayerKit emits events, but `playbackStarted` is not decoded first frame and the iTV host discards most QoE context while using only selected events for watch analytics/persistence. There is no common Standard baseline, written tolerance, dashboard, session/schema contract, server cohort or kill switch. | Stability/non-inferiority claims cannot be measured or rolled back centrally. The device-local selector is not production rollout control. | Define the host session/schema and decoded-first-frame signal; retain needed context without sensitive media data; capture common Standard/PlayerKit baselines and tolerances in a dashboard; then add a server cohort/kill switch. | D, X |
| B8 | **Offline has a code candidate but no runtime/airplane-mode proof.** PlayerKit `f179890` preserves a host-provided `AVURLAsset`; iTV `fbf7f80b` covers both Standard offline entries behind the existing selector, rejects non-local/missing files, suppresses online-only paths and preserves widget/Core Data progress. | Static and compile evidence does not prove a downloaded asset plays without networking, survives relaunch, or fails safely when missing/expired. Standard cannot be removed. | Execute both entries with valid, missing, expired and corrupted downloads in airplane mode; assert local-only loading, progress persistence/notification, teardown and relaunch. | R, X |
| B9 | **Generic live and shared-shell TV now have rollback-safe code candidates, not production proof.** PlayerKit `9e8d16a`, `9773f43` and `7b72368` supply explicit live timelines, typed live Cast handoff and opt-in track preservation; iTV `ebb9767b`, `afdcc554` and `b5f8cec2` route generic live and all existing TV constructors through the selector while leaving EPG, entitlement, timeshift and channel state app-owned. | Catch-up timeline semantics are unproved. Standard rebases logical programme time across replacement assets; PlayerKit publishes backend time and has direct backend-time consumers, so a URL-only callback is not a correct assumed fix. No live/DVR/TV fixture or device matrix ran; Standard remains the default rollback. | Probe a redacted production template/manifests at seconds 0, middle and live edge. If a single zero-second asset cannot seek natively, implement a token-scoped reloading-timeline projection plus guarded host resolver, then run live-edge, catch-up, ad/auth, track/quality, 100-switch and device matrices. | R, X |
| B10 | **Release dependency state is not reproducible enough.** Candidate iTV uses the unpublished local `../PlayerKit`; production previously used 1.1.0. IMA is pinned exactly to 3.28.10, but VLCKit remains a checksum-pinned binary from a personal PlayerKit release (`Package.swift:32-40`). | The IMA drift risk is closed, but a clean release cannot reproduce the unpublished PlayerKit candidate and the supply-chain/license/privacy/signing review is incomplete. | Publish a reviewed immutable PlayerKit version/commit; record vendor provenance, license, privacy manifest and signature/hash for every binary. | D, X |
| B11 | **Protected/header/FairPlay asset requirements are unconfirmed.** Public `PlayerItem` is URL-centric and has no explicit headers, resource-loader or DRM seam. | A protected production class could fail only after rollout. | App owner supplies a redacted asset inventory. If any active asset needs FairPlay/headers/resource loading, promote that exact contract into scope with a fixture. | D or R if present |

## Detailed capability diff

### VOD, trailer and episode playback

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| URL acquisition and authorization | App `FileViewModel` fetches URLs and calls `CheckAuthorization` on API errors. Standard reacts to the same delegate callbacks. | Candidate deliberately keeps URL/auth in iTV and uses the same view model. | **Ready-code**, runtime 200/401/402/invalid-data matrix open. | Add host integration tests with stubbed result shapes and one redacted service smoke. | D |
| Initial playback / teardown | Standard installs VersaPlayer after item resolution and owns dismissal cleanup. | Existing PlayerKit has AVPlayer load/play/teardown. The iTV candidate through `95ce19f6` mounts a host-managed `PlayerView`, pauses for temporary child navigation, tears down only when leaving the player presentation, rejects late media/payment installation after exit, and cleans singleton callback ownership. | **Ready-code after candidate lifecycle fix.** Compile and focused ownership checks are green; paid-next/back, double load, dismiss-during-load and playback-after-dismissal still need runtime proof. | Run presentation/dismiss/reopen plus “episode end -> paid next -> back”; assert terminal state is preserved temporarily and no audio/session/callback survives real dismissal. | D |
| Exact resume | Standard honors `exactStartPosition`, thresholds history, and rewinds non-trailers (`VideoPlayerViewController.swift:987-1010`). | The iTV bridge maps the same exact position, trailer threshold and non-trailer rewind (`5998dcee`). | **Ready-code**, edge fixtures open. | Test exact 0, below threshold, normal history, near end and trailer values. | D |
| Metadata / title art / Cast | Standard maps title/detail/poster and Cast URL. | The iTV bridge maps title image, title, description, poster, Cast/external URL, content type and duration (`5998dcee`). | **Ready-code**, receiver/runtime proof open. iOS 14 title art has a text fallback. | Golden metadata assertions plus Cast receiver inspection. | D |
| Exact intro/credits markers | Standard evaluates backend segments; credits can become next episode and the button pulses/auto-hides (`VideoPlayerViewController.swift:1137-1227`). | Candidate adds exact typed `PlayerSkipSegment` mapping and suppresses duration heuristics; focused tests exist. | **Partial.** Timing/target semantics are covered in unit tests; Standard's 10-second presentation/pulse behavior is not identical. | Device/UI test boundary times, overlap, episode credits, seek target and accessibility announcement; decide whether auto-hide is contract. | D |
| Episode next/previous/end | Standard handles order, availability, previous season and end-to-next (`VideoPlayerViewController.swift:832-985,1050-1111,1240-1242`). | The iTV candidate adds async availability, stale request identity, previous-season fallback, save-before-switch and external episode navigation (`5998dcee`, `82446853`). | **Partial, improved candidate.** No current app-level runtime/regression suite. | Stub asc/desc, first/last, missing file, paywall and 20 rapid switch cases. | D |
| Series catalog sheet | Standard exposes an app sheet and receives its delegate; coordinator assigns a delegate only when source is Standard (`MainCoordinator.swift:246-257`; `VideoPlayerViewController.swift:1410-1462`). | Candidate adds an episode-only host menu action that opens the existing app-owned catalog. Its typed callback saves the current position, fetches through `FileViewModel`, rejects stale/foreign identities and installs through the same episode adapter; nil callback preserves the Standard route. | **Ready-code / runtime-red.** `82446853` and the series bridge verifier pass; no real sheet, service response or competing-selection flow ran. | Run available/unavailable/paid selection, dismiss-without-selection, stale callback and rapid selection on phone/iPad. | D, X |
| Trailer product policy | Standard hides speed, quality and host settings/actions, keeps audio/subtitle and transport controls, applies no normal rewind, and ends without a generic replay/close overlay. | `PlayerPresentationPolicy` is a three-boolean host seam with backward-compatible defaults. The iTV trailer supplies hidden speed/quality/ended-overlay values and suppresses host actions, quality discovery and progress persistence. | **Ready-code / runtime-red.** Focused policy checks and the trailer static verifier pass. | Run the strict Standard trailer matrix with representative media and confirm no hidden feature is reachable through accessibility or stale menu state. | D |
| Playback end behavior | Standard calls next action; movie delegates/channel contexts can differ. Trailer's default next action is a no-op and leaves the last frame without generic replay/close UI. | PlayerKit emits completion and existing episode navigation. The host presentation policy now suppresses only the trailer ended overlay; normal movie/episode defaults are unchanged. | **Partial.** Trailer policy is code-ready, but no movie/episode/trailer golden completion flow or duplicate-analytics check ran. | Test each type's completion exactly once, trailer last-frame behavior, replay/close visibility and episode auto-next. | D |

### Ads, entitlement, auth and purchase

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| IMA preroll | Standard owns IMA loader/manager/display/playhead; pauses content, resumes on completion/no-fill/error, and handles lifecycle (`VideoPlayerViewController.swift:1583-1761`). Standard's fresh failure path calls `play()` without installing the held item, so the candidate must preserve policy rather than copy that bug. | Candidate keeps all IMA types/models in iTV, not PlayerKit. A UUID gate holds direct, fetched and switched items; a secure accessible overlay, KVO-compatible playhead, lifecycle pause/resume, stale-callback guards and exact-once fail-open release are implemented. | **Ready-code, still stop-ship on runtime evidence.** Pure reducer/static checks are green; no real tag ran. Post-roll is absent with Standard and stays outside scope unless product requires `contentComplete()`. | Execute the B1 matrix with real test tags and capture content-not-started assertions before every release condition. | D, R, X |
| VOD tariff/free/ADVOD/content purchase | Standard branches on `PaymentType`, opens tariff suggestion or content detail (`VideoPlayerViewController.swift:491-516`). | The iTV bridge mirrors the same app-owned branch (`5998dcee`). | **Ready-code**, runtime navigation/status matrix open. ADVOD still depends on B1. | Test every payment type and no-module/invalid payload; assert content never starts on 402. | D |
| Child restriction | Standard refuses payment path under child restriction. | Candidate uses the same `ChildProfileAccessPolicy` guard. | **Ready-code**, UI outcome open. | Verify restricted asset cannot play or open an inappropriate purchase screen. | D |
| Auth expiry | Both use `FileViewModel`/`CheckAuthorization`; bridge dismisses after auth state is consumed. | Same app ownership is retained, and manual PlayerKit recovery now asks the gateway for a fresh URL with current identity before reloading. | **Ready-code / runtime-red.** Initial auth and mid-play expiry remain unproved against the service. | Run initial 401, mid-play expiry, re-auth, cancel, payment and stale-response cases. | D |
| VPN/StoreKit subscription path | Standard implements `didRequireStoreKitSubscriptions`. | The iTV bridge implements the same callback (`5998dcee`). | **Ready-code**, device/store environment proof open. | Verify the exact service response opens StoreKit once and returns safely. | D |
| TV entitlement | `TVPlayerViewController` stores channel context and handles channel payment/tariff (`TVPlayerViewController.swift:190-235`). | iTV `b5f8cec2` keeps that existing shell authoritative and swaps only the selected transport; invalid or paid media fails before replacing accepted shell state. | **Ready-code / runtime-red.** The source contract and app build pass, but no live auth/tariff response ran. | Run free, paid, expired-auth, missing-media and stale-response cases through both selector branches. | R, X |

### History, state and analytics

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Watch position / widget | Standard writes widget state, backend seconds and watch-history refresh; saves on pause and switches (`VideoPlayerViewController.swift:1013-1038,1273-1275`). | Candidate writes widget/backend/history on exit, PlayerKit pause/completion/fatal, episode switches and guarded VOD/offline background entry. Close funnels through one exit save, and its network write is no longer canceled when the controller deinitializes (`95ce19f6`; `VideoPlayerViewModel.swift:18-47`). | **Ready-code after candidate change**, runtime cadence/open interruption cases remain. The write is best effort rather than an offline-durable queue. | Assert values after pause, home/background, kill, close, fatal, completion and switch; add a durable sync queue only if measured offline delivery requires it. | D |
| Offline progress | Standard additionally writes Core Data and posts download update (`VideoPlayerViewController.swift:1023-1025`). | Candidate `fbf7f80b` keeps the widget write, then uses the existing offline Core Data write and download-update notification before returning ahead of the online `userViewsSet` path. | **Ready-code / runtime-red.** Static ordering checks and the app build pass; pause/exit/relaunch values have not been observed. | Assert progress after pause, close, completion, kill and relaunch in airplane mode from both offline entries. | R, X |
| Selected audio/subtitle/rate persistence | Standard sends selected languages and speed; carries preferences across episodes and TV switches. | Existing PlayerKit exposes selections/rate and persists episode choices. PlayerKit `7b72368` adds a default-off direct-load option that matches prior audio/subtitle choices, including subtitle-off, without changing existing callers; iTV `b5f8cec2` enables it only for embedded TV reloads. Candidate VOD also sends language/id and speed in `userViewsSet`. | **Ready-code / runtime-red.** Focused default/preserve checks pass; app-locale fallback, reordered/absent/forced tracks and real channel manifests remain unrun. | Test relaunch, episode switch and rapid TV switches with reordered/absent/default/forced tracks. | D, R |
| Watch analytics | Standard sends AppsFlyer and Firebase watch events (`VideoPlayerViewController.swift:1124-1127`). | iTV `19520e06` deduplicates PlayerKit `.loadRequested` by logical kind plus app-owned content/file IDs. Signed-URL retry/reload does not re-emit; real movie, episode and identified-live transitions do. Embedded TV retains its existing channel-ID dedupe. The identity stores no URL, title, ad tag, user or playback credential. | **Ready-code / runtime-red.** The 13th host verifier and final dual-architecture app build pass; no analytics event ran. | Run AppsFlyer/Firebase event assertions for retry, episode switch, identified-live switch, embedded TV and missing IDs without logging playback credentials. | D |
| QoE telemetry | Standard has no comparable typed lifecycle stream in this controller. | Candidate PlayerKit emits privacy-safe load/play/pause/ready/active-playback/stall/seek/fatal/completed/exited events. iTV consumes only a subset and discards most event context. `playbackStarted` is not decoded first frame. | **Schema/session contract red.** No common Standard definitions, item/session correlation, written tolerances or dashboard exist. | Define one host schema/session contract, retain required privacy-safe context, add a decoded-first-frame signal, and publish common Standard/PlayerKit dashboards and tolerances. | D, X |

### Tracks, speed, quality, thumbnails and controls

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Audio tracks | Standard enumerates Versa tracks, applies app-localization fallback and persists the choice across episodes (`VideoPlayerViewController.swift:760-835,1244-1254`). | Existing AVPlayer wrapper enumerates/selects media groups with an iOS 14 fallback; candidate persists selected ID/language. Default fallback follows device preferred languages rather than the app's selected locale. | **Partial.** | Supply host preferred language or map app locale; test HLS alternate/default/unknown-language and episode reorder. | D |
| Subtitles | Standard supports off/selection and persistence. | Existing PlayerKit supports off/selection and state. | **Ready-code**, forced/default/SDH and relaunch proof open. | Production-shaped manifests plus VoiceOver checks. | D |
| Playback rates | Standard exposes 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 (`VideoPlayerViewController.swift:273-280`). | Candidate PlayerKit exposes the same eight rates from one native SwiftUI menu list. Focused tests assert the set and verify 0.75/1.75 reach and survive backend replacement. | **Ready-code**, runtime menu/layout, pause/seek/item-switch and persistence proof remain. | Run the rate matrix on small phone/iPad and across a real episode switch. | D |
| Manual HLS quality | Standard derives variants and maps Auto/min/mid/max to `preferredPeakBitRate` (`VideoPlayerViewController.swift:1312-1398`), but its fallback parser misses normal `#EXT-X-STREAM-INF:BANDWIDTH` syntax, lacks stale-item guards and can silently do nothing on iOS 14. | Candidate fixes the host parser, filters positive values without logging signed URLs, probes only explicit `.m3u8` content after ad release, and generation/owner/URL-guards responses. PlayerKit sorts/deduplicates raw bitrates, retains the semantic selection across episodes, maps lower-median Optimal, hides single-rendition controls and applies an adaptive cap to current/new AVPlayer items. | **Ready-code / runtime-red.** Parser, policy, semantic remap and replacement-item checks pass; no real multi-variant fixture or menu interaction ran. Extensionless HLS intentionally stays Auto until the host supplies an explicit media-kind signal. | Run Auto/Max/Optimal/Min, single/malformed/failure, episode switch, stale result and signed refresh on a production-shaped HLS fixture. | D |
| WebVTT scrub thumbnails | Standard/Versa loads WebVTT, supports sprite cropping, cancellation, cue lookup and bounded caches (`VersaPlayerControls.swift:124,482-497,753-756,994-1320`). | Candidate PlayerKit loads at most 1 MiB manifests and 16 MiB encoded sprites into ephemeral memory-only sessions, caps decoded sprites at 64 MiB, coalesces expensive work to one active plus one latest job, rasterizes independent crops, and guards owner/request/sprite identity. iTV validates and preserves `thumbnailUrl` across install and signed-URL retry copies. | **Ready-code / runtime-red.** Ten focused parser/transport/cancellation/ABA/memory/orientation checks pass; the current full 355-test suite and dual-architecture iOS/app builds pass. No real CDN redirect, representative VTT media, offline transition, layout or memory profile has run. | Run full-frame and sprite VTT fixtures, malformed/offline/redirect cases, rapid scrubbing, temporary disappearance and memory/network profiling on supported devices. | D, X |
| Issue reporting | Standard fetches report choices and sends selected error (`VideoPlayerViewController.swift:519-529,1113-1122,1294-1353`). | Candidate reuses `PlayerSettingsViewModel` entirely in iTV: fetched choices populate an app-owned report submenu, selection sends the existing file/error/message payload, and owner/exit guards reject late callbacks. The menu is hidden during ads/hidden controls and omitted for trailers. | **Ready-code / runtime-red.** `412ce885` and the host-action static verifier pass; no report list or POST ran. | Run list success/empty/failure, every report payload, POST success/failure, dismissal and stale callback without logging sensitive URLs. | D, X |
| Timestamp sharing | Standard constructs the app share URL with current seconds. | Candidate exposes timestamp sharing from the same app-owned host menu, truncates representable values toward zero, clamps negatives to zero, rejects non-finite/out-of-range values, and preserves UIKit's iPad popover handling. It is omitted for trailers and hidden with controls/ads. | **Ready-code / runtime-red.** `412ce885` and boundary/static checks pass; no share sheet ran. | Test URL/time at zero, fractional/NaN/infinite/out-of-range values, hidden/ad states and iPad presentation. | D |
| Gestures / lock / rotation | Versa supports pinch, double-tap seek, long-press speed, vertical volume/brightness and orientation locking. | Existing PlayerKit has richer gesture routing, coach/HUD, lock notifications, scrub, aspect controls and focused tests; candidate connects app orientation ownership. | **Ready-code with likely UX improvement**, but touch conflict/haptics/real brightness need devices. | Run gesture conflict matrix on small iPhone/iPad with VoiceOver/Voice Control on and off. | D |

### Recovery, lifecycle and system integrations

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Playback failure UX | Standard's `playbackDidFailed` callback is empty (`VideoPlayerViewController.swift:1231-1234`). | Existing PlayerKit has safe blocking/non-blocking recovery UI, retry/close/end decisions and regression tests. Candidate iTV retry now refetches a fresh URL, preserves metadata and reloads once at the current position. | **Ready-code / improvement**, service/runtime proof remains B3. | Test transient/fatal/close/duplicate retry, expiry/payment/stale identity and sanitized user copy. | D |
| Automatic recovery/backoff | Standard does not provide a robust controller-level strategy. | PlayerKit recovery exists, but no app policy for retries/backoff/refetch. | **Partial.** | Define bounded retry policy around network vs authorization; never loop or bypass paywall. | D |
| PiP | Standard embeds native PiP and restoration/orientation handling (`VersaPlayerView.swift:198-345`). | PlayerKit `f8a3937` permits the host restoration completion to finish asynchronously. iTV `db5be536` uses the existing root restoration helper to re-present the actual owning player, guarded against stale owner, exit and missing-root cases. | **Ready-code / runtime-red, device-critical.** The focused async regression, iTV static verifier and dual-architecture builds pass; no PiP session has run. | Test start, home, host dismissal, return, item end, restoration failure and repeated presentations on supported devices. | D, R |
| AirPlay | Standard has route picker/external playback behavior. | Existing PlayerKit supports AirPlay; candidate enables external playback. | **Ready-code**, real route/device/capture-policy proof open. | Test route connect/disconnect, seek, background, lock screen and protected-output policy. | D |
| Google Cast | Standard distinguishes buffered VOD vs live and sends metadata/start time (`VideoPlayerViewController.swift:1465-1580`). | PlayerKit `9773f43` keeps VOD buffered with its legacy start position and maps explicit live timelines to Cast live streams with start time zero. | **Ready-code / runtime-red.** Focused policy tests pass; no receiver/session/device flow ran. | Verify receiver metadata/type/start time for VOD and live, then test connect, disconnect, reconnect and failure on supported devices. | D for VOD, R for live |
| Background audio / Now Playing / remote commands | Standard app already declares background audio; the radio screen also installs process-wide remote targets. | PlayerKit `2a6c8bb` gates skip/scrub on the current live seek window and clears stale metadata on empty reset. iTV `30d56a6b` owns/removes only radio targets. iTV `95ce19f6` transfers Now Playing/remote ownership to IMA through `held`, `requesting`, `ready`, `playing` and `releasePending`, plus `released` VMAP while visible or paused under a covered presentation. It resumes covered content only for the same owner that had requested playback, preserving an existing user pause, and checkpoints guarded VOD/offline progress on background. | **Ready-code / runtime-red.** Library tests, all 13 PlayerKit host verifiers and the radio verifier pass; interruption, ads, route, Control Center and lock-screen behavior remain unrun. | Device-test ad/covered transitions, explicit user pause, background checkpoints, phone/Siri/headphones, Control Center and lock screen across VOD, offline, live, DVR and radio handoff. | D, R |
| Orientation / iPad / multitasking | Standard has years of app-owned rotation and layout behavior. | Candidate retains app orientation locking around PlayerKit; SwiftUI layout differs. | **Partial.** | Snapshot and interaction matrix across smallest phone, notched phone, iPad portrait/landscape/split view. | D |
| Singleton ownership | Standard controller owns a player instance. | PlayerKit uses `PlayerManager.shared`; candidate adds a callback owner UUID, host-managed view teardown, pause for child navigation, explicit teardown on true exit, and callback cleanup on deinit. | **Ready-code mitigation, architecture risk remains.** | Stress paid-next/back, sequential presentations, PiP restoration, rapid dismiss/reopen and any concurrent preview; prove stale controllers cannot receive events. | D |

### Offline, live and TV specifics

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Downloaded `AVURLAsset` | App passes the asset directly; this can preserve local/resource-loader configuration. | PlayerKit `f179890` adds one optional host-provided `AVURLAsset`, retains it through item copies and AV backend installation, and falls back to its URL for non-AV backends. iTV `fbf7f80b` exposes it only for `.download` after file-URL/existence validation. | **Ready-code / runtime-red.** Integrated lifecycle tests and dual-architecture builds pass; resource-loader, bookmark, missing-file and airplane-mode behavior remain unrun. | Run representative downloaded movie/episode assets, including relaunch bookmarks and failure shapes, without network access. | R, X |
| Pure live vs DVR | Standard hides VOD controls for live and exposes live-edge behavior. TV shell constructs catch-up/time URLs. | PlayerKit `9e8d16a` adds explicit automatic/VOD/seekable-live/pure-live timelines, live-edge state and native Go Live controls. iTV maps generic and TV live to `.pureLive`, and resolved catch-up media to `.onDemand`. | **Ready-code / runtime-red.** Timeline/UI tests and app static checks pass; no pure-live, moving DVR window or transition fixture ran. | Run live/DVR transitions and every seek path against moving-window fixtures. | R, X |
| Live edge / go live | Standard delegates `playbackCheckLive` and `playbackBackToLive` (`VideoPlayerViewController.swift:1264-1270`). | PlayerKit exposes live-edge state and `goLive`; the TV host action deliberately reloads the original live URL after catch-up rather than seeking inside an archive URL. | **Ready-code / runtime-red.** Static policies pass; moving-window and reload behavior remain unrun. | Test edge tolerance, delayed manifests, archive-to-live reload, failure and repeated Go Live. | R |
| EPG/timeshift/catch-up | Existing TV shell owns guide/current/previous/next, `{START_AT}`/time construction and selected guide. Standard rebases logical programme time over every replacement asset. | iTV `b5f8cec2` keeps app ownership and passes resolved live/catch-up items plus timeline mode into PlayerKit. Initial/program-selection URL construction is wired, but PlayerKit publishes backend time and several consumers read it directly. | **Partial / design-red.** A URL-only host interceptor would not preserve the logical timeline. No production-shaped template/manifests or boundary proof ran. | At logical seconds 0, middle and live edge, test whether AVFoundation can seek one zero-second resolved URL natively. Only if it cannot, add a token-scoped reloading-timeline projection and host resolver preserving paused intent with boundary/generation guards. | R, X |
| Channel navigation/zapping | TV shell owns list, pagination, favorites, next/previous and stale channel identity. | iTV `afdcc554` adds monotonic channel/guide/timeshift generations and `b5f8cec2` installs only accepted items through the embedded PlayerKit transport. | **Ready-code / runtime-red.** The source harness rejects 100 reverse-order channel and guide generations, stale pagination and stale failures; no actual 100-switch media stress ran. | Run 100 rapid switches with real/stubbed responses and assert accepted identity, cancellation, memory and final playback. | R, X |
| TV ads/tracks/quality/report | Standard TV independently implements IMA, Cast, tracks, quality and reports. | iTV `b5f8cec2` embeds the existing `NewPlayerViewController` host rather than duplicating those seams; PlayerKit `7b72368` preserves matching tracks across accepted TV reloads. TV-specific speed/ended chrome stays hidden while quality/tracks/report remain host-owned. | **Ready-code / runtime-red.** Ownership/static checks and app builds pass; TV ad, report, quality and track manifests remain unrun. | Execute ad success/error, report, quality and reordered-track matrices across live/catch-up/channel switches. | R, X |

### Localization, accessibility, capture and security

| Capability | Standard production contract / owner | PlayerKit + iTV candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| English/Russian/Uzbek chrome | Standard uses app localization in many menus but also contains hard-coded strings (including Russian-only normal speed). | Candidate now injects every iTV/iOS `PlayerStrings` scalar and formatter, including quality, eight rates, tracks, retry/recovery, PiP/Cast/AirPlay, buffering, exact markers, gesture UI, accessibility, streaming values and the hidden backend-debug menu. All 125 namespaced keys match across EN/RU/UZ; Foundation formats unit grammar, decimals and percentages. | **Ready-code / approval-red.** Static contracts, focused formatter tests and dual-architecture builds pass, but none of the three bags has named native approval and no localized layout/assistive-technology matrix has run. Global PlayerKit macOS diagnostics remain English outside this iTV scope. | Complete `ITV_PLAYERKIT_NATIVE_LANGUAGE_REVIEW_CHECKLIST.md`, then test truncation, Dynamic Type, VoiceOver/Voice Control/Switch Control and number grammar in context. | D |
| VoiceOver / Dynamic Type | Standard has UIKit controls but little code-level evidence of a complete audit. | Existing PlayerKit has labels, identifiers, accessibility actions/proxies, live slider semantics and regression tests. | **Ready-code / likely improvement**, physical screen-reader proof open. | Full VoiceOver traversal/action matrix at accessibility text sizes on phone/iPad. | D |
| Voice Control / Switch Control | No strong Standard automated evidence. | PlayerKit includes touch-routing/accessibility-aware behavior. | **Partial proof.** | Physical Voice Control names, Switch Control scan order and locked-player tests. | D |
| Screenshot/screen recording protection | Standard wraps rendering with `SnapshotSafeView` (`VideoPlayerViewController.swift:551`). | PlayerKit has a best-effort secure-text-field shield plus capture-state cover; the iTV bridge also wraps its hosting view in the app's `SnapshotSafeView` (`5998dcee`). | **Ready-code, security proof open.** Secure canvas discovery is best effort and OS-sensitive. | Physical screenshot, recording, app switcher, mirroring, AirPlay and Cast matrix on every supported OS. | D, R |
| Privacy-safe telemetry | Standard analytics attaches content identifiers. | PlayerKit QoE carries no URL/title/token/user identifier. iTV `19520e06` uses only app-owned kind/content/file IDs for watch dedupe; embedded TV remains channel-ID based. | **Ready-code / runtime-red.** Static and compile checks pass; the broader host schema and logging review remain red. | Assert emitted/logged analytics never contain signed URLs, query/header data, ad tags, titles or user identifiers. | D |
| DRM/request headers | Not explicit in audited VOD path; offline asset may hide resource loading. | No explicit public seam. | **Blocked on catalog inventory.** | Close B11; implement only a verified requirement. | D/R if present |

### Performance, stability, dependencies and operations

| Capability | Standard baseline | PlayerKit candidate | Status / evidence gap | Smallest next action | Gate |
| --- | --- | --- | --- | --- | --- |
| Startup time / first frame | No common Standard baseline or tolerance exists. | QoE has load/ready/`playbackStarted`, but `playbackStarted` is not decoded first frame and iTV drops most event context. | **Blocked on schema and measurement.** | Define sessions/context, add one monotonic decoded-first-frame measure, then capture p50/p95 on identical assets/devices for both. | D, X |
| Rebuffering / failures | No common Standard definitions, baseline, tolerance or dashboard exist. | PlayerKit emits stall start/end and fatal, but the host does not retain enough context or publish a comparison. | **Schema/dashboard red.** | Define a privacy-safe session schema and written non-inferiority thresholds before any canary. | D, X |
| CPU/memory/energy/leaks | No current Standard Instruments baseline. | PlayerKit has substantial unit/state coverage, but SwiftUI update cost, framework memory and long-session behavior are unmeasured on iOS. | **Blocked on profiles.** | Instruments launch/seek/menu/2-hour VOD and TV zap profiles; compare, fix measured hotspots only. | D for obvious regressions, X for removal |
| Automated library regression | N/A as app monolith. | Full PlayerKit `swift test` executes 355 tests with 5 environment skips and 0 failures; exact markers, quality, QoE, strings/privacy, recovery, WebVTT, lifecycle, local assets, live timelines/Cast/remote commands and opt-in track preservation have focused tests. | **Good code evidence, not app proof.** The result was captured before cache cleanup; skips need explicit disposition. | Keep suite green; document every skip; add the smallest iTV host checks for business seams. | D |
| iTV integration compile | Standard app is existing build target. | The final `itv-new` generic Debug build through `19520e06` compiles and links for arm64 and x86_64; `lipo` confirms a fat x86_64/arm64 app binary. | **Compile proof only.** Both architectures warn that the iOS-simulator 14.0 app links IMA/Cast built for 15.0; no simulator boot occurred. | Resolve B2, then run a booted runtime smoke when authorized. | D |
| iOS 14 source compatibility | Standard app target includes iOS 14. | PlayerKit source compiles with iOS 14 availability fallbacks, but pinned IMA and Cast slices declare iOS 15 in `LC_BUILD_VERSION`. | **Source compile only; release blocked by B2.** An iOS 14 smoke cannot close a binary-floor mismatch. | Raise app and PlayerKit minimums to 15, or replace both binaries with reviewed `minos <= 14.0` slices. | D, R |
| Dependency reproducibility | App previously resolved IMA from moving `main`; candidate pins it exactly to 3.28.10. | PlayerKit binary checksums are pinned; Google Cast is an official archive; VLCKit artifact provenance is project-owned/personal release. Candidate app still uses a local PlayerKit path. | **Partial / release blocker.** IMA drift is closed; PlayerKit publication and full binary provenance remain. | Publish immutable PlayerKit, then perform a clean-machine resolve/build/sign/privacy/license record. | D, X |
| Rollback | iTV `74f45e8b` accepts only the exact stored `Test Player` value; nil/old/unknown/empty/case variants resolve to Standard across all five selectors. The selector is device-local, not a server canary or kill switch. | Candidate VOD, offline, generic-live and shared-TV-shell routes coexist with the untouched Standard transport; each presentation snapshots its normalized route. | **Partial.** Fail-closed local fallback is statically covered, but emergency server control and a rollback rehearsal do not exist. | Add one server-controlled flag with instant fallback; rehearse during canary without an App Store release. | D, X |

## What was already in PlayerKit vs what changed this month

This distinction prevents candidate work from being reported as established
production behavior.

| Area | Existing before current worktree | Current candidate change | Still not delivered |
| --- | --- | --- | --- |
| Playback engine | AVPlayer and iOS VLC backends; playback state/control, tracks, speed, queue, seek ranges, recovery UI. | iOS 14 availability fallbacks; persisted quality cap applied to AVPlayer items; recovery copy/safety refinements; opt-in host ownership of `PlayerView` teardown with a focused default/override test. | iTV runtime proof and DRM/header contract if required. |
| Product metadata | Title, description, poster, Cast/external URL, last position, episode index. | Exact typed skip segments and bounded thumbnail-VTT input; host presentation policy; optional host-provided `AVURLAsset`; and explicit VOD/seekable-live/pure-live timeline modes with live-edge controls. | Runtime thumbnail/ad/trailer/local-asset/live proof and production-shaped catch-up timeline validation. |
| System integrations | PiP, AirPlay, Google Cast, background audio, Now Playing, remote commands, capture shield. | Source-level iOS 14 UI fallbacks; async host PiP restoration; explicit live Cast typing; live-aware remote seek gating; stale metadata reset; radio target isolation; IMA-owned remote suppression across every gate/visible-covered VMAP state; same-owner covered resume; and guarded VOD/offline background checkpoints. | All real-device PiP/restoration/Cast/AirPlay/ad/background/remote-command proof; binary minimum-OS resolution. |
| UX/accessibility | SwiftUI controls, menus, gestures, lock, scrub, accessibility labels/actions and tests. | Injectable `PlayerStrings`; exact marker UI; iOS 14 visual fallbacks; all eight rates; accessible adaptive-quality menu; full-frame scrub thumbnails; host-selectable trailer chrome/end-overlay visibility; and complete candidate EN/RU/UZ injection for the iTV/iOS surface with locale-aware seconds, rate, percentage, skip and streaming values. | Named native-language approval and real host-action/trailer/thumbnail/quality/layout proof. Global PlayerKit macOS diagnostics localization is separate and remains open. |
| Observability | Internal diagnostics and state. | Public privacy-safe QoE event stream plus app-ID-only logical watch dedupe across retry/transitions. | Host discards most QoE context; session/schema, decoded first frame, common Standard baseline/tolerances/dashboard and rollout controls remain red. |
| iTV adapter | Basic New player, close/share/history, simple URL fetch/episode switching, basic paywall and metadata mapping. | The VOD/offline/live/TV candidate plus generation-safe zapping, IMA/remote ownership, background checkpoints, exact-value fail-closed selection and app-ID-only logical watch dedupe. | Build/static proof is green through `19520e06`; runtime, catch-up timeline validation/projection if required, native-language approval, QoE schema/baseline/dashboard and server canary/kill switch remain red. |

## Verification ledger: compile proof is not runtime proof

### Verified in this audit/current work

| Evidence | Result | What it proves | What it does not prove |
| --- | --- | --- | --- |
| Full PlayerKit `swift test --no-parallel` | 355 executed, 5 environment skips, 0 failed before cache cleanup, including `7b72368` and `2a6c8bb`. | Library logic in the active host environment, including live timeline/Cast/remote gating, empty-reset metadata and default-off direct-load track preservation. | iOS frameworks, real media, iTV business flows, skipped environments or devices. |
| Focused PiP/local-asset regressions | Platform interaction 9/9 and backend lifecycle 17/17 passed for `f8a3937` and `f179890`. | A host may complete PiP restoration asynchronously; a supplied `AVURLAsset` survives item copying and reaches backend installation without changing default URL-only callers. | UIKit presentation restoration, bookmark/resource-loader behavior, downloaded playback or any device/system service. |
| Focused host presentation-policy tests | 10/10 passed for defaults and speed/quality/ended-overlay visibility. | `PlayerPresentationPolicy` keeps existing hosts unchanged by default and independently gates the three trailer surfaces. | Actual trailer rendering, accessibility reachability, completion media state or host wiring. |
| iTV VOD host static verifiers | Report/timestamp sharing (`412ce885`), series selection (`82446853`) and strict trailer policy (`73acc8b5`) checks all passed; PlayerKit policy is `3949727`. | The expected app-owned services, owner/request/identity guards, safe timestamp conversion and trailer exclusions remain wired in source. | Report service/POST, UIKit share sheet, series catalog/service round trip or trailer playback. |
| App-owned IMA gate harness | `xcrun swiftc` compiled the pure gate plus assertion program; stale token, duplicate release, fail-open, direct-start, finish and exit checks passed. | The content-release reducer is deterministic and exact-once without needing the ad SDK. | IMA SDK callbacks, rendering, real VAST/VMAP tags, networking or lifecycle on a device. |
| Signed-URL bridge contract check | The repository static check passed after final wiring. It asserts owner/item/generation/cancellation guards, unchanged-URL rejection, full item-field preservation, one reload owner and completion paths. | The intended host safety invariants remain present in the compiled source. | Real service status/auth behavior or actual expiring media. |
| HLS quality host checks | The standalone master-playlist harness passes normal `BANDWIDTH`, `AVERAGE-BANDWIDTH`, quoted-codec, zero and media-tag cases. EN/RU/UZ property lists and the app-owned PlayerKit key contract pass. | The corrected parser and new menu-key inventory are deterministic; signed manifest fetches use a no-cache ephemeral session. | CDN behavior, extensionless HLS, real variants, menu layout or native-language approval. |
| Complete iTV PlayerStrings contract | `scripts/verify_playerkit_localizations.py` passes: all 126 fields assigned, exactly 125 namespaced keys in each EN/RU/UZ property list, matching placeholder signatures, iTV's English locale fallback, locale-aware seconds at 0/1/2/5/11/21/22/25/1.5, all eight rates and 62% formatting. `plutil` and focused 7/7 string tests pass. | The iTV/iOS player surface no longer silently falls back to PlayerKit English; invalid numeric input and private backend details stay out of visible copy. | Translation quality, truncation, VoiceOver pronunciation, live language switching or native approval. |
| Generic iOS Simulator PlayerKit build | Succeeded for both arm64 and x86_64 after `f8a3937` and `f179890`; `PlayerKit.o` is a fat x86_64/arm64 object. | Candidate source compiles across both simulator architectures with async PiP restoration and optional local-asset input. | App launch/playback or iOS 14 runtime. |
| Generic iOS device PlayerKit build | Succeeded. | Candidate source/device slice can compile/link in that build context. | Installation, vendor binary load, signing, hardware/system behavior. |
| iTV PiP/offline static regressions | The guarded host-restoration verifier for `db5be536` and the two-entry local-only/offline-progress verifier for `fbf7f80b` pass; the touched Swift sources parse. | Expected owner/exit restoration guards, selector splits, file validation, online-path suppression and Core Data-before-online-return ordering remain present. | UIKit restoration, actual file decoding, persistence values, bookmark/resource-loader behavior or airplane mode. |
| iTV host static regressions | All 13 `verify_playerkit_*.py` scripts plus `verify_radio_remote_command_ownership.py` pass through iTV `19520e06`; EN/RU/UZ property lists pass `plutil`. | Exact-value fail-closed routing across five selectors, live/TV ownership, lifecycle, localization and app-ID-only logical watch dedupe remain wired. | Runtime, media playback, production-shaped catch-up semantics, real 100-switch stress and system/device behavior remain red. |
| iTV Xcode simulator build | The final `itv-new` generic Debug candidate through `19520e06` compiles/links for arm64 and x86_64 with zero errors; `lipo` reports x86_64 and arm64. | The complete audited adapter/API/app source compile together across both simulator architectures; the lockfile matches exact IMA 3.28.10. | No simulator boot/runtime proof. Both architectures warn that the iOS-simulator 14.0 app links IMA/Cast built for newer 15.0; packaged simulator slices confirm `minos 15.0`. |
| `LC_BUILD_VERSION` inspection | Packaged simulator slices and prior arm64 inspection report Cast 4.8.4 and IMA 3.28.10 at `minos 15.0`; VLCKit reports iOS 9.0. | The hard deployment floors embedded in the inspected binary slices and the source of both-architecture link warnings. | An iOS 14 smoke cannot change these values; release requires app/PlayerKit minimum 15 or reviewed replacement IMA and Cast slices declaring `minos <= 14.0`. |
| Static route/capability audit | Every known Standard/New/TV/offline/catalog entry and requested capability category was traced. | Current ownership, bypasses, code gaps and smallest next actions. | Hidden server/catalog behavior, production frequency, actual QoE, unprovided DRM/header requirements. |

### Explicitly unverified and therefore still red

- No current PlayerKit iTV playback session was launched on a simulator.
- No iOS 14 physical device launch or playback was run; such a smoke would not
  override the IMA/Cast `minos 15.0` release blocker in B2.
- No production-shaped VOD/ad/episode/offline/live/DVR/TV fixture matrix ran.
- Catch-up scrubbing is design-red: no redacted production template/manifests at
  logical seconds 0, middle and live edge have shown whether one zero-second URL
  supports native seeking. A URL-only interceptor is not accepted as sufficient.
- No real 100-switch TV stress run or live programme-boundary/clock-skew run
  occurred; the deterministic generation harness is static evidence only.
- No real IMA success/no-fill/error/background flow ran through the new
  host-owned gate; only its deterministic reducer and compile path were checked.
- VMAP post-roll is absent because the host does not call
  `adsLoader.contentComplete()`; it remains out unless product makes it a contract.
- No real signed URL expiry/refetch flow ran; only structural/static and compile
  checks exist.
- No real multi-variant HLS quality switch, stale-manifest race or eight-rate UI
  matrix ran; only parser/policy/backend tests and compile evidence exist.
- No report-list/POST, timestamp share sheet, series catalog selection or trailer
  media/end-policy flow ran; only static, focused unit and compile evidence exists.
- No downloaded movie or episode entered PlayerKit from either offline route; no
  local bookmark/resource-loader, missing/expired file, progress/relaunch or
  airplane-mode flow ran.
- No PiP session exercised the asynchronous callback or actual iTV host
  restoration; simulator and physical-device restoration remain red.
- No PiP, AirPlay, Cast, background interruption, route change, Now Playing,
  remote-command handoff, capture or assistive-technology physical matrix ran.
- No Standard-vs-PlayerKit p50/p95 startup, failure, stall, crash-free, memory,
  energy, leak or long-session comparison exists.
- No common Standard QoE definitions, baseline, tolerance or dashboard exists;
  `playbackStarted` is not decoded first frame, and the host discards most event
  context, so the session/schema contract remains red.
- iTV `19520e06` has static and dual-architecture compile evidence, but no
  simulator boot, runtime analytics or playback proof.
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
4. Evidence lane: after explicit simulator-boot permission, capture the Standard
   baseline and same PlayerKit golden movie rather than waiting for week 4.
5. Release lane: resolve B2 product decision and immutable dependency plan.

### Week 2: close visible VOD/episode regressions

**Exit:** movie, trailer and episode pass the golden matrix with Standard as an
instant fallback.

1. Runtime-prove the candidate Auto/Maximum/Optimal/Minimum menu and all eight rates.
2. ~~Add bounded WebVTT/sprite thumbnails.~~ *Candidate code and static/build evidence complete; runtime fixture proof remains.*
3. ~~Reuse iTV report and series catalog surfaces through host actions.~~
   *Candidate code/static/build evidence complete; service, share-sheet and catalog runtime proof remain.*
4. ~~Apply trailer control policy.~~ *Focused/static/build evidence complete; trailer media proof remains.*
   Inject complete English/Russian/Uzbek copy and obtain native-language approval.
5. Prove rapid episode navigation, stale responses, previous season, paywall,
   marker boundaries, network loss and ad failure.
6. Publish common QoE session definitions and provisional non-inferiority
   thresholds from measured Standard data.

### Week 3: route completeness without rewriting product shells

**Exit:** offline, catalog live and TV transport can select PlayerKit behind the
exact-value device-local selector; server cohort control remains a separate gate.

1. ~~Accept downloaded/local assets and preserve offline Core Data/widget state.~~
   *Candidate code/static/build evidence complete; both routes, local failures,
   persistence/relaunch and airplane-mode runtime proof remain.*
2. ~~Route generic pure-live and expose unified live-edge/go-live behavior.~~
   *Candidate code/static/build evidence complete; safe live/DVR fixtures remain red.*
3. ~~Put PlayerKit transport under existing TV EPG/channel/entitlement UI.~~
   *Candidate `b5f8cec2` retains Standard rollback and app business ownership;
   production-shaped catch-up timeline proof and all runtime matrices remain red.
   Do not assume a URL-only callback: first test one zero-second asset at logical
   0/middle/live-edge; if native seek fails, add the guarded token-scoped
   reloading-timeline projection and host resolver.*
4. ~~Reuse VOD ad/report/track/quality seams and correct live Cast/Now Playing
   command semantics.~~ *Static/library evidence is green through PlayerKit
   `7b72368` and `2a6c8bb` plus iTV `30d56a6b`; receiver/device proof is red.*
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
- app and PlayerKit minimums are raised to iOS 15, or both IMA and Cast are
  replaced with reviewed slices declaring `minos <= 14.0`;
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
`PlayerStringsTests.swift`, `SkipSegmentContractTests.swift`,
`PlaybackRecoveryRegressionTests.swift`, `PlatformInteractionRegressionTests.swift`,
and `BackendLifecycleRegressionTests.swift`. Those tests are necessary code evidence;
they do not substitute for the red runtime/device items above.
