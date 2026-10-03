import 'package:flutter/material.dart';

abstract final class StudioColors {
  static const ink = Color(0xff24332e);
  static const muted = Color(0xff69756f);
  static const accent = Color(0xffb85535);
  static const line = Color(0xffe1e5df);
  static const paper = Color(0xfff4f5f0);
}

ThemeData studioTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(
    seedColor: StudioColors.accent,
    primary: StudioColors.accent,
    onPrimary: Colors.white,
    surface: StudioColors.paper,
    onSurface: StudioColors.ink,
  ),
  splashFactory: InkSparkle.splashFactory,
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: StudioColors.ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: StudioColors.accent,
    linearTrackColor: StudioColors.line,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
  scaffoldBackgroundColor: StudioColors.paper,
  textTheme: ThemeData.light().textTheme.apply(
    bodyColor: StudioColors.ink,
    displayColor: StudioColors.ink,
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 400),
  ),
  dividerTheme: const DividerThemeData(color: StudioColors.line, thickness: 1),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: StudioColors.ink,
      minimumSize: const Size(0, 48),
      side: const BorderSide(color: StudioColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: StudioColors.ink),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xfffafbf8),
    labelStyle: const TextStyle(color: StudioColors.muted, fontSize: 13),
    hintStyle: const TextStyle(color: Color(0xffa5a69f), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: StudioColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: StudioColors.accent, width: 1.5),
    ),
  ),
);

/// Shared responsive workspace, inspired by the reference's floating panels.
class StudioShell extends StatelessWidget {
  const StudioShell({
    super.key,
    required this.section,
    required this.child,
    this.footer,
    this.onEditor,
    this.onHistory,
    this.onAuctionVehicles,
    this.onVehiclesLabel,
    this.onNew,
    this.busy = false,
  });

  final String section;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onEditor;
  final VoidCallback? onHistory;
  final VoidCallback? onAuctionVehicles;
  final VoidCallback? onVehiclesLabel;
  final VoidCallback? onNew;
  final bool busy;

  Widget _nav(String label, IconData icon, VoidCallback? action) {
    final selected = section == label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tooltip(
        message: label == 'Create' ? 'Editor' : label,
        child: Material(
          color: selected
              ? Colors.white.withValues(alpha: .13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: ValueKey(
              'studio-tab-${label.toLowerCase().replaceAll(' ', '-')}',
            ),
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : action,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? const Color(0xfff2f0e9)
                          : Colors.white.withValues(alpha: .07),
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: selected ? StudioColors.ink : Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : Colors.white60,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const CircleAvatar(
                      radius: 3,
                      backgroundColor: StudioColors.accent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<(String, IconData, VoidCallback?)> get _destinations => [
    ('Create', Icons.dashboard_outlined, onEditor),
    if (onAuctionVehicles != null || section == 'Auction List')
      ('Auction List', Icons.gavel_outlined, onAuctionVehicles),
    if (onVehiclesLabel != null || section == 'Vehicles Label')
      ('Vehicles Label', Icons.sell_outlined, onVehiclesLabel),
    if (onHistory != null || section == 'History')
      ('History', Icons.history_rounded, onHistory),
  ];

  Widget _mobileNavigation() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: StudioColors.line)),
      ),
      child: Row(
        children: [
          for (final destination in _destinations)
            Expanded(
              child: Semantics(
                selected: section == destination.$1,
                child: Tooltip(
                  message: destination.$1,
                  child: InkWell(
                    key: ValueKey(
                      'studio-tab-${destination.$1.toLowerCase().replaceAll(' ', '-')}',
                    ),
                    onTap: busy ? null : destination.$3,
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        color: section == destination.$1
                            ? const Color(0xfff6e8df)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            destination.$2,
                            size: 21,
                            color: section == destination.$1
                                ? StudioColors.accent
                                : StudioColors.muted,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            switch (destination.$1) {
                              'Auction List' => 'Vehicles',
                              'Vehicles Label' => 'Labels',
                              _ => destination.$1,
                            },
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: section == destination.$1
                                  ? StudioColors.accent
                                  : StudioColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffe9ede5), Color(0xfff4efe7)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop =
                constraints.maxWidth >= 1000 && constraints.maxHeight >= 600;
            return Padding(
              padding: EdgeInsets.all(desktop ? 20 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (desktop) ...[
                    Container(
                      width: 212,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xff2d443a), Color(0xff1e3029)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(10, 16, 0, 38),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_mosaic_rounded,
                                  color: Color(0xffe9bd8d),
                                  size: 28,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'NOJOOM',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'POSTER STUDIO',
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 9,
                                            letterSpacing: 1.6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 0, 0, 14),
                            child: Text(
                              'WORKSPACE',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          for (final destination in _destinations)
                            _nav(
                              destination.$1,
                              destination.$2,
                              destination.$3,
                            ),
                          if (section == 'Preview')
                            _nav('Preview', Icons.image_outlined, null),
                          const Spacer(),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.directions_car_outlined,
                                  color: Color(0xffe9bd8d),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Ready for auction.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Your vehicles, beautifully presented.',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: StudioColors.paper,
                        borderRadius: BorderRadius.circular(desktop ? 24 : 0),
                        border: desktop
                            ? Border.all(color: Colors.white)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: desktop ? 28 : 16,
                              vertical: 10,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                bottom: BorderSide(color: StudioColors.line),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (!desktop) ...[
                                  const Icon(
                                    Icons.auto_awesome_mosaic_rounded,
                                    color: StudioColors.accent,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    desktop
                                        ? 'Workspace  /  $section'
                                        : 'Nojoom Studio',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (onNew != null)
                                  IconButton.filledTonal(
                                    tooltip: 'New poster',
                                    onPressed: busy ? null : onNew,
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 21,
                                    ),
                                  ),
                                if (desktop) ...[
                                  const SizedBox(width: 16),
                                  const StudioBadge(
                                    label: 'VEHICLE STUDIO',
                                    icon: Icons.auto_awesome,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Expanded(child: child),
                          ?footer,
                          if (!desktop) _mobileNavigation(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class StudioBadge extends StatelessWidget {
  const StudioBadge({
    super.key,
    required this.label,
    this.icon = Icons.check_circle_outline,
    this.dark = false,
  });
  final String label;
  final IconData icon;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: .12)
          : const Color(0xfff2e5dc),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: dark ? Colors.white70 : StudioColors.accent,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: .6,
            fontWeight: FontWeight.w600,
            color: dark ? Colors.white70 : const Color(0xffac5639),
          ),
        ),
      ],
    ),
  );
}

class StudioCard extends StatelessWidget {
  const StudioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.dark = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: dark ? const Color(0xff2d443a) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: dark ? const Color(0xff40584b) : StudioColors.line,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .035),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

/// A shared confirmation dialog that matches the studio workspace panels.
class StudioConfirmDialog extends StatelessWidget {
  const StudioConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    this.confirmIcon = Icons.check_rounded,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final IconData confirmIcon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final primaryColor = destructive
        ? const Color(0xffb84b3a)
        : StudioColors.accent;
    final cancel = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(false),
      child: Text(cancelLabel),
    );
    final confirm = FilledButton.icon(
      onPressed: () => Navigator.of(context).pop(true),
      style: FilledButton.styleFrom(backgroundColor: primaryColor),
      icon: Icon(confirmIcon, size: 18),
      label: Text(confirmLabel),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: StudioCard(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stackActions = constraints.maxWidth < 400;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: StudioColors.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: StudioColors.line),
                        ),
                        child: Icon(icon, color: primaryColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: StudioColors.ink,
                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    style: const TextStyle(
                      color: StudioColors.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(height: 1),
                  ),
                  if (stackActions)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [cancel, const SizedBox(height: 10), confirm],
                    )
                  else
                    Row(
                      children: [
                        Expanded(child: cancel),
                        const SizedBox(width: 12),
                        Expanded(child: confirm),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class StudioHeading extends StatelessWidget {
  const StudioHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 32,
                height: 1.12,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: const TextStyle(
                color: StudioColors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 18), trailing!],
    ],
  );
}
