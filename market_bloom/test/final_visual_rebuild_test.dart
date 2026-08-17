import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/daily_event_game_controller.dart';
import 'package:pomarket/game/daily_event_models.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/main.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/screens/upgrades_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _visualEvent = DailyEventDefinition(id:'visual-event',type:MarketEventType.flashSale,title:'Flash Sale',description:'Featured products are worth more today.',effectSummary:'Sale value +20%',modifiers:DailyEventModifiers());

void main(){
  testWidgets('mobile navigation has deliberate destinations and compact hub',(tester)async{
    await _pumpApp(tester,const Size(390,844));
    expect(find.byKey(const ValueKey('mobile-game-navigation')),findsOneWidget);
    // Four permanent slots plus the overflow hub. Settings moved into the hub
    // when the dock replaced the hamburger, so it is asserted on expand below
    // rather than as a permanent slot.
    for(final name in <String>['market','upgrades','staff','shop']){expect(find.byKey(ValueKey('mobile-nav-$name')),findsOneWidget);}
    expect(find.byKey(const ValueKey('mobile-nav-more')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-upgrades')));await tester.pump(const Duration(milliseconds:220));expect(find.byType(UpgradesScreen),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-more')));await tester.pump(const Duration(milliseconds:320));
    for(final label in <String>['Departments','Inventory','Quests','Achievements','Settings']){expect(find.text(label),findsWidgets);}
    expect(find.byIcon(Icons.close_rounded),findsOneWidget);expect(tester.takeException(),isNull);
  });

  testWidgets('the dock spans the bottom symmetrically at every size',(tester)async{
    // The trailing side rail was removed so one dock serves every breakpoint;
    // it should sit across the bottom rather than hugging one edge.
    //
    // The dock is now a floating capsule: inset from the screen edges, and
    // capped to a comfortable measure so five slots do not spread across a
    // desktop window. So this asserts the properties that actually matter — it
    // is centred, symmetric, bottom-anchored, and fills the width up to the cap
    // — instead of pinning it to the exact viewport rect.
    for(final size in const[Size(320,568),Size(900,700),Size(1440,900)]){
      await _pumpApp(tester,size);
      final dock=tester.getRect(find.byKey(const ValueKey('mobile-game-navigation')));final viewport=tester.getRect(find.byKey(const ValueKey('pomarket-app-shell')));
      final inset=size.width<420?8.0:12.0;
      expect(dock.width,closeTo(math.min(viewport.width-inset*2,620),1),reason:'at $size');
      expect(dock.left-viewport.left,closeTo(viewport.right-dock.right,1),reason:'at $size');
      expect(viewport.bottom-dock.bottom,lessThanOrEqualTo(20),reason:'at $size');
      expect(tester.takeException(),isNull,reason:'at $size');
    }
  });

  testWidgets('HUD event and management title occupy separate vertical regions',(tester)async{
    await _pumpApp(tester,const Size(320,568));await tester.tap(find.byKey(const ValueKey('mobile-nav-upgrades')));await tester.pump(const Duration(milliseconds:220));
    final banner=tester.getRect(find.byKey(const ValueKey('daily-event-banner')));final title=tester.getRect(find.text('Upgrade Your Business'));
    expect(banner.bottom,lessThanOrEqualTo(title.top+.1));expect(banner.height,lessThanOrEqualTo(40));expect(tester.takeException(),isNull);
  });

  testWidgets('compact visual shell remains RTL and reduced-motion safe',(tester)async{
    SharedPreferences.setMockInitialValues(const <String,Object>{});tester.view.physicalSize=const Size(320,568);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final controller=_controller();await controller.initialize();controller.completeOnboarding();controller.acknowledgeDailyBonus();final settings=AppSettings();await settings.setLanguage(const Locale('ar'));await settings.setReducedMotion(true);await settings.load();
    await tester.pumpWidget(PoMarketApp(controller:controller,settings:settings,showSplash:false));await tester.pump();await tester.pump(const Duration(milliseconds:120));
    final shellContext=tester.element(find.byKey(const ValueKey('pomarket-app-shell')));expect(Directionality.of(shellContext),TextDirection.rtl);expect(find.byKey(const ValueKey('daily-event-banner')),findsOneWidget);expect(find.byKey(const ValueKey('mobile-game-navigation')),findsOneWidget);expect(tester.takeException(),isNull);
  });
}

Future<void> _pumpApp(WidgetTester tester,Size size)async{tester.view.physicalSize=size;tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);final controller=_controller();await controller.initialize();controller.completeOnboarding();controller.acknowledgeDailyBonus();await tester.pumpWidget(PoMarketApp(controller:controller,settings:AppSettings(),showSplash:false));await tester.pump();await tester.pump(const Duration(milliseconds:120));}
DailyEventGameController _controller()=>DailyEventGameController(storage:MemoryGameStorage(),monetization:PreviewMonetizationService(),forcedEvent:_visualEvent);
