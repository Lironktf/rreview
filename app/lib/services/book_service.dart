import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:review_core/review_core.dart';

/// Loads the precomputed opening book (lichess chess-openings, CC0) off the UI thread.
Future<OpeningBook> loadOpeningBook() async {
  final text = await rootBundle.loadString('assets/openings/book.json');
  return compute(_parse, text);
}

OpeningBook _parse(String text) => OpeningBook.fromJson(jsonDecode(text) as Map<String, dynamic>);
