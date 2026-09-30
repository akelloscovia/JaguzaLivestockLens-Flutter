import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> pickGalleryImageBytes() async {
  final completer = Completer<Uint8List?>();
  final input = html.FileUploadInputElement()..accept = 'image/*';

  input.onChange.listen((event) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }

    final file = files.first;
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      if (completer.isCompleted) return;
      final result = reader.result;
      if (result is! String) {
        completer.complete(null);
        return;
      }
      final separator = result.indexOf(',');
      if (separator < 0) {
        completer.complete(null);
        return;
      }
      try {
        completer.complete(base64Decode(result.substring(separator + 1)));
      } on FormatException {
        completer.complete(null);
      }
    });

    reader.onError.listen((_) {
      if (!completer.isCompleted) completer.complete(null);
    });

    reader.readAsDataUrl(file);
  });

  input.click();
  return completer.future;
}
