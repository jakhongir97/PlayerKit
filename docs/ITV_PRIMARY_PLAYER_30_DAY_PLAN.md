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
- iOS 14 remains supported unless a later measured blocker makes raising the app
  minimum the smaller change.
- This month does not include tvOS, public/open-source polish, or speculative DRM.
  A verified protected production asset immediately promotes FairPlay into scope.
- Reels remains a separate product surface. Inline previews may use a small native
  AVPlayer surface; they do not justify making full-screen PlayerKit state global.

## Current measured state — 3 August

- PlayerKit and the real iTV app compile against the local candidate; generic
  iOS 14 simulator and device PlayerKit slices also compile. The final warm iTV
  Debug simulator build completed in 23.8 seconds, and a second generic build
  from clean derived data resolved the dependency graph and succeeded.
- `swift test --no-parallel` executes 321 tests with 5 environment-dependent
  skips and 0 failures. Focused checks cover exact markers, quality policy, QoE,
  injectable strings, recovery, and host-owned PlayerView teardown policy.
- The candidate VOD bridge now preserves Standard's exact resume thresholds,
  metadata, intro/credits actions, entitlement/paywall decisions, sorted async
  episode navigation, previous-season fallback, history fields, selected tracks,
  playback rate, sharing, and watch analytics. Stale episode responses are
  rejected, paid-next navigation retains the completed player state, temporary
  child navigation pauses, and actual dismissal tears down the singleton owner.
  Late URL/payment responses cannot recreate playback after exit, and the one
  final progress write is allowed to outlive controller deinitialization.
- The two highest-risk VOD gaps were pulled forward: iTV now owns a deterministic
  generation-keyed IMA content gate and a current-item signed-URL refresh bridge.
  Ad-bearing content is held until IMA success/failure/timeout releases it once;
  stale ad and URL responses cannot install content. These are code-complete
  candidates, not production-proven behavior: the real tag/expiry matrices are
  still mandatory. VMAP post-roll is not claimed until inventory and episode
  auto-next deferral are confirmed.
- The pure IMA gate assertion harness and signed-URL structural contract check
  pass. The final generic iTV Debug build resolves exact IMA 3.28.10 and compiles
  and links the candidate for both arm64 and x86_64 with zero errors.
- PlayerKit now exposes all eight Standard playback rates and an accessible
  Auto/Maximum/Optimal/Minimum adaptive HLS menu. iTV fixes and reuses its master
  parser, supplies only sanitized raw bitrates after ad release, rejects stale
  item results, avoids shared persistent caching for signed manifests, preserves
  the semantic choice across episodes, and injects
  EN/RU/UZ copy for this menu slice. Parser/policy/rate checks pass; real HLS and
  layout proof remain open. The full approved PlayerStrings bags are still
  incomplete, and `playbackStarted` is not a decoded-first-frame metric.
- Runtime smoke testing is still open because no simulator is booted and the
  installed runtimes are iOS 18.5 and 26.3 only.
- The produced iTV app declares iOS 14, but its embedded Google Cast and Google
  IMA Mach-O binaries declare minimum iOS 15. This is a release blocker for any
  claim of iOS 14 support: prove the existing production combination on an iOS
  14 device, select compatible vendor binaries, isolate the features safely, or
  raise the app minimum from product data. Compilation does not close this gate.
- The candidate now pins Google IMA exactly to 3.28.10 instead of moving `main`.
  Release reproducibility still requires publishing the local PlayerKit candidate
  immutably and completing binary provenance/privacy/signing review.

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

- Restore iOS 14 compatibility and build simulator/device slices.
- Replace the app's 1.1.0 development pin with the reviewed candidate during
  integration; publish a versioned remote pin before release.
- Clean stale PlayerKit product references without changing unrelated project
  state.
- Add the smallest deliberate product contract: exact skip markers, host policy,
  quality cap, and required callbacks. Do not add app business models.
- Configure AVPlayer, AirPlay, background playback, Now Playing, PiP restoration,
  and signed-URL retry in the host.
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
- Restore trailer-specific controls/resume behavior and the episode sheet slot.
- Localize all PlayerKit chrome in English, Russian, and Uzbek.
- Add iOS QoE events for load, ready, first frame, stall, recovery, fatal error,
  seek, completion, external playback, and exit.
- Run network-loss, expired-URL, ad-failure, rapid episode-switch, and lifecycle
  checks against production-shaped fixtures.

## Week 3 — offline, live, and TV transport

**Exit:** every route that currently bypasses the Test Player can use PlayerKit
behind a feature flag while the existing iTV product UI remains intact.

- Accept downloaded/local assets and preserve offline Core Data progress.
- Introduce only the timeline distinctions the UI needs: VOD, seekable live/DVR,
  and pure live. All seek entry points use the same range.
- Put PlayerKit transport under the existing TV shell; retain iTV EPG, favorites,
  tariff/auth, channel pagination, and catch-up URL construction.
- Validate live edge, `{START_AT}`/`{SECONDS}` catch-up replacement, programme
  boundaries, rapid zapping, stale responses, and server/device clock offset.
- Fix live Cast/Now Playing semantics and verify PiP/AirPlay/background behavior.
- Remove full-screen Standard routes only after their PlayerKit equivalents pass;
  keep one rollback flag.

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
| Aug 6 | QoE event contract | connect existing analytics identifiers | Standard and PlayerKit startup/stall baselines |
| Aug 7 | lifecycle/recovery hardening | signed-URL refresh candidate pulled forward; PiP restoration and runtime expiry proof remain | Week 1 VOD smoke gate |
| Aug 10 | deterministic ad/content handoff seam | host-owned IMA candidate pulled forward; real SDK/tag failure paths remain | preroll/no-fill/error/background matrix |
| Aug 11 | WebVTT thumbnail loader/cache | connect iTV thumbnail URLs | scrub/memory/network checks |
| Aug 12 | episode navigation completion contract | next/previous, rapid switching, end state | episode race regression checks |
| Aug 13 | localizable PlayerKit strings | English/Russian/Uzbek host strings | truncation, RTL-safe layout, VoiceOver copy |
| Aug 14 | VOD defect burn-down | movie/trailer/episode golden flows | Week 2 non-inferiority gate |
| Aug 17 | local asset support | downloaded movie/episode routes and progress | airplane-mode and expired-download matrix |
| Aug 18 | unified VOD/live seekable ranges | generic live/DVR route | live-edge and catch-up range checks |
| Aug 19 | live transition/recovery rules | keep current EPG/channel shell | clock-offset/program-boundary fixtures |
| Aug 20 | rapid-load cancellation and identity | channel zapping and stale-response guards | 100-zap stress run |
| Aug 21 | external playback live semantics | AirPlay/Cast/PiP/background wiring | Week 3 route-completeness gate |
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
  live, DVR/catch-up, Cast-accessible URLs, and every track/subtitle shape.
- Confirmation whether any active catalog item uses FairPlay or request headers.
- Access to the existing feature-flag and analytics dashboards for cohort rollout.
