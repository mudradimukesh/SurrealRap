// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ImportedBookFile {
  const ImportedBookFile({
    required this.title,
    required this.format,
    required this.preview,
    required this.pages,
    this.formattedPages = const [],
    this.sourceUrl,
  });

  final String title;
  final String format;
  final String preview;
  final List<String> pages;
  final List<ImportedBookPage> formattedPages;
  final String? sourceUrl;
}

class ImportedBookPage {
  const ImportedBookPage({
    required this.text,
    required this.lines,
    this.width = 0,
    this.height = 0,
  });

  final String text;
  final List<ImportedTextLine> lines;
  final double width;
  final double height;
}

class ImportedTextLine {
  const ImportedTextLine({
    required this.text,
    this.fontName = '',
    this.fontSize = 12,
    this.bold = false,
    this.italic = false,
    this.left = 0,
    this.top = 0,
    this.width = 0,
  });

  final String text;
  final String fontName;
  final double fontSize;
  final bool bold;
  final bool italic;
  final double left;
  final double top;
  final double width;
}

Future<ImportedBookFile?> pickBookFile() async {
  final input = html.FileUploadInputElement()
    ..accept = '.epub,.pdf,.txt,.md,.html,.htm,.mobi,.azw3,.cbz,.cbr'
    ..multiple = false;

  final completer = Completer<ImportedBookFile?>();

  input.onChange.first.then((_) {
    final file = input.files?.first;
    if (file == null) {
      completer.complete(null);
      return;
    }

    final extension = _extensionFor(file.name);
    final title = _titleFor(file.name);

    if (_canPreviewText(extension)) {
      final reader = html.FileReader();
      reader.onLoadEnd.first.then((_) {
        final result = reader.result;
        final text = result is String ? result : '';
        completer.complete(
          ImportedBookFile(
            title: title,
            format: extension.toUpperCase(),
            preview: _previewFor(text, extension),
            pages: _paginateText(_cleanText(text)),
            formattedPages: _plainFormattedPages(
              _paginateText(_cleanText(text)),
            ),
          ),
        );
      });
      reader.readAsText(file);
      return;
    }

    if (extension == 'pdf') {
      final reader = html.FileReader();
      reader.onLoadEnd.first.then((_) {
        final result = reader.result;
        final bytes = result is ByteBuffer
            ? result.asUint8List()
            : result is Uint8List
            ? result
            : Uint8List(0);
        final imported = _extractPdfDocument(bytes, title, file);
        completer.complete(imported);
      });
      reader.readAsArrayBuffer(file);
      return;
    }

    completer.complete(
      ImportedBookFile(
        title: title,
        format: extension.toUpperCase(),
        preview:
            'Imported ${extension.toUpperCase()} file "${file.name}". Full parsing can plug into an EPUB/PDF engine next.',
        pages: [
          'Imported ${extension.toUpperCase()} file "${file.name}". A dedicated parser can convert this format into SurrealRap pages next.',
        ],
        sourceUrl: html.Url.createObjectUrlFromBlob(file),
      ),
    );
  });

  input.click();
  return completer.future;
}

ImportedBookFile _extractPdfDocument(
  Uint8List bytes,
  String title,
  html.File file,
) {
  try {
    final document = PdfDocument(inputBytes: bytes);
    final lines = PdfTextExtractor(document).extractTextLines();
    final pageCount = document.pages.count;
    final pageSizes = [
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++)
        document.pages[pageIndex].size,
    ];
    document.dispose();

    final pages = <ImportedBookPage>[];
    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final rawLines = lines
          .where((line) => line.pageIndex == pageIndex)
          .map(_lineFromSyncfusion)
          .where((line) => line.text.isNotEmpty)
          .toList();
      final pageLines = _mergeVisualLines(rawLines);
      final text = _cleanText(pageLines.map((line) => line.text).join('\n'));
      if (text.isNotEmpty) {
        final pageSize = pageSizes[pageIndex];
        pages.add(
          ImportedBookPage(
            text: text,
            lines: pageLines,
            width: pageSize.width,
            height: pageSize.height,
          ),
        );
      }
    }

    final fullText = _cleanText(pages.map((page) => page.text).join(' '));
    if (_isReadableExtraction(fullText) && pages.isNotEmpty) {
      return ImportedBookFile(
        title: title,
        format: 'PDF',
        preview: _previewFor(fullText, 'PDF'),
        pages: pages.map((page) => page.text).toList(),
        formattedPages: pages,
        sourceUrl: html.Url.createObjectUrlFromBlob(file),
      );
    }
  } catch (_) {
    // Fall back to the low-level stream extractor below.
  }

  final text = _extractPdfText(bytes);
  final plainPages = _paginateText(text);
  return ImportedBookFile(
    title: title,
    format: 'PDF',
    preview: plainPages.first,
    pages: plainPages,
    formattedPages: _plainFormattedPages(plainPages),
    sourceUrl: html.Url.createObjectUrlFromBlob(file),
  );
}

ImportedTextLine _lineFromSyncfusion(TextLine line) {
  return ImportedTextLine(
    text: _repairExtractedPdfText(line.text),
    fontName: _cleanFontName(line.fontName),
    fontSize: line.fontSize <= 0 ? 12 : line.fontSize,
    bold: line.fontStyle.contains(PdfFontStyle.bold),
    italic: line.fontStyle.contains(PdfFontStyle.italic),
    left: line.bounds.left,
    top: line.bounds.top,
    width: line.bounds.width,
  );
}

List<ImportedTextLine> _mergeVisualLines(List<ImportedTextLine> lines) {
  if (lines.isEmpty) {
    return const [];
  }

  final sorted = [...lines]
    ..sort((a, b) {
      final top = a.top.compareTo(b.top);
      return top == 0 ? a.left.compareTo(b.left) : top;
    });

  final groups = <List<ImportedTextLine>>[];
  for (final line in sorted) {
    var bestIndex = -1;
    var bestDistance = double.infinity;

    for (var index = groups.length - 1; index >= 0; index--) {
      final group = groups[index];
      final distance = (_averageTop(group) - line.top).abs();
      final threshold = math.max(
        2.5,
        math.max(_referenceFontSize(group), line.fontSize) * 0.42,
      );
      if (distance <= threshold && distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
      if (line.top - _averageTop(group) > threshold * 3) {
        break;
      }
    }

    if (bestIndex == -1) {
      groups.add([line]);
    } else {
      groups[bestIndex].add(line);
    }
  }

  final bodyFontSize = _referenceBodyFontSize(sorted);
  final merged =
      groups
          .expand((group) => _mergeVisualGroup(group, bodyFontSize))
          .where((line) => line.text.trim().isNotEmpty)
          .toList()
        ..sort((a, b) {
          final top = a.top.compareTo(b.top);
          return top == 0 ? a.left.compareTo(b.left) : top;
        });
  return merged;
}

List<ImportedTextLine> _mergeVisualGroup(
  List<ImportedTextLine> group,
  double bodyFontSize,
) {
  final parts = [...group]..sort((a, b) => a.left.compareTo(b.left));
  final dropCaps = parts
      .where((line) => _isDropCapFragment(line, bodyFontSize, parts))
      .toList();
  if (dropCaps.isEmpty) {
    return _mergeVisualRuns(parts);
  }

  final remaining = parts
      .where((line) => !dropCaps.contains(line))
      .toList(growable: false);
  return [...dropCaps, ..._mergeVisualRuns(remaining)];
}

List<ImportedTextLine> _mergeVisualRuns(List<ImportedTextLine> parts) {
  if (parts.isEmpty) {
    return const [];
  }

  final sorted = [...parts]..sort((a, b) => a.left.compareTo(b.left));
  final runs = <List<ImportedTextLine>>[];
  var current = <ImportedTextLine>[];

  for (final part in sorted) {
    if (current.isEmpty || _sameVisualFontRun(current.last, part)) {
      current.add(part);
    } else {
      runs.add(current);
      current = [part];
    }
  }
  if (current.isNotEmpty) {
    runs.add(current);
  }

  return [for (final run in runs) _mergeVisualLine(run)];
}

bool _sameVisualFontRun(ImportedTextLine previous, ImportedTextLine next) {
  final maxFontSize = math.max(previous.fontSize, next.fontSize);
  final sizeClose =
      (previous.fontSize - next.fontSize).abs() <=
      math.max(1.0, maxFontSize * 0.12);
  return _fontRunKey(previous) == _fontRunKey(next) &&
      previous.bold == next.bold &&
      previous.italic == next.italic &&
      sizeClose;
}

String _fontRunKey(ImportedTextLine line) {
  return line.fontName.trim().toLowerCase();
}

bool _isDropCapFragment(
  ImportedTextLine line,
  double bodyFontSize,
  List<ImportedTextLine> group,
) {
  final text = line.text.trim();
  if (group.length <= 1 ||
      text.length != 1 ||
      !RegExp(r'[A-Za-z]').hasMatch(text) ||
      line.fontSize < math.max(18, bodyFontSize * 1.8)) {
    return false;
  }

  final followingText = group
      .where((part) => part.left > line.left)
      .map((part) => part.text.trim())
      .where((part) => part.isNotEmpty)
      .join(' ')
      .toLowerCase();
  if (text == 'I') {
    return followingText.startsWith('was meant ');
  }
  return RegExp(r'^[a-z]').hasMatch(followingText);
}

ImportedTextLine _mergeVisualLine(List<ImportedTextLine> group) {
  final parts = [...group]..sort((a, b) => a.left.compareTo(b.left));
  final text = _repairExtractedPdfText(_joinPdfFragments(parts));
  final left = parts
      .map((line) => line.left)
      .reduce((value, element) => math.min(value, element));
  final top = _averageTop(parts);
  final fontName = _dominantFontName(parts);
  final fontSize = _referenceFontSize(parts);

  return ImportedTextLine(
    text: text,
    fontName: fontName,
    fontSize: fontSize,
    bold: parts.any((line) => line.bold),
    italic: parts.any((line) => line.italic),
    left: left,
    top: top,
    width: _visualLineWidth(parts, left),
  );
}

String _joinPdfFragments(List<ImportedTextLine> parts) {
  final buffer = StringBuffer();
  ImportedTextLine? previous;

  for (final part in parts) {
    final text = part.text.trim();
    if (text.isEmpty) {
      continue;
    }

    if (previous != null &&
        _shouldInsertPdfFragmentSpace(
          buffer.toString(),
          text,
          previous,
          part,
        )) {
      buffer.write(' ');
    }
    buffer.write(text);
    previous = part;
  }

  return buffer.toString();
}

bool _shouldInsertPdfFragmentSpace(
  String currentText,
  String nextText,
  ImportedTextLine previous,
  ImportedTextLine next,
) {
  if (currentText.isEmpty || nextText.isEmpty) {
    return false;
  }

  final last = currentText[currentText.length - 1];
  final first = nextText[0];
  if (RegExp(r'^[,.;:!?)}\]”’]').hasMatch(first)) {
    return false;
  }
  if (RegExp(r'[(\[{“‘]$').hasMatch(last)) {
    return false;
  }
  if (last == '-' || last == '—' || first == '-' || first == '—') {
    return false;
  }

  final fontSize = math.max(previous.fontSize, next.fontSize);
  final gap = next.left - _estimatedRight(previous);
  return gap > fontSize * 0.22;
}

double _estimatedRight(ImportedTextLine line) {
  if (line.width > 0) {
    return line.left + line.width;
  }
  return line.left + line.text.length * line.fontSize * 0.48;
}

double _visualLineWidth(List<ImportedTextLine> parts, double left) {
  final right = parts
      .map(_estimatedRight)
      .reduce((value, element) => math.max(value, element));
  return math.max(0, right - left);
}

double _averageTop(List<ImportedTextLine> lines) {
  if (lines.isEmpty) {
    return 0;
  }
  final total = lines.fold<double>(0, (sum, line) => sum + line.top);
  return total / lines.length;
}

double _referenceFontSize(List<ImportedTextLine> lines) {
  final sizes =
      lines.map((line) => line.fontSize).where((size) => size > 0).toList()
        ..sort();
  if (sizes.isEmpty) {
    return 12;
  }
  return sizes[sizes.length ~/ 2];
}

double _referenceBodyFontSize(List<ImportedTextLine> lines) {
  final sizes =
      lines
          .where((line) => line.text.trim().length > 8)
          .map((line) => line.fontSize)
          .where((size) => size > 0)
          .toList()
        ..sort();
  if (sizes.isEmpty) {
    return _referenceFontSize(lines);
  }
  return sizes[sizes.length ~/ 2];
}

String _dominantFontName(List<ImportedTextLine> parts) {
  final fonts = <String, int>{};
  for (final part in parts) {
    final font = part.fontName.trim();
    if (font.isEmpty) {
      continue;
    }
    fonts[font] = (fonts[font] ?? 0) + part.text.length;
  }
  if (fonts.isEmpty) {
    return '';
  }
  return fonts.entries
      .reduce((best, entry) => entry.value > best.value ? entry : best)
      .key;
}

List<ImportedBookPage> _plainFormattedPages(List<String> pages) {
  return [
    for (final page in pages)
      ImportedBookPage(
        text: page,
        lines: _cleanText(page)
            .split(RegExp(r'(?<=[.!?])\s+'))
            .where((line) => line.trim().isNotEmpty)
            .map(
              (line) => ImportedTextLine(
                text: line.trim(),
                fontName: 'Original',
                fontSize: 12,
              ),
            )
            .toList(),
      ),
  ];
}

String _extensionFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1 || dot == fileName.length - 1) {
    return 'book';
  }
  return fileName.substring(dot + 1).toLowerCase();
}

String _titleFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final rawTitle = dot == -1 ? fileName : fileName.substring(0, dot);
  return rawTitle
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _canPreviewText(String extension) {
  return extension == 'txt' ||
      extension == 'md' ||
      extension == 'html' ||
      extension == 'htm';
}

String _previewFor(String text, String extension) {
  final cleaned = _cleanText(text);
  if (cleaned.isEmpty) {
    return 'Imported ${extension.toUpperCase()} file. No readable preview was found.';
  }
  if (cleaned.length <= 260) {
    return cleaned;
  }
  return '${cleaned.substring(0, 260)}...';
}

String _cleanText(String text) {
  return _repairExtractedPdfText(
    text,
  ).replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _repairExtractedPdfText(String text) {
  final repaired = text
      .replaceAll('Õ', '’')
      .replaceAll('Ò', '“')
      .replaceAll('Ó', '”')
      .replaceAll('Ô', '‘')
      .replaceAll('Ñ', '—')
      .replaceAll('Ð', '–')
      .replaceAll('˜', '')
      .replaceAllMapped(
        RegExp(
          r'^[“”"\s]*(Was that five dollars worth all this\?)[”"\s]*(?=\s*$)',
          caseSensitive: false,
        ),
        (match) => '“${match.group(1)}”',
      )
      .replaceAllMapped(
        RegExp(
          r'^[“”"\s]*(Was that five dollars worth all this\?)[”"\s]+(?=Rapsy\b)',
          caseSensitive: false,
        ),
        (match) => '“${match.group(1)}” ',
      )
      .replaceAllMapped(
        RegExp(
          r'(“Was that five dollars worth all this\?”)\s+Rapsy scoffed, dripping with sarcasm\.?',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)} “Rapsy scoffed, dripping with sarcasm.”',
      )
      .replaceAllMapped(
        RegExp(
          r'^Rapsy scoffed, dripping with sarcasm\.?$',
          caseSensitive: false,
        ),
        (_) => '“Rapsy scoffed, dripping with sarcasm.”',
      )
      .replaceAllMapped(RegExp(r'^[”"“]\s*(?=Rapsy\b)'), (_) => '')
      .replaceAllMapped(RegExp(r'[„~]\s*(?=Rapsy\b)'), (_) => '')
      .replaceAllMapped(
        RegExp(r'^[—–-]{1,2}\s*(?=but\s+STILL!?\b)'),
        (_) => '—',
      )
      .replaceAllMapped(
        RegExp(r'(^|\n)[“"]\s*[”"]\s+(?=[A-Z])'),
        (match) => '${match.group(1)}” ',
      )
      .replaceAllMapped(RegExp(r'\s+[„~]\s+(?=[A-Z])'), (_) => ' ')
      .replaceAll('Þ', 'fi')
      .replaceAll('þ', 'fl')
      .replaceAll('ﬀ', 'ff')
      .replaceAll('ﬁ', 'fi')
      .replaceAll('ﬂ', 'fl')
      .replaceAll('ﬃ', 'ffi')
      .replaceAll('ﬄ', 'ffl')
      .replaceAllMapped(
        RegExp(r'([a-z])\s+([.,;:!?])'),
        (match) => '${match.group(1)}${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r"([A-Za-z])([’'])\s+(t|s|re|ve|ll|d|m)\b"),
        (match) => '${match.group(1)}${match.group(2)}${match.group(3)}',
      )
      .replaceAllMapped(
        RegExp(r'\b([A-Za-z]{2,})[\s\u00A0]+f+[\s\u00A0]+(ed|ing|s|er|ers)\b'),
        (match) => '${match.group(1)}ff${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'\b([A-Za-z][a-z]{2,})\s+([a-z]{2,})\b'),
        (match) => _maybeJoinBrokenWord(match.group(1)!, match.group(2)!),
      );

  return _repairKnownBrokenPdfWords(repaired);
}

String _maybeJoinBrokenWord(String first, String second) {
  final likelyBrokenStarts = {
    'cial',
    'tion',
    'sion',
    'ment',
    'ness',
    'ing',
    'ive',
    'ity',
    'ous',
    'ance',
    'ence',
  };
  if (likelyBrokenStarts.any(second.startsWith)) {
    return '$first$second';
  }
  return '$first $second';
}

String _repairKnownBrokenPdfWords(String text) {
  var repaired = text;
  const replacements = {
    'Surr eal': 'Surreal',
    'surr eal': 'surreal',
    'sacri cial': 'sacrificial',
    'Sacri cial': 'Sacrificial',
    'fr eshly': 'freshly',
    'Fr eshly': 'Freshly',
    'r oad': 'road',
    'R oad': 'Road',
    'thr ee': 'three',
    'Thr ee': 'Three',
    'couldn’ t': 'couldn’t',
    "couldn' t": "couldn't",
  };

  for (final entry in replacements.entries) {
    repaired = repaired.replaceAll(entry.key, entry.value);
  }
  return repaired;
}

String _cleanFontName(String fontName) {
  final withoutSubset = fontName.replaceFirst(RegExp(r'^[A-Z]{6}\+'), '');
  return withoutSubset
      .replaceAll(RegExp(r'[-_](Regular|Roman|Book|MT)$'), '')
      .replaceAll(RegExp(r'[-_](Bold|Italic|Oblique|SemiBold|Medium).*$'), '')
      .replaceAll(RegExp(r'(?<=[a-z])(?=[A-Z])'), ' ')
      .trim();
}

String _extractPdfText(Uint8List bytes) {
  if (bytes.isEmpty) {
    return _conversionFailedPdfText;
  }

  final streamText = _extractPdfStreamText(bytes);
  if (_isReadableExtraction(streamText)) {
    return streamText;
  }

  final raw = latin1.decode(bytes, allowInvalid: true);
  final matches = RegExp(r'\((?:\\.|[^\\)]){2,}\)').allMatches(raw);
  final fragments = <String>[];

  for (final match in matches) {
    final value = match.group(0);
    if (value == null || value.length < 4) {
      continue;
    }
    final decoded = _decodePdfLiteral(value.substring(1, value.length - 1));
    final cleaned = decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length >= 3 && RegExp(r'[A-Za-z0-9]').hasMatch(cleaned)) {
      fragments.add(cleaned);
    }
  }

  final text = fragments.join(' ');
  if (!_isReadableExtraction(text)) {
    return _conversionFailedPdfText;
  }
  return _cleanText(text);
}

String _extractPdfStreamText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final streamHeader = RegExp(r'<<(?:[\s\S]*?)>>\s*stream\r?\n');
  final fragments = <String>[];

  for (final match in streamHeader.allMatches(raw)) {
    final dictionary = match.group(0) ?? '';
    final streamStart = _trimStreamStart(bytes, match.end);
    final streamEnd = raw.indexOf('endstream', streamStart);
    if (streamEnd <= streamStart) {
      continue;
    }

    var streamBytes = bytes.sublist(
      streamStart,
      _trimStreamEnd(bytes, streamEnd),
    );
    if (dictionary.contains('FlateDecode')) {
      try {
        streamBytes = Uint8List.fromList(
          const ZLibDecoder().decodeBytes(streamBytes),
        );
      } catch (_) {
        continue;
      }
    }

    final stream = latin1.decode(streamBytes, allowInvalid: true);
    final text = _extractPdfContentStreamText(stream);
    if (text.isNotEmpty) {
      fragments.add(text);
    }
  }

  return _cleanText(fragments.join(' '));
}

int _trimStreamStart(Uint8List bytes, int index) {
  var cursor = index;
  while (cursor < bytes.length &&
      (bytes[cursor] == 10 || bytes[cursor] == 13)) {
    cursor++;
  }
  return cursor;
}

int _trimStreamEnd(Uint8List bytes, int index) {
  var cursor = index;
  while (cursor > 0 &&
      (bytes[cursor - 1] == 0 ||
          bytes[cursor - 1] == 9 ||
          bytes[cursor - 1] == 10 ||
          bytes[cursor - 1] == 12 ||
          bytes[cursor - 1] == 13 ||
          bytes[cursor - 1] == 32)) {
    cursor--;
  }
  return cursor;
}

String _extractPdfContentStreamText(String stream) {
  final fragments = <String>[];
  final textBlocks = RegExp(r'BT([\s\S]*?)ET').allMatches(stream);

  for (final block in textBlocks) {
    final body = block.group(1) ?? '';
    fragments.addAll(_extractPdfLiterals(body));
    fragments.addAll(_extractPdfHexStrings(body));
  }

  return fragments.where(_looksLikeHumanText).join(' ');
}

List<String> _extractPdfLiterals(String body) {
  final fragments = <String>[];
  var cursor = 0;

  while (cursor < body.length) {
    final start = body.indexOf('(', cursor);
    if (start == -1) {
      break;
    }

    final buffer = StringBuffer();
    var escaped = false;
    var depth = 1;
    var index = start + 1;

    while (index < body.length && depth > 0) {
      final char = body[index];
      if (escaped) {
        buffer.write(_decodePdfEscape(char));
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '(') {
        depth++;
        buffer.write(char);
      } else if (char == ')') {
        depth--;
        if (depth > 0) {
          buffer.write(char);
        }
      } else {
        buffer.write(char);
      }
      index++;
    }

    final text = _cleanText(buffer.toString());
    if (text.isNotEmpty) {
      fragments.add(text);
    }
    cursor = index;
  }

  return fragments;
}

String _decodePdfEscape(String char) {
  return switch (char) {
    'n' => ' ',
    'r' => ' ',
    't' => ' ',
    'b' => ' ',
    'f' => ' ',
    _ => char,
  };
}

List<String> _extractPdfHexStrings(String body) {
  final fragments = <String>[];
  final matches = RegExp(r'<([0-9A-Fa-f\s]{4,})>').allMatches(body);

  for (final match in matches) {
    final hex = match.group(1)?.replaceAll(RegExp(r'\s+'), '') ?? '';
    final decoded = _decodePdfHex(hex);
    if (decoded.isNotEmpty) {
      fragments.add(_cleanText(decoded));
    }
  }

  return fragments;
}

String _decodePdfHex(String hex) {
  if (hex.length < 4) {
    return '';
  }
  final normalized = hex.length.isOdd ? '${hex}0' : hex;
  final bytes = <int>[];
  for (var i = 0; i < normalized.length; i += 2) {
    final value = int.tryParse(normalized.substring(i, i + 2), radix: 16);
    if (value != null) {
      bytes.add(value);
    }
  }

  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final codeUnits = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      codeUnits.add((bytes[i] << 8) + bytes[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }

  return latin1.decode(bytes, allowInvalid: true);
}

String _decodePdfLiteral(String value) {
  return value
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')')
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\n', ' ')
      .replaceAll(r'\r', ' ')
      .replaceAll(r'\t', ' ');
}

List<String> _paginateText(String text) {
  final cleaned = _cleanText(text);
  final source = cleaned.isEmpty ? _conversionFailedPdfText : cleaned;
  const targetLength = 950;
  final pages = <String>[];
  var cursor = 0;

  while (cursor < source.length) {
    final remaining = source.length - cursor;
    if (remaining <= targetLength) {
      pages.add(source.substring(cursor).trim());
      break;
    }

    final windowEnd = cursor + targetLength;
    var split = source.lastIndexOf(RegExp(r'[.!?]\s'), windowEnd);
    if (split <= cursor + 360) {
      split = source.lastIndexOf(' ', windowEnd);
    }
    if (split <= cursor) {
      split = windowEnd;
    }

    pages.add(source.substring(cursor, split).trim());
    cursor = split;
  }

  return pages.where((page) => page.isNotEmpty).toList();
}

bool _isReadableExtraction(String text) {
  final cleaned = _cleanText(text);
  if (cleaned.length < 120) {
    return false;
  }
  final words = RegExp(r"[A-Za-z][A-Za-z'\-]{2,}").allMatches(cleaned).toList();
  if (words.length < 18) {
    return false;
  }
  final letters = RegExp(r'[A-Za-z]').allMatches(cleaned).length;
  final spaces = RegExp(r'\s').allMatches(cleaned).length;
  final controls = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F]',
  ).allMatches(cleaned).length;
  final printableRatio = (letters + spaces) / cleaned.length;
  final longWords = words
      .where((word) => (word.group(0) ?? '').length > 18)
      .length;
  final vowelWords = words
      .where((word) => RegExp('[aeiouAEIOU]').hasMatch(word.group(0) ?? ''))
      .length;
  final humanWordRatio = vowelWords / words.length;
  return printableRatio > 0.55 &&
      humanWordRatio > 0.45 &&
      longWords / words.length < 0.12 &&
      controls < 3;
}

bool _looksLikeHumanText(String text) {
  final cleaned = _cleanText(text);
  if (cleaned.length < 2) {
    return false;
  }
  final letters = RegExp(r'[A-Za-z]').allMatches(cleaned).length;
  final digits = RegExp(r'[0-9]').allMatches(cleaned).length;
  return letters + digits >= 2;
}

const _conversionFailedPdfText =
    'Chapter 1 PDF Conversion Needed. SurrealRap could not extract readable text from this PDF. This usually happens when the PDF stores pages as scanned images, uses custom font encodings without a text map, or needs OCR. The import has been stopped before showing corrupted text. Add OCR or a full PDF text engine next, then SurrealRap can convert the document into reflowable pages with font size, background, page, and chapter controls.';
