import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/route_paths.dart';

/// Unlocked/locked-generator shell with the v0.5 bottom navigation.
final class AppShell extends StatelessWidget {
  /// Creates the shell around the active feature route.
  const AppShell({
    super.key,
    required this.currentLocation,
    required this.child,
  });

  /// Current route path used to select the navigation destination.
  final String currentLocation;

  /// Active feature page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final int selectedIndex = switch (currentLocation) {
      generatorRoutePath => 1,
      settingsRoutePath => 2,
      _ => 0,
    };
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (int index) {
          context.go(switch (index) {
            1 => generatorRoutePath,
            2 => settingsRoutePath,
            _ => vaultRoutePath,
          });
        },
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.lock_outline),
            selectedIcon: const Icon(Icons.lock),
            label: context.l10n.vault,
          ),
          NavigationDestination(
            icon: const Icon(Icons.password_outlined),
            selectedIcon: const Icon(Icons.password),
            label: context.l10n.generator,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: context.l10n.settings,
          ),
        ],
      ),
    );
  }
}
