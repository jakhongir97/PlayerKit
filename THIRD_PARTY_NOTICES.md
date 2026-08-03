# Third-Party Notices

This inventory records the remote binary targets resolved by Swift Package
Manager. A checksum proves that an archive matches `Package.swift`; it does not
prove vendor authorship, redistribution rights, or App Store compliance.

## VLCKit

- Artifact URL: `https://github.com/jakhongir97/PlayerKit/releases/download/1.0.7/VLCKit.xcframework.zip`
- SwiftPM checksum: `2bb6de2ccd80a972cec24f19a2e1ecd3829eb87c6ea972cb39ca8c7c3968d997`
- Resolved version/build: the framework plist reports `1.0`; embedded strings identify a VLC `4.0.0-dev-32833-g8e7ce13130` build. The exact VLCKit source commit and contrib lock are not recorded.
- Upstream and license: [VLCKit](https://code.videolan.org/videolan/VLCKit) is published by VideoLAN under LGPL-2.1-or-later terms. The binary also contains codec/support libraries whose exact versions and notices must be generated from the corresponding build inputs.
- Privacy manifest: missing from the resolved XCFramework. The binary imports filesystem API families covered by Apple's required-reason policy; approved reasons must be selected from actual call-site analysis, not guessed here.
- Code signature and provenance: the resolved device framework is unsigned and is mirrored from this repository's release assets rather than linked to an attested upstream build.
- Release status: **blocked** until the exact source/build recipe, corresponding-source and relinkability material, complete SBOM/notices, required-reason manifest, and verifiable artifact provenance are available.

## GoogleCast

- Artifact URL: `https://dl.google.com/dl/chromecast/sdk/ios/GoogleCastSDK-ios-4.8.4_dynamic.zip`
- SwiftPM checksum: `c9c3a794e8585198b59c6bb7da5418a3194ffa1ffa6f9a1cbdf4dc0ea26dc6cf`
- Resolved version/build: Google Cast iOS Sender SDK 4.8.4 vendor archive. Its framework plist retains Google's internal `4.8.3` bundle version.
- Upstream and license: distributed under the [Google Cast SDK and Google APIs terms](https://developers.google.com/cast/docs/terms), not PlayerKit's MIT license.
- Privacy manifest: present in the XCFramework and declares Device ID, Other Diagnostic Data, and Product Interaction. The archive's separate `NutritionLabel.txt` also describes automatic diagnostics in terms of Coarse Location, Device ID, and Performance Data. PlayerKit disables Cast analytics logging, but that does not resolve the mismatch between the vendor's two disclosures; hosts must obtain clarification and answer App Privacy from actual behavior.
- Code signature and provenance: downloaded directly from `dl.google.com`; the resolved device framework itself reports unsigned, so the release gate still requires confirmation against Apple's current SDK-signature rules.
- Release status: **blocked** pending a pinned vendor signing identity/signature-rule confirmation and reconciliation of the privacy-manifest/nutrition-label mismatch. Vendor download provenance and the upstream open-source license payload are present.

Do not remove a blocked status merely to make a release check pass. Resolve the
underlying evidence and update this inventory in the same change.
