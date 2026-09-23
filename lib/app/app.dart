import 'package:flutter/material.dart';

import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/app/navigation/app_shell.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/login_screen.dart';

class SarathiGroceryApp extends StatelessWidget {
  const SarathiGroceryApp({super.key, required this.scope});

  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sarathi Grocery',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        visualDensity: VisualDensity.comfortable,
      ),
      home: AuthGate(scope: scope),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.scope});

  final AppScope scope;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AppScope get _scope => widget.scope;
  late final Future<void> _restored = _scope.auth.restoreSession();

  @override
  void dispose() {
    _scope.auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _restored,
      builder: (context, snapshot) =>
          snapshot.connectionState != ConnectionState.done
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ListenableBuilder(
              listenable: _scope.auth,
              builder: (context, _) {
                if (_scope.auth.currentUser == null) {
                  return LoginScreen(auth: _scope.auth);
                }
                return AppShell(scope: _scope);
              },
            ),
    );
  }
}
