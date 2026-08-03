# iTV primary-player 30-day plan

**Window:** 3–31 August 2026
**Outcome:** make PlayerKit the rollback-safe primary player for iTV iOS without
losing the Standard Player's production contract.

## Scope that makes one month possible

- AVPlayer is the production backend. The backend picker is not a user feature.
- iTV keeps ownership of URLs/authentication, entitlements, IMA, history, EPG,
  channel data, sharing, issue reporting, and analytics.
- PlayerKit owns playback, timeline mechanics, controls, recovery, tracks,
  gestures, accessibility, PiP, AirPlay, Cast integration, and observable state.
- The app source target remains iOS 14, but pinned IMA and Cast slices declare
  `LC_BUILD_VERSION minos 15.0`. An iOS 14 smoke cannot close that mismatch:
  release must raise both app and PlayerKit minimums to 15 or replace both
  binaries with reviewed slices declaring `minos <= 14.0`.
- This month does not include tvOS, public/open-source polish, or speculative DRM.
  A verified protected production asset immediately promotes FairPlay into scope.
- Reels remains a separate product surface. Inline previews may use a small native
  AVPlayer surface; they do not justify making full-screen PlayerKit state global.

## Current measured state — 3 August

- PlayerKit and the real iTV app compile against the local candidate. Current
  generic Debug simulator builds pass for both arm64 and x86_64 in PlayerKit and
  iTV; generic iOS 14 PlayerKit source/device slices also compiled earlier.
- The latest full `swift test --no-parallel` result, captured before cache
  cleanup, executes 355 tests with 5 environment-dependent skips and 0 failures.
  Focused checks now also cover explicit live timelines/Cast/remote commands,
  empty-state Now Playing cleanup and opt-in direct-load track preservation.
- The candidate VOD bridge now preserves Standard's exact resume thresholds,
  metadata, intro/credits actions, entitlement/paywall decisions, sorted async
  episode navigation, previous-season fallback, history fields, selected tracks,
  playback rate, sharing, and watch analytics. iTV `19520e06` now deduplicates
  watch events by logical kind plus app-owned content/file IDs: retry does not
  re-emit, while real movie, episode and identified-live transitions do;
  embedded TV keeps its channel-ID path. No URL/title/ad/user data enters the
  identity. The verifier and final dual-architecture build pass; runtime event
  proof remains red.
  Stale episode responses are rejected, paid-next navigation retains the
  completed player state, temporary child navigation pauses, and actual
  dismissal tears down the singleton owner.
  Late URL/payment responses cannot recreate playback after exit, and the one
  final progress write is allowed to outlive controller deinitialization.
- The two highest-risk VOD gaps were pulled forward: iTV now owns a deterministic
  generation-keyed IMA content gate and a current-item signed-URL refresh bridge.
  Ad-bearing content is held until IMA success/failure/timeout releases it once;
  stale ad and URL responses cannot install content. These are code-complete
  candidates, not production-proven behavior: the real tag/expiry matrices are
  still mandatory. VMAP post-roll is absent because the host does not call
  `adsLoader.contentComplete()`; add it only if product makes post-roll a contract.
- The pure IMA gate assertion harness and signed-URL structural contract check
  pass. The final generic iTV Debug build resolves exact IMA 3.28.10 and compiles
  and links the candidate for both arm64 and x86_64 with zero errors.
- The remaining audited VOD host seams now have code candidates: PlayerKit
  `3949727` adds a backward-compatible speed/quality/ended-overlay presentation
  policy; iTV `412ce885` reuses the existing report service and timestamp share,
  `82446853` round-trips typed selections through the existing series catalog,
  and `73acc8b5` applies strict Standard trailer control/end/progress behavior.
  All three iTV static verifiers and the dual-architecture builds pass.
- PlayerKit `f8a3937` allows a host to complete PiP restoration asynchronously,
  and iTV `db5be536` restores the actual owning presentation through its existing
  root helper with owner/exit/root guards. PlayerKit `f179890` adds one optional,
  host-retained `AVURLAsset`; iTV `fbf7f80b` routes both downloaded-entry shapes
  behind the existing selector only for an existing local file, suppresses
  online-only ad/retry/quality/menu paths, and preserves widget/Core Data
  progress. The focused tests, iTV static verifiers, Swift source parses and
  dual-architecture PlayerKit/iTV builds pass. No PiP session or downloaded
  playback has run, and airplane-mode, invalid/expired-file, progress/relaunch
  and physical-device gates remain red.
- Step 6 now has a rollback-safe static candidate. PlayerKit `9e8d16a` adds
  explicit VOD/seekable-live/pure-live timelines and live-edge controls;
  `9773f43` types live Cast handoffs; and `7b72368` adds default-off track
  preservation for host reloads. iTV `ebb9767b` routes generic live through the
  existing selector, `afdcc554` rejects stale TV channel/guide/timeshift
  generations, and `b5f8cec2` puts PlayerKit transport inside the one shared TV
  shell while retaining app-owned EPG/auth/favorites/timeshift state and the
  Standard-default rollback. Initial/program catch-up URLs are wired, but
  catch-up seeking is design-red: Standard rebases logical programme time over
  replacement assets while PlayerKit publishes backend time and direct consumers
  read it. A URL-only callback is not sufficient by assumption. A redacted
  template plus manifests at logical seconds 0, middle and live edge must first
  show whether native AVFoundation seeking on one zero-second URL works. If not,
  use a token-scoped reloading-timeline projection and host resolver with paused
  intent, boundary and generation guards. All live/DVR/TV runtime gates remain red.
- iTV `74f45e8b` makes exact stored `Test Player` the only PlayerKit opt-in across
  all five selectors. Nil, `Standard Player`, unknown, empty and case variants
  fail closed to Standard. This device-local setting is not the server
  canary/kill switch required for rollout.
- The PlayerKit Step 7 static slice is also green. PlayerKit `2a6c8bb` gates
  remote skip/scrub commands on the current seek window and clears stale
  Now Playing metadata after an empty reset. iTV `30d56a6b` retains and removes
  only radio-owned remote targets so radio cannot intercept the player after
  dismissal. iTV `95ce19f6` then gives IMA remote ownership while the content
  gate is `held`, `requesting`, `ready`, `playing` or `releasePending`, and while
  `released` VMAP is visible or paused under a covered presentation. Covered
  content resumes only for the same owner that previously requested playback,
  preserving user pause; background entry checkpoints guarded VOD/offline
  progress without writing embedded TV, trailer/live or IMA-controlled state.
  Interruption, receiver, ad, lock-screen, route and device proof remains red.
- All 13 iTV `verify_playerkit_*.py` scripts and the radio ownership verifier
  pass through `19520e06`; EN/RU/UZ property lists pass `plutil`. The final
  generic Debug build through `19520e06` passes for arm64 and x86_64, and `lipo`
  confirms a fat x86_64/arm64 app binary. Both architectures warn that the
  iOS-simulator 14.0 app links IMA/Cast built for 15.0; packaged slices confirm
  `minos 15.0`. No simulator boot/runtime proof exists. Native RU/UZ approval
  remains red.
- PlayerKit now exposes all eight Standard playback rates and an accessible
  Auto/Maximum/Optimal/Minimum adaptive HLS menu. iTV fixes and reuses its master
  parser, supplies only sanitized raw bitrates after ad release, rejects stale
  item results, avoids shared persistent caching for signed manifests, preserves
  the semantic choice across episodes, and injects
  EN/RU/UZ copy. PlayerKit `18cd8a7` and iTV `c3cbf3bc` now cover all 126
  iTV/iOS `PlayerStrings` values with 125 matched host keys or locale-aware
  numeric formatters; the contract, property-list, placeholder-signature,
  seconds/rate/percentage and 7 focused library checks pass. Candidate copy is
  not native-approved and localized device/layout proof remains open. The
  macOS-only diagnostics console is outside this iTV/iOS slice and remains
  English.
- QoE production proof is red. `playbackStarted` is not a decoded-first-frame
  metric; the host discards most event context; and no common Standard
  definitions, baseline, written tolerances, dashboard or session/schema
  contract exists. There is also no server cohort or kill switch.
- Runtime smoke testing is still open because no simulator is booted and the
  installed runtimes are iOS 18.5 and 26.3 only. In particular, no report
  list/POST, timestamp share sheet, series catalog selection or trailer media/end
  flow has run; these slices remain runtime-red despite static/test/build proof.
  Neither offline entry nor PiP host restoration has run; no live/DVR/TV,
  production-shaped catch-up timeline, Cast, AirPlay, remote-command or
  physical-device flow has run. Airplane-mode and every fixture, device and
  system-service gate remain red.
- The produced iTV app declares iOS 14, but embedded Cast and IMA declare
  `LC_BUILD_VERSION minos 15.0`. Compilation and an iOS 14 runtime smoke cannot
  close this release blocker. Raise app and PlayerKit minimums to 15, or replace
  both binaries with reviewed slices declaring `minos <= 14.0`.
- The candidate now pins Google IMA exactly to 3.28.10 instead of moving `main`.
  iTV still resolves the unpublished local `../PlayerKit`; release reproducibility
  requires publishing it immutably and completing binary provenance/privacy/signing review.

## Non-negotiable release contract

Standard Player is removable only when all existing iOS entry points pass and the
PlayerKit cohort is non-inferior for:

- playback-start success and p50/p95 startup time;
- fatal playback failures and crash-free sessions;
- rebuffer count and rebuffer-time ratio;
- seek completion, resume position, and end-of-item behavior;
- ads, history, selected tracks/rate, sharing, and issue reporting;
- offline playback, generic live, TV live edge, catch-up, and channel switching;
- PiP, AirPlay, Cast, background audio, interruptions, and route changes;
- English, Russian, and Uzbek UI;
- VoiceOver, Voice Control, Switch Control, Dynamic Type, orientation, and iPad.

No gate is satisfied by compilation alone. Every non-trivial behavior gets one
small runnable regression check, and system integrations get device evidence.

## Week 1 — one real integration baseline

**Exit:** the current PlayerKit branch builds inside the real iTV app, and a VOD
session preserves the app's metadata and persistence contract.

- Resolve the minimum OS honestly: raise app and PlayerKit to iOS 15, or replace
  both IMA and Cast with reviewed `minos <= 14.0` binary slices.
- Replace the app's 1.1.0 development pin with the reviewed candidate during
  integration; publish a versioned remote pin before release.
- Clean stale PlayerKit product references without changing unrelated project
  state.
- Add the smallest deliberate product contract: exact skip markers, host policy,
  quality cap, and required callbacks. Do not add app business models.
- Configure AVPlayer, AirPlay, background playback, Now Playing, PiP restoration,
  and signed-URL retry in the host. The PiP restoration candidate is compiled;
  its device matrix remains open.
- Preserve exact resume, poster/Cast metadata, selected audio/subtitle/rate,
  history, widget, sharing, paywall, and episode navigation.
- Establish PlayerKit unit tests plus an iTV integration smoke check.

## Week 2 — VOD and episode parity

**Exit:** movies, trailers, and episodes pass the golden-flow matrix with Standard
still available as a runtime fallback.

- Keep IMA host-owned and make content installation/failure recovery deterministic.
- Runtime-prove the implemented adaptive HLS Auto/Maximum/Optimal/Minimum menu.
- Add backend-provided intro/credits behavior; heuristics are fallback only.
- Runtime-prove the implemented bounded WebVTT scrub thumbnails with representative media.
- Runtime-prove the implemented strict trailer controls/resume/end policy and
  existing-series-catalog episode selection bridge.
- Runtime-prove the implemented app-owned report and timestamp-share menu.
- Localize all PlayerKit chrome in English, Russian, and Uzbek.
- Define the host QoE session/schema and retain required privacy-safe context;
  add a true decoded-first-frame signal alongside load/ready/stall/recovery/fatal/
  seek/completion/external/exit events.
- Run network-loss, expired-URL, ad-failure, rapid episode-switch, and lifecycle
  checks against production-shaped fixtures.

## Week 3 — offline, live, and TV transport

**Exit:** every route that currently bypasses the Test Player can use PlayerKit
behind the exact-value device-local selector while existing iTV product UI stays
intact. This is not the server rollout flag required by Week 4.

- ~~Accept downloaded/local assets and preserve offline Core Data progress.~~
  Candidate code/static/build evidence is complete for both entries; actual
  playback, failure, progress/relaunch and airplane-mode proof remain open.
- ~~Introduce only the timeline distinctions the UI needs: VOD, seekable
  live/DVR, and pure live.~~ Candidate library and generic-live routing are
  statically green; safe live/DVR fixtures and runtime transitions remain red.
- ~~Put PlayerKit transport under the existing TV shell while retaining iTV EPG,
  favorites, tariff/auth, channel pagination and catch-up ownership.~~ Candidate
  `b5f8cec2` is compiled behind the Standard-default selector. Catch-up timeline
  semantics remain unproved; do not add a URL-only callback.
- Validate a redacted template/manifests at logical seconds 0, middle and live
  edge. If one zero-second URL cannot seek natively, add a token-scoped
  reloading-timeline projection plus host resolver with paused-intent, boundary
  and generation guards. Then run programme-boundary, rapid-zap and clock checks.
- ~~Fix live Cast/Now Playing and radio remote-command ownership semantics.~~
  PlayerKit `9773f43`/`2a6c8bb` and iTV `30d56a6b`/`95ce19f6` have focused static
  checks, including IMA ownership, covered resume and background checkpoints;
  verify PiP/AirPlay/Cast/background/ad/remote behavior on devices.
- Remove full-screen Standard routes only after their PlayerKit equivalents pass;
  keep the device-local rollback and add separate server rollout control.

## Week 4 — proof and rollout

**Exit:** PlayerKit is the default for a measured cohort, rollback is immediate,
and Standard removal has an evidence-backed go/no-go decision.

- Test the supported iPhone/iPad and iOS-version matrix on physical devices.
- Run VoiceOver, Voice Control, Switch Control, large Dynamic Type, rotation,
  multitasking, interruptions, headphones, AirPlay, Cast, PiP, and capture policy.
- Profile SwiftUI updates, CPU, memory, energy, startup, and long-session leaks.
- Start with internal users, then 1%, 5%, 25%, and 100% only while quality gates
  stay green. Cohort changes are server-controlled and reversible.
- Remove the Standard selector and dead implementation only after the sustained
  100% gate. Deletion is a separate reviewed change, not part of enabling 100%.
- Publish the versioned PlayerKit release, migration note, known limitations, and
  evidence bundle.

## Parallel lanes

1. **Engine/API:** compatibility, exact contracts, playback/recovery, tests.
2. **iTV integration:** adapter, ads, persistence, paywall, routes, TV shell.
3. **UX/accessibility/localization:** chrome, thumbnails, strings, assistive tech.
4. **Evidence/release:** fixtures, QoE, devices, profiles, canary, rollback.

The first three lanes can progress concurrently. The evidence lane begins on day
one because a month-end comparison is impossible without a Standard baseline.

## Daily execution board

| Date | Engine / PlayerKit | iTV integration | Evidence and release gate |
| --- | --- | --- | --- |
| Aug 3 | iOS 14 compile, exact marker contract | local candidate pin, remove stale package refs | freeze scope; capture Standard capability baseline |
| Aug 4 | product policy/callback seams | VOD metadata, exact resume, history and track/rate persistence | app compile plus unit suite |
| Aug 5 | manual HLS quality policy implemented early | iTV parser/tier mapping candidate complete | quality-switch and fallback runtime fixtures |
| Aug 6 | QoE event enum exists; decoded first frame does not | logical watch IDs are deduped, but most QoE context is discarded | Standard definitions/baseline/tolerances/dashboard and session schema red |
| Aug 7 | lifecycle/recovery hardening; async PiP restoration contract now compiled | signed-URL refresh and guarded PiP host restoration candidates pulled forward; runtime expiry/PiP proof remain | Week 1 VOD smoke gate |
| Aug 10 | deterministic ad/content handoff seam | host-owned IMA candidate pulled forward; real SDK/tag failure paths remain | preroll/no-fill/error/background matrix |
| Aug 11 | WebVTT thumbnail loader/cache | connect iTV thumbnail URLs | scrub/memory/network checks |
| Aug 12 | host presentation policy pulled forward; episode navigation contract | report/share menu and typed existing-catalog selection pulled forward | static checks green; report/share/catalog/trailer runtime and episode race checks remain |
| Aug 13 | complete injectable iTV/iOS PlayerStrings candidate | matched English/Russian/Uzbek host bags and locale-aware formatters | static/compile gates green; native approval, truncation, RTL-safe layout and VoiceOver copy remain |
| Aug 14 | VOD defect burn-down | movie/trailer/episode golden flows; strict trailer candidate already compiled | Week 2 non-inferiority gate; host-action/trailer media proof required |
| Aug 17 | host-retained local `AVURLAsset` candidate compiled and focused lifecycle check green | both downloaded movie/episode entries route behind the selector and preserve offline progress in code | airplane-mode, invalid/expired-download, relaunch and progress runtime matrix remains red |
| Aug 18 | explicit VOD/seekable-live/pure-live candidate landed | generic pure-live route compiled behind selector | live/DVR fixture and transition proof red |
| Aug 19 | live edge/go-live candidate landed | shared EPG/channel shell retained around PlayerKit transport | zero-second native-seek probe and, if needed, guarded reloading-timeline projection remain red |
| Aug 20 | opt-in track preservation and load identity landed | stale zapping generations plus shared TV transport statically verified | deterministic 100-generation check green; real 100-switch stress red |
| Aug 21 | live Cast and remote seek gating landed | radio targets plus IMA/covered/background ownership hardened through `95ce19f6` | all AirPlay/Cast/PiP/ad/background/lock-screen/device proof red |
| Aug 24 | accessibility/performance fixes | host chrome integration cleanup | supported iPhone/iPad accessibility matrix |
| Aug 25 | long-session leak/energy fixes | integration ownership/teardown audit | Instruments and 2-hour playback evidence |
| Aug 26 | release API freeze | remote version pin and rollback flag | clean-checkout build and migration rehearsal |
| Aug 27 | release-candidate defect burn-down | production-shaped catalog sweep | internal cohort go/no-go |
| Aug 28 | no feature work; RC stabilization | canary configuration | 1% then 5% only if gates stay green |
| Aug 31 | release/known-limitations note | 25%/100% decision remains metric-gated | retain immediate Standard rollback; removal is separate |

## Ownership and working rhythm

- Codex owns code changes, focused regression checks, compile/test loops, diff
  review, migration notes, and keeping this board current.
- The app owner supplies production access that cannot live in the repository:
  devices, redacted streams, analytics/flag permissions, signing, and final
  product calls. Those inputs do not block unrelated implementation work.
- Every day ends with a green branch or an explicit red gate with its failing
  command, log, owner, and smallest next action. Work is merged vertically by
  user-visible flow, not as large engine-only batches.
- Standard remains the runtime fallback while parity is proved. New PlayerKit
  behavior lands behind the existing selection/flag seam until rollout.

## Definition of done for each route

A route is not complete until all of these are true:

1. It enters PlayerKit from the real app and plays a production-shaped asset.
2. Auth/paywall/ad ownership and failure behavior match Standard.
3. Resume, history, audio, subtitle, rate, sharing, and analytics survive exit,
   relaunch, and episode/channel transitions where applicable.
4. Seek, retry, end, background/foreground, interruption, rotation, and teardown
   each have either a focused automated check or named device evidence.
5. Accessibility and localization pass on the smallest iPhone and iPad layouts.
6. Its QoE metrics meet the release contract and Standard can still be restored
   immediately without an App Store release.

## Stop-ship conditions

- Any crash, content/entitlement bypass, broken ad obligation, history corruption,
  or playback continuing after dismissal.
- Worse playback-start failure, fatal-error, or rebuffer rates outside the agreed
  measurement tolerance; the tolerance must be written in the dashboard before
  canary rollout.
- A supported route silently falling back to a different URL, losing required
  request authorization, or exposing protected capture/output.
- No working server-side rollback, no clean-checkout reproducible build, or no
  physical-device evidence for PiP/AirPlay/Cast/interruption behavior.

## Inputs only the app owner can provide

- A booted simulator and, for final gates, supported physical devices.
- A redacted production test catalog covering VOD, ads, episodes, offline, pure
  live, DVR/catch-up, Cast-accessible URLs, and every track/subtitle shape. The
  catch-up fixture must include its template and manifests at logical seconds 0,
  middle and live edge.
- Confirmation whether any active catalog item uses FairPlay or request headers.
- A product-owned server cohort/kill-switch contract and access to analytics
  dashboards for rollout; neither server control nor a common QoE dashboard
  exists in the current candidate.
