import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(ApiClient())..initialize(),
      child: const DocumentApp(),
    ),
  );
}
