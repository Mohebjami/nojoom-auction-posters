# Vehicle Poster

A Flutter app for creating polished vehicle sale posters from up to four photos and a small set of vehicle details. Posters can be previewed, saved as JPG, exported as PNG or SVG, shared, and reopened from local history.

## Features

- Four optional photo slots with centered cover cropping during poster generation.
- Editable title, model, USD price, color, VIN, and top-left reference number.
- Responsive editor with a two-column desktop layout and a scrollable mobile layout.
- Persistent local history for saving drafts, reopening posters, editing entries, and deleting projects.
- JPG export at 1621 × 1987 pixels, plus PNG and self-contained SVG export.
- Native gallery saving and sharing on supported platforms, with browser downloads on the web.

## Requirements

- Flutter with Dart SDK `3.12.2` or newer within the supported Flutter release.
- Android, iOS, macOS 11+, or a modern web browser.

Windows and Linux export code is included, but runner projects for those platforms are not currently part of this repository.

## Getting started

```sh
flutter pub get
flutter run
```

To run on a specific device, list available targets and pass one to Flutter:

```sh
flutter devices
flutter run -d <device-id>
```

## Using the app

1. Add a main photo and up to three supporting photos. Photos are optional.
2. Enter the vehicle details you want displayed. All fields are optional.
3. Select **Generate poster** to preview and save the current project to History, or select **Save draft** to save without opening the preview.
4. Export the result as JPG, PNG, or SVG. On macOS, JPG export opens a save dialog; on the web, it downloads the file.
5. Open **History** to reopen and edit an existing project. Use **New poster** to start a separate project.

History is stored locally on the device, or in the browser profile and site address on the web. There is no account or cross-device synchronization. Uninstalling the app or clearing browser storage removes local history.

## Rendering and export

The fixed poster artwork is retained from the supplied design. Editable text is rendered from the bundled Inter vector outlines, and long values shrink to fit. Photos are prepared once and reused by the preview, PNG capture, and SVG export. SVG exports embed all required images and do not require network access.

JPG export produces a real JPEG at quality 95, preserves the 1621 × 1987 poster dimensions, and flattens transparency onto white. Native encoding runs in a background isolate.

## Verification

```sh
flutter analyze
flutter test
flutter build bundle --debug
```

The test suite covers optional inputs, vector text, embedded images, photo cropping, transparent corners, logo rendering, responsive layouts, JPEG encoding, persistent history, reopening and editing, and storage errors. Widget tests write visual QA artifacts to `build/verification`.

Figma import and physical-device gallery or share sheets require manual verification.

## Project structure

- [`lib/main.dart`](lib/main.dart): editor, photo picker, preview, and sharing.
- [`lib/poster.dart`](lib/poster.dart): template loading, image preparation, logo rendering, SVG export, and text layout.
- [`lib/poster_history.dart`](lib/poster_history.dart) and [`lib/storage/`](lib/storage/): persistent projects for native and web platforms.
- [`lib/history_screen.dart`](lib/history_screen.dart): saved-project list, reopening, and deletion.
- [`lib/poster_export.dart`](lib/poster_export.dart): JPEG encoding.
- [`assets/template.svg`](assets/template.svg): fixed poster artwork.
- [`assets/glyphs.json`](assets/glyphs.json): Inter vector outlines, advances, and kerning data.
- [`assets/original_text.json`](assets/original_text.json): original text outlines.
- [`test/widget_test.dart`](test/widget_test.dart): regression tests and visual QA capture.

The original supplied artwork is retained under `reference/Group 11.svg`. The Inter license is included in [`INTER-LICENSE.txt`](INTER-LICENSE.txt).

## SVG compression and reusable templates

**Share SVG** now removes duplicate embedded image data and losslessly optimizes
PNGs. Photo pixels, transparency, vector artwork, and dimensions are preserved.
An optimization is kept only if it makes the output smaller. Native compression
runs in a background isolate. The result is a normal `.svg`; savings depend on
its images.

In the editor, use **Change template** to select **Original artwork**, **Clean
showroom**, or **Import SVG template…**. Existing vehicle fields and all four
photos stay in place. Save or generate to store the selected template with the
draft. History restores the saved design; older drafts use Original artwork.

Start your design from [`assets/templates/clean.svg`](assets/templates/clean.svg).
Arbitrary SVG designs must first be prepared with placeholders; the app cannot
infer which outlined text or images should be replaced.

- Place `{{title}}`, `{{model}}`, `{{price}}`, `{{color}}`, `{{vin}}`, and
  `{{number}}` inside `<text>` or `<tspan>` elements.
- Use `<image href="{{photo0}}" .../>` for the main photo, and `{{photo1}}`,
  `{{photo2}}`, `{{photo3}}` for supporting photos. `{{logo}}` uses the original logo.
- Set the image positions, dimensions, and clip paths in your design. Use
  `preserveAspectRatio="xMidYMid slice"` for centered cover crops.
- Add `data-max-width="600"` to a simple `<text font-size="48">` element to shrink
  long values to fit. Use numeric font sizes; complex tspan styling needs space
  in the design. Missing fields become empty text and missing photos are omitted.
- Use `viewBox="0 0 width height"`, at most 4096 pixels per side and 8 million
  pixels total, in an SVG file up to 10 MB. Imported designs export at their own
  dimensions; the original remains 1621 × 1987.
- Embed any other images as PNG/JPEG data URIs. Static paths, shapes, text,
  gradients, clips, and masks are supported. External links, scripts,
  stylesheets, and unsupported elements are rejected with an explanation.

Preview, PNG, and JPG render from the populated custom design. SVG sharing keeps
its vector elements. Imported text uses fonts available on the device; outline
fixed decorative text for consistent appearance across devices. The in-app
**Template guide** describes the same placeholder format.
