import 'package:flutter/material.dart';

abstract final class StudioColors {
  static const ink = Color(0xff262724);
  static const muted = Color(0xff777973);
  static const accent = Color(0xffd96b49);
  static const line = Color(0xffe4e5e0);
  static const paper = Color(0xfff5f5f2);
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
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
    fillColor: const Color(0xfff6f6f3),
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
    this.onNew,
    this.busy = false,
  });

  final String section;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onEditor;
  final VoidCallback? onHistory;
  final VoidCallback? onAuctionVehicles;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffd8d9d5), Color(0xffaeb0ab), Color(0xff797c77)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop =
                constraints.maxWidth >= 1000 && constraints.maxHeight >= 600;
            final padding = desktop ? 28.0 : 10.0;
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (desktop) ...[
                    Container(
                      width: 180,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .24),
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xff62655f), Color(0xff353832)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 14, 0, 32),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_mosaic_rounded,
                                  color: Color(0xffefebe0),
                                  size: 25,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'poster\nstudio.',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      height: .98,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _nav('Create', Icons.dashboard_outlined, onEditor),
                          if (onAuctionVehicles != null ||
                              section == 'Auction List')
                            _nav(
                              'Auction List',
                              Icons.gavel_outlined,
                              onAuctionVehicles,
                            ),
                          if (onHistory != null || section == 'History')
                            _nav('History', Icons.history_rounded, onHistory),
                          if (section == 'Preview')
                            _nav('Preview', Icons.image_outlined, null),
                          const Spacer(),

                          // Container(
                          //   padding: const EdgeInsets.all(14),
                          //   decoration: BoxDecoration(
                          //     borderRadius: BorderRadius.circular(18),
                          //     gradient: const LinearGradient(
                          //       begin: Alignment.topLeft,
                          //       end: Alignment.bottomRight,
                          //       colors: [Color(0xff53564f), Color(0xff746054)],
                          //     ),
                          //     border: Border.all(color: Colors.white12),
                          //   ),
                          //   child: Column(
                          //     crossAxisAlignment: CrossAxisAlignment.start,
                          //     children: [
                          //       const Icon(
                          //         Icons.auto_awesome,
                          //         size: 20,
                          //         color: Color(0xffeaa184),
                          //       ),
                          //       const SizedBox(height: 12),
                          //       const Text(
                          //         'A better first\nimpression.',
                          //         style: TextStyle(
                          //           color: Colors.white,
                          //           fontSize: 15,
                          //           height: 1.2,
                          //           fontWeight: FontWeight.w500,
                          //         ),
                          //       ),
                          //       const SizedBox(height: 8),
                          //       const Text(
                          //         'Your vehicles.\nBeautifully presented.',
                          //         style: TextStyle(
                          //           color: Colors.white60,
                          //           fontSize: 11,
                          //           height: 1.5,
                          //         ),
                          //       ),
                          //       if (onNew != null) ...[
                          //         const SizedBox(height: 12),
                          //         FilledButton(
                          //           onPressed: busy ? null : onNew,
                          //           style: FilledButton.styleFrom(
                          //             backgroundColor: const Color(0xffeeeae0),
                          //             foregroundColor: StudioColors.ink,
                          //             minimumSize: const Size(0, 34),
                          //             padding: const EdgeInsets.symmetric(
                          //               horizontal: 12,
                          //             ),
                          //           ),
                          //           child: const Text(
                          //             'Create poster',
                          //             style: TextStyle(fontSize: 10),
                          //           ),
                          //         ),
                          //       ],
                          //     ],
                          //   ),
                          // ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(10, 18, 0, 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 12,
                                  color: Colors.white54,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Your personal workspace',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(desktop ? 28 : 24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .85),
                          width: 1.5,
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xfff7f7f4), Color(0xffedeeea)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .07),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              desktop ? 28 : 14,
                              12,
                              desktop ? 24 : 10,
                              10,
                            ),
                            child: Row(
                              children: [
                                if (!desktop && section != 'Create')
                                  IconButton(
                                    tooltip: 'Back to editor',
                                    onPressed: busy ? null : onEditor,
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 20,
                                    ),
                                  ),
                                if (!desktop && section == 'Create') ...[
                                  const Icon(
                                    Icons.auto_awesome_mosaic_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 9),
                                ],
                                Text(
                                  desktop
                                      ? 'WORKSPACE  /  ${section.toUpperCase()}'
                                      : 'Poster Studio',
                                  style: TextStyle(
                                    fontSize: desktop ? 10 : 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: desktop ? 1.5 : -.3,
                                    color: StudioColors.muted,
                                  ),
                                ),
                                const Spacer(),
                                if (onNew != null)
                                  IconButton(
                                    tooltip: 'New poster',
                                    onPressed: busy ? null : onNew,
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 21,
                                    ),
                                  ),
                                if (!desktop && onHistory != null)
                                  IconButton(
                                    tooltip: 'History',
                                    onPressed: busy ? null : onHistory,
                                    icon: const Icon(
                                      Icons.history_rounded,
                                      size: 21,
                                    ),
                                  ),
                                if (!desktop && onAuctionVehicles != null)
                                  IconButton(
                                    tooltip: 'Auction list',
                                    onPressed: busy ? null : onAuctionVehicles,
                                    icon: const Icon(
                                      Icons.gavel_outlined,
                                      size: 21,
                                    ),
                                  ),
                                if (desktop)
                                  const StudioBadge(
                                    label: 'VEHICLE STUDIO',
                                    icon: Icons.auto_awesome,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(child: child),
                          ?footer,
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
      color: dark
          ? const Color(0xff434740)
          : Colors.white.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: dark ? const Color(0xff55594f) : Colors.white),
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
                fontSize: 36,
                height: 1.05,
                fontWeight: FontWeight.w500,
                letterSpacing: -1.8,
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
