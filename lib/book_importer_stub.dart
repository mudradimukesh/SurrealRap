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
  throw UnsupportedError('File import is available in the web test build.');
}
