# Frame

Frame is a Flutter camera app for capturing cattle tags and reviewing tag OCR results.

## Capture Flow

- Captures and preserves the original JPEG from the device camera.
- Also accepts a full-resolution photo selected from the device photo library.
- With the Jaguzi backend configured, sends the original image for automatic tag detection and tag-text recognition, then crops the highest-confidence tag box locally.
- Runs Latin-script Google ML Kit OCR only on that crop as an independent on-device check on Android and iOS.
- Without the Jaguzi backend configured, allows the user to draw the tag box and uses crop-only ML Kit OCR as a fallback.
- Reviews the original with tag boxes, crop with OCR boxes, all API tag-text candidates, local verification text/confidence, and an optional workflow-annotated image.
- Stores the five most recent originals, crops, annotated outputs, detections, text, bounds, confidence, and upload results in app documents storage on Android/iOS.

The browser can use the configured Jaguzi backend for detection/OCR; the additional local ML Kit check is only available on Android/iOS. Browser evidence is kept in memory for the current session.

When no backend URL is configured, the manual rectangle is used because no cattle-tag detector model is bundled in the app.

## Ear-Tag API

Set `EAR_TAG_API_URL` to the full Jaguzi backend route. The Flutter app sends JSON with an `imageBase64` field and expects an `outputs` list with `tag_text`, `tag_detections`, and optional `output_image` fields:

```powershell
flutter run -d <android-device> --dart-define=EAR_TAG_API_URL=https://your-jaguzi-backend/api/read-ear-tag
```

For local browser inference, the included Python service now proxies `/api/read-ear-tag` to the Roboflow Workflow. Keep the key in the backend process, not the Flutter build. In one PowerShell terminal, enter the key at the secure prompt and start the service:

```powershell
$secureKey = Read-Host 'Roboflow API key' -AsSecureString
$env:ROBOFLOW_API_KEY = (New-Object System.Net.NetworkCredential('', $secureKey)).Password
try { python backend/upload_server.py } finally { Remove-Item Env:ROBOFLOW_API_KEY }
```

In another terminal, build and serve the browser app with both local routes:

```powershell
flutter build web --release `
	--dart-define=EAR_TAG_API_URL=http://127.0.0.1:8001/api/read-ear-tag `
	--dart-define=UPLOAD_API_URL=http://127.0.0.1:8001/api/uploads
python -m http.server 8000 --directory build/web
```

When configured this way, selecting a photo automatically sends it for tag detection and text reading; no manual tag rectangle is needed. The workflow must be active and return `tag_text` plus `tag_detections` in its outputs. `/health` reports whether the local server sees a model key. If the key is missing, the model route returns HTTP 503 without exposing or storing a key.

The Jaguzi backend should call the Roboflow Workflow. The current Serverless Workflows route is:

```text
https://serverless.roboflow.com/akello-scovia/workflows/jaguzi-ear-tag-reader-1790754713845
```

The backend sends `Authorization: Bearer <ROBOFLOW_API_KEY>` and a JSON body using `inputs.image.type = base64` with the base64 image value. Keep that private Roboflow key on the backend; do not pass it to Flutter or compile it into the mobile app.

For local development, create `backend/.env` once with the private key:

```text
ROBOFLOW_API_KEY=your-roboflow-api-key
```

The local backend loads this file automatically. It is ignored by Git. Then start the backend normally with `python backend/upload_server.py`.

## Evidence Upload

An optional separate `UPLOAD_API_URL` receives a multipart `POST` with:

- `image`: original JPEG bytes.
- `tag_crop`: the detected tag crop as PNG, when a box is available.
- `annotated_image`: the workflow's annotated image as PNG, when returned.
- `ocr_json`: capture metadata, `tag_id`, candidate tag texts, detections/confidences, image dimensions, and local crop OCR evidence.

Any `2xx` response is treated as success. The project includes a local development receiver that stores uploaded files under `backend/uploads`:

```powershell
python backend/upload_server.py
flutter build web --release --dart-define=UPLOAD_API_URL=http://127.0.0.1:8001/api/uploads
python -m http.server 8000 --directory build/web
```

Run each command in a separate terminal. Open `http://localhost:8000`, select a photo, and press **Upload photo**. The local receiver accepts browser requests from localhost and is bound to `127.0.0.1`; it is not a public or production upload service. To upload from other devices or deploy the app, host the receiver behind HTTPS and set `UPLOAD_API_URL` to that public route. Do not expose the local receiver to the network without adding authentication and deployment security.

Without `UPLOAD_API_URL`, upload status indicates that no destination is configured. The Jaguzi model-reading endpoint is separate and still requires `EAR_TAG_API_URL`.

## Checks

```powershell
flutter analyze
flutter test
flutter build web
```
