import 'package:flutter/widgets.dart';

class OriginalPdfPageView extends StatelessWidget {
  const OriginalPdfPageView({
    super.key,
    required this.sourceUrl,
    required this.pageIndex,
  });

  final String sourceUrl;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
