import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'auction_vehicles_screen.dart';
import 'poster_history.dart';
import 'studio_ui.dart';
import 'vehicle_number_sort.dart';

enum _HistorySort { numberAscending, numberDescending, newest, oldest }

class HistoryScreen extends StatefulWidget {
  final PosterHistory history;
  final bool embedded;
  final VoidCallback? onSelectEditor;
  final Future<void> Function(PosterDraft draft)? onDraftSelected;
  final Listenable? refreshSignal;

  const HistoryScreen({
    super.key,
    required this.history,
    this.embedded = false,
    this.onSelectEditor,
    this.onDraftSelected,
    this.refreshSignal,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<PosterHistoryEntry>> _entries;
  bool _busy = false;
  String _query = '';
  bool _recentOnly = false;
  bool _grid = true;
  _HistorySort _sort = _HistorySort.numberAscending;
  final _search = TextEditingController();
  final Map<int, Future<Uint8List?>> _thumbnails = {};
  final Set<String> _openedDateFolders = {};

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_reloadEntries);
    _search.dispose();
    super.dispose();
  }

  Future<Uint8List?> _thumbnail(int id) =>
      _thumbnails.putIfAbsent(id, () async {
        final draft = await widget.history.load(id);
        return draft.photos.whereType<Uint8List>().firstOrNull;
      });

  @override
  void initState() {
    super.initState();
    _entries = widget.history.list();
    widget.refreshSignal?.addListener(_reloadEntries);
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal == widget.refreshSignal) return;
    oldWidget.refreshSignal?.removeListener(_reloadEntries);
    widget.refreshSignal?.addListener(_reloadEntries);
  }

  void _reloadEntries() {
    if (!mounted) return;
    setState(() {
      _thumbnails.clear();
      _entries = widget.history.list();
    });
  }

  Future<void> _open(PosterHistoryEntry entry) async {
    setState(() => _busy = true);
    try {
      final draft = await widget.history.load(entry.id);
      if (!mounted) return;
      final onDraftSelected = widget.onDraftSelected;
      if (onDraftSelected != null) {
        await onDraftSelected(draft);
      } else {
        Navigator.pop(context, draft);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _delete(PosterHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StudioConfirmDialog(
        title: 'Delete saved poster?',
        message:
            'Remove ${entry.title} from history? Images already exported to your device will remain.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Delete',
        icon: Icons.delete_outline_rounded,
        confirmIcon: Icons.delete_outline_rounded,
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.history.delete(entry.id);
      if (mounted) {
        setState(() {
          _entries = widget.history.list();
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stat(
    String value,
    String label,
    IconData icon, {
    bool dark = false,
  }) => StudioCard(
    dark: dark,
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: dark ? Colors.white60 : StudioColors.muted,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontSize: 27,
                  letterSpacing: -1,
                  fontWeight: FontWeight.w500,
                  color: dark ? Colors.white : StudioColors.ink,
                ),
              ),
            ],
          ),
        ),
        Icon(
          icon,
          size: 27,
          color: dark ? const Color(0xffe4a086) : StudioColors.accent,
        ),
      ],
    ),
  );

  Widget _empty({bool filtered = false, bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: const Color(0xffe9eae4),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(
              error
                  ? Icons.cloud_off_outlined
                  : filtered
                  ? Icons.search_off_rounded
                  : Icons.collections_bookmark_outlined,
              size: 32,
              color: StudioColors.muted,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            error
                ? 'Could not load poster history.'
                : filtered
                ? 'No matching posters'
                : 'Your next great poster starts here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            error
                ? 'Try again to reconnect to your saved workspace.'
                : filtered
                ? 'Try another search or show all your posters.'
                : 'No saved posters yet. Create a poster or save a draft,\nand it will be waiting here whenever you need it.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: StudioColors.muted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: error
                ? () => setState(() {
                    _entries = widget.history.list();
                  })
                : filtered
                ? () => setState(() {
                    _query = '';
                    _search.clear();
                    _recentOnly = false;
                  })
                : () {
                    final onSelectEditor = widget.onSelectEditor;
                    if (onSelectEditor != null) {
                      onSelectEditor();
                    } else {
                      Navigator.pop(context);
                    }
                  },
            icon: Icon(
              error
                  ? Icons.refresh
                  : filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.add,
              size: 18,
            ),
            label: Text(
              error
                  ? 'Retry'
                  : filtered
                  ? 'Clear filters'
                  : 'Go to editor',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _cover(PosterHistoryEntry entry, {bool compact = false}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xffe9eae4),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Uint8List?>(
          future: _thumbnail(entry.id),
          builder: (context, snapshot) => snapshot.data != null
              ? Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  cacheWidth: 650,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.directions_car_outlined,
                      size: 40,
                      color: StudioColors.muted,
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    Icons.directions_car_outlined,
                    size: compact ? 28 : 54,
                    color: const Color(0xffb0b3a7),
                  ),
                ),
        ),
        if (!compact)
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                entry.vehicle.number.isEmpty
                    ? 'SAVED POSTER'
                    : 'NO. ${entry.vehicle.number}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .8,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _posterCard(PosterHistoryEntry entry) {
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(entry.updatedAt.toLocal());
    final price = entry.vehicle.price.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : () => _open(entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _grid
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _cover(entry)),
                    const SizedBox(height: 14),
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      price.isEmpty ? 'Vehicle poster' : '\$ $price',
                      style: const TextStyle(
                        fontSize: 12,
                        color: StudioColors.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Edited $date',
                            style: const TextStyle(
                              fontSize: 10,
                              color: StudioColors.muted,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete ${entry.title}',
                          onPressed: _busy ? null : () => _delete(entry),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 17,
                            color: StudioColors.muted,
                          ),
                        ),
                        const Icon(
                          Icons.arrow_outward_rounded,
                          size: 16,
                          color: StudioColors.accent,
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: _cover(entry, compact: true),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Edited $date',
                            style: const TextStyle(
                              fontSize: 10,
                              color: StudioColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete ${entry.title}',
                      onPressed: _busy ? null : () => _delete(entry),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    ),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: StudioColors.accent,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _toolbar(bool wide) {
    final search = TextField(
      controller: _search,
      onChanged: (value) => setState(() => _query = value.toLowerCase().trim()),
      decoration: InputDecoration(
        hintText: 'Search vehicles, VIN or number…',
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
                icon: const Icon(Icons.close, size: 17),
              ),
        fillColor: Colors.white,
      ),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<_HistorySort>(
            value: _sort,
            borderRadius: BorderRadius.circular(16),
            style: const TextStyle(
              fontFamily: 'Roboto',
              color: StudioColors.ink,
              fontSize: 12,
            ),
            items: const [
              DropdownMenuItem(
                value: _HistorySort.numberAscending,
                child: Text('Number: low to high'),
              ),
              DropdownMenuItem(
                value: _HistorySort.numberDescending,
                child: Text('Number: high to low'),
              ),
              DropdownMenuItem(
                value: _HistorySort.newest,
                child: Text('Newest first'),
              ),
              DropdownMenuItem(
                value: _HistorySort.oldest,
                child: Text('Oldest first'),
              ),
            ],
            onChanged: (value) => setState(() => _sort = value!),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Grid view',
          isSelected: _grid,
          onPressed: () => setState(() => _grid = true),
          style: IconButton.styleFrom(
            backgroundColor: _grid ? Colors.white : Colors.transparent,
            foregroundColor: StudioColors.muted,
          ),
          icon: const Icon(Icons.grid_view_rounded, size: 19),
        ),
        IconButton(
          tooltip: 'List view',
          isSelected: !_grid,
          onPressed: () => setState(() => _grid = false),
          style: IconButton.styleFrom(
            backgroundColor: !_grid ? Colors.white : Colors.transparent,
            foregroundColor: StudioColors.muted,
          ),
          icon: const Icon(Icons.view_list_outlined, size: 21),
        ),
      ],
    );
    return wide
        ? Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 24),
              controls,
            ],
          )
        : Column(
            children: [
              search,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: controls),
            ],
          );
  }

  String _dateFolderKey(DateTime value) {
    final date = value.toLocal();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, List<PosterHistoryEntry>> _dateFolders(
    List<PosterHistoryEntry> entries,
  ) {
    final folders = <String, List<PosterHistoryEntry>>{};
    for (final entry in entries) {
      folders.putIfAbsent(_dateFolderKey(entry.updatedAt), () => []).add(entry);
    }
    return folders;
  }

  Widget _dateFolderHeading(
    String key,
    List<PosterHistoryEntry> entries, {
    required bool wide,
  }) {
    final opened = _openedDateFolders.contains(key);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(entries.first.updatedAt.toLocal());
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 18, wide ? 28 : 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('date-folder-$key'),
          onTap: () => setState(() {
            if (opened) {
              _openedDateFolders.remove(key);
            } else {
              _openedDateFolders.add(key);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  opened ? Icons.folder_open_rounded : Icons.folder_rounded,
                  color: StudioColors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    date,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.3,
                    ),
                  ),
                ),
                Text(
                  '${entries.length} file${entries.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: StudioColors.muted,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  opened
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: StudioColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String label, int count, {required bool fresh}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
        child: Row(
          children: [
            Icon(
              fresh ? Icons.fiber_new_rounded : Icons.history_rounded,
              size: 18,
              color: fresh ? StudioColors.accent : StudioColors.muted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(fontSize: 11, color: StudioColors.muted),
            ),
          ],
        ),
      );

  List<Widget> _dateFolderContents(
    List<PosterHistoryEntry> entries,
    BoxConstraints constraints,
    bool wide,
  ) {
    final newEntries = entries
        .where((entry) => entry.section == PosterSections.newVehicles)
        .toList();
    final oldEntries = entries
        .where((entry) => entry.section == PosterSections.oldVehicles)
        .toList();
    return [
      if (newEntries.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _sectionHeading(
            'New vehicles',
            newEntries.length,
            fresh: true,
          ),
        ),
        _sectionEntries(newEntries, constraints, wide),
      ],
      if (oldEntries.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _sectionHeading(
            'Old vehicles',
            oldEntries.length,
            fresh: false,
          ),
        ),
        _sectionEntries(oldEntries, constraints, wide),
      ],
    ];
  }

  Widget _sectionEntries(
    List<PosterHistoryEntry> entries,
    BoxConstraints constraints,
    bool wide,
  ) {
    final collection = _grid
        ? SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _posterCard(entries[index]),
              childCount: entries.length,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 600
                  ? 2
                  : 1,
              mainAxisExtent: 290,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
          )
        : SliverList.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _posterCard(entries[index]),
          );
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16),
      sliver: collection,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<PosterHistoryEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _empty(error: true);
        final entries = snapshot.data!;
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        final recent = entries
            .where((entry) => entry.updatedAt.isAfter(cutoff))
            .length;
        final filtered = entries.where((entry) {
          final text =
              '${entry.title} ${entry.vehicle.vin} ${entry.vehicle.number} ${entry.vehicle.color}'
                  .toLowerCase();
          return text.contains(_query) &&
              (!_recentOnly || entry.updatedAt.isAfter(cutoff));
        }).toList();
        filtered.sort((a, b) {
          final comparison = switch (_sort) {
            _HistorySort.numberAscending ||
            _HistorySort.numberDescending => compareVehicleNumbers(
              a.vehicle.number,
              b.vehicle.number,
              ascending: _sort == _HistorySort.numberAscending,
            ),
            _HistorySort.newest => b.updatedAt.compareTo(a.updatedAt),
            _HistorySort.oldest => a.updatedAt.compareTo(b.updatedAt),
          };
          return comparison == 0 ? a.id.compareTo(b.id) : comparison;
        });
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final folders = _dateFolders(filtered);
            final folderKeys = folders.keys.toList()
              ..sort((a, b) => b.compareTo(a));
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 28 : 16,
                    16,
                    wide ? 28 : 16,
                    20,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const StudioHeading(
                          title: 'Good work.\nAll in one place.',
                          subtitle:
                              'Revisit, refine, and make your next impression.',
                        ),
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Expanded(
                              child: _stat(
                                '${entries.length}'.padLeft(2, '0'),
                                'Saved posters',
                                Icons.collections_bookmark_outlined,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _stat(
                                '$recent'.padLeft(2, '0'),
                                'Edited this week',
                                Icons.history_rounded,
                                dark: true,
                              ),
                            ),
                            if (wide) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: _stat(
                                  'On device',
                                  'Your private collection',
                                  Icons.lock_outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            const Text(
                              'Your collection',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.5,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${filtered.length} posters',
                              style: const TextStyle(
                                fontSize: 11,
                                color: StudioColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All posters'),
                              selected: !_recentOnly,
                              onSelected: (_) =>
                                  setState(() => _recentOnly = false),
                              showCheckmark: false,
                              side: BorderSide.none,
                              selectedColor: Colors.white,
                              backgroundColor: Colors.transparent,
                              labelStyle: const TextStyle(fontSize: 11),
                            ),
                            ChoiceChip(
                              label: const Text('This week'),
                              selected: _recentOnly,
                              onSelected: (_) =>
                                  setState(() => _recentOnly = true),
                              showCheckmark: false,
                              side: BorderSide.none,
                              selectedColor: Colors.white,
                              backgroundColor: Colors.transparent,
                              labelStyle: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _toolbar(wide),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverToBoxAdapter(
                    child: _empty(filtered: entries.isNotEmpty),
                  )
                else
                  for (final key in folderKeys) ...[
                    SliverToBoxAdapter(
                      child: _dateFolderHeading(key, folders[key]!, wide: wide),
                    ),
                    if (_openedDateFolders.contains(key)) ...[
                      ..._dateFolderContents(folders[key]!, constraints, wide),
                    ],
                  ],
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Saved on this device. Open a date folder, then select a poster to continue editing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: StudioColors.muted, fontSize: 11),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (widget.embedded) return body;
    return StudioShell(
      section: 'History',
      busy: _busy,
      onEditor: widget.onSelectEditor ?? () => Navigator.pop(context),
      onAuctionVehicles: () => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => AuctionVehiclesScreen(history: widget.history),
        ),
      ),
      child: body,
    );
  }
}
