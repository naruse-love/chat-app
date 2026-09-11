import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/native/native_services.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/api_config_screen.dart';
import 'screens/system_prompt_screen.dart';
import 'screens/mcp_server_management_screen.dart';
import 'screens/sandbox_management_screen.dart';
import 'screens/model_selector_screen.dart';
import 'screens/vocabulary_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/vocabulary':
        return _slideRoute(const VocabularyScreen());
      case '/settings':
        return _slideRoute(const SettingsScreen());
      case '/settings/api_config':
        return _slideRoute(const ApiConfigScreen());
      case '/settings/system_prompts':
        return _slideRoute(const SystemPromptScreen());
      case '/settings/mcp_servers':
        return _slideRoute(const McpServerManagementScreen());
      case '/settings/sandbox':
        return _slideRoute(const SandboxManagementScreen());
      case '/model_selector':
        return MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ModelSelectorScreen(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }

  static PageRouteBuilder _slideRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  StreamSubscription<String>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    // 监听通知栏常驻快捷入口点击事件
    final notificationService = ref.read(persistentNotificationServiceProvider);
    _notificationSub = notificationService.onNotificationTapped.listen((payload) {
      _navigateForPayload(payload);
    });

    // 检查冷启动是否携带通知点击载荷
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launchPayload = await notificationService.getLaunchPayload();
      if (launchPayload != null && mounted) {
        _navigateForPayload(launchPayload);
      }
    });
  }

  void _navigateForPayload(String payload) {
    if (payload == '/vocabulary') {
      final navState = appNavigatorKey.currentState;
      if (navState != null) {
        // 如果当前不在单词本页面，则推入该页面
        bool isAlreadyOnVocab = false;
        navState.popUntil((route) {
          if (route.settings.name == '/vocabulary') {
            isAlreadyOnVocab = true;
          }
          return true;
        });

        if (!isAlreadyOnVocab) {
          navState.pushNamed('/vocabulary');
        }
      }
    }
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'AI Agent Chat',
      navigatorKey: appNavigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      onGenerateRoute: AppRouter.generateRoute,
      initialRoute: '/',
      debugShowCheckedModeBanner: false,
    );
  }
}
