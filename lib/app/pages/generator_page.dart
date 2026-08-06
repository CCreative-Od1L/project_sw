import 'package:flutter/material.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';

/// Placeholder route replaced by the complete generator slice in #33.
final class GeneratorPage extends StatelessWidget {
  /// Creates the generator route placeholder.
  const GeneratorPage({super.key});

  @override
  Widget build(BuildContext context) => SessionPageScaffold(
    title: context.l10n.generator,
    child: Center(child: Text(context.l10n.generatorComingSoon)),
  );
}
