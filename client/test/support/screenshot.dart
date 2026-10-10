import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where [saveScreenshot] writes, when `SIGNALHUB_SCREENSHOTS` names a
/// directory. Without it nothing is written, so the suite stays quiet; the
/// screens are compared with their drawings by running the tests that call it
/// with the variable set (docs/development.md, "Client").
final screenshotDirectory = Platform.environment['SIGNALHUB_SCREENSHOTS'];

/// Whether this run writes screenshots.
bool get screenshotsEnabled => screenshotDirectory?.isNotEmpty ?? false;

/// Loads Roboto and the Material icons from the Flutter SDK, so a screenshot
/// shows real text and icons instead of the test font's blocks.
Future<void> loadDesignFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, Map<String, int> files) async {
    final loader = FontLoader(family);
    for (final name in files.keys) {
      final bytes = await File('$fonts/$name').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', {
    'Roboto-Regular.ttf': 400,
    'Roboto-Medium.ttf': 500,
    'Roboto-Bold.ttf': 700,
  });
  await load('MaterialIcons', {'MaterialIcons-Regular.otf': 400});
}

/// Writes what [boundary] draws as `<name>.png` in [screenshotDirectory], at
/// the view's pixel ratio. Does nothing unless screenshots are enabled.
///
/// Wrap the app in a `RepaintBoundary(key: screenshotKey)` and pass its
/// finder.
Future<void> saveScreenshot(
  WidgetTester tester,
  Finder boundary,
  String name,
) async {
  final directory = screenshotDirectory;
  if (directory == null || directory.isEmpty) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(boundary);
    final image = await render.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// The key of the boundary [saveScreenshot] captures.
const screenshotKey = Key('screenshot');
