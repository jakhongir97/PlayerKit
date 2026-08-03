# iTV PlayerKit native-language review checklist

Candidate copy exists for English, Russian, and Uzbek, but none of the three
language sets is approved by a named native reviewer yet. Static coverage is not
language approval and must not be reported as release parity.

This checklist covers the iTV iOS primary-player surface. PlayerKit's
macOS-only diagnostics console is release-reachable but is not used by iTV and
remains English; this migration therefore does not claim globally complete
PlayerKit localization.

## Sign-off

| Locale | Reviewer | Review date | Build/commit | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| English | — | — | — | Not reviewed | — |
| Russian | — | — | — | Not reviewed | — |
| Uzbek | — | — | — | Not reviewed | — |

## In-context review

- [ ] Verify Play versus Resume, Pause versus Stop, Close versus Dismiss, Lock
  versus Unlock, and Picture in Picture start versus stop in their actual states.
- [ ] Confirm Apple and Google terminology and AirPlay/Chromecast brand casing.
- [ ] Confirm audio, subtitle, playback-speed, quality, and streaming-stat nouns.
- [ ] Confirm recovery messages are calm, actionable, and contain no URL, token,
  backend error, or other diagnostic detail.
- [ ] Confirm every VoiceOver label and hint is unique, actionable, and describes
  the result rather than the visual icon.
- [ ] Confirm gesture-coach imperatives, scrub-tier labels, lock announcements,
  capture/mirroring copy, and Voice Control/Switch Control names and order.
- [ ] Confirm the multiplication sign in all eight speed labels is announced as
  “times,” with the expected decimal separator.

## Grammar and formatting matrix

- [ ] Check seconds at 0, 1, 2, 5, 11, 21, 22, 25, and 1.5.
- [ ] Check 0%, 62%, and 100%, including Russian nonbreaking-space behavior.
- [ ] Check 0.25×, 0.5×, 0.75×, 1×, 1.25×, 1.5×, 1.75×, and 2×.
- [ ] Check playback-position word order and scrub announcements with and without
  the optional detail.
- [ ] Check bitrate, buffer duration, frame rate, resolution, and Unknown values.
- [ ] Change language, reopen the player, and verify an unsupported stored locale
  falls back wholly to English rather than mixing number/unit grammar.

## Layout and assistive technology

- [ ] Test the smallest supported iPhone and iPad in portrait and landscape.
- [ ] Test every accessibility text size for clipping, overlap, and menu wrapping.
- [ ] Run VoiceOver, Voice Control, and Switch Control through all controls,
  recovery states, menus, gestures, and the playback-ended surface.
- [ ] Review screen-recording/mirroring protection copy and PiP restoration on a
  supported physical device.

All applicable boxes and the sign-off row must be complete before the locale is
called approved. Standard Player remains the production rollback until the full
runtime, device, QoE, and release gates also pass.
