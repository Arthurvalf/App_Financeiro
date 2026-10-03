import 'package:flutter/material.dart';

import '../theme.dart';
import 'budgets_screen.dart';
import 'debts_screen.dart';
import 'simulator_screen.dart';

/// Aba "Planos": metas, dívidas e simulador.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Planos'),
          bottom: const TabBar(
            labelColor: C.ink,
            unselectedLabelColor: C.muted,
            indicatorColor: C.ink,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Metas'),
              Tab(text: 'Dívidas'),
              Tab(text: 'E se...?'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          BudgetsScreen(),
          DebtsScreen(),
          SimulatorScreen(),
        ]),
      ),
    );
  }
}
