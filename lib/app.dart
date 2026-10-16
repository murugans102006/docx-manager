import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'models.dart';
import 'screens.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  AppUser? user;
  bool ready = false;

  Future<void> initialize() async {
    await api.initialize();
    if (api.isAuthenticated) {
      try {
        final value = asJson(unwrap(await api.fetchMe()));
        user = AppUser.fromJson(value);
      } catch (_) {
        await api.clearToken();
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await api.login(email, password);
    user = AppUser.fromJson(data);
    notifyListeners();
  }

  Future<void> register(JsonMap values) async {
    final data = await api.register(values);
    if (api.isAuthenticated) {
      user = AppUser.fromJson(data);
    } else {
      await login(textOf(values['email']), textOf(values['password']));
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } finally {
      user = null;
      notifyListeners();
    }
  }
}

class DocumentApp extends StatelessWidget {
  const DocumentApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'College Documents',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff244c91),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff5f7fb),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff5f7fb),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe7ebf2)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdce2ec)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdce2ec)),
        ),
      ),
    ),
    home: Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return state.user == null
            ? const AuthScreen()
            : RoleHome(user: state.user!);
      },
    ),
  );
}
