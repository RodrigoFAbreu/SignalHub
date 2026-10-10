import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/people_controller.dart';
import '../models/users.dart';
import 'invite_screen.dart';
import 'person_screen.dart';
import 'widgets/app_row.dart';
import 'widgets/empty_state.dart';
import 'widgets/person_avatar.dart';
import 'widgets/resource_status.dart';
import 'widgets/search_field.dart';
import 'widgets/skeleton.dart';
import 'widgets/tags.dart';

/// The People tab, an admin's: everyone on the server in sections by role,
/// each saying in a sentence what the role can do, with search, pull to
/// refresh and Invite. The list is read when the tab opens and when the app
/// returns to the foreground.
class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key, required this.controller});

  final AppController controller;

  /// The one sentence under a role's label.
  static String explanation(UserRole role) => switch (role) {
    UserRole.admin =>
      'Manage people and their devices, except other admins. Set on the '
          'admin page.',
    UserRole.mod => 'Manage their own devices, producers and subscriptions.',
    UserRole.basic =>
      'Create producers and subscribe. Their devices are read only.',
  };

  /// The section label of a role.
  static String sectionLabel(UserRole role) => switch (role) {
    UserRole.admin => 'Admins',
    UserRole.mod => 'Mods',
    UserRole.basic => 'Basic',
  };

  /// A row's second line: only what the list gives, their active devices.
  static String? summary(Person person) {
    if (person.hasPaired == false) return 'Invited · not paired yet';
    final devices = person.activeDevices;
    if (devices == null) return null;
    return switch (devices) {
      0 => 'No devices',
      1 => '1 device',
      _ => '$devices devices',
    };
  }

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> with WidgetsBindingObserver {
  final _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  AppController get _app => widget.controller;
  PeopleController get _people => _app.people;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Not while building: reading notifies the controller's listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) => _people.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_people.load());
  }

  void _setSearching(bool searching) => setState(() {
    _searching = searching;
    if (!searching) {
      _search.clear();
      _query = '';
    }
  });

  Future<void> _invite() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => InviteScreen(controller: _app)),
    );
    // Whoever was invited is listed, and has joined if the code was used.
    if (mounted) unawaited(_people.load());
  }

  Future<void> _open(Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonScreen(controller: _app, personId: person.id),
      ),
    );
    if (mounted) unawaited(_people.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _people,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: _searching
            ? BackButton(onPressed: () => _setSearching(false))
            : null,
        title: const Text('People'),
        automaticallyImplyLeading: false,
        actions: [
          if (!_searching)
            IconButton(
              tooltip: 'Search people',
              icon: const Icon(Icons.search),
              onPressed: () => _setSearching(true),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            AppSearchField(
              controller: _search,
              hint: 'Search people',
              onChanged: (text) => setState(() => _query = text.trim()),
            ),
          Expanded(child: _content(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Another tab has a floating button too; the tabs share a navigator.
        heroTag: 'people-invite',
        // Tonal and flat, as drawn: nothing but menus is lifted.
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        onPressed: _invite,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Invite'),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    final list = _people.list;
    if (list.showSkeleton) return const SkeletonRows(count: 6);
    if (list.failedWithoutList) {
      return LoadFailed(resource: list, what: 'people', onRetry: _people.load);
    }
    final matches = _query.isEmpty
        ? null
        : _people.people
              .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
    return RefreshIndicator(
      onRefresh: _people.load,
      child: matches != null && matches.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (list.stale)
                  StaleBanner(resource: list, onRetry: _people.load),
                SizedBox(
                  height: 320,
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'No one matches "$_query".',
                  ),
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // The floating button sits 16 dp above the bar; a list under
              // it has 88 dp of bottom padding.
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                if (list.stale)
                  StaleBanner(resource: list, onRetry: _people.load),
                for (final role in [
                  UserRole.admin,
                  UserRole.mod,
                  UserRole.basic,
                ])
                  ..._section(role),
              ],
            ),
    );
  }

  List<Widget> _section(UserRole role) {
    final all = _people.withRole(role);
    if (all.isEmpty) return const [];
    final searching = _query.isNotEmpty;
    final shown = searching
        ? [
            for (final p in all)
              if (p.name.toLowerCase().contains(_query.toLowerCase())) p,
          ]
        : all;
    final count = searching
        ? '${shown.length} of ${all.length}'
        : '${all.length}';
    return [
      _SectionHeader(PeopleTab.sectionLabel(role), count),
      if (!searching)
        _Explanation(PeopleTab.explanation(role))
      else if (shown.isEmpty)
        const _Explanation('No one matches.'),
      for (final person in shown)
        _PersonRow(
          person: person,
          you: person.id == _app.userId,
          onTap: () => _open(person),
        ),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.count);

  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: '$label, $count',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              count,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          height: 18 / 13,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.you,
    required this.onTap,
  });

  final Person person;
  final bool you;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppRow(
    key: Key('person-${person.id}'),
    leading: PersonAvatar(person.name, you: you),
    title: person.name,
    tags: [if (you) const LabelTag('You', style: LabelTagStyle.primary)],
    subtitle: PeopleTab.summary(person),
    trailing: Icon(
      Icons.chevron_right,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onTap: onTap,
  );
}
