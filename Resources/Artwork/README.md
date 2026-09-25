# Clock & Ledger application icon

Created with the built-in image generation tool. The original transparent PNG
is `ClockAndLedger-master.png`. The generated artwork was preserved, including
its alpha channel; platform assets only resize or re-encode it.

Run `make -f Makefile icons` on macOS to reproduce the packaged assets using
`sips` and `iconutil`:

- `Resources/ClockAndLedger.png`: 128×128 transparent GNUstep icon. GNUmakefile
  names it with `ClockAndLedger_APPLICATION_ICON` and includes it through
  `ClockAndLedger_RESOURCE_FILES`. GNUstep Make generates `NSIcon` and the
  desktop launcher icon entry. No source-tree paths are used inside the bundle.
- `Resources/ClockAndLedger.icns`: macOS icon with 16, 32, 128, 256 and 512-point
  images at 1× and 2× (up to 1024 pixels). `CFBundleIconFile` points to this file
  in `Contents/Resources`.

Normal builds use the checked-in assets; GNUstep builds do not need macOS tools
or access to the image generation service.

## Generation prompt

Use case: logo-brand. Asset type: production desktop application icon for
Clock & Ledger, a native time tracking and invoice app for GNUstep and macOS.
Create one square 1024x1024 icon on a genuinely transparent background. Subject:
a handsome closed bookkeeping ledger with a simple analog clock integrated
over its cover, combining accounting and tracked time into one bold recognizable
silhouette. Style: refined classic desktop icon illustration with subtle
dimensional shading, clean precise edges, substantial simple shapes, restrained
detail, professional rather than cartoonish. Clock face is light, with two
clearly readable dark hands and minimal hour markers; the ledger has a distinct
spine and a few neat page edges. Center the complete object with approximately
8 percent transparent margin on all sides. Strong contrast and legibility at
32 and 48 pixels. No text, no letters, no numerals, no currency symbols, no logos,
no watermark, no surrounding scene, no background tile, no drop shadow beyond
the object silhouette. Return a finished icon asset, not a presentation or mockup.
