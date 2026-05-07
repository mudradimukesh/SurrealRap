import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_importer.dart';

void main() {
  runApp(const SurrealRapApp());
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
    required this.mode,
    required this.highlights,
    required this.highlightController,
    required this.onProgressChanged,
    required this.onPageChanged,
    required this.onFontChanged,
    required this.onLineHeightChanged,
    required this.onFontFamilyChanged,
    required this.onThemeChanged,
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
  final String mode;
  final List<String> highlights;
  final TextEditingController highlightController;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<double> onFontChanged;
  final ValueChanged<double> onLineHeightChanged;
  final ValueChanged<String> onFontFamilyChanged;
  final ValueChanged<ReaderTheme> onThemeChanged;
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
                progress: progress,
                onProgressChanged: onProgressChanged,
                onPageChanged: onPageChanged,
              );
              final tools = _ReaderTools(
                fontSize: fontSize,
                lineHeight: lineHeight,
                fontFamily: fontFamily,
                highlights: highlights,
                highlightController: highlightController,
                onFontChanged: onFontChanged,
                onLineHeightChanged: onLineHeightChanged,
                onFontFamilyChanged: onFontFamilyChanged,
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

class _ReadingPane extends StatelessWidget {
  const _ReadingPane({
    required this.colors,
    required this.book,
    required this.pageIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
                      color: colors.foreground.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.search, size: 20),
                const SizedBox(width: 12),
                const Icon(Icons.tune, size: 20),
              ],
            ),
            const SizedBox(height: 22),
            _FormattedPageView(
              page: currentPage,
              colors: colors,
              baseFontSize: fontSize,
              lineHeight: lineHeight,
              fontFamily: fontFamily,
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
                color: colors.foreground.withValues(alpha: 0.64),
              ),
            ),
          ],
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
  });

  final ImportedBookPage page;
  final _ReaderColors colors;
  final double baseFontSize;
  final double lineHeight;
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    final lines = page.lines.isEmpty
        ? _plainLinesFor(page.text)
        : page.lines.where((line) => line.text.trim().isNotEmpty).toList();
    if (_hasOriginalPageGeometry(lines)) {
      return _PdfPageCanvas(page: page, lines: lines, colors: colors);
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
              style: TextStyle(
                color: colors.foreground,
                fontFamily: _resolvedFontFamily(line.fontName, fontFamily),
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

  String? _resolvedFontFamily(String originalFontName, String selected) {
    if (selected == 'Serif') {
      return 'Georgia';
    }
    if (selected == 'Sans') {
      return 'Arial';
    }
    if (selected == 'Mono') {
      return 'Menlo';
    }
    if (originalFontName.trim().isEmpty || originalFontName == 'Original') {
      return 'Georgia';
    }
    return originalFontName;
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
  });

  final ImportedBookPage page;
  final List<ImportedTextLine> lines;
  final _ReaderColors colors;

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

        return SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: ColoredBox(
            color: colors.background,
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
                      style: TextStyle(
                        color: colors.foreground,
                        fontFamily: _originalPdfFontFamily(entry.line.fontName),
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

    var floor = 0.0;
    return [
      for (final entry in positioned)
        _positionedWithoutCollision(entry, pageWidth, () {
          final adjustedTop = math.max(entry.top, floor);
          floor = adjustedTop + entry.fontSize * 1.18;
          return adjustedTop;
        }),
    ];
  }

  _PositionedPdfLine _positionedWithoutCollision(
    _PositionedPdfLine entry,
    double pageWidth,
    double Function() nextBodyTop,
  ) {
    final text = entry.line.text.trim();
    final isDropCap = _isDropCapLine(text, entry.fontSize);
    if (isDropCap) {
      return entry;
    }

    final isHeading = _isLikelyHeadingLine(entry.line, pageWidth);
    if (isHeading) {
      return entry;
    }

    return _PositionedPdfLine(
      line: entry.line,
      top: nextBodyTop(),
      fontSize: entry.fontSize,
    );
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

    final fontFamily = _originalPdfFontFamily(line.fontName);
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
    final font = originalFontName.trim();
    if (font.isEmpty || font == 'Original') {
      return 'Arial';
    }

    final lower = font.toLowerCase();
    if (lower.contains('times')) {
      return 'Times New Roman';
    }
    if (lower.contains('courier')) {
      return 'Courier New';
    }
    if (lower.contains('helvetica') || lower.contains('arial')) {
      return 'Arial';
    }
    if (lower.contains('georgia')) {
      return 'Georgia';
    }
    if (lower.contains('avenir')) {
      return 'Avenir Next';
    }
    return 'Arial';
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
    required this.highlights,
    required this.highlightController,
    required this.onFontChanged,
    required this.onLineHeightChanged,
    required this.onFontFamilyChanged,
    required this.onAddHighlight,
  });

  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final List<String> highlights;
  final TextEditingController highlightController;
  final ValueChanged<double> onFontChanged;
  final ValueChanged<double> onLineHeightChanged;
  final ValueChanged<String> onFontFamilyChanged;
  final VoidCallback onAddHighlight;

  @override
  Widget build(BuildContext context) {
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
          DropdownButtonFormField<String>(
            initialValue: fontFamily,
            decoration: const InputDecoration(
              labelText: 'Font family',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Original', child: Text('Original')),
              DropdownMenuItem(value: 'Serif', child: Text('Serif')),
              DropdownMenuItem(value: 'Sans', child: Text('Sans')),
              DropdownMenuItem(value: 'Mono', child: Text('Mono')),
            ],
            onChanged: (value) {
              if (value != null) {
                onFontFamilyChanged(value);
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
