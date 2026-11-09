import 'package:pica_comic/foundation/reading_stats.dart';
import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/window_frame.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/app_usage.dart';
import 'package:pica_comic/foundation/app_page_route.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/init.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:pica_comic/pages/auth_page.dart';
import 'package:pica_comic/pages/main_page.dart';
import 'package:pica_comic/pages/welcome_page.dart';
import 'package:pica_comic/tools/block_screenshot.dart';
import 'package:pica_comic/tools/mouse_listener.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:window_manager/window_manager.dart';

import 'components/components.dart';
import 'network/webdav.dart';

bool notFirstUse = false;

void main(List<String> args) {
  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await init();
    FlutterError.onError = (details) {
      LogManager.addLog(LogLevel.error, "Unhandled Exception",
          "${details.exception}\n${details.stack}");
    };
    notFirstUse = appdata.firstUse[3] == "1";
    setNetworkProxy();
    runApp(const MyApp());
    if (App.isDesktop) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow().then((_) async {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: App.isMacOS,
        );
        if (App.isLinux) {
          await windowManager.setBackgroundColor(Colors.transparent);
        }
        await windowManager.setMinimumSize(const Size(500, 600));
        if (!App.isLinux) {
          // https://github.com/leanflutter/window_manager/issues/460
          var placement = await WindowPlacement.loadFromFile();
          await placement.applyToWindow();
          await windowManager.show();
          WindowPlacement.loop();
        }
      });
    }
  }, (error, stack) {
    LogManager.addLog(LogLevel.error, "Unhandled Exception", "$error\n$stack");
  });
}

/// 应用「屏幕刷新率」设置 (settings[38]): 0 跟随系统, 1 高刷, 2 60Hz。
/// [onlyIfForced] 为 true 时, 跟随系统模式下不做任何调用。
Future<void> applyRefreshRateSetting({bool onlyIfForced = false}) async {
  if (!App.isAndroid) return;
  final mode = appdata.settings[38];
  if (onlyIfForced && mode != "1" && mode != "2") return;
  try {
    switch (mode) {
      case "1":
        await FlutterDisplayMode.setHighRefreshRate();
        break;
      case "2":
        final modes = await FlutterDisplayMode.supported;
        final active = await FlutterDisplayMode.active;
        final candidates = modes
            .where((m) =>
                m.width == active.width &&
                m.height == active.height &&
                m.refreshRate < 61)
            .toList()
          ..sort((a, b) => b.refreshRate.compareTo(a.refreshRate));
        if (candidates.isNotEmpty) {
          await FlutterDisplayMode.setPreferredMode(candidates.first);
        } else {
          await FlutterDisplayMode.setLowRefreshRate();
        }
        break;
      default:
        await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
    }
  } catch (_) {
    // 部分机型不支持
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static void Function()? updater;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  DateTime time = DateTime.fromMillisecondsSinceEpoch(0);

  bool forceRebuild = false;

  OverlayEntry? hideContentOverlay;

  void hideContent() {
    if (hideContentOverlay != null) return;
    hideContentOverlay = OverlayEntry(
        builder: (context) => Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.width,
              color: Theme.of(context).colorScheme.surface,
            ));
    OverlayWidget.addOverlay(hideContentOverlay!);
  }

  void showContent() {
    hideContentOverlay = null;
    OverlayWidget.removeAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppUsageTracker.instance.handleLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      ReadingStats.instance.resume();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      ReadingStats.instance.pause();
    }
    bool enableAuth = appdata.settings[13] == "1";
    if (state == AppLifecycleState.resumed) {
      applyRefreshRateSetting(onlyIfForced: true);
    }
    setNetworkProxy();
    scheduleMicrotask(() {
      if (state == AppLifecycleState.hidden && enableAuth) {
        if (!AuthPage.lock && appdata.settings[13] == "1") {
          AuthPage.initial = false;
          AuthPage.lock = true;
          App.to(App.globalContext!, () => const AuthPage());
        }
      }

      if (state == AppLifecycleState.inactive && enableAuth) {
        hideContent();
      } else if (state == AppLifecycleState.resumed) {
        showContent();
        Future.delayed(const Duration(milliseconds: 200), checkClipboard);
      }

      if (DateTime.now().millisecondsSinceEpoch - time.millisecondsSinceEpoch >
          7200000) {
        Webdav.syncData();
        time = DateTime.now();
      }
    });
  }

  @override
  void initState() {
    MyApp.updater = () => setState(() => forceRebuild = true);
    time = DateTime.now();
    TagsTranslation.readData();
    applyRefreshRateSetting(onlyIfForced: true);
    listenMouseSideButtonToBack();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    notifications.init();
    if (appdata.settings[12] == "1") {
      blockScreenshot();
    }
    PaintingBinding.instance.imageCache.maximumSizeBytes = 200 * 1024 * 1024;
    super.initState();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  (ColorScheme, ColorScheme) _generateColorSchemes(
      ColorScheme? light, ColorScheme? dark) {
    // 用柔和的种子色，而不是 Material Accent —— 后者饱和度过高，
    // fromSeed 出来的主色会偏「电子味」，缺少 HyperOS 的灰调质感。
    final int themeSetting = int.parse(appdata.settings[27]);
    final Color color = useDynamicColor(themeSetting)
        ? (light?.primary ?? themeSeedColor(themeSetting))
        : themeSeedColor(themeSetting);
    light = ColorScheme.fromSeed(seedColor: color);
    dark = ColorScheme.fromSeed(seedColor: color, brightness: Brightness.dark);
    final bool isPureBlack = appdata.settings[84] == "1";
    light = light.copyWith(
      surface: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F7F8),
      surfaceContainerHigh: const Color(0xFFEEEEF0),
      surfaceContainerHighest: const Color(0xFFE5E5EA),
      outlineVariant: const Color(0x14000000),
    );
    dark = dark.copyWith(
      surface: isPureBlack ? const Color(0xFF000000) : const Color(0xFF1C1C1E),
      surfaceContainer: isPureBlack ? const Color(0xFF141416) : const Color(0xFF1C1C1E),
      surfaceContainerLow: isPureBlack ? const Color(0xFF0A0A0A) : const Color(0xFF141416),
      surfaceContainerHigh: isPureBlack ? const Color(0xFF1C1C1E) : const Color(0xFF242426),
      surfaceContainerHighest: isPureBlack ? const Color(0xFF242426) : const Color(0xFF2C2C2E),
      outlineVariant: const Color(0x22FFFFFF),
    );
    return (light, dark);
  }

  @override
  Widget build(BuildContext context) {
    if (forceRebuild) {
      forceRebuild = false;
      void rebuild(Element el) {
        el.markNeedsBuild();
        el.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    }
    return DynamicColorBuilder(builder: (light, dark) {
      var (lightColor, darkColor) = _generateColorSchemes(light, dark);
      // 种子色：动态取色时跟随系统壁纸，否则用色板里选中的颜色
      final int themeSetting = int.parse(appdata.settings[27]);
      final Color seed = useDynamicColor(themeSetting)
          ? (light?.primary ?? themeSeedColor(themeSetting))
          : themeSeedColor(themeSetting);
      final Color primaryColor = seed;
      final bool systemIsDark =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark;
      final int darkModeSetting = appdata.appSettings.darkMode;
      final bool isDark = darkModeSetting == 2
          ? true
          : (darkModeSetting == 1 ? false : systemIsDark);
      final bool isPureBlack = isDark && appdata.settings[84] == "1";

      // 用 miuixColorsFromSeed 从种子色展开出整套 27 个语义色。
      // 之前只覆盖了 primary，primaryContainer / tertiaryContainer 等仍是
      // miuix 默认的蓝色，换主题时会出现「主色是红的、容器还是蓝的」的错位。
      final seedColors = miuixColorsFromSeed(
        seed: seed,
        dark: isDark,
        paletteStyle: MiuixThemePaletteStyle.tonalSpot,
      );

      final rootMiuixTheme = isDark
          ? MiuixThemeData.dark(
              colors: seedColors.copy(
                primary: primaryColor,
                background:
                    isPureBlack ? Colors.black : const Color(0xFF121212),
                surface:
                    isPureBlack ? Colors.black : const Color(0xFF121212),
                surfaceContainer: isPureBlack
                    ? const Color(0xFF161618)
                    : const Color(0xFF1C1C1E),
                surfaceContainerHigh: isPureBlack
                    ? const Color(0xFF1E1E22)
                    : const Color(0xFF242426),
                surfaceContainerHighest: isPureBlack
                    ? const Color(0xFF26262A)
                    : const Color(0xFF2C2C2E),
              ),
            )
          : MiuixThemeData.light(
              colors: seedColors.copy(
                primary: primaryColor,
                background: const Color(0xFFF4F4F6),
                surface: const Color(0xFFF4F4F6),
                surfaceContainer: Colors.white,
              ),
            );

      return MiuixTheme(
        data: rootMiuixTheme,
        child: MaterialApp(
            title: 'Pica Comic',
            debugShowCheckedModeBanner: false,
            navigatorKey: App.navigatorKey,
            theme: ThemeData(
              colorScheme: lightColor,
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFFF4F4F6),
              cardColor: Colors.white,
              canvasColor: const Color(0xFFF4F4F6),
              dialogBackgroundColor: Colors.white,
              dialogTheme: DialogTheme(
                backgroundColor: Colors.white,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                shape: const MiuixSquircleBorder(cornerRadius: 28),
                titleTextStyle: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: lightColor.onSurface,
                ),
                contentTextStyle: TextStyle(
                  fontSize: 15,
                  color: lightColor.onSurfaceVariant,
                ),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
              ),
              cardTheme: const CardTheme(
                color: Colors.white,
                elevation: 0,
                shape: MiuixSquircleBorder(cornerRadius: 16),
              ),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                },
              ),
              fontFamily: App.isWindows ? "font" : "",
            ),
            darkTheme: ThemeData(
              colorScheme: darkColor,
              useMaterial3: true,
              scaffoldBackgroundColor:
                  isPureBlack ? const Color(0xFF000000) : const Color(0xFF121212),
              cardColor: const Color(0xFF1C1C1E),
              canvasColor:
                  isPureBlack ? const Color(0xFF000000) : const Color(0xFF121212),
              dialogBackgroundColor:
                  isPureBlack ? const Color(0xFF161618) : const Color(0xFF1C1C1E),
              dialogTheme: DialogTheme(
                backgroundColor: isPureBlack
                    ? const Color(0xFF161618)
                    : const Color(0xFF1C1C1E),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                shape: const MiuixSquircleBorder(cornerRadius: 28),
                titleTextStyle: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: darkColor.onSurface,
                ),
                contentTextStyle: TextStyle(
                  fontSize: 15,
                  color: darkColor.onSurfaceVariant,
                ),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
              ),
              cardTheme: const CardTheme(
                color: Color(0xFF1C1C1E),
                elevation: 0,
                shape: MiuixSquircleBorder(cornerRadius: 16),
              ),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                },
              ),
              fontFamily: App.isWindows ? "font" : "",
              brightness: Brightness.dark,
            ),
            themeMode: darkModeSetting == 2
                ? ThemeMode.dark
                : darkModeSetting == 1
                ? ThemeMode.light
                : ThemeMode.system,
            onGenerateRoute: (settings) => AppPageRoute(
              builder: (context) => notFirstUse
                  ? (appdata.settings[13] == "1"
                  ? const AuthPage()
                  : const MainPage())
                  : const WelcomePage(),
            ),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
              Locale('en', 'US')
            ],
            builder: (context, widget) {
              ErrorWidget.builder = (details) {
                LogManager.addLog(LogLevel.error, "Unhandled Exception",
                    "${details.exception}\n${details.stack}");
                return Material(
                  child: Center(
                    child: Text(details.exception.toString()),
                  ),
                );
              };
              if (widget != null) {
                final isDarkNow =
                    Theme.of(context).brightness == Brightness.dark;
                final isPureBlackNow =
                    isDarkNow && appdata.settings[84] == "1";
                final effectiveMiuixTheme = isDarkNow
                    ? MiuixThemeData.dark(
                        colors: darkColorScheme().copy(
                          primary: primaryColor,
                          background: isPureBlackNow
                              ? Colors.black
                              : const Color(0xFF121212),
                          surface: isPureBlackNow
                              ? Colors.black
                              : const Color(0xFF121212),
                          surfaceContainer: isPureBlackNow
                              ? const Color(0xFF161618)
                              : const Color(0xFF1C1C1E),
                          surfaceContainerHigh: isPureBlackNow
                              ? const Color(0xFF1E1E22)
                              : const Color(0xFF242426),
                          surfaceContainerHighest: isPureBlackNow
                              ? const Color(0xFF26262A)
                              : const Color(0xFF2C2C2E),
                        ),
                      )
                    : MiuixThemeData.light(
                        colors: lightColorScheme().copy(
                          primary: primaryColor,
                          background: const Color(0xFFF4F4F6),
                          surface: const Color(0xFFF4F4F6),
                          surfaceContainer: Colors.white,
                        ),
                      );
                widget = MiuixTheme(
                  data: effectiveMiuixTheme,
                  child: MiuixPopupHost(child: widget),
                );
                widget = OverlayWidget(widget);
                if (App.isDesktop) {
                  widget = Shortcuts(
                    shortcuts: {
                      LogicalKeySet(LogicalKeyboardKey.escape):
                      VoidCallbackIntent(
                            () {
                          if (App.canPop) {
                            App.globalBack();
                          } else {
                            App.mainNavigatorKey?.currentContext?.pop();
                          }
                        },
                      ),
                    },
                    child: WindowFrame(widget),
                  );
                }
                return _SystemUiProvider(widget);
              }
              throw ('widget is null');
            },
          ),
      );
    });
  }
}

class _SystemUiProvider extends StatelessWidget {
  const _SystemUiProvider(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var brightness = Theme.of(context).brightness;
    SystemUiOverlayStyle systemUiStyle;
    if (brightness == Brightness.light) {
      systemUiStyle = SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      );
    } else {
      systemUiStyle = SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: child,
    );
  }
}
