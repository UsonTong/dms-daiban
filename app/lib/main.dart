import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'state/dms_bridge.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/panel/panel_app.dart';
import 'ui/app_theme.dart';
import 'ui/widgets/fps_overlay.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--panel')) {
    runPanel(showOnStart: args.contains('--show'));
    return;
  }
  final state = AppState();
  DmsBridge(state);
  runApp(ChangeNotifierProvider.value(value: state, child: const TodoApp()));
  state.init();
}

class TodoApp extends StatefulWidget {
  const TodoApp({super.key});

  @override
  State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    context.read<AppState>().notify = (msg, {undo}) {
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            // 带撤销的多留一会儿
            duration: Duration(seconds: undo == null ? 4 : 6),
            action: undo == null
                ? null
                : SnackBarAction(label: '撤销', onPressed: undo),
          ),
        );
    };
  }

  @override
  Widget build(BuildContext context) {
    return themedApp(
      (light, dark, mode) => MaterialApp(
        title: '待办',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messenger,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => FpsOverlay(child: child!),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final Widget child;
    if (!s.ready) {
      child = const Scaffold(key: ValueKey('splash'));
    } else if (!s.loggedIn) {
      child = const LoginPage(key: ValueKey('login'));
    } else {
      child = const HomeShell(key: ValueKey('home'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}
