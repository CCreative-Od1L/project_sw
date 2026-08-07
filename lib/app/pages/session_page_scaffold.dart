import 'package:flutter/material.dart';

/// Shared compact page layout for the route skeleton.
final class SessionPageScaffold extends StatelessWidget {
  /// Creates a page with [title] and [child] content.
  const SessionPageScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  /// The page title.
  final String title;

  /// The page's primary content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    );
  }
}
