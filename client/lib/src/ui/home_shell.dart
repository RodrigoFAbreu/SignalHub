import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/users.dart';
import 'inbox_screen.dart';
import 'link_opener.dart';
import 'pairing_scanner_screen.dart';
import 'people_tab.dart';
import 'producers_tab.dart';
import 'role_lacks_screen.dart';
import 'settings_screen.dart';
import 'widgets/snack.dart';

/// The connected app: a bottom bar with Inbox, Producers and Settings (People
/// too for an admin), the unread count as a badge on Inbox. Pushed screens
/// are drawn over it and hide it. Tabs are built when first shown and keep
/// their state; switching is not animated.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    required this.openLink,
    this.signInScanner = scanWebSignInCode,
  });

  final AppController controller;
  final LinkOpener openLink;

  /// The camera of _Sign in a browser_; tests replace the camera.
  final PairingScannerBuilder signInScanner;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _visited = <HomeTab>{};

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sayRoleChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sayRoleChange());
  }

  @override
  void dispose() {
    _controller.removeListener(_sayRoleChange);
    super.dispose();
  }

  /// A role changed under the person: said once, as a message. The screens
  /// already follow the new role.
  void _sayRoleChange() {
    if (!mounted || !_controller.hasRoleChange) return;
    final change = _controller.takeRoleChange()!;
    showAppSnackBar(context, roleChangeMessage(change.to));
  }

  /// "Your role changed. You're now a Mod."
  static String roleChangeMessage(UserRole to) => switch (to) {
    UserRole.mod => "Your role changed. You're now a Mod.",
    UserRole.admin => "Your role changed. You're now an admin.",
    UserRole.basic => "Your role changed. You're now Basic.",
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final tabs = _controller.tabs;
      final current = _controller.tab;
      _visited.add(current);
      final index = tabs.indexOf(current);
      return Scaffold(
        // Not an IndexedStack, which finds a child by its position: a tab
        // must keep its state when the bar gains or loses People.
        body: Stack(
          fit: StackFit.expand,
          children: [
            for (final tab in tabs)
              Visibility(
                key: ValueKey(tab),
                visible: tab == current,
                maintainState: true,
                child: _visited.contains(tab)
                    ? _body(tab)
                    : const SizedBox.shrink(),
              ),
            // A tab this role no longer has (People, after a demotion) shows
            // what a missing screen shows, under a bar that already has the
            // new role's tabs.
            if (index < 0)
              RoleLacksScreen(
                onBack: () => _controller.selectTab(HomeTab.inbox),
              ),
          ],
        ),
        bottomNavigationBar: _NavigationBar(
          controller: _controller,
          tabs: tabs,
          selected: index,
        ),
      );
    },
  );

  Widget _body(HomeTab tab) => switch (tab) {
    HomeTab.inbox => InboxScreen(
      controller: _controller,
      openLink: widget.openLink,
    ),
    HomeTab.producers => ProducersTab(controller: _controller),
    HomeTab.people => PeopleTab(controller: _controller),
    HomeTab.settings => SettingsScreen(
      controller: _controller,
      signInScanner: widget.signInScanner,
    ),
  };
}

class _NavigationBar extends StatelessWidget {
  const _NavigationBar({
    required this.controller,
    required this.tabs,
    required this.selected,
  });

  final AppController controller;
  final List<HomeTab> tabs;
  final int selected;

  static const _icons = {
    HomeTab.inbox: (Icons.inbox_outlined, Icons.inbox),
    HomeTab.producers: (Icons.sensors_outlined, Icons.sensors),
    HomeTab.people: (Icons.group_outlined, Icons.group),
    HomeTab.settings: (Icons.settings_outlined, Icons.settings),
  };

  static const _labels = {
    HomeTab.inbox: 'Inbox',
    HomeTab.producers: 'Producers',
    HomeTab.people: 'People',
    HomeTab.settings: 'Settings',
  };

  @override
  Widget build(BuildContext context) {
    final unread = controller.unreadCount ?? 0;
    final toAnswer = controller.toAnswerCount;
    // The labels never wrap: their text scale stops at about 1.3x, and the
    // bar grows only by the extra line height. Icons keep their size.
    final media = MediaQuery.of(context);
    final scaler = media.textScaler.clamp(maxScaleFactor: 1.3);
    return MediaQuery(
      data: media.copyWith(textScaler: scaler),
      child: NavigationBar(
        // Tab switches are used constantly: no animation, not even the
        // indicator's.
        animationDuration: Duration.zero,
        selectedIndex: selected < 0 ? 0 : selected,
        // Nothing is selected while a missing screen shows.
        indicatorColor: selected < 0 ? Colors.transparent : null,
        onDestinationSelected: (i) => controller.selectTab(tabs[i]),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              key: Key('tab-${tab.name}'),
              icon: _icon(
                tab,
                selected: false,
                unread: unread,
                toAnswer: toAnswer,
              ),
              selectedIcon: _icon(
                tab,
                selected: true,
                unread: unread,
                toAnswer: toAnswer,
              ),
              label: _labels[tab]!,
              tooltip: tab == HomeTab.inbox
                  ? (inboxName(unread, toAnswer) ?? 'Inbox')
                  : _labels[tab],
            ),
        ],
      ),
    );
  }

  /// What the Inbox tab is named while something waits on it: `Inbox, 3
  /// unread`, `Inbox, 2 to answer`, or both; `null` with neither.
  @visibleForTesting
  static String? inboxName(int unread, int toAnswer) {
    final parts = [
      if (unread > 0) '$unread unread',
      if (toAnswer > 0) '$toAnswer to answer',
    ];
    return parts.isEmpty ? null : 'Inbox, ${parts.join(', ')}';
  }

  /// The number of unread events as a badge; with nothing unread and
  /// questions waiting, a dot without a number, so the number stays read
  /// state only.
  Widget _icon(
    HomeTab tab, {
    required bool selected,
    required int unread,
    required int toAnswer,
  }) {
    final (outlined, filled) = _icons[tab]!;
    final icon = Icon(selected ? filled : outlined);
    final name = inboxName(unread, toAnswer);
    if (tab != HomeTab.inbox || name == null) return icon;
    return Semantics(
      label: name,
      child: unread > 0
          ? Badge(
              key: const Key('unreadCount'),
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: icon,
            )
          : Badge(key: const Key('toAnswerDot'), child: icon),
    );
  }
}
