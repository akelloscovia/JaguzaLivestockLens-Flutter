# Frame

Frame is a Flutter camera app for capturing tagged items and reviewing OCR results.

## Capture Flow

- Captures the original JPEG from the device camera.
- Runs Latin-script text recognition on-device with Google ML Kit on Android and iOS.
- Shows detected text with image-space bounding boxes; confidence is included when the platform provides it.
- Sends the original image and OCR evidence to a configured backend.
- Keeps the five most recent captures in memory for review in Photos. Evidence is cleared when the app process exits.

The browser camera preview is supported, but the native ML Kit OCR plugin does not support Flutter Web. A browser capture records that limitation in its evidence and can still be uploaded.

## Backend Contract

Set `UPLOAD_API_URL` at build/run time:

```powershell
flutter run -d <android-device> --dart-define=UPLOAD_API_URL=https://your-api.example/upload
```

The app sends a `POST` multipart request with:

- `image`: original JPEG bytes, named `capture_<capture_id>.jpg`, with content type `image/jpeg`.
- `ocr_json`: JSON containing the schema version, capture ID and timestamp, image dimensions, full recognized text, OCR error if present, and text blocks with bounding boxes, optional confidence, and recognized languages.
- `ocr_error`: an additional text field only when on-device OCR failed or is unsupported.

Any `2xx` response is treated as success. Without `UPLOAD_API_URL`, the upload remains pending and the UI explains how to configure it. The endpoint path, authentication, field names, and response handling can be aligned to the real backend when its contract is available. For browser uploads, the API must allow the app's origin through CORS.

## Checks

```powershell
flutter analyze
flutter test
flutter build web
```
