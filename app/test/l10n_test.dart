/// Localization: both locales load, directions are correct, and key
/// strings differ per locale.

library aftab_l10n_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aftab_media/l10n/app_localizations.dart';

Widget _app(Locale locale, Widget child) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fa loads with RTL direction', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(_app(
      const Locale('fa'),
      Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pumpAndSettle();
    final s = S.of(captured);
    expect(s.appName, 'آفتاب مدیا');
    expect(s.navHome, 'خانه');
    expect(s.navLibrary, 'کتابخانه');
    expect(Directionality.of(captured), TextDirection.rtl);
  });

  testWidgets('en loads with LTR direction', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(_app(
      const Locale('en'),
      Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pumpAndSettle();
    final s = S.of(captured);
    expect(s.appName, 'Aftab Media');
    expect(s.navHome, 'Home');
    expect(s.navLibrary, 'Library');
    expect(Directionality.of(captured), TextDirection.ltr);
  });

  testWidgets('placeholders and plurals resolve per locale (fa)',
      (tester) async {
    late BuildContext fa;
    await tester.pumpWidget(_app(
      const Locale('fa'),
      Builder(
        builder: (context) {
          fa = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(S.of(fa).searchNoResults('آب'), 'نتیجه‌ای برای «آب» یافت نشد');
    expect(S.of(fa).searchResultsCount(1, '۱'), 'یک نتیجه');
    expect(S.of(fa).searchResultsCount(5, '۵'), '۵ نتیجه');
    expect(S.of(fa).episodesCount(1, '۱'), 'یک قسمت');
    expect(S.of(fa).imdbRating('۷٫۴'), 'IMDb ۷٫۴');
  });

  testWidgets('placeholders and plurals resolve per locale (en)',
      (tester) async {
    late BuildContext en;
    await tester.pumpWidget(_app(
      const Locale('en'),
      Builder(
        builder: (context) {
          en = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(S.of(en).searchNoResults('sun'), 'No results for “sun”');
    expect(S.of(en).searchResultsCount(1, '1'), 'one result');
    expect(S.of(en).searchResultsCount(5, '5'), '5 results');
    expect(S.of(en).episodesCount(3, '3'), '3 episodes');
  });
}
