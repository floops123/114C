import 'package:flutter/material.dart';

import '../core/format.dart';
import 'theme.dart';

// Dates des notifications et du salon : séparateurs de jour, heures courtes.

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// « Aujourd'hui », « Hier », « vendredi 16 octobre » (+ année si besoin).
String dayLabel(DateTime d) {
  final day = d.toLocal();
  final now = DateTime.now();
  if (sameDay(day, now)) return 'Aujourd’hui';
  if (sameDay(day, now.subtract(const Duration(days: 1)))) return 'Hier';
  final label =
      '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
  return day.year == now.year ? label : '$label ${day.year}';
}

class DaySeparator extends StatelessWidget {
  const DaySeparator(this.date, {super.key});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              dayLabel(date),
              style: TextStyle(
                color: c.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: c.border)),
        ],
      ),
    );
  }
}

/// Heure d'une notification : relative le jour même, sinon HH:mm (le jour
/// figure dans le séparateur).
String shortTime(DateTime d) {
  final t = d.toLocal();
  if (sameDay(t, DateTime.now())) return formatAgo(d);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

