/// UI smoke tests with fake data sources: adaptive shell, home rails,
/// discover filters, search flow, states and components.

library aftab_ui_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aftab_media/components/aftab_image.dart';
import 'package:aftab_media/components/media_card.dart';
import 'package:aftab_media/components/states.dart';
import 'package:aftab_media/core/aftab_ffi.dart';
import 'package:aftab_media/core/models.dart';
import 'package:aftab_media/features/home/home_screen.dart';
import 'package:aftab_media/navigation/app_shell.dart';
import 'package:aftab_media/platform/form_factor.dart';
import 'package:aftab_media/tv/tv_shell.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('components', () {
    testWidgets('PosterCard renders title and fallback artwork',
        (tester) async {
      final item = fakeItem(title: 'گوشه', image: '');
      await tester.pumpWidget(testApp(
        child: SizedBox(
          width: 200,
          height: 320,
          child: PosterCard(item: item, onTap: () {}),
        ),
      ));
      expect(find.text('گوشه'), findsOneWidget);
      // Fallback icon, not a network image.
      expect(find.byType(AftabImage), findsOneWidget);
    });

    testWidgets('error pane offers retry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(testApp(
        child: AftabErrorPane(
          message: 'شبکه قطع است',
          onRetry: () => retries += 1,
        ),
      ));
      expect(find.text('شبکه قطع است'), findsOneWidget);
      await tester.tap(find.text('تلاش دوباره'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('empty pane shows hint', (tester) async {
      await tester.pumpWidget(testApp(
        child: const AftabEmptyPane(title: 'خالی', hint: 'راهنما'),
      ));
      expect(find.text('خالی'), findsOneWidget);
      expect(find.text('راهنما'), findsOneWidget);
    });
  });

  group('AppShell', () {
    testWidgets('compact width uses a bottom navigation bar',
        (tester) async {
      tester.view.physicalSize = const Size(720, 1600); // 360x800 logical
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final catalog = FakeCatalogSource(
        movies: <CatalogItem>[fakeItem(id: 1), fakeItem(id: 2)],
        series: <CatalogItem>[fakeItem(id: 3, kind: 'serie')],
      );
      await tester.pumpWidget(testApp(
        catalog: catalog,
        child: const AppShell(formFactor: FormFactor.phone),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      // Home rails loaded from the fake catalog.
      expect(find.text('فیلم‌های برتر'), findsOneWidget);
      expect(find.text('سریال‌های برتر'), findsOneWidget);
    });

    testWidgets('medium width uses a navigation rail', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200); // 800x600 logical
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final catalog = FakeCatalogSource(
        movies: <CatalogItem>[fakeItem(id: 1)],
      );
      await tester.pumpWidget(testApp(
        catalog: catalog,
        child: const AppShell(formFactor: FormFactor.tablet),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('tapping Library switches the visible tab', (tester) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final catalog = FakeCatalogSource(
        movies: <CatalogItem>[fakeItem(id: 1)],
      );
      await tester.pumpWidget(testApp(
        catalog: catalog,
        child: const AppShell(formFactor: FormFactor.phone),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('کتابخانه'));
      await tester.pumpAndSettle();
      expect(find.text('علاقه‌مندی‌ها'), findsWidgets);
      expect(find.text('دانلودها'), findsOneWidget);
    });
  });

  group('HomeScreen', () {
    testWidgets('greeting and rails render from fake data',
        (tester) async {
      final catalog = FakeCatalogSource(
        movies: <CatalogItem>[fakeItem(id: 1, title: 'فیلم یک')],
        series: <CatalogItem>[fakeItem(id: 2, kind: 'serie', title: 'سریال دو')],
      );
      await tester.pumpWidget(
          testApp(catalog: catalog, child: const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('آفتاب مدیا'), findsOneWidget);
      expect(find.text('فیلم‌های برتر'), findsOneWidget);
      expect(find.text('فیلم یک'), findsOneWidget);
      expect(find.text('سریال‌های برتر'), findsOneWidget);
      expect(find.text('سریال دو'), findsOneWidget);
    });

    testWidgets('total failure shows a retry pane', (tester) async {
      final catalog = _FailingCatalog();
      await tester.pumpWidget(
          testApp(catalog: catalog, child: const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(AftabErrorPane), findsOneWidget);
      expect(find.text('ارتباط برقرار نشد'), findsOneWidget);
    });
  });

  group('TvShell', () {
    testWidgets('renders the 10-foot navigation row', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final catalog = FakeCatalogSource(
        movies: <CatalogItem>[fakeItem(id: 1, title: 'فیلم یک')],
      );
      await tester.pumpWidget(
          testApp(catalog: catalog, child: const TvShell()));
      await tester.pumpAndSettle();
      expect(find.text('خانه'), findsOneWidget);
      expect(find.text('جست‌وجو'), findsOneWidget);
      expect(find.text('کتابخانه'), findsOneWidget);
      expect(find.text('تنظیمات'), findsOneWidget);
      expect(find.text('فیلم‌های برتر'), findsOneWidget);
    });
  });
}

class _FailingCatalog extends FakeCatalogSource {
  @override
  Future<List<CatalogItem>> movies({
    int genre = 0,
    CatalogSort sort = CatalogSort.newest,
    int page = 0,
  }) async => throw const AftabException(aftabNetwork, 'شبکه قطع است');

  @override
  Future<List<CatalogItem>> series({
    int genre = 0,
    CatalogSort sort = CatalogSort.newest,
    int page = 0,
  }) async => throw const AftabException(aftabNetwork, 'شبکه قطع است');
}
