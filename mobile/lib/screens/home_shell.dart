import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app.dart';
import '../widgets/common.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'invest_screen.dart';
import 'jose_screen.dart';
import 'transactions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  Future<void> _tick() async {
    await app.refreshCaptureStatus();
    final n = await app.syncCaptured();
    if (n > 0 && mounted) {
      toast(context, n == 1 ? '1 gasto do Nubank anotado automaticamente' : '$n gastos do Nubank anotados');
    }
  }

  void goTo(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onNavigate: goTo),
      const TransactionsScreen(),
      const JoseScreen(),
      const BudgetsScreen(),
      const InvestScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: goTo,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Gastos'),
          NavigationDestination(icon: JoseAvatar(size: 28), label: 'José Pinto'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'Metas'),
          NavigationDestination(icon: Icon(Icons.trending_up_outlined), selectedIcon: Icon(Icons.trending_up), label: 'Investir'),
        ],
      ),
    );
  }
}
