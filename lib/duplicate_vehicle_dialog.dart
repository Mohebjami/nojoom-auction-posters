import 'package:flutter/material.dart';

import 'poster.dart';
import 'vehicle_draft_import.dart';

class DuplicateVehicleDialog extends StatefulWidget {
  final VehicleImportConflict conflict;

  const DuplicateVehicleDialog({super.key, required this.conflict});

  @override
  State<DuplicateVehicleDialog> createState() => _DuplicateVehicleDialogState();
}

class _DuplicateVehicleDialogState extends State<DuplicateVehicleDialog> {
  bool _applyToRemaining = false;
  int _matchIndex = 0;

  String _describe(VehicleDetails vehicle) => [
    if (vehicle.number.trim().isNotEmpty) 'No. ${vehicle.number}',
    [vehicle.title, vehicle.model].where((part) => part.isNotEmpty).join(' '),
    if (vehicle.vin.trim().isNotEmpty) 'VIN: ${vehicle.vin}',
    if (vehicle.color.isNotEmpty) 'Color: ${vehicle.color}',
    if (vehicle.price.isNotEmpty) 'Price: ${vehicle.price}',
  ].where((part) => part.isNotEmpty).join('\n');

  void _choose(DuplicateImportAction action) => Navigator.pop(
    context,
    DuplicateImportDecision(
      action,
      matchIndex: _matchIndex,
      applyToRemaining: _applyToRemaining,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final conflict = widget.conflict;
    final match = conflict.matches[_matchIndex];
    return AlertDialog(
      title: const Text('Duplicate vehicle found'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This VIN or vehicle number is already in the list.'),
              const SizedBox(height: 16),
              Text(
                'Incoming data row ${conflict.importRow}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(_describe(conflict.incoming)),
              const SizedBox(height: 16),
              if (conflict.matches.length > 1) ...[
                const Text('Multiple entries match. Choose which to replace:'),
                DropdownButton<int>(
                  value: _matchIndex,
                  isExpanded: true,
                  items: [
                    for (var i = 0; i < conflict.matches.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          'Match ${i + 1}: No. ${conflict.matches[i].vehicle.number}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _matchIndex = value!),
                ),
              ],
              Text(
                match.id == null
                    ? 'Earlier imported data row ${match.importRow}'
                    : 'Existing saved draft',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(_describe(match.vehicle)),
              const SizedBox(height: 16),
              const Text(
                'Replace updates the details and keeps saved photos and the '
                'template. Skip keeps the existing entry.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Apply to remaining duplicates'),
                value: _applyToRemaining,
                onChanged: (value) =>
                    setState(() => _applyToRemaining = value ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _choose(DuplicateImportAction.cancel),
          child: const Text('Cancel import'),
        ),
        OutlinedButton(
          onPressed: () => _choose(DuplicateImportAction.skip),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => _choose(DuplicateImportAction.replace),
          child: const Text('Replace'),
        ),
      ],
    );
  }
}
