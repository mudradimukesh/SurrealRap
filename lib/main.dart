import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'book_importer.dart';
import 'error_log_persistence.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      AppErrorLog.instance.install();
      runApp(const SurrealRapApp());
    },
    (error, stackTrace) => AppErrorLog.instance.recordError(
      source: 'runZonedGuarded',
      message: 'Unhandled async error escaped the Flutter zone.',
      error: error,
      stackTrace: stackTrace,
    ),
  );
}

class AppErrorLog extends ChangeNotifier {
  AppErrorLog._();

  static final AppErrorLog instance = AppErrorLog._();
  static const int _maxEntries = 80;

  final List<String> _entries = [];
  bool _installed = false;
  bool _notifyScheduled = false;

  List<String> get entries => List.unmodifiable(_entries);

  String get document {
    final latestError = _entries.cast<String?>().firstWhere(
      (entry) => entry?.contains('[ERROR]') ?? false,
      orElse: () => null,
    );
    final buffer = StringBuffer()
      ..writeln('SurrealRap Crash Log Document')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('Storage key: surreal_rap_error_log_v1')
      ..writeln()
      ..writeln('Entries: ${_entries.length}')
      ..writeln();
    if (_entries.isEmpty) {
      buffer.writeln('No errors have been captured yet.');
      return buffer.toString();
    }
    if (latestError != null) {
      buffer
        ..writeln('Latest Application Error')
        ..writeln(latestError)
        ..writeln();
    }
    for (var index = 0; index < _entries.length; index++) {
      buffer
        ..writeln('--- Entry ${index + 1} ---')
        ..writeln(_entries[index])
        ..writeln();
    }
    return buffer.toString();
  }

  void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    _entries
      ..clear()
      ..addAll(loadPersistedErrorLog());

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      recordFlutterError(details, source: 'FlutterError.onError');
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformError = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
      recordError(
        source: 'PlatformDispatcher.onError',
        message: 'Unhandled platform or render pipeline error.',
        error: error,
        stackTrace: stackTrace,
      );
      return previousPlatformError?.call(error, stackTrace) ?? true;
    };

    final previousErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      recordFlutterError(details, source: 'ErrorWidget.builder');
      return previousErrorWidgetBuilder(details);
    };

    installBrowserErrorCapture((source, message, stack) {
      recordError(source: source, message: message, stack: stack);
    });

    recordEvent(
      source: 'app.error_log.install',
      message: 'Crash logging installed.',
    );
  }

  void recordFlutterError(
    FlutterErrorDetails details, {
    required String source,
  }) {
    recordError(
      source: source,
      message: details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
      context: details.context?.toStringDeep(),
      library: details.library,
    );
  }

  void recordTextureRequest({
    required ReaderTexture from,
    required ReaderTexture to,
    required Book book,
    required int pageIndex,
  }) {
    recordEvent(
      source: 'reader.texture.change.requested',
      message: [
        'From: ${from.name}',
        'To: ${to.name}',
        'Texture image: ${_textureImagePathForLog(to) ?? 'none'}',
        'Book: ${book.title}',
        'Format: ${book.format}',
        'Imported: ${book.sourceUrl == null ? 'no' : 'yes'}',
        'Page: ${pageIndex + 1} of ${book.pages.length}',
        'Formatted pages: ${book.formattedPages.length}',
      ].join('\n'),
      stack: _trimStack(StackTrace.current, maxLines: 18),
    );
  }

  void recordTextureApplied({
    required ReaderTexture texture,
    required Book book,
    required int pageIndex,
  }) {
    recordEvent(
      source: 'reader.texture.change.applied',
      message: [
        'Texture: ${texture.name}',
        'Texture image: ${_textureImagePathForLog(texture) ?? 'none'}',
        'Book: ${book.title}',
        'Page: ${pageIndex + 1} of ${book.pages.length}',
      ].join('\n'),
      stack: _trimStack(StackTrace.current, maxLines: 18),
    );
  }

  void recordEvent({
    required String source,
    required String message,
    String? stack,
  }) {
    _addEntry(severity: 'INFO', source: source, message: message, stack: stack);
  }

  void recordError({
    required String source,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    String? stack,
    String? context,
    String? library,
  }) {
    _addEntry(
      severity: 'ERROR',
      source: source,
      message: [
        message,
        if (error != null) 'Dart exception type: ${error.runtimeType}',
        if (library != null && library.isNotEmpty) 'Library: $library',
        if (context != null && context.trim().isNotEmpty) 'Context:\n$context',
        if (error != null) 'Error: $error',
      ].join('\n'),
      stack: stack ?? _trimStack(stackTrace ?? StackTrace.current),
    );
  }

  void clear() {
    _entries.clear();
    clearPersistedErrorLog();
    notifyListeners();
  }

  void _addEntry({
    required String severity,
    required String source,
    required String message,
    String? stack,
  }) {
    final entry = [
      '${DateTime.now().toIso8601String()} [$severity] $source',
      message,
      if (stack != null && stack.trim().isNotEmpty) 'Stack:\n$stack',
    ].join('\n');
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    savePersistedErrorLog(_entries);
    debugPrint(entry);
    _scheduleNotifyListeners();
  }

  void _scheduleNotifyListeners() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  String? _trimStack(StackTrace? stackTrace, {int maxLines = 80}) {
    if (stackTrace == null) {
      return null;
    }
    final lines = stackTrace.toString().trim().split('\n');
    return lines.take(maxLines).join('\n');
  }
}

class SurrealRapApp extends StatelessWidget {
  const SurrealRapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SurrealRap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF18A999),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        useMaterial3: true,
      ),
      home: const SurrealRapHome(),
    );
  }
}

enum ReaderTheme { night, paper, sepia }

enum ReaderTexture {
  none,
  paper,
  paperBackground,
  oldPaper,
  whitePaper,
  watercolor,
  kraft,
  vintage,
  blackPaper,
  torn,
  crumpled,
  brownPaper,
  folded,
  ripped,
  grunge,
  recycled,
  craft,
  linen,
  overlay,
  greenPaper,
  rough,
  redPaper,
  bluePaper,
  glued,
  japanese,
  construction,
  notebook,
  wrinkled,
  handmade,
  yellowPaper,
  greyPaper,
  newspaper,
  marbled,
  charcoal,
}

class ReaderTextureOption {
  const ReaderTextureOption({
    required this.value,
    required this.label,
    required this.description,
  });

  final ReaderTexture value;
  final String label;
  final String description;
}

const List<ReaderTextureOption> readerTextureOptions = [
  ReaderTextureOption(
    value: ReaderTexture.none,
    label: 'None',
    description: 'Flat page color',
  ),
  ReaderTextureOption(
    value: ReaderTexture.paper,
    label: 'Paper Texture',
    description: 'Fine artistic grain',
  ),
  ReaderTextureOption(
    value: ReaderTexture.paperBackground,
    label: 'Paper Background',
    description: 'Soft full-page paper wash',
  ),
  ReaderTextureOption(
    value: ReaderTexture.oldPaper,
    label: 'Old Paper',
    description: 'Aged fibers and stains',
  ),
  ReaderTextureOption(
    value: ReaderTexture.whitePaper,
    label: 'White Paper',
    description: 'Clean bright paper tooth',
  ),
  ReaderTextureOption(
    value: ReaderTexture.watercolor,
    label: 'Watercolor Paper',
    description: 'Washed handmade-paper tone',
  ),
  ReaderTextureOption(
    value: ReaderTexture.kraft,
    label: 'Kraft Paper',
    description: 'Coarse brown stock',
  ),
  ReaderTextureOption(
    value: ReaderTexture.vintage,
    label: 'Vintage Paper',
    description: 'Retro aged paper marks',
  ),
  ReaderTextureOption(
    value: ReaderTexture.blackPaper,
    label: 'Black Paper',
    description: 'Dark art-paper fibers',
  ),
  ReaderTextureOption(
    value: ReaderTexture.torn,
    label: 'Torn Paper',
    description: 'Irregular torn edges',
  ),
  ReaderTextureOption(
    value: ReaderTexture.crumpled,
    label: 'Crumpled Paper',
    description: 'Soft crushed facets',
  ),
  ReaderTextureOption(
    value: ReaderTexture.brownPaper,
    label: 'Brown Paper',
    description: 'Warm brown recycled stock',
  ),
  ReaderTextureOption(
    value: ReaderTexture.folded,
    label: 'Folded Paper',
    description: 'Visible fold creases',
  ),
  ReaderTextureOption(
    value: ReaderTexture.ripped,
    label: 'Ripped Paper',
    description: 'Rough ripped fiber edge',
  ),
  ReaderTextureOption(
    value: ReaderTexture.grunge,
    label: 'Grunge Paper',
    description: 'Distressed speckled paper',
  ),
  ReaderTextureOption(
    value: ReaderTexture.recycled,
    label: 'Recycled Paper',
    description: 'Flecks and uneven pulp',
  ),
  ReaderTextureOption(
    value: ReaderTexture.craft,
    label: 'Craft Paper',
    description: 'Textured handmade craft stock',
  ),
  ReaderTextureOption(
    value: ReaderTexture.linen,
    label: 'Linen Paper',
    description: 'Subtle woven paper fibers',
  ),
  ReaderTextureOption(
    value: ReaderTexture.overlay,
    label: 'Paper Texture Overlay',
    description: 'Transparent overlay grain',
  ),
  ReaderTextureOption(
    value: ReaderTexture.greenPaper,
    label: 'Green Paper',
    description: 'Muted green paper texture',
  ),
  ReaderTextureOption(
    value: ReaderTexture.rough,
    label: 'Rough Paper',
    description: 'Heavy rough tooth',
  ),
  ReaderTextureOption(
    value: ReaderTexture.redPaper,
    label: 'Red Paper',
    description: 'Muted red paper texture',
  ),
  ReaderTextureOption(
    value: ReaderTexture.bluePaper,
    label: 'Blue Paper',
    description: 'Muted blue paper texture',
  ),
  ReaderTextureOption(
    value: ReaderTexture.glued,
    label: 'Glued Paper',
    description: 'Paste streaks and paper drag',
  ),
  ReaderTextureOption(
    value: ReaderTexture.japanese,
    label: 'Japanese Paper',
    description: 'Long handmade fibers',
  ),
  ReaderTextureOption(
    value: ReaderTexture.construction,
    label: 'Construction Paper',
    description: 'Colored classroom paper tooth',
  ),
  ReaderTextureOption(
    value: ReaderTexture.notebook,
    label: 'Notebook Paper',
    description: 'Ruled notebook background',
  ),
  ReaderTextureOption(
    value: ReaderTexture.wrinkled,
    label: 'Wrinkled Paper',
    description: 'Fine wrinkle map',
  ),
  ReaderTextureOption(
    value: ReaderTexture.handmade,
    label: 'Handmade Paper',
    description: 'Pulp flecks and fiber strands',
  ),
  ReaderTextureOption(
    value: ReaderTexture.yellowPaper,
    label: 'Yellow Paper',
    description: 'Soft yellow paper texture',
  ),
  ReaderTextureOption(
    value: ReaderTexture.greyPaper,
    label: 'Grey Paper',
    description: 'Neutral grey paper texture',
  ),
  ReaderTextureOption(
    value: ReaderTexture.newspaper,
    label: 'News Paper',
    description: 'Subtle newsprint columns',
  ),
  ReaderTextureOption(
    value: ReaderTexture.marbled,
    label: 'Marbled',
    description: 'Light flowing paper veins',
  ),
  ReaderTextureOption(
    value: ReaderTexture.charcoal,
    label: 'Charcoal',
    description: 'Dark speckled art paper',
  ),
];

class ReaderFontOption {
  const ReaderFontOption({
    required this.label,
    this.family,
    required this.description,
  });

  final String label;
  final String? family;
  final String description;
}

const List<ReaderFontOption> readerFontOptions = [
  ReaderFontOption(
    label: 'Original',
    description: 'Match imported PDF fonts to the closest bundled family',
  ),
  ReaderFontOption(
    label: 'Merriweather',
    family: 'Merriweather',
    description: 'Serif, warm long-form reading',
  ),
  ReaderFontOption(
    label: 'Lora',
    family: 'Lora',
    description: 'Serif, literary and balanced',
  ),
  ReaderFontOption(
    label: 'Crimson Text',
    family: 'Crimson Text',
    description: 'Classic book-style serif',
  ),
  ReaderFontOption(
    label: 'Source Serif 4',
    family: 'Source Serif 4',
    description: 'Editorial serif with broad coverage',
  ),
  ReaderFontOption(
    label: 'Inter',
    family: 'Inter',
    description: 'Clean modern sans',
  ),
  ReaderFontOption(
    label: 'Atkinson Hyperlegible',
    family: 'Atkinson Hyperlegible',
    description: 'Accessibility-focused sans',
  ),
  ReaderFontOption(
    label: 'Source Sans 3',
    family: 'Source Sans 3',
    description: 'Readable humanist sans',
  ),
  ReaderFontOption(
    label: 'Roboto Slab',
    family: 'Roboto Slab',
    description: 'Sturdy slab serif',
  ),
  ReaderFontOption(
    label: 'JetBrains Mono',
    family: 'JetBrains Mono',
    description: 'Monospace',
  ),
  ReaderFontOption(
    label: 'Playfair Display',
    family: 'Playfair Display',
    description: 'Display serif for dramatic reading',
  ),
];

const List<String> featuredGoogleReaderFonts = [
  'Libre Baskerville',
  'EB Garamond',
  'Cormorant Garamond',
  'Literata',
  'Noto Serif',
  'Noto Sans',
  'Roboto',
  'Open Sans',
  'Lato',
  'Montserrat',
  'Cascadia Code',
  'Cascadia Mono',
];

final allGoogleFonts = GoogleFonts.asMap();

final List<ReaderFontOption> allReaderFontOptions = _buildReaderFontOptions();

List<ReaderFontOption> _buildReaderFontOptions() {
  final seen = <String>{for (final option in readerFontOptions) option.label};
  final featured = <ReaderFontOption>[
    for (final fontName in featuredGoogleReaderFonts)
      if (allGoogleFonts.containsKey(fontName) && seen.add(fontName))
        ReaderFontOption(
          label: fontName,
          description: fontName.startsWith('Cascadia')
              ? 'Microsoft open-source family via Google Fonts'
              : 'Google Fonts open-source family',
        ),
  ];
  final rest =
      allGoogleFonts.keys
          .where((fontName) => seen.add(fontName))
          .map(
            (fontName) => ReaderFontOption(
              label: fontName,
              description: 'Google Fonts open-source family',
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
  return [...readerFontOptions, ...featured, ...rest];
}

String? _readerFontFamilyFor(String label) {
  for (final option in readerFontOptions) {
    if (option.label == label) {
      return option.family;
    }
  }
  return null;
}

bool _isGoogleReaderFont(String label) => allGoogleFonts.containsKey(label);

TextStyle _readerFontStyle({
  required String selectedFont,
  String? originalFontFamily,
  Color? color,
  double? fontSize,
  double? height,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) {
  final baseStyle = TextStyle(
    color: color,
    fontSize: fontSize,
    height: height,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
  );
  final bundledFamily = _readerFontFamilyFor(selectedFont);
  if (bundledFamily != null) {
    return baseStyle.copyWith(fontFamily: bundledFamily);
  }
  if (_isGoogleReaderFont(selectedFont)) {
    return GoogleFonts.getFont(selectedFont, textStyle: baseStyle);
  }
  return baseStyle.copyWith(fontFamily: originalFontFamily);
}

String? _measurementFontFamily({
  required String selectedFont,
  String? originalFontFamily,
}) {
  final bundledFamily = _readerFontFamilyFor(selectedFont);
  if (bundledFamily != null) {
    return bundledFamily;
  }
  if (_isGoogleReaderFont(selectedFont)) {
    return GoogleFonts.getFont(selectedFont).fontFamily;
  }
  return originalFontFamily;
}

String _normalizedPdfFontName(String fontName) {
  return fontName
      .replaceFirst(RegExp(r'^[A-Z]{6}\+'), '')
      .replaceAll(RegExp(r'[_-]'), ' ')
      .replaceAll(RegExp(r'(?<=[a-z])(?=[A-Z])'), ' ')
      .replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ' ')
      .toLowerCase()
      .replaceAll(RegExp(r'\b(ps|mt|std|pro|regular|roman|book)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _bestBundledFontForPdf(String originalFontName) {
  final normalized = _normalizedPdfFontName(originalFontName);
  if (normalized.isEmpty || normalized == 'original') {
    return 'Lora';
  }

  final exactMatch = <String, String>{
    for (final option in readerFontOptions)
      if (option.family != null)
        _normalizedPdfFontName(option.label): option.family!,
  }[normalized];
  if (exactMatch != null) {
    return exactMatch;
  }

  if (_containsAny(normalized, const [
    'mono',
    'code',
    'courier',
    'consolas',
    'menlo',
    'monaco',
    'terminal',
    'typewriter',
  ])) {
    return 'JetBrains Mono';
  }
  if (_containsAny(normalized, const [
    'hyperlegible',
    'dyslexic',
    'accessibility',
  ])) {
    return 'Atkinson Hyperlegible';
  }
  if (_containsAny(normalized, const [
    'slab',
    'rockwell',
    'clarendon',
    'egyptian',
  ])) {
    return 'Roboto Slab';
  }
  if (_containsAny(normalized, const [
    'didot',
    'bodoni',
    'display',
    'poster',
    'title',
    'headline',
    'fatface',
    'cinzel',
    'abril',
  ])) {
    return 'Playfair Display';
  }
  if (_containsAny(normalized, const [
    'garamond',
    'baskerville',
    'caslon',
    'palatino',
    'minion',
    'jenson',
    'sabon',
    'cochin',
    'hoefler',
    'bookman',
    'charter',
    'times',
    'serif',
  ])) {
    return 'Crimson Text';
  }
  if (_containsAny(normalized, const [
    'helvetica',
    'arial',
    'avenir',
    'futura',
    'gotham',
    'frutiger',
    'myriad',
    'verdana',
    'tahoma',
    'segoe',
    'optima',
    'sans',
  ])) {
    return 'Source Sans 3';
  }

  const fallbackFamilies = [
    'Lora',
    'Source Sans 3',
    'Crimson Text',
    'Source Serif 4',
    'Inter',
    'Roboto Slab',
    'Playfair Display',
  ];
  return fallbackFamilies[_stableFontBucket(
    normalized,
    fallbackFamilies.length,
  )];
}

bool _containsAny(String value, List<String> needles) {
  return needles.any((needle) => value.contains(needle));
}

int _stableFontBucket(String value, int bucketCount) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash % bucketCount;
}

class Book {
  const Book({
    required this.title,
    required this.author,
    required this.format,
    required this.progress,
    required this.tags,
    required this.excerpt,
    required this.pages,
    this.formattedPages = const [],
    this.sourceUrl,
  });

  final String title;
  final String author;
  final String format;
  final double progress;
  final List<String> tags;
  final String excerpt;
  final List<String> pages;
  final List<ImportedBookPage> formattedPages;
  final String? sourceUrl;
}

class SceneCard {
  const SceneCard({
    required this.title,
    required this.status,
    required this.pov,
    required this.words,
  });

  final String title;
  final String status;
  final String pov;
  final int words;
}

class SurrealRapHome extends StatefulWidget {
  const SurrealRapHome({super.key});

  @override
  State<SurrealRapHome> createState() => _SurrealRapHomeState();
}

class _SurrealRapHomeState extends State<SurrealRapHome> {
  int _tabIndex = 0;
  int _selectedBook = 0;
  int _readerPage = 0;
  double _fontSize = 18;
  double _lineHeight = 1.45;
  double _readerProgress = 0.38;
  ReaderTheme _readerTheme = ReaderTheme.night;
  ReaderTexture _readerTexture = ReaderTexture.none;
  String _readerMode = 'Paged';
  String _readerFontFamily = 'Original';

  final TextEditingController _highlightController = TextEditingController();
  final TextEditingController _manuscriptController = TextEditingController(
    text:
        'The city hummed in blue static while Mira tuned the subway rail like a bass string. Every station name had changed overnight, and the map was now written in rhymes only she could hear.',
  );

  final List<String> _highlights = [
    'Neon rain writing character motives across the glass.',
    'A chorus can work like a recurring symbol, not only a hook.',
    'Use silence after a reveal like a page turn.',
  ];

  final List<String> _readerIdeas = [
    'Turn favorite highlights into scene prompts',
    'Track characters, places, and motifs while reading',
    'Compare pacing between books and your draft',
  ];

  final List<Book> _books = [
    const Book(
      title: 'Glass Metro Cantos',
      author: 'A. Rivera',
      format: 'EPUB',
      progress: 0.38,
      tags: ['Surreal', 'Verse novel', 'Study'],
      excerpt:
          'The train arrived without doors. People entered anyway, folding themselves into music until the tunnel became a throat.',
      pages: [
        'Chapter 1. The train arrived without doors. People entered anyway, folding themselves into music until the tunnel became a throat.',
        'Chapter 2. Mira marked every impossible station name in amber and listened for the chorus hiding under the rails.',
      ],
    ),
    const Book(
      title: 'The Orchard Under Mars',
      author: 'N. Iyer',
      format: 'PDF',
      progress: 0.64,
      tags: ['Worldbuilding', 'Annotations'],
      excerpt:
          'Every fruit had a weather system inside it. The farmers harvested thunder by candlelight and sold the echoes by weight.',
      pages: [
        'Chapter 1. Every fruit had a weather system inside it. The farmers harvested thunder by candlelight and sold the echoes by weight.',
        'Chapter 2. The orchard forecast called for red dust, low moons, and one argument blooming at dawn.',
      ],
    ),
    const Book(
      title: 'Manual for Dream Thieves',
      author: 'L. Chen',
      format: 'EPUB',
      progress: 0.12,
      tags: ['Research', 'Characters'],
      excerpt:
          'A thief never steals the dream itself. They lift the hinge that lets morning close over it.',
      pages: [
        'Chapter 1. A thief never steals the dream itself. They lift the hinge that lets morning close over it.',
        'Chapter 2. The manual warned that every stolen dream leaves a grammar-shaped bruise.',
      ],
    ),
  ];

  final List<SceneCard> _scenes = const [
    SceneCard(
      title: 'Prologue: Static in the Rail',
      status: 'Draft',
      pov: 'Mira',
      words: 920,
    ),
    SceneCard(
      title: 'Chapter 1: The Map Starts Rhyming',
      status: 'Needs rewrite',
      pov: 'Mira',
      words: 1840,
    ),
    SceneCard(
      title: 'Chapter 2: The Hook Market',
      status: 'Outlined',
      pov: 'Cass',
      words: 460,
    ),
  ];

  @override
  void dispose() {
    _highlightController.dispose();
    _manuscriptController.dispose();
    super.dispose();
  }

  void _addHighlight() {
    final text = _highlightController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _highlights.insert(0, text);
      _highlightController.clear();
    });
  }

  void _changeReaderTexture(ReaderTexture value) {
    final previous = _readerTexture;
    final book = _books[_selectedBook];
    AppErrorLog.instance.recordTextureRequest(
      from: previous,
      to: value,
      book: book,
      pageIndex: _readerPage,
    );
    try {
      setState(() => _readerTexture = value);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (!mounted) {
            return;
          }
          AppErrorLog.instance.recordTextureApplied(
            texture: _readerTexture,
            book: _books[_selectedBook],
            pageIndex: _readerPage,
          );
        } catch (error, stackTrace) {
          AppErrorLog.instance.recordError(
            source: 'reader.texture.change.postFrame',
            message: 'Texture change failed after the next Flutter frame.',
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
      });
    } catch (error, stackTrace) {
      AppErrorLog.instance.recordError(
        source: 'reader.texture.change.setState',
        message: 'Texture change failed during setState.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _importBook() async {
    try {
      final imported = await pickBookFile();
      if (!mounted || imported == null) {
        return;
      }

      final book = Book(
        title: imported.title.isEmpty ? 'Untitled import' : imported.title,
        author: 'Imported file',
        format: imported.format,
        progress: 0,
        tags: const ['Imported', 'Offline'],
        excerpt: imported.preview,
        pages: imported.pages,
        formattedPages: imported.formattedPages,
        sourceUrl: imported.sourceUrl,
      );

      setState(() {
        _books.insert(0, book);
        _selectedBook = 0;
        _readerPage = 0;
        _readerProgress = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported "${book.title}" into your library.')),
      );
    } on UnsupportedError catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Import is unavailable here.')),
      );
      AppErrorLog.instance.recordError(
        source: 'book.import.unsupported',
        message: error.message ?? 'Import is unavailable here.',
        error: error,
      );
    } catch (error, stackTrace) {
      AppErrorLog.instance.recordError(
        source: 'book.import.failed',
        message: 'Book import failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import failed. See Crash Log Document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 920;
            return Row(
              children: [
                if (isWide)
                  _NavigationRail(
                    selectedIndex: _tabIndex,
                    onSelected: (index) => setState(() => _tabIndex = index),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        selectedIndex: _tabIndex,
                        isWide: isWide,
                        onSelected: (index) =>
                            setState(() => _tabIndex = index),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _tabIndex,
                          children: [
                            _LibraryView(
                              books: _books,
                              selectedBook: _selectedBook,
                              onImport: _importBook,
                              onSelected: (index) => setState(() {
                                _selectedBook = index;
                                final pageCount = _books[index].pages.length;
                                _readerPage = pageCount <= 1
                                    ? 0
                                    : (_books[index].progress * (pageCount - 1))
                                          .round();
                                _readerProgress = _books[index].progress;
                                _tabIndex = 1;
                              }),
                            ),
                            _ReaderView(
                              book: _books[_selectedBook],
                              pageIndex: _readerPage,
                              progress: _readerProgress,
                              fontSize: _fontSize,
                              lineHeight: _lineHeight,
                              fontFamily: _readerFontFamily,
                              theme: _readerTheme,
                              texture: _readerTexture,
                              mode: _readerMode,
                              highlights: _highlights,
                              highlightController: _highlightController,
                              onProgressChanged: (value) =>
                                  setState(() => _readerProgress = value),
                              onPageChanged: (page) => setState(() {
                                _readerPage = page;
                                final lastPage =
                                    _books[_selectedBook].pages.length - 1;
                                _readerProgress = lastPage <= 0
                                    ? 0
                                    : page / lastPage;
                              }),
                              onFontChanged: (value) =>
                                  setState(() => _fontSize = value),
                              onLineHeightChanged: (value) =>
                                  setState(() => _lineHeight = value),
                              onFontFamilyChanged: (value) =>
                                  setState(() => _readerFontFamily = value),
                              onThemeChanged: (value) =>
                                  setState(() => _readerTheme = value),
                              onTextureChanged: _changeReaderTexture,
                              onModeChanged: (value) =>
                                  setState(() => _readerMode = value),
                              onAddHighlight: _addHighlight,
                            ),
                            _WriterView(
                              scenes: _scenes,
                              manuscriptController: _manuscriptController,
                              readerIdeas: _readerIdeas,
                            ),
                            _InsightsView(
                              highlights: _highlights,
                              manuscriptController: _manuscriptController,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      minWidth: 92,
      backgroundColor: const Color(0xFF151821),
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.only(top: 18, bottom: 18),
        child: Icon(Icons.auto_stories, size: 34),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.library_books_outlined),
          selectedIcon: Icon(Icons.library_books),
          label: Text('Library'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: Text('Reader'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.edit_note_outlined),
          selectedIcon: Icon(Icons.edit_note),
          label: Text('Writer'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: Text('Insights'),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selectedIndex,
    required this.isWide,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool isWide;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1115),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            const Icon(Icons.graphic_eq, color: Color(0xFF18A999), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SurrealRap',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Novel reader, annotation lab, and writing studio',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
            if (!isWide)
              DropdownButton<int>(
                value: selectedIndex,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Library')),
                  DropdownMenuItem(value: 1, child: Text('Reader')),
                  DropdownMenuItem(value: 2, child: Text('Writer')),
                  DropdownMenuItem(value: 3, child: Text('Insights')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onSelected(value);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryView extends StatelessWidget {
  const _LibraryView({
    required this.books,
    required this.selectedBook,
    required this.onImport,
    required this.onSelected,
  });

  final List<Book> books;
  final int selectedBook;
  final VoidCallback onImport;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return _Screen(
      title: 'Reading Library',
      subtitle:
          'Import EPUB/PDF, organize shelves, sync progress, and keep books available offline.',
      actions: [
        _ActionButton(
          icon: Icons.upload_file,
          label: 'Import',
          onPressed: onImport,
        ),
        const _ActionButton(icon: Icons.cloud_sync, label: 'Sync'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(label: 'Books', value: '42'),
              _MetricTile(label: 'Formats', value: 'EPUB PDF CBZ'),
              _MetricTile(label: 'Offline', value: '18 saved'),
              _MetricTile(label: 'Reading goal', value: '64%'),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 900 ? 3 : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: columns == 1 ? 2.8 : 1.05,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) {
                  return _BookTile(
                    book: books[index],
                    selected: index == selectedBook,
                    onTap: () => onSelected(index),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 22),
          const _FeatureBand(
            icon: Icons.folder_copy_outlined,
            title: 'Reader requirements covered',
            items: [
              'Shelves, tags, series grouping, search, and metadata',
              'EPUB/PDF/comic import model with offline-first storage',
              'Bookmarks, progress, notes, highlights, and export-ready annotations',
              'Accessibility-ready themes, text scaling, keyboard-friendly layout, and TTS hooks',
            ],
          ),
        ],
      ),
    );
  }
}

class _ReaderView extends StatelessWidget {
  const _ReaderView({
    required this.book,
    required this.pageIndex,
    required this.progress,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.theme,
    required this.texture,
    required this.mode,
    required this.highlights,
    required this.highlightController,
    required this.onProgressChanged,
    required this.onPageChanged,
    required this.onFontChanged,
    required this.onLineHeightChanged,
    required this.onFontFamilyChanged,
    required this.onThemeChanged,
    required this.onTextureChanged,
    required this.onModeChanged,
    required this.onAddHighlight,
  });

  final Book book;
  final int pageIndex;
  final double progress;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final ReaderTheme theme;
  final ReaderTexture texture;
  final String mode;
  final List<String> highlights;
  final TextEditingController highlightController;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<double> onFontChanged;
  final ValueChanged<double> onLineHeightChanged;
  final ValueChanged<String> onFontFamilyChanged;
  final ValueChanged<ReaderTheme> onThemeChanged;
  final ValueChanged<ReaderTexture> onTextureChanged;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onAddHighlight;

  @override
  Widget build(BuildContext context) {
    final colors = switch (theme) {
      ReaderTheme.night => const _ReaderColors(
        background: Color(0xFF141820),
        foreground: Color(0xFFE8EDF2),
      ),
      ReaderTheme.paper => const _ReaderColors(
        background: Color(0xFFF5F1E8),
        foreground: Color(0xFF222222),
      ),
      ReaderTheme.sepia => const _ReaderColors(
        background: Color(0xFF2A231B),
        foreground: Color(0xFFEAD9BE),
      ),
    };

    return _Screen(
      title: book.title,
      subtitle:
          '${book.author} · ${book.format} · Page ${pageIndex + 1} of ${book.pages.length}',
      actions: const [
        _ActionButton(icon: Icons.volume_up_outlined, label: 'Read Aloud'),
        _ActionButton(icon: Icons.bookmark_add_outlined, label: 'Bookmark'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SegmentButton(
                label: 'Paged',
                selected: mode == 'Paged',
                onTap: () => onModeChanged('Paged'),
              ),
              _SegmentButton(
                label: 'Scroll',
                selected: mode == 'Scroll',
                onTap: () => onModeChanged('Scroll'),
              ),
              _ThemeButton(
                label: 'Night',
                selected: theme == ReaderTheme.night,
                onTap: () => onThemeChanged(ReaderTheme.night),
              ),
              _ThemeButton(
                label: 'Paper',
                selected: theme == ReaderTheme.paper,
                onTap: () => onThemeChanged(ReaderTheme.paper),
              ),
              _ThemeButton(
                label: 'Sepia',
                selected: theme == ReaderTheme.sepia,
                onTap: () => onThemeChanged(ReaderTheme.sepia),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 920;
              final readingPane = _ReadingPane(
                colors: colors,
                book: book,
                pageIndex: pageIndex,
                fontSize: fontSize,
                lineHeight: lineHeight,
                fontFamily: fontFamily,
                texture: texture,
                progress: progress,
                onProgressChanged: onProgressChanged,
                onPageChanged: onPageChanged,
              );
              final tools = _ReaderTools(
                fontSize: fontSize,
                lineHeight: lineHeight,
                fontFamily: fontFamily,
                texture: texture,
                highlights: highlights,
                highlightController: highlightController,
                onFontChanged: onFontChanged,
                onLineHeightChanged: onLineHeightChanged,
                onFontFamilyChanged: onFontFamilyChanged,
                onTextureChanged: onTextureChanged,
                onAddHighlight: onAddHighlight,
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [readingPane, const SizedBox(height: 18), tools],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: readingPane),
                  const SizedBox(width: 18),
                  Expanded(flex: 4, child: tools),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WriterView extends StatelessWidget {
  const _WriterView({
    required this.scenes,
    required this.manuscriptController,
    required this.readerIdeas,
  });

  final List<SceneCard> scenes;
  final TextEditingController manuscriptController;
  final List<String> readerIdeas;

  @override
  Widget build(BuildContext context) {
    return _Screen(
      title: 'Novel Studio',
      subtitle:
          'Outline, draft, revise, and convert reader discoveries into better scenes.',
      actions: const [
        _ActionButton(icon: Icons.download_outlined, label: 'Export EPUB'),
        _ActionButton(icon: Icons.description_outlined, label: 'Export DOCX'),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 980;
          final outline = _WriterOutline(scenes: scenes);
          final editor = _ManuscriptEditor(controller: manuscriptController);
          final bible = _StoryBible(readerIdeas: readerIdeas);

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                outline,
                const SizedBox(height: 16),
                editor,
                const SizedBox(height: 16),
                bible,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: outline),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: editor),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: bible),
            ],
          );
        },
      ),
    );
  }
}

class _InsightsView extends StatelessWidget {
  const _InsightsView({
    required this.highlights,
    required this.manuscriptController,
  });

  final List<String> highlights;
  final TextEditingController manuscriptController;

  @override
  Widget build(BuildContext context) {
    final wordCount = manuscriptController.text
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .length;

    return _Screen(
      title: 'Reader-to-Writer Insights',
      subtitle:
          'The best reader features become revision tools for the novelist.',
      actions: const [
        _ActionButton(icon: Icons.ios_share_outlined, label: 'Export Notes'),
        _ActionButton(icon: Icons.auto_fix_high_outlined, label: 'Style Pass'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(label: 'Draft words', value: '$wordCount'),
              _MetricTile(label: 'Highlights', value: '${highlights.length}'),
              const _MetricTile(label: 'Daily goal', value: '750'),
              const _MetricTile(label: 'Streak', value: '5 days'),
            ],
          ),
          const SizedBox(height: 22),
          const _FeatureBand(
            icon: Icons.psychology_alt_outlined,
            title: 'Reader features that help writers',
            items: [
              'X-Ray-style character, place, object, and motif index for your own manuscript',
              'Highlight-to-scene prompts that turn favorite passages into craft exercises',
              'Pacing map that compares read-time, tension, dialogue density, and chapter length',
              'Continuity checker for names, timelines, locations, and recurring symbols',
            ],
          ),
          const SizedBox(height: 16),
          _InsightGrid(highlights: highlights),
        ],
      ),
    );
  }
}

class _ReaderColors {
  const _ReaderColors({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

class _ReaderTextureSurface extends StatelessWidget {
  const _ReaderTextureSurface({
    required this.colors,
    required this.texture,
    required this.child,
  });

  final _ReaderColors colors;
  final ReaderTexture texture;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (texture == ReaderTexture.none) {
      return child;
    }
    final textureImage = _textureImageFor(texture);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (textureImage != null) ...[
          Positioned.fill(
            child: Opacity(
              opacity: textureImage.opacity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: ResizeImage(
                      AssetImage(textureImage.path),
                      width: 128,
                      height: 128,
                    ),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    colorFilter: textureImage.color == null
                        ? null
                        : ColorFilter.mode(
                            textureImage.color!,
                            textureImage.blendMode,
                          ),
                    onError: (error, stackTrace) {
                      AppErrorLog.instance.recordError(
                        source: 'reader.texture.image.load',
                        message: [
                          'Texture image failed to load.',
                          'Texture: ${texture.name}',
                          'Path: ${textureImage.path}',
                        ].join('\n'),
                        error: error,
                        stackTrace: stackTrace,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (textureImage.backgroundWashAlpha > 0)
            Positioned.fill(
              child: ColoredBox(
                color: colors.background.withValues(
                  alpha: textureImage.backgroundWashAlpha,
                ),
              ),
            ),
        ],
        RepaintBoundary(child: child),
      ],
    );
  }

  _ReaderTextureImage? _textureImageFor(ReaderTexture texture) {
    return switch (texture) {
      ReaderTexture.none => null,
      ReaderTexture.paper ||
      ReaderTexture.paperBackground ||
      ReaderTexture.whitePaper ||
      ReaderTexture.watercolor ||
      ReaderTexture.linen ||
      ReaderTexture.overlay ||
      ReaderTexture.rough ||
      ReaderTexture.glued ||
      ReaderTexture.japanese ||
      ReaderTexture.notebook ||
      ReaderTexture.handmade ||
      ReaderTexture.greyPaper ||
      ReaderTexture.marbled => const _ReaderTextureImage(
        path: 'assets/textures/paper_white.png',
        opacity: 0.34,
        backgroundWashAlpha: 0.18,
      ),
      ReaderTexture.oldPaper ||
      ReaderTexture.vintage ||
      ReaderTexture.yellowPaper ||
      ReaderTexture.newspaper => const _ReaderTextureImage(
        path: 'assets/textures/old_paper.jpg',
        opacity: 0.42,
        backgroundWashAlpha: 0.16,
      ),
      ReaderTexture.kraft ||
      ReaderTexture.brownPaper ||
      ReaderTexture.recycled ||
      ReaderTexture.craft ||
      ReaderTexture.construction => const _ReaderTextureImage(
        path: 'assets/textures/paper_brown.jpg',
        opacity: 0.38,
        backgroundWashAlpha: 0.18,
      ),
      ReaderTexture.crumpled ||
      ReaderTexture.torn ||
      ReaderTexture.folded ||
      ReaderTexture.ripped ||
      ReaderTexture.wrinkled ||
      ReaderTexture.grunge => const _ReaderTextureImage(
        path: 'assets/textures/crumpled_paper.png',
        opacity: 0.5,
        backgroundWashAlpha: 0.1,
      ),
      ReaderTexture.blackPaper ||
      ReaderTexture.charcoal => const _ReaderTextureImage(
        path: 'assets/textures/crumpled_paper.png',
        opacity: 0.48,
        color: Color(0xFF151515),
        blendMode: BlendMode.modulate,
        backgroundWashAlpha: 0.08,
      ),
      ReaderTexture.greenPaper => const _ReaderTextureImage(
        path: 'assets/textures/paper_white.png',
        opacity: 0.38,
        color: Color(0xFF6D9172),
        blendMode: BlendMode.modulate,
        backgroundWashAlpha: 0.14,
      ),
      ReaderTexture.redPaper => const _ReaderTextureImage(
        path: 'assets/textures/paper_white.png',
        opacity: 0.38,
        color: Color(0xFFC76565),
        blendMode: BlendMode.modulate,
        backgroundWashAlpha: 0.14,
      ),
      ReaderTexture.bluePaper => const _ReaderTextureImage(
        path: 'assets/textures/paper_white.png',
        opacity: 0.38,
        color: Color(0xFF668AC4),
        blendMode: BlendMode.modulate,
        backgroundWashAlpha: 0.14,
      ),
    };
  }
}

class _ReaderPageTextureSurface extends StatelessWidget {
  const _ReaderPageTextureSurface({
    required this.colors,
    required this.texture,
    required this.child,
  });

  final _ReaderColors colors;
  final ReaderTexture texture;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final texturePath = _textureImagePathForLog(texture);
    final background = _readerPageBackgroundForTexture(colors, texture);
    if (texturePath == null) {
      return ColoredBox(color: background, child: child);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: background),
        Opacity(
          opacity: _readerPageTextureOpacity(texture),
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(texturePath),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                colorFilter: _readerPageTextureFilter(texture),
                onError: (error, stackTrace) {
                  AppErrorLog.instance.recordError(
                    source: 'reader.page.texture.image.load',
                    message: [
                      'Page texture image failed to load.',
                      'Texture: ${texture.name}',
                      'Path: $texturePath',
                    ].join('\n'),
                    error: error,
                    stackTrace: stackTrace,
                  );
                },
              ),
            ),
          ),
        ),
        if (_readerPageTextureWash(texture) case final wash?)
          ColoredBox(color: wash),
        RepaintBoundary(child: child),
      ],
    );
  }
}

class _ReaderTextureImage {
  const _ReaderTextureImage({
    required this.path,
    required this.opacity,
    this.color,
    this.blendMode = BlendMode.modulate,
    this.backgroundWashAlpha = 0,
  });

  final String path;
  final double opacity;
  final Color? color;
  final BlendMode blendMode;
  final double backgroundWashAlpha;
}

String? _textureImagePathForLog(ReaderTexture texture) {
  return switch (texture) {
    ReaderTexture.none => null,
    ReaderTexture.paper ||
    ReaderTexture.paperBackground ||
    ReaderTexture.whitePaper ||
    ReaderTexture.watercolor ||
    ReaderTexture.linen ||
    ReaderTexture.overlay ||
    ReaderTexture.rough ||
    ReaderTexture.glued ||
    ReaderTexture.japanese ||
    ReaderTexture.notebook ||
    ReaderTexture.handmade ||
    ReaderTexture.greyPaper ||
    ReaderTexture.marbled ||
    ReaderTexture.greenPaper ||
    ReaderTexture.redPaper ||
    ReaderTexture.bluePaper => 'assets/textures/paper_white.png',
    ReaderTexture.oldPaper ||
    ReaderTexture.vintage ||
    ReaderTexture.yellowPaper ||
    ReaderTexture.newspaper => 'assets/textures/old_paper.jpg',
    ReaderTexture.kraft ||
    ReaderTexture.brownPaper ||
    ReaderTexture.recycled ||
    ReaderTexture.craft ||
    ReaderTexture.construction => 'assets/textures/paper_brown.jpg',
    ReaderTexture.crumpled ||
    ReaderTexture.torn ||
    ReaderTexture.folded ||
    ReaderTexture.ripped ||
    ReaderTexture.wrinkled ||
    ReaderTexture.grunge ||
    ReaderTexture.blackPaper ||
    ReaderTexture.charcoal => 'assets/textures/crumpled_paper.png',
  };
}

Color _readerPageBackgroundForTexture(
  _ReaderColors colors,
  ReaderTexture texture,
) {
  return switch (texture) {
    ReaderTexture.none => colors.background,
    ReaderTexture.blackPaper ||
    ReaderTexture.charcoal => const Color(0xFF171615),
    ReaderTexture.kraft ||
    ReaderTexture.brownPaper ||
    ReaderTexture.recycled ||
    ReaderTexture.craft ||
    ReaderTexture.construction => const Color(0xFFD0B28A),
    ReaderTexture.oldPaper ||
    ReaderTexture.vintage ||
    ReaderTexture.yellowPaper ||
    ReaderTexture.newspaper => const Color(0xFFE7D3A9),
    ReaderTexture.greenPaper => const Color(0xFFDDE6D4),
    ReaderTexture.redPaper => const Color(0xFFE9D0CF),
    ReaderTexture.bluePaper => const Color(0xFFD9E1EF),
    ReaderTexture.crumpled ||
    ReaderTexture.torn ||
    ReaderTexture.folded ||
    ReaderTexture.ripped ||
    ReaderTexture.wrinkled ||
    ReaderTexture.grunge => const Color(0xFFF0E8DC),
    ReaderTexture.paper ||
    ReaderTexture.paperBackground ||
    ReaderTexture.whitePaper ||
    ReaderTexture.watercolor ||
    ReaderTexture.linen ||
    ReaderTexture.overlay ||
    ReaderTexture.rough ||
    ReaderTexture.glued ||
    ReaderTexture.japanese ||
    ReaderTexture.notebook ||
    ReaderTexture.handmade ||
    ReaderTexture.greyPaper ||
    ReaderTexture.marbled => const Color(0xFFF3EFE5),
  };
}

Color _readerPageForegroundForTexture(
  _ReaderColors colors,
  ReaderTexture texture,
) {
  return switch (texture) {
    ReaderTexture.none => colors.foreground,
    ReaderTexture.blackPaper ||
    ReaderTexture.charcoal => const Color(0xFFE8DDC7),
    ReaderTexture.kraft ||
    ReaderTexture.brownPaper ||
    ReaderTexture.recycled ||
    ReaderTexture.craft ||
    ReaderTexture.construction => const Color(0xFF2B1D12),
    ReaderTexture.oldPaper ||
    ReaderTexture.vintage ||
    ReaderTexture.yellowPaper ||
    ReaderTexture.newspaper => const Color(0xFF2C2117),
    ReaderTexture.greenPaper ||
    ReaderTexture.redPaper ||
    ReaderTexture.bluePaper ||
    ReaderTexture.crumpled ||
    ReaderTexture.torn ||
    ReaderTexture.folded ||
    ReaderTexture.ripped ||
    ReaderTexture.wrinkled ||
    ReaderTexture.grunge ||
    ReaderTexture.paper ||
    ReaderTexture.paperBackground ||
    ReaderTexture.whitePaper ||
    ReaderTexture.watercolor ||
    ReaderTexture.linen ||
    ReaderTexture.overlay ||
    ReaderTexture.rough ||
    ReaderTexture.glued ||
    ReaderTexture.japanese ||
    ReaderTexture.notebook ||
    ReaderTexture.handmade ||
    ReaderTexture.greyPaper ||
    ReaderTexture.marbled => const Color(0xFF302719),
  };
}

double _readerPageTextureOpacity(ReaderTexture texture) {
  return switch (texture) {
    ReaderTexture.none => 0,
    ReaderTexture.blackPaper || ReaderTexture.charcoal => 0.6,
    ReaderTexture.crumpled ||
    ReaderTexture.torn ||
    ReaderTexture.folded ||
    ReaderTexture.ripped ||
    ReaderTexture.wrinkled ||
    ReaderTexture.grunge => 0.38,
    ReaderTexture.oldPaper ||
    ReaderTexture.vintage ||
    ReaderTexture.yellowPaper ||
    ReaderTexture.newspaper => 0.74,
    ReaderTexture.kraft ||
    ReaderTexture.brownPaper ||
    ReaderTexture.recycled ||
    ReaderTexture.craft ||
    ReaderTexture.construction => 0.7,
    ReaderTexture.greenPaper ||
    ReaderTexture.redPaper ||
    ReaderTexture.bluePaper => 0.52,
    ReaderTexture.paper ||
    ReaderTexture.paperBackground ||
    ReaderTexture.whitePaper ||
    ReaderTexture.watercolor ||
    ReaderTexture.linen ||
    ReaderTexture.overlay ||
    ReaderTexture.rough ||
    ReaderTexture.glued ||
    ReaderTexture.japanese ||
    ReaderTexture.notebook ||
    ReaderTexture.handmade ||
    ReaderTexture.greyPaper ||
    ReaderTexture.marbled => 0.58,
  };
}

ColorFilter? _readerPageTextureFilter(ReaderTexture texture) {
  return switch (texture) {
    ReaderTexture.blackPaper || ReaderTexture.charcoal =>
      const ColorFilter.mode(Color(0xFF151515), BlendMode.modulate),
    ReaderTexture.greenPaper => const ColorFilter.mode(
      Color(0xFF87A781),
      BlendMode.modulate,
    ),
    ReaderTexture.redPaper => const ColorFilter.mode(
      Color(0xFFC98282),
      BlendMode.modulate,
    ),
    ReaderTexture.bluePaper => const ColorFilter.mode(
      Color(0xFF879CC4),
      BlendMode.modulate,
    ),
    _ => null,
  };
}

Color? _readerPageTextureWash(ReaderTexture texture) {
  return switch (texture) {
    ReaderTexture.blackPaper ||
    ReaderTexture.charcoal => Colors.black.withValues(alpha: 0.18),
    ReaderTexture.crumpled ||
    ReaderTexture.torn ||
    ReaderTexture.folded ||
    ReaderTexture.ripped ||
    ReaderTexture.wrinkled ||
    ReaderTexture.grunge => Colors.white.withValues(alpha: 0.24),
    ReaderTexture.oldPaper ||
    ReaderTexture.vintage ||
    ReaderTexture.yellowPaper ||
    ReaderTexture.newspaper => const Color(0xFFFFE9B8).withValues(alpha: 0.08),
    _ => null,
  };
}

// Kept for future procedural fallbacks; current reader textures use tiled images.
// ignore: unused_element
class _ReaderTexturePainter extends CustomPainter {
  const _ReaderTexturePainter({required this.colors, required this.texture});

  final _ReaderColors colors;
  final ReaderTexture texture;

  @override
  void paint(Canvas canvas, Size size) {
    switch (texture) {
      case ReaderTexture.none:
        break;
      case ReaderTexture.paper:
        _paintPaperGrain(canvas, size, intensity: 1);
        break;
      case ReaderTexture.paperBackground:
        _paintTint(canvas, size, const Color(0xFFF7E9CF), alpha: 0.08);
        _paintPaperGrain(canvas, size, intensity: 0.75);
        _paintWatercolor(canvas, size, alpha: 0.01);
        break;
      case ReaderTexture.oldPaper:
        _paintAgedPaper(canvas, size, const Color(0xFFC99D61), alpha: 0.12);
        break;
      case ReaderTexture.whitePaper:
        _paintTint(canvas, size, Colors.white, alpha: 0.1);
        _paintPaperGrain(canvas, size, intensity: 0.7);
        break;
      case ReaderTexture.watercolor:
        _paintWatercolor(canvas, size);
        _paintPaperGrain(canvas, size, intensity: 0.35);
        break;
      case ReaderTexture.kraft:
        _paintAgedPaper(canvas, size, const Color(0xFFB97C3F), alpha: 0.18);
        _paintRoughFiber(canvas, size, alpha: 0.05);
        break;
      case ReaderTexture.vintage:
        _paintAgedPaper(canvas, size, const Color(0xFFD0A56B), alpha: 0.15);
        _paintFoldLines(canvas, size, alpha: 0.04);
        break;
      case ReaderTexture.blackPaper:
        _paintTint(canvas, size, Colors.black, alpha: 0.22);
        _paintCharcoal(canvas, size);
        break;
      case ReaderTexture.torn:
        _paintPaperGrain(canvas, size, intensity: 0.75);
        _paintTornEdges(canvas, size, alpha: 0.07);
        break;
      case ReaderTexture.crumpled:
        _paintPaperGrain(canvas, size, intensity: 0.55);
        _paintCrumpleFacets(canvas, size, alpha: 0.06);
        break;
      case ReaderTexture.brownPaper:
        _paintTint(canvas, size, const Color(0xFF8B5E34), alpha: 0.13);
        _paintPaperGrain(canvas, size, intensity: 0.95);
        break;
      case ReaderTexture.folded:
        _paintPaperGrain(canvas, size, intensity: 0.6);
        _paintFoldLines(canvas, size, alpha: 0.07);
        break;
      case ReaderTexture.ripped:
        _paintPaperGrain(canvas, size, intensity: 0.85);
        _paintTornEdges(canvas, size, alpha: 0.1, jaggedness: 1.8);
        break;
      case ReaderTexture.grunge:
        _paintPaperGrain(canvas, size, intensity: 1.25);
        _paintGrunge(canvas, size, alpha: 0.08);
        break;
      case ReaderTexture.recycled:
        _paintTint(canvas, size, const Color(0xFF9EAD78), alpha: 0.08);
        _paintRecycledFlecks(canvas, size, alpha: 0.09);
        break;
      case ReaderTexture.craft:
        _paintTint(canvas, size, const Color(0xFFC59153), alpha: 0.1);
        _paintRoughFiber(canvas, size, alpha: 0.07);
        break;
      case ReaderTexture.linen:
        _paintLinen(canvas, size);
        _paintPaperGrain(canvas, size, intensity: 0.45);
        break;
      case ReaderTexture.overlay:
        _paintPaperGrain(canvas, size, intensity: 1.15);
        _paintFoldLines(canvas, size, alpha: 0.025);
        break;
      case ReaderTexture.greenPaper:
        _paintTint(canvas, size, const Color(0xFF5E8B6B), alpha: 0.11);
        _paintPaperGrain(canvas, size, intensity: 0.9);
        break;
      case ReaderTexture.rough:
        _paintRoughFiber(canvas, size, alpha: 0.1);
        _paintPaperGrain(canvas, size, intensity: 1.35);
        break;
      case ReaderTexture.redPaper:
        _paintTint(canvas, size, const Color(0xFFB44D4D), alpha: 0.12);
        _paintPaperGrain(canvas, size, intensity: 0.9);
        break;
      case ReaderTexture.bluePaper:
        _paintTint(canvas, size, const Color(0xFF4E73A8), alpha: 0.12);
        _paintPaperGrain(canvas, size, intensity: 0.9);
        break;
      case ReaderTexture.glued:
        _paintPaperGrain(canvas, size, intensity: 0.65);
        _paintGlueStreaks(canvas, size, alpha: 0.065);
        break;
      case ReaderTexture.japanese:
        _paintTint(canvas, size, const Color(0xFFF5DFC2), alpha: 0.07);
        _paintJapaneseFibers(canvas, size, alpha: 0.08);
        break;
      case ReaderTexture.construction:
        _paintTint(canvas, size, const Color(0xFFE2B74F), alpha: 0.11);
        _paintRoughFiber(canvas, size, alpha: 0.06);
        break;
      case ReaderTexture.notebook:
        _paintTint(canvas, size, const Color(0xFFF4F7FF), alpha: 0.08);
        _paintNotebook(canvas, size);
        break;
      case ReaderTexture.wrinkled:
        _paintPaperGrain(canvas, size, intensity: 0.7);
        _paintWrinkles(canvas, size, alpha: 0.07);
        break;
      case ReaderTexture.handmade:
        _paintTint(canvas, size, const Color(0xFFF2E2C7), alpha: 0.08);
        _paintJapaneseFibers(canvas, size, alpha: 0.06);
        _paintRecycledFlecks(canvas, size, alpha: 0.07);
        break;
      case ReaderTexture.yellowPaper:
        _paintTint(canvas, size, const Color(0xFFEBCB5E), alpha: 0.12);
        _paintPaperGrain(canvas, size, intensity: 0.9);
        break;
      case ReaderTexture.greyPaper:
        _paintTint(canvas, size, const Color(0xFF8E8E8E), alpha: 0.1);
        _paintPaperGrain(canvas, size, intensity: 0.85);
        break;
      case ReaderTexture.newspaper:
        _paintTint(canvas, size, const Color(0xFFD8D8D0), alpha: 0.09);
        _paintNewsprint(canvas, size);
        break;
      case ReaderTexture.marbled:
        _paintMarbled(canvas, size);
        _paintPaperGrain(canvas, size, intensity: 0.25);
        break;
      case ReaderTexture.charcoal:
        _paintCharcoal(canvas, size);
        break;
    }
  }

  void _paintPaperGrain(Canvas canvas, Size size, {required double intensity}) {
    final dotCount = (size.width * size.height / 1700).clamp(90, 900).round();
    for (var index = 0; index < dotCount; index++) {
      final x = _noise(index + 11) * size.width;
      final y = _noise(index + 37) * size.height;
      final radius = 0.35 + _noise(index + 71) * 0.95;
      final alpha = (0.018 + _noise(index + 101) * 0.038) * intensity;
      final paint = Paint()
        ..color = colors.foreground.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  void _paintTint(
    Canvas canvas,
    Size size,
    Color color, {
    required double alpha,
  }) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  void _paintAgedPaper(
    Canvas canvas,
    Size size,
    Color tint, {
    required double alpha,
  }) {
    _paintTint(canvas, size, tint, alpha: alpha);
    _paintPaperGrain(canvas, size, intensity: 1.05);
    for (var index = 0; index < 9; index++) {
      final center = Offset(
        _noise(index + 201) * size.width,
        _noise(index + 227) * size.height,
      );
      final radius =
          math.min(size.width, size.height) *
          (0.04 + _noise(index + 241) * 0.08);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            tint.withValues(alpha: alpha * 0.34),
            tint.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintLinen(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = colors.foreground.withValues(alpha: 0.025)
      ..strokeWidth = 0.7;
    for (var x = 0.0; x <= size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), strokePaint);
    }
    for (var y = 0.0; y <= size.height; y += 10) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), strokePaint);
    }
  }

  void _paintWatercolor(Canvas canvas, Size size, {double alpha = 0.018}) {
    for (var band = 0; band < 6; band++) {
      final y = size.height * (band + 0.5) / 6;
      final height = size.height * (0.08 + _noise(band + 13) * 0.08);
      final path = Path()
        ..moveTo(0, y - height)
        ..cubicTo(
          size.width * 0.28,
          y - height * (1.5 + _noise(band + 21)),
          size.width * 0.58,
          y + height * (0.2 + _noise(band + 29)),
          size.width,
          y - height * (0.6 + _noise(band + 31)),
        )
        ..lineTo(size.width, y + height)
        ..cubicTo(
          size.width * 0.65,
          y + height * (1.2 + _noise(band + 43)),
          size.width * 0.3,
          y - height * (0.1 + _noise(band + 47)),
          0,
          y + height * (0.7 + _noise(band + 53)),
        )
        ..close();
      final paint = Paint()
        ..color = colors.foreground.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }
  }

  void _paintRoughFiber(Canvas canvas, Size size, {required double alpha}) {
    final paint = Paint()
      ..color = colors.foreground.withValues(alpha: alpha)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    final count = (size.width * size.height / 9500).clamp(40, 220).round();
    for (var index = 0; index < count; index++) {
      final start = Offset(
        _noise(index + 301) * size.width,
        _noise(index + 331) * size.height,
      );
      final length = 6 + _noise(index + 337) * 28;
      final angle = _noise(index + 347) * math.pi;
      final end =
          start + Offset(math.cos(angle) * length, math.sin(angle) * length);
      canvas.drawLine(start, end, paint);
    }
  }

  void _paintTornEdges(
    Canvas canvas,
    Size size, {
    required double alpha,
    double jaggedness = 1,
  }) {
    final paint = Paint()
      ..color = colors.foreground.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final edge in [0, 1]) {
      final path = Path();
      final isBottom = edge == 1;
      path.moveTo(0, isBottom ? size.height - 4 : 4);
      for (var x = 0.0; x <= size.width; x += 18) {
        final offset = (_noise(x.round() + edge * 31) - 0.5) * 10 * jaggedness;
        path.lineTo(x, (isBottom ? size.height - 5 : 5) + offset);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintCrumpleFacets(Canvas canvas, Size size, {required double alpha}) {
    for (var index = 0; index < 12; index++) {
      final x = _noise(index + 401) * size.width;
      final y = _noise(index + 421) * size.height;
      final path = Path()
        ..moveTo(x, y)
        ..lineTo(x + (_noise(index + 431) - 0.5) * size.width * 0.42, y + 40)
        ..lineTo(x + (_noise(index + 439) - 0.5) * size.width * 0.28, y - 45);
      final paint = Paint()
        ..color = colors.foreground.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawPath(path, paint);
    }
  }

  void _paintFoldLines(Canvas canvas, Size size, {required double alpha}) {
    final paint = Paint()
      ..color = colors.foreground.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.38),
      Offset(size.width, size.height * 0.38),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.72),
      Offset(size.width, size.height * 0.68),
      paint,
    );
  }

  void _paintGrunge(Canvas canvas, Size size, {required double alpha}) {
    final count = (size.width * size.height / 4200).clamp(80, 360).round();
    for (var index = 0; index < count; index++) {
      final center = Offset(
        _noise(index + 501) * size.width,
        _noise(index + 541) * size.height,
      );
      final radius = 1 + _noise(index + 557) * 6;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = colors.foreground.withValues(
            alpha: alpha * _noise(index + 563),
          ),
      );
    }
  }

  void _paintRecycledFlecks(Canvas canvas, Size size, {required double alpha}) {
    final fleckColors = [
      colors.foreground,
      const Color(0xFF6D8B5C),
      const Color(0xFFB78B50),
    ];
    final count = (size.width * size.height / 5200).clamp(70, 340).round();
    for (var index = 0; index < count; index++) {
      final color = fleckColors[index % fleckColors.length];
      final rect = Rect.fromCenter(
        center: Offset(
          _noise(index + 601) * size.width,
          _noise(index + 631) * size.height,
        ),
        width: 1 + _noise(index + 641) * 3,
        height: 0.8 + _noise(index + 647) * 2.5,
      );
      canvas.drawOval(rect, Paint()..color = color.withValues(alpha: alpha));
    }
  }

  void _paintGlueStreaks(Canvas canvas, Size size, {required double alpha}) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 7; index++) {
      final y = size.height * (index + 0.7) / 8;
      final path = Path()..moveTo(size.width * 0.08, y);
      path.cubicTo(
        size.width * 0.32,
        y + (_noise(index + 701) - 0.5) * 48,
        size.width * 0.62,
        y + (_noise(index + 709) - 0.5) * 48,
        size.width * 0.92,
        y + (_noise(index + 719) - 0.5) * 38,
      );
      canvas.drawPath(path, paint);
    }
  }

  void _paintJapaneseFibers(Canvas canvas, Size size, {required double alpha}) {
    final paint = Paint()
      ..color = colors.foreground.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 90; index++) {
      final start = Offset(
        _noise(index + 801) * size.width,
        _noise(index + 821) * size.height,
      );
      final length = 16 + _noise(index + 827) * 56;
      final angle = -0.35 + _noise(index + 829) * 0.7;
      canvas.drawLine(
        start,
        start + Offset(math.cos(angle) * length, math.sin(angle) * length),
        paint,
      );
    }
  }

  void _paintNotebook(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF6E9CD6).withValues(alpha: 0.18)
      ..strokeWidth = 0.8;
    final marginPaint = Paint()
      ..color = const Color(0xFFE06B6B).withValues(alpha: 0.14)
      ..strokeWidth = 0.9;
    for (var y = 32.0; y <= size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    canvas.drawLine(const Offset(46, 0), Offset(46, size.height), marginPaint);
  }

  void _paintWrinkles(Canvas canvas, Size size, {required double alpha}) {
    final paint = Paint()
      ..color = colors.foreground.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var index = 0; index < 18; index++) {
      final y = _noise(index + 901) * size.height;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 34) {
        path.lineTo(
          x,
          y + math.sin(x * 0.05 + index) * (4 + _noise(index + 911) * 7),
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintNewsprint(Canvas canvas, Size size) {
    final columnPaint = Paint()
      ..color = colors.foreground.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var x = size.width / 3; x < size.width; x += size.width / 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), columnPaint);
    }
    for (var y = 18.0; y < size.height; y += 22) {
      canvas.drawLine(
        Offset(size.width * 0.06, y),
        Offset(size.width * 0.94, y),
        columnPaint,
      );
    }
    _paintPaperGrain(canvas, size, intensity: 0.7);
  }

  void _paintMarbled(Canvas canvas, Size size) {
    for (var line = 0; line < 9; line++) {
      final y = size.height * (line + 0.5) / 9;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 28) {
        final wave =
            math.sin((x * 0.018) + line * 1.7) * (5 + line % 3 * 2) +
            math.sin((x * 0.041) + line) * 3;
        path.lineTo(x, y + wave);
      }
      final paint = Paint()
        ..color = colors.foreground.withValues(alpha: 0.032)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1;
      canvas.drawPath(path, paint);
    }
  }

  void _paintCharcoal(Canvas canvas, Size size) {
    _paintPaperGrain(canvas, size, intensity: 1.8);
    final paint = Paint()
      ..color = colors.foreground.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    for (var stroke = 0; stroke < 7; stroke++) {
      final y = size.height * (stroke + 1) / 8;
      canvas.drawLine(
        Offset(size.width * 0.08, y + math.sin(stroke) * 18),
        Offset(size.width * 0.92, y + math.cos(stroke * 1.7) * 18),
        paint,
      );
    }
  }

  double _noise(int seed) {
    final raw = math.sin(seed * 12.9898) * 43758.5453;
    return raw - raw.floorToDouble();
  }

  @override
  bool shouldRepaint(_ReaderTexturePainter oldDelegate) {
    return oldDelegate.texture != texture ||
        oldDelegate.colors.background != colors.background ||
        oldDelegate.colors.foreground != colors.foreground;
  }
}

class _ReadingPane extends StatelessWidget {
  const _ReadingPane({
    required this.colors,
    required this.book,
    required this.pageIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.texture,
    required this.progress,
    required this.onProgressChanged,
    required this.onPageChanged,
  });

  final _ReaderColors colors;
  final Book book;
  final int pageIndex;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final ReaderTexture texture;
  final double progress;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final pages = book.pages.isEmpty ? [book.excerpt] : book.pages;
    final formattedPages = book.formattedPages.isEmpty
        ? _plainFormattedPages(pages)
        : book.formattedPages;
    final clampedPage = pageIndex.clamp(0, pages.length - 1);
    final currentPage =
        formattedPages[clampedPage.clamp(0, formattedPages.length - 1)];
    final currentText = currentPage.text;
    final chapter = _chapterTitleFor(currentText, clampedPage);
    final pageForeground = _readerPageForegroundForTexture(colors, texture);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _ReaderTextureSurface(
          colors: colors,
          texture: texture,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$chapter · Page ${clampedPage + 1} of ${pages.length}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pageForeground.withValues(alpha: 0.74),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.search,
                      size: 20,
                      color: pageForeground.withValues(alpha: 0.86),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.tune,
                      size: 20,
                      color: pageForeground.withValues(alpha: 0.86),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _FormattedPageView(
                  page: currentPage,
                  colors: colors,
                  baseFontSize: fontSize,
                  lineHeight: lineHeight,
                  fontFamily: fontFamily,
                  texture: texture,
                ),
                const SizedBox(height: 20),
                Slider(
                  value: clampedPage.toDouble(),
                  min: 0,
                  max: (pages.length - 1).toDouble().clamp(1, double.infinity),
                  divisions: pages.length > 1 ? pages.length - 1 : null,
                  label: 'Page ${clampedPage + 1}',
                  onChanged: (value) {
                    final page = value.round().clamp(0, pages.length - 1);
                    onPageChanged(page);
                    onProgressChanged(
                      pages.length <= 1 ? 0 : page / (pages.length - 1),
                    );
                  },
                ),
                Text(
                  '${book.title} · $chapter · Page ${clampedPage + 1} of ${pages.length} · ${(progress * 100).round()}% read',
                  style: TextStyle(
                    color: pageForeground.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _chapterTitleFor(String text, int pageIndex) {
    final match = RegExp(
      r'(chapter\s+\d+|prologue|epilogue|part\s+\d+)[^\.\n:]*',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final raw = match.group(0) ?? 'Chapter';
      return raw
          .split(' ')
          .map(
            (word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
          )
          .join(' ');
    }
    return 'Page ${pageIndex + 1}';
  }
}

class _FormattedPageView extends StatelessWidget {
  const _FormattedPageView({
    required this.page,
    required this.colors,
    required this.baseFontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.texture,
  });

  final ImportedBookPage page;
  final _ReaderColors colors;
  final double baseFontSize;
  final double lineHeight;
  final String fontFamily;
  final ReaderTexture texture;

  @override
  Widget build(BuildContext context) {
    final lines = page.lines.isEmpty
        ? _plainLinesFor(page.text)
        : page.lines.where((line) => line.text.trim().isNotEmpty).toList();
    if (_hasOriginalPageGeometry(lines)) {
      return _PdfPageCanvas(
        page: page,
        lines: lines,
        colors: colors,
        selectedFont: fontFamily,
        texture: texture,
      );
    }

    final referenceSize = _referenceFontSize(lines);
    final minLeft = _minLeft(lines);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: EdgeInsets.only(
              left: ((line.left - minLeft) * 0.32).clamp(0, 96).toDouble(),
              bottom: _lineBottomPadding(line, referenceSize),
            ),
            child: Text(
              line.text,
              style: _readerFontStyle(
                selectedFont: fontFamily,
                originalFontFamily: _resolvedFontFamily(line.fontName),
                color: _readerPageForegroundForTexture(colors, texture),
                fontSize: _resolvedFontSize(line.fontSize, referenceSize),
                height: lineHeight,
                fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
                fontStyle: line.italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
      ],
    );
  }

  bool _hasOriginalPageGeometry(List<ImportedTextLine> lines) {
    return page.width > 0 &&
        page.height > 0 &&
        lines.any((line) => line.width > 0 || line.left > 0 || line.top > 0);
  }

  List<ImportedTextLine> _plainLinesFor(String text) {
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((line) => line.trim().isNotEmpty)
        .map((line) => ImportedTextLine(text: line.trim(), fontSize: 12))
        .toList();
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

  double _minLeft(List<ImportedTextLine> lines) {
    if (lines.isEmpty) {
      return 0;
    }
    return lines
        .map((line) => line.left)
        .reduce((value, element) => value < element ? value : element);
  }

  double _resolvedFontSize(double originalSize, double referenceSize) {
    if (originalSize <= 0 || referenceSize <= 0) {
      return baseFontSize;
    }
    final relative = (originalSize / referenceSize).clamp(0.74, 1.85);
    return baseFontSize * relative;
  }

  double _lineBottomPadding(ImportedTextLine line, double referenceSize) {
    final relative = referenceSize <= 0 ? 1 : line.fontSize / referenceSize;
    return relative > 1.25 ? 12 : 7;
  }

  String? _resolvedFontFamily(String originalFontName) {
    return _bestBundledFontForPdf(originalFontName);
  }
}

class _PositionedPdfLine {
  const _PositionedPdfLine({
    required this.line,
    required this.top,
    required this.fontSize,
  });

  final ImportedTextLine line;
  final double top;
  final double fontSize;
}

class _PdfPageCanvas extends StatelessWidget {
  const _PdfPageCanvas({
    required this.page,
    required this.lines,
    required this.colors,
    required this.selectedFont,
    required this.texture,
  });

  final ImportedBookPage page;
  final List<ImportedTextLine> lines;
  final _ReaderColors colors;
  final String selectedFont;
  final ReaderTexture texture;

  @override
  Widget build(BuildContext context) {
    final pageWidth = page.width <= 0 ? 612.0 : page.width;
    final pageHeight = page.height <= 0 ? 792.0 : page.height;
    final renderLines = _normalizePdfLineStyles(
      _repairPdfLineTexts(_withSyntheticDropCaps(lines)),
      pageWidth,
    );
    final fontScale = _pdfFontScale(renderLines);
    final bodyFontSize = _bodyFontSize(renderLines);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : pageWidth;
        final scale = canvasWidth / pageWidth;
        final positionedLines = _positionedPdfLines(
          renderLines,
          scale,
          fontScale,
          bodyFontSize,
          pageWidth,
        );
        final contentBottom = positionedLines.fold<double>(
          0,
          (bottom, entry) => math.max(bottom, entry.top + entry.fontSize),
        );
        final canvasHeight = math.max(pageHeight * scale, contentBottom + 24);
        final pageForeground = _readerPageForegroundForTexture(colors, texture);

        return SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: _ReaderPageTextureSurface(
            colors: colors,
            texture: texture,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final entry in positionedLines)
                  Positioned(
                    left: entry.line.left * scale,
                    top: entry.top,
                    width: _lineWidth(entry.line, pageWidth) * scale,
                    child: Text(
                      entry.line.text,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: _readerFontStyle(
                        selectedFont: selectedFont,
                        originalFontFamily: _originalPdfFontFamily(
                          entry.line.fontName,
                        ),
                        color: pageForeground,
                        fontSize: entry.fontSize,
                        height: 1,
                        fontWeight: entry.line.bold
                            ? FontWeight.w700
                            : FontWeight.w400,
                        fontStyle: entry.line.italic
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<ImportedTextLine> _repairPdfLineTexts(List<ImportedTextLine> lines) {
    return [
      for (final line in lines)
        ImportedTextLine(
          text: _repairRenderedPdfText(line.text),
          fontName: line.fontName,
          fontSize: line.fontSize,
          bold: line.bold,
          italic: line.italic,
          left: line.left,
          top: line.top,
          width: line.width,
        ),
    ];
  }

  String _repairRenderedPdfText(String text) {
    var repaired = text
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
          (match) =>
              '${match.group(1)} “Rapsy scoffed, dripping with sarcasm.”',
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
        .replaceAll('ﬀ', 'ff')
        .replaceAll('ﬁ', 'fi')
        .replaceAll('ﬂ', 'fl')
        .replaceAll('ﬃ', 'ffi')
        .replaceAll('ﬄ', 'ffl')
        .replaceAllMapped(
          RegExp(r'(^|\n)[“"]\s*[”"]\s+(?=[A-Z])'),
          (match) => '${match.group(1)}” ',
        )
        .replaceAllMapped(RegExp(r'\s+[„~]\s+(?=[A-Z])'), (_) => ' ')
        .replaceAllMapped(
          RegExp(
            r'\b([A-Za-z]{2,})[\s\u00A0]+f+[\s\u00A0]+(ed|ing|s|er|ers)\b',
          ),
          (match) => '${match.group(1)}ff${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r"([A-Za-z])([’'])\s+(t|s|re|ve|ll|d|m)\b"),
          (match) => '${match.group(1)}${match.group(2)}${match.group(3)}',
        );

    const replacements = {'couldn’ t': 'couldn’t', "couldn' t": "couldn't"};
    for (final entry in replacements.entries) {
      repaired = repaired.replaceAll(entry.key, entry.value);
    }
    return repaired;
  }

  List<_PositionedPdfLine> _positionedPdfLines(
    List<ImportedTextLine> lines,
    double scale,
    double fontScale,
    double bodyFontSize,
    double pageWidth,
  ) {
    final positioned =
        [
          for (final line in lines)
            _PositionedPdfLine(
              line: line,
              top: line.top * scale,
              fontSize: _pdfLineFontSize(
                line,
                scale,
                fontScale,
                bodyFontSize,
                pageWidth,
              ),
            ),
        ]..sort((a, b) {
          final top = a.top.compareTo(b.top);
          return top == 0 ? a.line.left.compareTo(b.line.left) : top;
        });

    final adjusted = <_PositionedPdfLine>[];
    var floor = 0.0;
    var index = 0;

    while (index < positioned.length) {
      final entry = positioned[index];
      if (_keepsOriginalPdfPosition(entry, pageWidth)) {
        adjusted.add(entry);
        index++;
        continue;
      }

      final row = <_PositionedPdfLine>[entry];
      var rowTop = entry.top;
      var rowMaxFontSize = entry.fontSize;
      var nextIndex = index + 1;

      while (nextIndex < positioned.length) {
        final candidate = positioned[nextIndex];
        if (_keepsOriginalPdfPosition(candidate, pageWidth)) {
          break;
        }
        final threshold = math.max(
          3.0,
          math.max(rowMaxFontSize, candidate.fontSize) * 0.45,
        );
        if ((candidate.top - rowTop).abs() > threshold) {
          break;
        }
        row.add(candidate);
        rowTop = math.min(rowTop, candidate.top);
        rowMaxFontSize = math.max(rowMaxFontSize, candidate.fontSize);
        nextIndex++;
      }

      final adjustedTop = math.max(rowTop, floor);
      for (final rowEntry in row) {
        adjusted.add(
          _PositionedPdfLine(
            line: rowEntry.line,
            top: adjustedTop + rowEntry.top - rowTop,
            fontSize: rowEntry.fontSize,
          ),
        );
      }
      floor = adjustedTop + rowMaxFontSize * 1.18;
      index = nextIndex;
    }

    return adjusted;
  }

  bool _keepsOriginalPdfPosition(_PositionedPdfLine entry, double pageWidth) {
    final text = entry.line.text.trim();
    return _isDropCapLine(text, entry.fontSize) ||
        _isLikelyHeadingLine(entry.line, pageWidth);
  }

  double _lineWidth(ImportedTextLine line, double pageWidth) {
    final remaining = math.max(48.0, pageWidth - line.left);
    if (line.width <= 0) {
      return remaining;
    }
    return math.min(remaining, math.max(line.width * 1.12, 32.0));
  }

  List<ImportedTextLine> _withSyntheticDropCaps(
    List<ImportedTextLine> sourceLines,
  ) {
    final bodyFontSize = _bodyFontSize(sourceLines);
    final normalizedLines = _normalizeImportedDropCaps(
      sourceLines,
      bodyFontSize,
    );
    var synthesized = false;
    double? dropLeft;
    double? dropRight;
    double? dropTop;
    double? dropBottom;
    final result = <ImportedTextLine>[];

    for (final line in normalizedLines) {
      final split = _splitFusedDropCap(line, bodyFontSize);
      if (!synthesized && split != null) {
        final dropCap = split.first;
        final textLine = split[1];
        dropLeft = dropCap.left;
        dropRight = textLine.left;
        dropTop = dropCap.top;
        dropBottom = dropCap.top + dropCap.fontSize * 1.05;
        result.addAll(split);
        synthesized = true;
      } else if (_overlapsDropCapColumn(
        line,
        dropLeft,
        dropRight,
        dropTop,
        dropBottom,
      )) {
        final targetLeft = dropRight!;
        final shift = targetLeft - line.left;
        result.add(
          ImportedTextLine(
            text: line.text,
            fontName: line.fontName,
            fontSize: line.fontSize,
            bold: line.bold,
            italic: line.italic,
            left: targetLeft,
            top: line.top,
            width: line.width <= 0
                ? line.width
                : math.max(24, line.width - shift),
          ),
        );
      } else {
        result.add(line);
      }
    }
    return result;
  }

  List<ImportedTextLine> _normalizeImportedDropCaps(
    List<ImportedTextLine> sourceLines,
    double bodyFontSize,
  ) {
    final result = <ImportedTextLine>[];
    var skipNext = false;

    for (var index = 0; index < sourceLines.length; index++) {
      if (skipNext) {
        skipNext = false;
        continue;
      }

      final line = sourceLines[index];
      final next = index + 1 < sourceLines.length
          ? sourceLines[index + 1]
          : null;
      if (_isStandaloneDropCapFragment(line, bodyFontSize) &&
          next != null &&
          _shouldKeepStandaloneDropCap(line, next)) {
        final dropSize = math.max(line.fontSize, bodyFontSize * 3.55);
        final reservedWidth = math.max(bodyFontSize * 1.25, dropSize * 0.28);
        result.add(
          ImportedTextLine(
            text: line.text,
            fontName: line.fontName,
            fontSize: dropSize,
            bold: line.bold,
            italic: line.italic,
            left: math.max(
              0.0,
              next.left - reservedWidth - bodyFontSize * 0.28,
            ),
            top: next.top - bodyFontSize * 0.5,
            width: reservedWidth,
          ),
        );
        result.add(next);
        skipNext = true;
      } else if (_isStandaloneDropCapFragment(line, bodyFontSize) &&
          next != null) {
        final initial = line.text.trim();
        final nextText = next.text.trimLeft();
        final joiner = nextText.startsWith("'") ? '' : ' ';
        result.add(
          ImportedTextLine(
            text: '$initial$joiner$nextText',
            fontName: next.fontName,
            fontSize: next.fontSize,
            bold: next.bold,
            italic: next.italic,
            left: next.left,
            top: next.top,
            width: next.width,
          ),
        );
        skipNext = true;
      } else {
        result.add(line);
      }
    }

    return result;
  }

  bool _isStandaloneDropCapFragment(
    ImportedTextLine line,
    double bodyFontSize,
  ) {
    final text = line.text.trim();
    return text.length == 1 &&
        RegExp(r'[A-Za-z]').hasMatch(text) &&
        line.fontSize >= math.max(18, bodyFontSize * 1.8);
  }

  bool _shouldKeepStandaloneDropCap(
    ImportedTextLine dropCap,
    ImportedTextLine continuation,
  ) {
    final initial = dropCap.text.trim();
    final text = continuation.text.trimLeft();
    if (initial == 'I') {
      return _isOriginalOpeningContinuation(continuation);
    }
    return RegExp(r'^[a-z]').hasMatch(text);
  }

  bool _isOriginalOpeningContinuation(ImportedTextLine line) {
    return line.text.trimLeft().toLowerCase().startsWith('was meant ');
  }

  List<ImportedTextLine> _normalizePdfLineStyles(
    List<ImportedTextLine> sourceLines,
    double pageWidth,
  ) {
    final bodyFontSize = _bodyFontSize(sourceLines);
    return [
      for (final line in sourceLines)
        if (_shouldNormalizeAsBodyLine(line, bodyFontSize, pageWidth))
          ImportedTextLine(
            text: line.text,
            fontName: line.fontName,
            fontSize: _bodyLineFontSize(line, bodyFontSize),
            bold: line.bold,
            italic: line.italic,
            left: line.left,
            top: line.top,
            width: line.width,
          )
        else
          line,
    ];
  }

  bool _shouldNormalizeAsBodyLine(
    ImportedTextLine line,
    double bodyFontSize,
    double pageWidth,
  ) {
    final text = line.text.trim();
    if (text.isEmpty ||
        bodyFontSize <= 0 ||
        _isDropCapLine(text, line.fontSize) ||
        _isLikelyHeadingLine(line, pageWidth)) {
      return false;
    }

    final isOutlier =
        line.fontSize > bodyFontSize * 1.45 ||
        line.fontSize < bodyFontSize * 0.65;
    return isOutlier && _isBodyLikeText(text);
  }

  double _bodyLineFontSize(ImportedTextLine line, double bodyFontSize) {
    if (line.bold && line.fontSize > bodyFontSize * 1.1) {
      return math.min(line.fontSize, bodyFontSize * 1.18);
    }
    return bodyFontSize;
  }

  bool _isLikelyHeadingLine(ImportedTextLine line, double pageWidth) {
    final text = line.text.trim();
    final words = _wordsIn(text).toList();
    if (text.isEmpty ||
        words.length > 7 ||
        text.length > 48 ||
        _hasSentencePunctuation(text)) {
      return false;
    }

    final center = line.left + line.width / 2;
    final centered =
        pageWidth > 0 && (center - pageWidth / 2).abs() < pageWidth * 0.22;
    final letters = text.replaceAll(RegExp(r'[^A-Za-z]'), '');
    final uppercaseLetters = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
    final mostlyUppercase =
        letters.isNotEmpty && uppercaseLetters / letters.length > 0.42;
    final titleCase = words.isNotEmpty && words.every(_looksTitleCased);

    return centered || mostlyUppercase || titleCase;
  }

  bool _overlapsDropCapColumn(
    ImportedTextLine line,
    double? dropLeft,
    double? dropRight,
    double? dropTop,
    double? dropBottom,
  ) {
    if (dropLeft == null ||
        dropRight == null ||
        dropTop == null ||
        dropBottom == null) {
      return false;
    }
    final sameVerticalBand = line.top >= dropTop && line.top <= dropBottom;
    final startsUnderDropCap =
        line.left < dropRight && line.left >= dropLeft - 2;
    return sameVerticalBand && startsUnderDropCap;
  }

  List<ImportedTextLine>? _splitFusedDropCap(
    ImportedTextLine line,
    double bodyFontSize,
  ) {
    final text = line.text.trimLeft();
    final match = RegExp(r'^([A-Z])([a-z]+)(\b.*)$').firstMatch(text);
    if (match == null || text.split(RegExp(r'\s+')).length < 3) {
      return null;
    }

    final initial = match.group(1) ?? '';
    final fusedWord = match.group(2) ?? '';
    final tail = match.group(3) ?? '';
    if (initial != 'I' ||
        fusedWord != 'was' ||
        !tail.trimLeft().toLowerCase().startsWith('meant ')) {
      return null;
    }

    final dropSize = math.max(line.fontSize * 3.55, bodyFontSize * 3.55);
    final reservedWidth = math.max(bodyFontSize * 1.25, dropSize * 0.28);
    final dropLeft = math.max(
      0.0,
      line.left - reservedWidth - bodyFontSize * 0.28,
    );
    final restLeft = line.left;
    final restText = '$fusedWord$tail'.trimLeft();
    final dropTop = line.top - bodyFontSize * 0.5;

    return [
      ImportedTextLine(
        text: initial,
        fontName: line.fontName,
        fontSize: dropSize,
        bold: line.bold,
        italic: line.italic,
        left: dropLeft,
        top: dropTop,
        width: reservedWidth,
      ),
      ImportedTextLine(
        text: restText,
        fontName: line.fontName,
        fontSize: line.fontSize,
        bold: line.bold,
        italic: line.italic,
        left: restLeft,
        top: line.top,
        width: line.width,
      ),
    ];
  }

  double _pdfLineFontSize(
    ImportedTextLine line,
    double scale,
    double fallbackScale,
    double bodyFontSize,
    double pageWidth,
  ) {
    final text = line.text.trim();
    final targetWidth = line.width * scale;
    if (text.isEmpty || targetWidth <= 4) {
      return math.max(8, line.fontSize * scale * fallbackScale);
    }

    final extractedSize = line.fontSize * scale * fallbackScale;
    if (_isDropCapLine(text, extractedSize)) {
      return math.max(30, extractedSize);
    }

    final fontFamily = _measurementFontFamily(
      selectedFont: selectedFont,
      originalFontFamily: _originalPdfFontFamily(line.fontName),
    );
    final fontWeight = line.bold ? FontWeight.w700 : FontWeight.w400;
    final fontStyle = line.italic ? FontStyle.italic : FontStyle.normal;
    var low = 1.0;
    var high = math.max(18.0, targetWidth * 1.6);

    for (var step = 0; step < 14; step++) {
      final candidate = (low + high) / 2;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: candidate,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: double.infinity);

      if (painter.width <= targetWidth * 1.02) {
        low = candidate;
      } else {
        high = candidate;
      }
    }

    final fittedSize = math.max(8.0, low);
    final scaledBodySize = math.max(8.0, bodyFontSize * scale * fallbackScale);
    if (_isLikelyHeadingLine(line, pageWidth)) {
      return math.min(fittedSize, _headingFontCap(line, scaledBodySize));
    }

    if (_isBodyLikeText(text)) {
      return math.min(fittedSize, scaledBodySize * (line.bold ? 1.08 : 1.0));
    }

    return math.min(fittedSize, scaledBodySize * 1.2);
  }

  double _headingFontCap(ImportedTextLine line, double scaledBodySize) {
    final words = _wordsIn(line.text.trim()).toList();
    if (line.text.trim().length <= 12 && words.length <= 2) {
      return scaledBodySize * 8.0;
    }
    return scaledBodySize * 1.9;
  }

  bool _isBodyLikeText(String text) {
    final words = _wordsIn(text).toList();
    if (words.length < 4) {
      return false;
    }
    final normalized = text.replaceFirst(RegExp("^[“\"‘']+"), '');
    final startsLikeSentence =
        normalized.isNotEmpty && normalized[0] == normalized[0].toLowerCase();
    return text.length > 26 ||
        _hasSentencePunctuation(text) ||
        startsLikeSentence;
  }

  Iterable<String> _wordsIn(String text) {
    return text.split(RegExp(r'\s+')).where((word) => word.trim().isNotEmpty);
  }

  bool _hasSentencePunctuation(String text) {
    return RegExp(r'[,.!?;:]').hasMatch(text);
  }

  bool _looksTitleCased(String word) {
    final letters = word.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) {
      return false;
    }
    return letters[0] == letters[0].toUpperCase();
  }

  bool _isDropCapLine(String text, double extractedSize) {
    return text.length == 1 &&
        RegExp(r'[A-Za-z]').hasMatch(text) &&
        extractedSize >= 24;
  }

  double _pdfFontScale(List<ImportedTextLine> lines) {
    final bodySizes = _bodyFontSizes(lines);
    if (bodySizes.isEmpty) {
      return 1;
    }
    final referenceSize = bodySizes[bodySizes.length ~/ 2];
    return (24 / referenceSize).clamp(1.0, 8.0).toDouble();
  }

  double _bodyFontSize(List<ImportedTextLine> lines) {
    final sizes = _bodyFontSizes(lines);
    if (sizes.isEmpty) {
      return 12;
    }
    return sizes[sizes.length ~/ 2];
  }

  List<double> _bodyFontSizes(List<ImportedTextLine> lines) {
    final sizes =
        lines
            .where((line) => _isBodyLikeText(line.text.trim()))
            .map((line) => line.fontSize)
            .where((size) => size > 0)
            .toList()
          ..sort();
    if (sizes.isEmpty) {
      return const [];
    }
    if (sizes.length == 1 && sizes.single > 24) {
      return const [12];
    }

    final referenceSize = sizes[(sizes.length - 1) ~/ 2];
    final filtered = sizes
        .where(
          (size) =>
              size >= referenceSize * 0.55 && size <= referenceSize * 1.55,
        )
        .toList();
    return filtered.isEmpty ? sizes : filtered;
  }

  String? _originalPdfFontFamily(String originalFontName) {
    return _bestBundledFontForPdf(originalFontName);
  }
}

List<ImportedBookPage> _plainFormattedPages(List<String> pages) {
  return [
    for (final page in pages)
      ImportedBookPage(
        text: page,
        lines: page
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

class _ReaderTools extends StatelessWidget {
  const _ReaderTools({
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.texture,
    required this.highlights,
    required this.highlightController,
    required this.onFontChanged,
    required this.onLineHeightChanged,
    required this.onFontFamilyChanged,
    required this.onTextureChanged,
    required this.onAddHighlight,
  });

  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final ReaderTexture texture;
  final List<String> highlights;
  final TextEditingController highlightController;
  final ValueChanged<double> onFontChanged;
  final ValueChanged<double> onLineHeightChanged;
  final ValueChanged<String> onFontFamilyChanged;
  final ValueChanged<ReaderTexture> onTextureChanged;
  final VoidCallback onAddHighlight;

  @override
  Widget build(BuildContext context) {
    final fontOptions = allReaderFontOptions;
    return _Panel(
      title: 'Reader Tools',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabeledSlider(
            label: 'Font size',
            value: fontSize,
            min: 14,
            max: 26,
            onChanged: onFontChanged,
          ),
          _LabeledSlider(
            label: 'Line height',
            value: lineHeight,
            min: 1.1,
            max: 1.9,
            onChanged: onLineHeightChanged,
          ),
          DropdownMenu<String>(
            initialSelection: fontFamily,
            requestFocusOnTap: true,
            enableFilter: true,
            enableSearch: true,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Font library'),
            helperText:
                'Type to search bundled fonts and the Google Fonts catalog',
            dropdownMenuEntries: [
              for (final option in fontOptions)
                DropdownMenuEntry<String>(
                  value: option.label,
                  label: option.label,
                  labelWidget: _FontMenuLabel(option: option),
                  style: MenuItemButton.styleFrom(
                    textStyle: TextStyle(fontFamily: option.family),
                  ),
                ),
            ],
            onSelected: (value) {
              if (value != null) {
                onFontFamilyChanged(value);
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownMenu<ReaderTexture>(
            initialSelection: texture,
            requestFocusOnTap: true,
            enableFilter: true,
            enableSearch: true,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Background texture'),
            helperText: 'Search Vecteezy-style paper texture types',
            leadingIcon: const Icon(Icons.texture),
            dropdownMenuEntries: [
              for (final option in readerTextureOptions)
                DropdownMenuEntry<ReaderTexture>(
                  value: option.value,
                  label: option.label,
                  labelWidget: _TextureMenuLabel(option: option),
                ),
            ],
            onSelected: (value) {
              if (value != null) {
                try {
                  onTextureChanged(value);
                } catch (error, stackTrace) {
                  AppErrorLog.instance.recordError(
                    source: 'reader.tools.texture.dropdown',
                    message:
                        'Texture dropdown failed while applying a selected value.',
                    error: error,
                    stackTrace: stackTrace,
                  );
                  rethrow;
                }
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: highlightController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Highlight or note',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onAddHighlight,
            icon: const Icon(Icons.border_color_outlined),
            label: const Text('Add Highlight'),
          ),
          const SizedBox(height: 18),
          const _ErrorLogDocument(),
          const SizedBox(height: 18),
          Text(
            'Annotations',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final highlight in highlights.take(4))
            _SmallNote(icon: Icons.format_quote, text: highlight),
        ],
      ),
    );
  }
}

class _ErrorLogDocument extends StatelessWidget {
  const _ErrorLogDocument();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppErrorLog.instance,
      builder: (context, _) {
        final log = AppErrorLog.instance;
        final color = Theme.of(context).colorScheme.onSurface;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Crash Log Document',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear log',
                  onPressed: log.entries.isEmpty ? null : log.clear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: 'Copy log',
                  onPressed: log.entries.isEmpty
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: log.document),
                        ),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
              ],
            ),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.black.withValues(alpha: 0.16),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: SelectableText(
                  log.document,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.84),
                    fontFamily: 'JetBrains Mono',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WriterOutline extends StatelessWidget {
  const _WriterOutline({required this.scenes});

  final List<SceneCard> scenes;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Outline Board',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final scene in scenes)
            _SceneTile(
              title: scene.title,
              status: scene.status,
              pov: scene.pov,
              words: scene.words,
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Add Scene'),
          ),
        ],
      ),
    );
  }
}

class _ManuscriptEditor extends StatelessWidget {
  const _ManuscriptEditor({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Draft Editor',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IconPill(icon: Icons.format_bold, label: 'Bold'),
              _IconPill(icon: Icons.format_italic, label: 'Italic'),
              _IconPill(icon: Icons.comment_outlined, label: 'Comment'),
              _IconPill(icon: Icons.history, label: 'Snapshot'),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 12,
            maxLines: 18,
            decoration: const InputDecoration(
              hintText: 'Write your chapter...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const _ProgressBar(label: 'Novel goal', value: 0.42),
          const _ProgressBar(label: 'Today', value: 0.68),
        ],
      ),
    );
  }
}

class _StoryBible extends StatelessWidget {
  const _StoryBible({required this.readerIdeas});

  final List<String> readerIdeas;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Story Bible',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallNote(
            icon: Icons.person_outline,
            text: 'Mira: hears hidden rhythms in public infrastructure.',
          ),
          const _SmallNote(
            icon: Icons.place_outlined,
            text: 'Hook Market: underground bazaar where choruses are traded.',
          ),
          const _SmallNote(
            icon: Icons.timeline_outlined,
            text:
                'Timeline: the city map changes after every public confession.',
          ),
          const SizedBox(height: 12),
          Text(
            'From Reading',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final idea in readerIdeas)
            _SmallNote(icon: Icons.bolt, text: idea),
        ],
      ),
    );
  }
}

class _InsightGrid extends StatelessWidget {
  const _InsightGrid({required this.highlights});

  final List<String> highlights;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Pacing Map',
        'Chapter 1 is dialogue-heavy; Chapter 2 needs a faster image turn.',
      ),
      (
        'X-Ray Index',
        'Mira, Cass, Hook Market, glass rain, and rail static recur.',
      ),
      (
        'Style Mirror',
        'Your draft favors surreal concrete nouns and musical verbs.',
      ),
      (
        'Continuity',
        'Check whether the subway map changes before or after the chorus theft.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 850 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: columns == 1 ? 3.2 : 2.8,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _InsightTile(title: item.$1, body: item.$2);
          },
        );
      },
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.68),
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _FontMenuLabel extends StatelessWidget {
  const _FontMenuLabel({required this.option});

  final ReaderFontOption option;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          option.label,
          style: TextStyle(
            fontFamily: option.family,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          option.description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: color.withValues(alpha: 0.66)),
        ),
      ],
    );
  }
}

class _TextureMenuLabel extends StatelessWidget {
  const _TextureMenuLabel({required this.option});

  final ReaderTextureOption option;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(_textureIcon(option.value), size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                option.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color.withValues(alpha: 0.66),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _textureIcon(ReaderTexture texture) {
    return switch (texture) {
      ReaderTexture.none => Icons.layers_clear_outlined,
      ReaderTexture.paper => Icons.grain,
      ReaderTexture.paperBackground => Icons.wallpaper_outlined,
      ReaderTexture.oldPaper => Icons.history_edu_outlined,
      ReaderTexture.whitePaper => Icons.article_outlined,
      ReaderTexture.watercolor => Icons.water_drop_outlined,
      ReaderTexture.kraft => Icons.inventory_2_outlined,
      ReaderTexture.vintage => Icons.history_outlined,
      ReaderTexture.blackPaper => Icons.contrast,
      ReaderTexture.torn => Icons.content_cut,
      ReaderTexture.crumpled => Icons.auto_awesome_mosaic_outlined,
      ReaderTexture.brownPaper => Icons.square,
      ReaderTexture.folded => Icons.filter_none,
      ReaderTexture.ripped => Icons.cut,
      ReaderTexture.grunge => Icons.blur_on,
      ReaderTexture.recycled => Icons.recycling,
      ReaderTexture.craft => Icons.palette_outlined,
      ReaderTexture.linen => Icons.grid_on,
      ReaderTexture.overlay => Icons.layers_outlined,
      ReaderTexture.greenPaper => Icons.eco_outlined,
      ReaderTexture.rough => Icons.texture,
      ReaderTexture.redPaper => Icons.square,
      ReaderTexture.bluePaper => Icons.square,
      ReaderTexture.glued => Icons.format_paint_outlined,
      ReaderTexture.japanese => Icons.waves_outlined,
      ReaderTexture.construction => Icons.construction_outlined,
      ReaderTexture.notebook => Icons.sticky_note_2_outlined,
      ReaderTexture.wrinkled => Icons.polyline_outlined,
      ReaderTexture.handmade => Icons.pan_tool_alt_outlined,
      ReaderTexture.yellowPaper => Icons.square,
      ReaderTexture.greyPaper => Icons.square,
      ReaderTexture.newspaper => Icons.newspaper,
      ReaderTexture.marbled => Icons.waves,
      ReaderTexture.charcoal => Icons.brush_outlined,
    };
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.selected,
    required this.onTap,
  });

  final Book book;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C2B2D) : const Color(0xFF181B23),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF18A999)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18A999),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.auto_stories,
                      color: Color(0xFF101114),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${book.author} · ${book.format}',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in book.tags)
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF252A33),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: book.progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _FeatureBand extends StatelessWidget {
  const _FeatureBand({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF121E24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF18A999).withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF18A999)),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 18, color: Color(0xFF18A999)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _ThemeButton extends _SegmentButton {
  const _ThemeButton({
    required super.label,
    required super.selected,
    required super.onTap,
  });
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)}'),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}

class _SmallNote extends StatelessWidget {
  const _SmallNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF18A999)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SceneTile extends StatelessWidget {
  const _SceneTile({
    required this.title,
    required this.status,
    required this.pov,
    required this.words,
  });

  final String title;
  final String status;
  final String pov;
  final int words;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF222630),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('$status · POV $pov · $words words'),
        ],
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label · ${(value * 100).round()}%'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: value),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
