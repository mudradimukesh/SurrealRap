import 'package:flutter/material.dart';

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
        scaffoldBackgroundColor: const Color(0xFF101114),
        useMaterial3: true,
      ),
      home: const SurrealRapHome(),
    );
  }
}

class SurrealRapHome extends StatefulWidget {
  const SurrealRapHome({super.key});

  @override
  State<SurrealRapHome> createState() => _SurrealRapHomeState();
}

class _SurrealRapHomeState extends State<SurrealRapHome> {
  final List<String> _ideas = [
    'Moonlit bassline over glass-city drums',
    'Hook: I woke up fluent in thunder',
    'Verse image: neon rain writing my name',
  ];

  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addIdea() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _ideas.insert(0, text);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(child: _HeaderPanel()),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _IdeaPanel(
                                ideas: _ideas,
                                controller: _controller,
                                onAdd: _addIdea,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _HeaderPanel(),
                            const SizedBox(height: 24),
                            _IdeaPanel(
                              ideas: _ideas,
                              controller: _controller,
                              onAdd: _addIdea,
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF18A999),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.graphic_eq,
            color: Color(0xFF101114),
            size: 40,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'SurrealRap',
          style: textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 0.98,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Catch strange bars, visual hooks, and performance moods before they evaporate.',
          style: textTheme.titleLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _MoodChip(label: 'Lucid'),
            _MoodChip(label: 'Raw'),
            _MoodChip(label: 'After-hours'),
          ],
        ),
      ],
    );
  }
}

class _IdeaPanel extends StatelessWidget {
  const _IdeaPanel({
    required this.ideas,
    required this.controller,
    required this.onAdd,
  });

  final List<String> ideas;
  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF191B20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Idea Deck',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd(),
              decoration: InputDecoration(
                hintText: 'Drop a bar, image, hook, or rhythm...',
                filled: true,
                fillColor: const Color(0xFF101114),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Idea'),
            ),
            const SizedBox(height: 20),
            for (final idea in ideas) _IdeaTile(text: idea),
          ],
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: const Color(0xFF252832),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    );
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF22252C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
