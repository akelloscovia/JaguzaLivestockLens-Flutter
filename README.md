# Frame

Frame is a Flutter camera app for capturing cattle tags and reviewing tag OCR results.

## Capture Flow

- Captures and preserves the original JPEG from the device camera.
- Lets the user draw and confirm the physical tag rectangle, then crops it in original-image coordinates.
- Runs Latin-script text recognition on the tag crop only with Google ML Kit on Android and iOS.
- Shows the selected tag box on the original and OCR boxes/text on the crop; confidence is included when the platform provides it.
- Sends the original image, tag crop, and tag-only OCR evidence to a configured backend.
- Stores the five most recent originals, crops, text, bounds, confidence, and upload results in app documents storage on Android/iOS.

The browser camera preview is supported, but the native ML Kit OCR plugin does not support Flutter Web. Browser evidence is kept in memory for the current session.

The tag box is user-confirmed because the project does not yet include a trained cattle-tag detector. This keeps OCR focused now and leaves a clean integration point for an automatic detector later.

## Backend Contract

Set `UPLOAD_API_URL` at build/run time:

```powershell
flutter run -d <android-device> --dart-define=UPLOAD_API_URL=https://your-api.example/upload
```

The app sends a `POST` multipart request with:

- `image`: original JPEG bytes, named `capture_<capture_id>.jpg`, with content type `image/jpeg`.
- `tag_crop`: selected tag region as PNG bytes, named `tag_crop_<capture_id>.png`.
- `ocr_json`: JSON containing schema version, capture ID and timestamp, original dimensions, tag-region coordinates, crop dimensions, `ocr.tag_id`, optional confidence, and crop-relative OCR block bounds/languages.
- `ocr_error`: an additional text field only when on-device OCR failed or is unsupported.

Any `2xx` response is treated as success. Without `UPLOAD_API_URL`, the upload remains pending and the UI explains how to configure it. The endpoint path, authentication, field names, and response handling can be aligned to the real backend when its contract is available. For browser uploads, the API must allow the app's origin through CORS.

## Checks

```powershell
flutter analyze
flutter test
flutter build web
```
