// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class OriginalPdfPageView extends StatelessWidget {
  OriginalPdfPageView({
    super.key,
    required this.sourceUrl,
    required this.pageIndex,
  }) : _viewType = 'surreal-rap-pdf-${DateTime.now().microsecondsSinceEpoch}';

  final String sourceUrl;
  final int pageIndex;
  final String _viewType;

  @override
  Widget build(BuildContext context) {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final page = pageIndex + 1;
      return html.IFrameElement()
        ..src = '$sourceUrl#page=$page&toolbar=0&navpanes=0&scrollbar=0'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#ffffff'
        ..allow = 'fullscreen';
    });

    return AspectRatio(
      aspectRatio: 612 / 792,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
