# Vehicle Poster

Flutter app for creating vehicle posters from four optional photos and vehicle details.

## Run

```sh
flutter pub get
flutter run
```

## Use

1. Add a main photo and up to three supporting photos.
2. Enter any title, model, USD price, color, VIN, and top-left number you want displayed. All fields and photos are optional; the Type / trim field has been removed.
3. Select **Generate poster** to review the poster. Its editable details and original selected photos are automatically saved to History before the preview opens. You can also use **Save draft** without generating.
4. Select **Save JPG to gallery** on Android/iPhone/iPad. Grant photo-saving permission when requested. On macOS, **Save JPG** opens a file save dialog. On the web it downloads the JPG; mobile browsers may require you to move the download into Photos manually.
5. **Share SVG** and **Share PNG** remain available.
6. Use the **History** icon in the editor to reopen a poster, even after restarting the app. Change its photos or details, then use **Save changes** or **Generate poster** to update the same history entry.
7. Use **New poster** (+) to start a separate poster. The editor asks before discarding unsaved changes. History also lets you delete saved projects; exported images remain untouched.

History is local to the device (or browser profile and site address), with no account or cross-device sync. Uninstalling the app or clearing its data/browser storage removes history. Save draft or generate before closing the app to preserve your latest edits. Posters created before this feature was installed cannot be recovered from previous sessions.

The macOS app now requires macOS 11 or later because of the gallery plugin's native dependency. Windows and Linux save-dialog code is included, but this repository does not currently contain Windows/Linux runner projects.

The editor uses two columns on larger screens and a scrollable single column on phones. The Generate action remains available at the bottom.

## Rendering and export

- Poster dimensions are 1621 × 1987 pixels.
- Selected images are resized without cropping on selection. During generation, each image receives a centered cover crop for its own frame, including transparent diagonal corners where appropriate.
- The prepared PNG bytes are shared by the app preview, PNG capture, and SVG export. SVG photos have explicit bounds and do not depend on an importer's interpretation of SVG slice cropping or photo clip paths. Photos remain separate image layers; areas outside the prepared crop are discarded in the exported asset.
- The NCA logo is extracted from the template's embedded image and original pattern transform. It is rendered directly in Flutter and embedded directly in the exported SVG, without a pattern fill.
- The fixed poster artwork and vector text are retained. Color alone occupies the original red detail line. Supported editable text uses the bundled Inter outlines, and long values shrink to fit.
- The preview waits for its raster images before PNG capture. SVG files embed all required images and do not require network access.
- JPG export encodes a real JPEG at quality 95, preserving 1621 × 1987 pixels and flattening transparency onto white. Encoding runs on a background isolate on native devices.
- Native history uses an application-support database; the web uses IndexedDB. Text, timestamps, and four original photo slots are saved transactionally. Existing history entries are updated without creating duplicates. Storage errors keep the editor inputs available for retry.
- `PosterTemplate.build` is asynchronous and returns the vector design, complete export SVG, prepared photos, and logo. Callers must await it and use its prepared images in the preview.

## Verification

```sh
flutter analyze
flutter test
flutter build bundle --debug
```

Tests cover optional inputs, vector outlines, embedded image consistency, photo crop pixels and transparent corners, logo rendering, phone/desktop layouts, JPEG encoding, persistent history, reopening/editing, and storage errors. Visual QA artifacts are written to `build/verification` by the widget tests.

Direct import into the Figma application and physical-device gallery/share sheets require manual verification.

## Project map

- `lib/main.dart`: editor, photo picker, preview, and native sharing.
- `lib/poster.dart`: template loading, photo/logo preparation, SVG export, and vector text layout.
- `lib/poster_history.dart` and `lib/storage/`: persistent editable projects on native devices and the web.
- `lib/history_screen.dart`: saved-poster list, reopening, and deletion.
- `lib/poster_export.dart`: JPEG encoding.
- `assets/template.svg`: fixed poster artwork.
- `assets/glyphs.json`: Inter vector outlines, advances, and kerning.
- `assets/original_text.json`: original text outlines.
- `test/widget_test.dart`: regression tests and visual QA capture.

The original supplied artwork is retained under `reference/Group 11.svg`. Inter's license is included in `INTER-LICENSE.txt`.
