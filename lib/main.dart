import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:versecatch/widgets/ocr_scan_overlay.dart';

part 'src/core.dart';
part 'src/bible_keys.dart';
part 'src/legacy_home_page.dart';
part 'src/data_store.dart';
part 'src/bible_and_text.dart';
part 'src/wizard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _validateMasterBookAliasesOrThrow();
  _validateMasterBookChapterMetadataOrThrow();
  runApp(const VerseCatchApp());
}
