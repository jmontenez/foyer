import 'package:flutter/material.dart';
import 'ui.dart';

/// Vue Calendrier — squelette du palier 1a (nav).
///
/// La vue Semaine (grille horaire), la bande « toute la journée » et les
/// événements arrivent au palier 1c ; d'ici là, un état d'attente « Découpes ».
class CalendarView extends StatelessWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: EmptyState(
      title: 'Le calendrier arrive',
      message:
          'La vue Semaine, les événements et la synchro agenda se branchent ici très bientôt.',
      signs: [FoyerSign.grid, FoyerSign.cal, FoyerSign.sun],
    ),
  );
}
