# CricfyRebuild

Apple TV inspired native Android UI edits for `CRICFy_v7.3.apk`. The original APK and the working original app in the main LDPlayer instance are preserved.

**Status: the redesign builds and signs successfully. Startup is not fixed or verified end to end.** The native library pins the vendor signing certificate and refuses to decrypt startup configuration after re-signing. A certificate-pin proposal is prepared, but automatic approval review rejected installing/running it without explicit approval. The UI-review APK retains vendor native files and still reaches the configuration error.

Git tracks the build/edit scripts, resource overlays, SVG artwork, and bundled fonts. The original APK, decoded vendor files, tool downloads, signing keys, build outputs, and diagnostic logs stay local. After cloning, place your original `CRICFy_v7.3.apk` in the repository root and use the fresh-decode commands below.

## Files

| Item | Location |
| --- | --- |
| UI-review APK, original native verification | `build/CRICFy-Preview-ui-review.apk` |
| Same UI-review APK at default build path | `build/CRICFy-Preview.apk` |
| Proposed signer-pin build, **not run; approval pending** | `build/CRICFy-Preview-proposed.apk` |
| Editable native Android resources | `decoded/res` |
| Resource overlays and bundled fonts | `ui-res` |
| Outline SVG icons and Preview logo | `design/icons` |
| Complete change and validation status | `analysis/overnight-status.json` |
| Compiled resource/binding validation | `analysis/compiled-ui-validation.json` |
| Certificate-pin scope verification | `analysis/native-signer-scope-verification.json` |
| Emulator screenshots and logs | `analysis/runtime/ui-review` |

Preview is named **CRICFy Preview**, with a slate TV/play vector logo, adaptive launcher icon, and package ID `com.cricfytv.studio`. The vendor app remains `com.cricfytv.sports`. Provider and permission namespaces are separated so both apps can coexist. Existing Java class names remain unchanged because bindings and native entry points reference them.

## Design changes

- Flat charcoal backgrounds, off-white text, and restrained pale-blue accents. App gradients and orange/brown focus colors removed.
- Bundled **Inter** in regular, medium, semibold, and bold. This is an Apple-like typography choice, not Apple's SF font. No font download is needed.
- Shared **20dp** corners, quiet focus enlargement, press feedback, and page fades.
- Named sport tiles, live/upcoming headings, existing event filters, and two event columns in landscape/TV mode.
- Consistent opponent-logo placement, roomier match cards, outline navigation icons, and a redesigned category picker.
- Centered Preview logo, clean typography, and a monochrome loading ring. The live-event animation uses the neutral palette too.
- The Telegram join popup's **display trigger is disabled** in MainActivity. Layouts and binding IDs are retained.
- Native Android click sounds respect system sound settings. Audio and TV interactions still need verification after startup works.

Team logos and sport images supplied by the service retain their artwork and colors.

## Build

From PowerShell in this workspace:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Apk.ps1 -Sign
```

The default build restores vendor native files before building and writes `build/CRICFy-Preview.apk`. It is useful for UI review, but the vendor certificate pin prevents successful startup with our local key.

After editing overlays or restyle scripts, apply them before building:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-Apple-Style.ps1
```

`Apply-Ui.ps1` reapplies the full stored redesign and overwrites target resources. Preserve direct edits to `decoded/res` before using it again.

For a fresh decode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-Tools.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Decompile-Apk.ps1 -Output .\decoded-fresh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-Ui.ps1 -Project .\decoded-fresh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Apk.ps1 -Project .\decoded-fresh -Sign
```

The decoder refuses to overwrite an existing output folder. Portable tools are under `.tools`; setup verifies pinned download checksums. Inter's source and OFL license are under `design/fonts`; static faces are included in `ui-res/font`.

## Startup diagnosis and pending action

The untouched original reached its home screen and loaded event listings in an isolated LDPlayer instance. Re-signing the otherwise unchanged original reproduced the configuration failure. Native analysis identified this sequence:

1. `Baker_merge` calls the native anti-tamper verifier.
2. `apk_sig.verify` compares the APK certificate's SHA-256 fingerprint with a hard-coded vendor fingerprint.
3. Our local test signature is rejected, leaving configuration encrypted. The app then tries to parse that encrypted string as JSON.

The proposal replaces exactly **32 certificate-data bytes per ABI**, across four `libnative-lib.so` files, with our local Preview certificate fingerprint. Gate functions, the SHA-256 comparison, Android signature checks, and environment checks remain unchanged. It changes which signer is trusted; it has not been installed or run.

Automatic approval review requires explicit approval for this exact certificate trust change before emulator execution. Do not retry execution through another launch path or disable verification. After approval, test the proposed APK in the separate **CRICFy Preview** LDPlayer instance: configuration loading, home/category filtering, TV focus, popup suppression, and playback. Further issues may still emerge.

`Build-Apk.ps1 -UsePreviewSignerPin` prepares the proposal. It restores vendor native files in `decoded` afterward, including on build/signing failure. This option does not grant approval to run the result.

## Editing map

| Change | File |
| --- | --- |
| Home and landscape variant | `decoded/res/layout/fragment_home.xml`, `layout-land/fragment_home.xml` |
| Sport tiles/category picker | `event_cat_item.xml`, `cat_item.xml`, `cat_chose_dialog.xml` under `decoded/res/layout` |
| Event cards | `decoded/res/layout/event_item.xml`, `layout-land/event_item.xml` |
| Navigation | `decoded/res/layout/activity_main.xml`, `tv_top_ly.xml` |
| Palette/radius/typography | `ui-res/values/ui_colors.xml`, `ui_dimens.xml`, `ui_styles.xml`, `ui-res/font` |
| Launch/error UI | `ui-res/layout/activity_splash.xml`, `error_layout.xml` |
| Global restyle/wide-screen layouts | `scripts/apple_style.py` |
| Popup, category captions, TV columns | `scripts/apply_app_edits.py` |
| Native certificate proposal | `scripts/Apply-Native-Signer.ps1` |

Keep existing view IDs and classes: compiled view bindings depend on them.

## Decompilation and validation

The resource table had misleading type names. `Normalize-Resources.ps1` repairs them in a copy and preserves numeric IDs. Apktool decodes resources without rebuilding protected bytecode.

DEX also contains invalid unreachable payload trailers. `readable_dex.py` removes them **only in analysis copies**, enabling usable JADX output under `analysis/readable-source/sources`. The initial `reference/sources` output is incomplete. This is not an original Android Studio source project.

Production DEX retains original trailers and code offsets. Only narrow UI behavior edits and the package-identity string change; SHA-1 and Adler-32 headers are recomputed. Independent decompilation confirms named sport captions and the two-column TV grid, and shows the Telegram popup branch is unreachable.

Checks cover **6,008 original resource IDs**, **558 bound view IDs/classes across 126 layout variants**, DEX integrity, original assets, native-library scope, zip alignment, and v2/v3 signatures. Home, filtering, audio, and playback runtime checks remain pending approval of the signer proposal.

The local key is `.tools/keys/cricfy-ui-test.p12`, alias `cricfy-ui`, password `android`. Keep it for subsequent Preview updates. It cannot sign an update to the vendor-signed original package.
