import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_feedback.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_scope.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

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
    final SensitiveClipboardController? clipboard =
        SensitiveClipboardScope.maybeOf(context);
    final Widget scaffold = Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BlocBuilder<AuthCubit, AuthViewState>(
                builder: (BuildContext context, AuthViewState state) {
                  return Text(
                    'Session route: ${state.routeState.name}',
                    style: Theme.of(context).textTheme.labelMedium,
                  );
                },
              ),
              const SizedBox(height: 24),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
    if (clipboard == null) return scaffold;
    return SensitiveClipboardFeedback(controller: clipboard, child: scaffold);
  }
}
