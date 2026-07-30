import 'package:flutter/widgets.dart';

import '../game/game_models.dart';

/// Localization bundle for PoMarket supporting English, Hebrew, and Arabic.
///
/// English uses LTR; Hebrew and Arabic use RTL. The brand name "PoMarket"
/// is preserved in all languages.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('he'),
    Locale('ar'),
  ];

  bool get isRtl => locale.languageCode == 'ar' || locale.languageCode == 'he';

  static const _strings = <String, Map<String, String>>{
    'en': _english,
    'he': _hebrew,
    'ar': _arabic,
  };

  String _t(String key) {
    return _strings[locale.languageCode]?[key] ?? _english[key] ?? key;
  }

  // ---------------------------------------------------------------------------
  // Existing strings (preserved for backward compatibility)
  // ---------------------------------------------------------------------------

  String get businessHubTitle => _t('businessHubTitle');

  String get businessHubSubtitle => _t('businessHubSubtitle');

  String get scoreLabel => _t('scoreLabel');

  String get achievementsTabLabel => _t('achievementsTabLabel');

  String get statsTabLabel => _t('statsTabLabel');

  String get leaderboardTabLabel => _t('leaderboardTabLabel');

  String get settingsTabLabel => _t('settingsTabLabel');

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  String get market => _t('market');

  String get upgrades => _t('upgrades');

  String get staff => _t('staff');

  String get departments => _t('departments');

  String get inventory => _t('inventory');

  String get quests => _t('quests');

  String get achievements => _t('achievements');

  String get shop => _t('shop');

  String get settings => _t('settings');

  String get more => _t('more');

  // ---------------------------------------------------------------------------
  // Upgrades screen
  // ---------------------------------------------------------------------------

  String get upgradeYourBusiness => _t('upgradeYourBusiness');

  String get investToServe => _t('investToServe');

  String get level => _t('level');

  String get carryProducts => _t('carryProducts');

  String get capacity => _t('capacity');

  String get profitPerSale => _t('profitPerSale');

  String get movementSpeed => _t('movementSpeed');

  String get serveCustomersFaster => _t('serveCustomersFaster');

  String get keepShelvesFilled => _t('keepShelvesFilled');

  String get buy => _t('buy');

  String get affordable => _t('affordable');

  String get notEnoughCoins => _t('notEnoughCoins');

  String upgradeTitle(UpgradeType type) {
    return _t('upgradeTitle${type.name}');
  }

  String questTitle(int stage, int target) {
    final key = switch (stage) {
      0 => 'questStockProducts',
      1 => 'questCompleteSales',
      2 => 'questBuyUpgrade',
      _ => 'questCompleteMoreSales',
    };
    return _t(key).replaceFirst('{target}', '$target');
  }

  // ---------------------------------------------------------------------------
  // Staff screen
  // ---------------------------------------------------------------------------

  String get staffManagement => _t('staffManagement');

  String get hire => _t('hire');

  String get hired => _t('hired');

  String get hireStaff => _t('hireStaff');

  String get upgradeStaff => _t('upgradeStaff');

  String get staffRoleCashier => _t('staffRoleCashier');

  String get staffRoleStocker => _t('staffRoleStocker');

  String get staffRoleCleaner => _t('staffRoleCleaner');

  String get staffRoleBaker => _t('staffRoleBaker');

  String get staffRoleManager => _t('staffRoleManager');

  String get staffRoleCourier => _t('staffRoleCourier');

  String get staffRolePromoter => _t('staffRolePromoter');

  String get staffSummaryCashier => _t('staffSummaryCashier');

  String get staffSummaryStocker => _t('staffSummaryStocker');

  String get staffSummaryCleaner => _t('staffSummaryCleaner');

  String get staffSummaryBaker => _t('staffSummaryBaker');

  String get staffSummaryManager => _t('staffSummaryManager');

  String get staffSummaryCourier => _t('staffSummaryCourier');

  String get staffSummaryPromoter => _t('staffSummaryPromoter');

  String get staffLocked => _t('staffLocked');

  String get staffUnlockRequirement => _t('staffUnlockRequirement');

  String get staffNeedsCoins => _t('staffNeedsCoins');

  String get staffAssignment => _t('staffAssignment');

  String get staffStatus => _t('staffStatus');

  String get statusIdle => _t('statusIdle');

  String get statusServing => _t('statusServing');

  String get statusStocking => _t('statusStocking');

  String get statusWaitingStock => _t('statusWaitingStock');

  String get statusWaitingShelf => _t('statusWaitingShelf');

  String get statusCleaning => _t('statusCleaning');

  String get statusBaking => _t('statusBaking');

  String get statusManaging => _t('statusManaging');

  String get statusDelivering => _t('statusDelivering');

  String get statusPromoting => _t('statusPromoting');

  String get assignmentCheckout => _t('assignmentCheckout');

  String get assignmentShelves => _t('assignmentShelves');

  String get assignmentFloor => _t('assignmentFloor');

  String get assignmentBakery => _t('assignmentBakery');

  String get assignmentOffice => _t('assignmentOffice');

  String get assignmentDelivery => _t('assignmentDelivery');

  String get assignmentEntrance => _t('assignmentEntrance');

  String get serviceTime => _t('serviceTime');

  String get teamOverview => _t('teamOverview');

  String get teamMembers => _t('teamMembers');

  String get teamPower => _t('teamPower');

  String get addWorker => _t('addWorker');

  String get maxWorkers => _t('maxWorkers');

  String get nextWorkerSlot => _t('nextWorkerSlot');

  String get roleUnlockAtLevel => _t('roleUnlockAtLevel');

  String get workerRoute => _t('workerRoute');

  // ---------------------------------------------------------------------------
  // Departments screen
  // ---------------------------------------------------------------------------

  String get departmentsTitle => _t('departmentsTitle');

  String get departmentOperations => _t('departmentOperations');

  String get departmentOperationsSubtitle => _t('departmentOperationsSubtitle');

  String get departmentMilestones => _t('departmentMilestones');

  String get activeDepartments => _t('activeDepartments');

  String get floorStock => _t('floorStock');

  String get salesBoost => _t('salesBoost');

  String get liveInStore => _t('liveInStore');

  String get warehouseStock => _t('warehouseStock');

  String get profitPerItem => _t('profitPerItem');

  String get itemsSold => _t('itemsSold');

  String get upgradeDepartment => _t('upgradeDepartment');

  String get prepareCrate => _t('prepareCrate');

  String get crateSelected => _t('crateSelected');

  String get orderCategoryStock => _t('orderCategoryStock');

  String get deliveryInTransit => _t('deliveryInTransit');

  String get starterStockAdded => _t('starterStockAdded');

  String get departmentUpgraded => _t('departmentUpgraded');

  String get unlocked => _t('unlocked');

  String get locked => _t('locked');

  String get unlockAtLevel => _t('unlockAtLevel');

  String get unlockCost => _t('unlockCost');

  String get departmentGeneralGoods => _t('departmentGeneralGoods');

  String get departmentGeneralGoodsDesc => _t('departmentGeneralGoodsDesc');

  String get departmentBakery => _t('departmentBakery');

  String get departmentBakeryDesc => _t('departmentBakeryDesc');

  String get departmentProduce => _t('departmentProduce');

  String get departmentProduceDesc => _t('departmentProduceDesc');

  String get departmentRefrigerated => _t('departmentRefrigerated');

  String get departmentRefrigeratedDesc => _t('departmentRefrigeratedDesc');

  String get departmentBeauty => _t('departmentBeauty');

  String get departmentBeautyDesc => _t('departmentBeautyDesc');

  String get departmentElectronics => _t('departmentElectronics');

  String get departmentElectronicsDesc => _t('departmentElectronicsDesc');

  String get bakeryUnlocked => _t('bakeryUnlocked');

  String get bakeryUnlockedMessage => _t('bakeryUnlockedMessage');

  String get bakeryReady => _t('bakeryReady');

  String get bakeryBakingHint => _t('bakeryBakingHint');

  String get bakeryCollectingHint => _t('bakeryCollectingHint');

  String get bakeryBagFullHint => _t('bakeryBagFullHint');

  String get bakeryLockedHint => _t('bakeryLockedHint');

  String get storageEmptyHint => _t('storageEmptyHint');

  String get collectingStorageHint => _t('collectingStorageHint');

  String get bagFullHint => _t('bagFullHint');

  String get bagEmptyHint => _t('bagEmptyHint');

  String get shelfFullHint => _t('shelfFullHint');

  String get stockingShelfHint => _t('stockingShelfHint');

  String get checkoutHint => _t('checkoutHint');

  // ---------------------------------------------------------------------------
  // Inventory screen
  // ---------------------------------------------------------------------------

  String get inventoryTitle => _t('inventoryTitle');

  String get carried => _t('carried');

  String get shelfStock => _t('shelfStock');

  String get storage => _t('storage');

  String get totalInventory => _t('totalInventory');

  String get inventoryCapacity => _t('inventoryCapacity');

  String get pendingDeliveries => _t('pendingDeliveries');

  String get noPendingDeliveries => _t('noPendingDeliveries');

  String get placeOrder => _t('placeOrder');

  String get fulfill => _t('fulfill');

  String get emptyInventory => _t('emptyInventory');

  String get orderGeneralStock => _t('orderGeneralStock');

  String get emergencyStock => _t('emergencyStock');

  String get emergencyStockDesc => _t('emergencyStockDesc');

  String get deliveryReady => _t('deliveryReady');

  String get quickRestock => _t('quickRestock');

  String get quickRestockPending => _t('quickRestockPending');

  String get quickRestockOrdered => _t('quickRestockOrdered');

  // ---------------------------------------------------------------------------
  // Quests screen
  // ---------------------------------------------------------------------------

  String get questsTitle => _t('questsTitle');

  String get activeQuest => _t('activeQuest');

  String get claimReward => _t('claimReward');

  String get questCompleted => _t('questCompleted');

  String get questInProgress => _t('questInProgress');

  String get noActiveQuest => _t('noActiveQuest');

  // ---------------------------------------------------------------------------
  // Achievements screen
  // ---------------------------------------------------------------------------

  String get achievementsTitle => _t('achievementsTitle');

  String get badgesUnlocked => _t('badgesUnlocked');

  String get unlockedLabel => _t('unlockedLabel');

  String get bronze => _t('bronze');

  String get silver => _t('silver');

  String get gold => _t('gold');

  String get platinum => _t('platinum');

  String get noAchievementsYet => _t('noAchievementsYet');

  // ---------------------------------------------------------------------------
  // Shop screen
  // ---------------------------------------------------------------------------

  String get shopTitle => _t('shopTitle');

  String get rewardedBonus => _t('rewardedBonus');

  String get watchAndEarn => _t('watchAndEarn');

  String get freeBonus => _t('freeBonus');

  String get freeBonusSubtitle => _t('freeBonusSubtitle');

  String get rewardCenterTitle => _t('rewardCenterTitle');

  String get optionalAdDescription => _t('optionalAdDescription');

  String get mobileFeaturePreview => _t('mobileFeaturePreview');

  String get watchAndReceive => _t('watchAndReceive');

  String get rewardUnavailable => _t('rewardUnavailable');

  String get rewardCooldown => _t('rewardCooldown');

  String get dailyLimitReached => _t('dailyLimitReached');

  String get rewardPreviewUnavailable => _t('rewardPreviewUnavailable');

  String get rewardDismissed => _t('rewardDismissed');

  String get rewardFailed => _t('rewardFailed');

  String get rewardClaimsToday => _t('rewardClaimsToday');

  String get rewardCoinsTitle => _t('rewardCoinsTitle');

  String get rewardCoinsBenefit => _t('rewardCoinsBenefit');

  String get rewardOfflineTitle => _t('rewardOfflineTitle');

  String get rewardOfflineBenefit => _t('rewardOfflineBenefit');

  String get rewardEmergencyTitle => _t('rewardEmergencyTitle');

  String get rewardEmergencyBenefit => _t('rewardEmergencyBenefit');

  String get starterOffers => _t('starterOffers');

  String get coinPacks => _t('coinPacks');

  String get gemPacks => _t('gemPacks');

  String get emergencySupplies => _t('emergencySupplies');

  String get permanentBenefits => _t('permanentBenefits');

  String get removeAdsCategory => _t('removeAdsCategory');

  String get mobileStoreAvailability => _t('mobileStoreAvailability');

  String get noAds => _t('noAds');

  String get oneTimePurchase => _t('oneTimePurchase');

  String get owned => _t('owned');

  String get starterPack => _t('starterPack');

  String get starterPackDesc => _t('starterPackDesc');

  String get coinPack => _t('coinPack');

  String get coinPackDesc => _t('coinPackDesc');

  String get gemPack => _t('gemPack');

  String get gemPackDesc => _t('gemPackDesc');

  String get emergencySupplyPack => _t('emergencySupplyPack');

  String get emergencySupplyPackDesc => _t('emergencySupplyPackDesc');

  String get previewMode => _t('previewMode');

  String get setupRequired => _t('setupRequired');

  String get previewModeDesc => _t('previewModeDesc');

  String get rewardedPreviewDesc => _t('rewardedPreviewDesc');

  String get purchaseComplete => _t('purchaseComplete');

  String get productNotConfigured => _t('productNotConfigured');

  String get purchaseCancelled => _t('purchaseCancelled');

  String get purchaseFailed => _t('purchaseFailed');

  String get previewPrice => _t('previewPrice');

  String get previewPrice2 => _t('previewPrice2');

  String get previewPrice3 => _t('previewPrice3');

  String get secureStorePurchases => _t('secureStorePurchases');

  // ---------------------------------------------------------------------------
  // Settings screen
  // ---------------------------------------------------------------------------

  String get settingsTitle => _t('settingsTitle');

  String get language => _t('language');

  String get sound => _t('sound');

  String get soundEffects => _t('soundEffects');

  String get soundEffectsDesc => _t('soundEffectsDesc');

  String get reducedMotion => _t('reducedMotion');

  String get reducedMotionDesc => _t('reducedMotionDesc');

  String get restorePurchases => _t('restorePurchases');

  String get about => _t('about');

  String get version => _t('version');

  String get autoSaveOn => _t('autoSaveOn');

  String get autoSaveDesc => _t('autoSaveDesc');

  String get quickTutorial => _t('quickTutorial');

  String get replayTutorial => _t('replayTutorial');

  String get dailyStreak => _t('dailyStreak');

  String get days => _t('days');

  String get best => _t('best');

  String get resetProgress => _t('resetProgress');

  String get resetConfirm => _t('resetConfirm');

  String get cancel => _t('cancel');

  String get reset => _t('reset');

  String get english => _t('english');

  String get hebrew => _t('hebrew');

  String get arabic => _t('arabic');

  String get systemDefault => _t('systemDefault');

  String get restorePurchasesSuccess => _t('restorePurchasesSuccess');

  String get restorePurchasesNone => _t('restorePurchasesNone');

  String get restorePurchasesUnavailable => _t('restorePurchasesUnavailable');

  String get restorePurchasesDesc => _t('restorePurchasesDesc');

  String get replay => _t('replay');

  // ---------------------------------------------------------------------------
  // Game screen (existing + new)
  // ---------------------------------------------------------------------------

  String get yourMiniMarket => _t('yourMiniMarket');

  String get muteSound => _t('muteSound');

  String get unmuteSound => _t('unmuteSound');

  String get reward => _t('reward');

  String get loading => _t('loading');

  String get unavailable => _t('unavailable');

  String get retryIn => _t('retryIn');

  String get hub => _t('hub');

  String get coinsEarned => _t('coinsEarned');

  String get productStocked => _t('productStocked');

  String get saleCompleted => _t('saleCompleted');

  String get welcomeBack => _t('welcomeBack');

  String get businessKeptEarning => _t('businessKeptEarning');

  String get collect => _t('collect');

  String get double => _t('double');

  String get previewGrantsReward => _t('previewGrantsReward');

  String get dailyBonus => _t('dailyBonus');

  String get streak => _t('streak');

  String get dayStreak => _t('dayStreak');

  String get comeBackTomorrow => _t('comeBackTomorrow');

  String get collectReward => _t('collectReward');

  String get maxLevel => _t('maxLevel');

  String get yourCurrentBusinessScore => _t('yourCurrentBusinessScore');

  String get postScore => _t('postScore');

  String get challenge => _t('challenge');

  String get localTop10 => _t('localTop10');

  String get savedOnThisDevice => _t('savedOnThisDevice');

  String get podiumWaiting => _t('podiumWaiting');

  String get postYourScore => _t('postYourScore');

  String get nickname => _t('nickname');

  String get enterYourPlayerName => _t('enterYourPlayerName');

  String get post => _t('post');

  String get joinedLeaderboard => _t('joinedLeaderboard');

  String get performanceHistory => _t('performanceHistory');

  String get savedSnapshots => _t('savedSnapshots');

  String get scoreOverTime => _t('scoreOverTime');

  String get keepPlayingChart => _t('keepPlayingChart');

  String get playTime => _t('playTime');

  String get actions => _t('actions');

  String get bestBalance => _t('bestBalance');

  String get highScore => _t('highScore');

  String get customers => _t('customers');

  String get sales => _t('sales');

  String get demand => _t('demand');

  String get sellingPrice => _t('sellingPrice');

  String get estimatedProfit => _t('estimatedProfit');

  String get shift => _t('shift');

  String get shiftPreparation => _t('shiftPreparation');

  String get shiftOpen => _t('shiftOpen');

  String get rushHour => _t('rushHour');

  String get shiftClosing => _t('shiftClosing');

  String get currentEarnings => _t('currentEarnings');

  String get satisfaction => _t('satisfaction');

  String get nextRush => _t('nextRush');

  String get shiftSummary => _t('shiftSummary');

  String get revenue => _t('revenue');

  String get missedSales => _t('missedSales');

  String get stockRemaining => _t('stockRemaining');

  String get shiftXp => _t('shiftXp');

  String get continueShift => _t('continueShift');

  String get upgradeNow => _t('upgradeNow');

  String get shiftMission => _t('shiftMission');

  String get dailyMission => _t('dailyMission');

  String get progressionMission => _t('progressionMission');

  String get serveFiveCustomers => _t('serveFiveCustomers');

  String get keepCustomersHappy => _t('keepCustomersHappy');

  String get active => _t('active');

  String get claimed => _t('claimed');

  String get missionReward => _t('missionReward');

  String get claimMission => _t('claimMission');

  String get vipCustomer => _t('vipCustomer');

  String get fastCheckout => _t('fastCheckout');

  String get fastCheckoutBonus => _t('fastCheckoutBonus');

  String get claimBonus => _t('claimBonus');

  String get itemsStocked => _t('itemsStocked');

  String get upgradesCount => _t("upgradesCount");

  String get achievementUnlocked => _t('achievementUnlocked');

  String achievementTitle(String id) => _t('achievementTitle_$id');

  String achievementDescription(String id) => _t('achievementDescription_$id');

  String get levelLabel => _t('levelLabel');

  String get storeLevel => _t('storeLevel');

  String get coinsShort => _t('coinsShort');

  String get gemsShort => _t('gemsShort');

  String get lowStock => _t('lowStock');

  String get controlMode => _t('controlMode');

  String get directTouchInstruction => _t('directTouchInstruction');

  String get floatingJoystickInstruction => _t('floatingJoystickInstruction');

  String get leftHandedJoystickInstruction =>
      _t('leftHandedJoystickInstruction');

  String get directTouch => _t('directTouch');

  String get floatingJoystick => _t('floatingJoystick');

  String get leftHandedJoystick => _t('leftHandedJoystick');

  String get yourMarketAwaits => _t('yourMarketAwaits');

  String get openingYourStore => _t('openingYourStore');

  String get pocketSizedEmpire => _t('pocketSizedEmpire');

  String get welcomeToPoMarket => _t('welcomeToPoMarket');

  String get gotItNext => _t('gotItNext');

  String get keepShelvesFull => _t('keepShelvesFull');

  String get sellEarnGrow => _t('sellEarnGrow');

  String get startPlaying => _t('startPlaying');

  String get skip => _t('skip');

  String get tutorialSubtitle => _t('tutorialSubtitle');

  String get tutorialStep => _t('tutorialStep');

  String get moveAndCollect => _t('moveAndCollect');

  String get moveAndCollectDesc => _t('moveAndCollectDesc');

  String get keepShelvesFullDesc => _t('keepShelvesFullDesc');

  String get sellEarnGrowDesc => _t('sellEarnGrowDesc');

  // ---------------------------------------------------------------------------
  // Static lookup
  // ---------------------------------------------------------------------------

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  // ---------------------------------------------------------------------------
  // English
  // ---------------------------------------------------------------------------

  static const _english = <String, String>{
    'businessHubTitle': 'Business Hub',
    'businessHubSubtitle': 'Your progress, records, and rewards',
    'scoreLabel': 'SCORE',
    'achievementsTabLabel': 'ACHIEVEMENTS',
    'statsTabLabel': 'STATS',
    'leaderboardTabLabel': 'LEADERBOARD',
    'settingsTabLabel': 'SETTINGS',
    'market': 'Market',
    'upgrades': 'Upgrades',
    'staff': 'Staff',
    'departments': 'Departments',
    'inventory': 'Inventory',
    'quests': 'Quests',
    'achievements': 'Achievements',
    'shop': 'Shop',
    'settings': 'Settings',
    'more': 'More',
    'upgradeYourBusiness': 'Upgrade Your Business',
    'investToServe': 'Invest to serve more customers',
    'level': 'Level',
    'carryProducts': 'Carry {capacity} products',
    'capacity': 'Capacity',
    'profitPerSale': 'Profit per sale: {value}',
    'movementSpeed': 'Movement speed +{value}%',
    'serveCustomersFaster': 'Speeds checkout and tips',
    'keepShelvesFilled': 'Keep shelves filled smoothly',
    'buy': 'Buy',
    'affordable': 'Affordable',
    'notEnoughCoins': 'You need more coins for this upgrade',
    'upgradeTitlebag': 'Bigger Bag',
    'upgradeTitleshelf': 'Expanded Shelf',
    'upgradeTitleprice': 'Premium Products',
    'upgradeTitlespeed': 'Running Shoes',
    'upgradeTitlecheckout': 'Checkout Speed',
    'upgradeTitlerestock': 'Restock Flow',
    'questStockProducts': 'Stock {target} products on the shelf',
    'questCompleteSales': 'Complete {target} sales',
    'questBuyUpgrade': 'Buy a business upgrade',
    'questCompleteMoreSales': 'Complete {target} more sales',
    'staffManagement': 'Staff Management',
    'hire': 'Hire',
    'hired': 'Hired',
    'hireStaff': 'Hire Staff',
    'upgradeStaff': 'Upgrade Staff',
    'staffRoleCashier': 'Cashier',
    'staffRoleStocker': 'Stocker',
    'staffRoleCleaner': 'Cleaner',
    'staffRoleBaker': 'Baker',
    'staffRoleManager': 'Manager',
    'staffRoleCourier': 'Courier',
    'staffRolePromoter': 'Promoter',
    'staffSummaryCashier': 'Speeds checkout and tips',
    'staffSummaryStocker': 'Restocks shelves faster',
    'staffSummaryCleaner': 'Keeps satisfaction steady',
    'staffSummaryBaker': 'Bakes fresh goods faster',
    'staffSummaryManager': 'Boosts global efficiency',
    'staffSummaryCourier': 'Speeds up stock deliveries',
    'staffSummaryPromoter': 'Attracts more customers',
    'staffLocked': 'Staff feature locked',
    'staffUnlockRequirement': 'Unlock at store level 3',
    'staffNeedsCoins': 'You need {cost} coins to hire this worker',
    'staffAssignment': 'Assignment',
    'staffStatus': 'Status',
    'statusIdle': 'Idle',
    'statusServing': 'Serving',
    'statusStocking': 'Stocking',
    'statusWaitingStock': 'Waiting for stock',
    'statusWaitingShelf': 'Shelf is full',
    'statusCleaning': 'Cleaning',
    'statusBaking': 'Baking',
    'statusManaging': 'Managing',
    'statusDelivering': 'Delivering',
    'statusPromoting': 'Promoting',
    'assignmentCheckout': 'Checkout',
    'assignmentShelves': 'Shelves',
    'assignmentFloor': 'Market floor',
    'assignmentBakery': 'Bakery',
    'assignmentOffice': 'Office',
    'assignmentDelivery': 'Deliveries',
    'assignmentEntrance': 'Entrance',
    'serviceTime': '{value}s per customer',
    'teamOverview': 'Team Operations',
    'teamMembers': '{count} workers hired',
    'teamPower': 'Team power {power}',
    'addWorker': 'Add worker',
    'maxWorkers': 'Maximum team reached',
    'nextWorkerSlot': 'Next worker slot at level {level}',
    'roleUnlockAtLevel': 'Role unlocks at store level {level}',
    'workerRoute': 'Live route: storage → shelf',
    'departmentsTitle': 'Departments',
    'departmentOperations': 'Live Department Hub',
    'departmentOperationsSubtitle':
        'Every unlocked department appears on the market floor with its own stock, demand, and profit.',
    'departmentMilestones': 'Build your modern market',
    'activeDepartments': 'Active',
    'floorStock': 'Floor stock',
    'salesBoost': 'Value boost',
    'liveInStore': 'LIVE IN STORE',
    'warehouseStock': 'Warehouse',
    'profitPerItem': 'Value',
    'itemsSold': 'Sold',
    'upgradeDepartment': 'Upgrade',
    'prepareCrate': 'Prepare crate',
    'crateSelected': 'Crate selected',
    'orderCategoryStock': 'Order stock',
    'deliveryInTransit': 'Delivery on the way',
    'starterStockAdded': 'department opened with starter stock',
    'departmentUpgraded': 'department upgraded',
    'unlocked': 'Unlocked',
    'locked': 'Locked',
    'unlockAtLevel': 'Unlocks at level {level}',
    'unlockCost': 'Unlock cost: {cost} coins',
    'departmentGeneralGoods': 'General Goods',
    'departmentGeneralGoodsDesc': 'The foundation of your market.',
    'departmentBakery': 'Bakery',
    'departmentBakeryDesc': 'Fresh bread and pastries.',
    'departmentProduce': 'Produce',
    'departmentProduceDesc': 'Fresh fruits and vegetables.',
    'departmentRefrigerated': 'Refrigerated',
    'departmentRefrigeratedDesc': 'Cold storage for perishables.',
    'departmentBeauty': 'Beauty',
    'departmentBeautyDesc': 'Cosmetics and personal care.',
    'departmentElectronics': 'Electronics',
    'departmentElectronicsDesc': 'Gadgets and tech accessories.',
    'bakeryUnlocked': 'Bakery unlocked!',
    'bakeryUnlockedMessage':
        'Fresh bread and pastries are now available in your market.',
    'bakeryReady': 'Ready {current}/{capacity}',
    'bakeryBakingHint': 'The bakery is baking fresh pastries…',
    'bakeryCollectingHint': 'Collecting fresh pastries from the bakery',
    'bakeryBagFullHint': 'Bag full — take the pastries to the shelf',
    'bakeryLockedHint': 'The bakery unlocks at level {level}',
    'storageEmptyHint': 'Storage is empty — order stock below',
    'collectingStorageHint': 'Collecting products from storage',
    'bagFullHint': 'Bag full — take the products to the shelf',
    'bagEmptyHint': 'Your bag is empty',
    'shelfFullHint': 'The shelf is full',
    'stockingShelfHint': 'Stocking products on the shelf',
    'checkoutHint': 'Customers pay here',
    'inventoryTitle': 'Inventory',
    'carried': 'Carried',
    'shelfStock': 'Shelf Stock',
    'storage': 'Storage',
    'totalInventory': 'Total Inventory',
    'inventoryCapacity': 'Capacity',
    'pendingDeliveries': 'Pending Deliveries',
    'noPendingDeliveries': 'No pending deliveries',
    'placeOrder': 'Place Order',
    'fulfill': 'Fulfill',
    'emptyInventory': 'Your inventory is empty',
    'orderGeneralStock': 'Order 6 general products',
    'emergencyStock': 'Free emergency stock',
    'emergencyStockDesc':
        'Available only when your market has no stock and cannot place an order.',
    'deliveryReady': 'Delivery ready',
    'quickRestock': 'Order 6 stock · 20',
    'quickRestockPending': 'Stock delivery is on the way',
    'quickRestockOrdered': 'Stock ordered — delivery is on the way',
    'questsTitle': 'Quests',
    'activeQuest': 'Active Quest',
    'claimReward': 'Claim Reward',
    'questCompleted': 'Quest Completed!',
    'questInProgress': 'In Progress',
    'noActiveQuest': 'No active quest',
    'achievementsTitle': 'Achievements',
    'achievementTitle_first_sale': 'First Checkout',
    'achievementDescription_first_sale': 'Complete your first customer sale.',
    'achievementTitle_shelf_starter': 'Shelf Starter',
    'achievementDescription_shelf_starter':
        'Stock 25 products on your shelves.',
    'achievementTitle_bustling_market': 'Bustling Market',
    'achievementDescription_bustling_market': 'Serve 50 happy customers.',
    'achievementTitle_coin_club': 'Coin Club',
    'achievementDescription_coin_club':
        'Earn 1,000 coins across your business.',
    'achievementTitle_upgrade_pro': 'Upgrade Pro',
    'achievementDescription_upgrade_pro': 'Purchase 10 business upgrades.',
    'achievementTitle_growing_business': 'Growing Business',
    'achievementDescription_growing_business': 'Reach store level 5.',
    'achievementTitle_streak_starter': 'Streak Starter',
    'achievementDescription_streak_starter': 'Open PoMarket 3 days in a row.',
    'achievementTitle_market_mogul': 'Market Mogul',
    'achievementDescription_market_mogul': 'Hold a balance of 5,000 coins.',
    'badgesUnlocked': 'badges unlocked',
    'unlockedLabel': 'UNLOCKED',
    'bronze': 'Bronze',
    'silver': 'Silver',
    'gold': 'Gold',
    'platinum': 'Platinum',
    'noAchievementsYet': 'No achievements yet. Keep playing to earn badges!',
    'shopTitle': 'Shop',
    'rewardedBonus': 'Rewarded Bonus',
    'watchAndEarn': 'Watch & Earn',
    'freeBonus': 'Free Bonus',
    'freeBonusSubtitle': 'Watch ad • Choose reward',
    'rewardCenterTitle': 'Reward Center',
    'optionalAdDescription':
        'Watch an optional video and receive the selected reward after the video is completed.',
    'mobileFeaturePreview': 'Mobile feature preview',
    'watchAndReceive': 'Watch and receive',
    'rewardUnavailable': 'Unavailable',
    'rewardCooldown': 'Ready after {time}',
    'dailyLimitReached': 'Daily limit reached',
    'rewardPreviewUnavailable':
        'Rewarded ads are unavailable in this Web preview. No reward is granted.',
    'rewardDismissed':
        'No reward was granted because the video was not completed.',
    'rewardFailed': 'The optional video could not be completed.',
    'rewardClaimsToday': 'Rewards today',
    'rewardCoinsTitle': 'Coin boost',
    'rewardCoinsBenefit': '+{value} coins',
    'rewardOfflineTitle': 'Double offline earnings',
    'rewardOfflineBenefit': '{value} coins instead of {base}',
    'rewardEmergencyTitle': 'Emergency stock',
    'rewardEmergencyBenefit': '+{value} products',
    'starterOffers': 'Starter Offers',
    'coinPacks': 'Coin Packs',
    'gemPacks': 'Gem Packs',
    'emergencySupplies': 'Emergency Supplies',
    'permanentBenefits': 'Permanent Benefits',
    'removeAdsCategory': 'Remove Ads',
    'mobileStoreAvailability': 'Available in the mobile store version.',
    'noAds': 'No Ads',
    'oneTimePurchase': 'One-time purchase',
    'owned': 'Owned',
    'starterPack': 'Starter Pack',
    'starterPackDesc': '500 coins, 20 gems, and two upgrades',
    'coinPack': '1,000 Coin Pack',
    'coinPackDesc': 'Grow your business faster',
    'gemPack': '40 Gem Pack',
    'gemPackDesc': 'A small bundle of premium currency',
    'emergencySupplyPack': 'Emergency Supply Pack',
    'emergencySupplyPackDesc': 'Adds 12 general products to storage',
    'previewMode': 'Preview mode',
    'setupRequired': 'SETUP REQUIRED',
    'previewModeDesc':
        'Preview build — store items activate after they are created in the developer accounts.',
    'rewardedPreviewDesc':
        'Rewarded ads are unavailable in this preview build.',
    'purchaseComplete': 'Purchase complete — items added to your game',
    'productNotConfigured':
        'This product has not been configured in the store yet',
    'purchaseCancelled': 'Purchase cancelled',
    'purchaseFailed': 'Purchase could not be verified',
    'previewPrice': 'Preview · US\$0.99',
    'previewPrice2': 'Preview · US\$4.99',
    'previewPrice3': 'Preview · US\$9.99',
    'secureStorePurchases':
        'Secure purchases through the App Store or Google Play.',
    'settingsTitle': 'Settings',
    'language': 'Language',
    'sound': 'Sound',
    'soundEffects': 'Sound Effects',
    'soundEffectsDesc': 'Clicks, successes, and milestone cues',
    'reducedMotion': 'Reduced Motion',
    'reducedMotionDesc': 'Minimize animations and motion',
    'restorePurchases': 'Restore Purchases',
    'about': 'About',
    'version': 'Version',
    'autoSaveOn': 'Auto-Save Is On',
    'autoSaveDesc':
        'Progress, inventory, achievements, and stats are saved securely on this device.',
    'quickTutorial': 'Quick Tutorial',
    'replayTutorial': 'Replay the three-step beginner guide',
    'dailyStreak': 'Daily Streak',
    'days': 'days',
    'best': 'best',
    'resetProgress': 'Reset Progress',
    'resetConfirm':
        'This permanently removes coins, inventory, upgrades, achievements, stats, streaks, and local leaderboard entries from this device.',
    'cancel': 'CANCEL',
    'reset': 'RESET',
    'english': 'English',
    'hebrew': 'Hebrew',
    'arabic': 'Arabic',
    'systemDefault': 'System Default',
    'restorePurchasesSuccess': 'Purchases restored successfully',
    'restorePurchasesNone': 'No previous purchases found',
    'restorePurchasesUnavailable':
        'Restore purchases is not available in preview mode',
    'restorePurchasesDesc': 'Restore previous purchases',
    'replay': 'REPLAY',
    'yourMiniMarket': 'Your mini market',
    'muteSound': 'Mute sound',
    'unmuteSound': 'Unmute sound',
    'reward': 'REWARD',
    'loading': 'LOADING…',
    'unavailable': 'UNAVAILABLE',
    'retryIn': 'RETRY IN {seconds}s',
    'hub': 'HUB',
    'coinsEarned': 'You received {value} coins',
    'productStocked': 'Product stocked!',
    'saleCompleted': 'Sale! +{value} coins',
    'welcomeBack': 'Welcome Back!',
    'businessKeptEarning': 'Your business kept earning while you were away.',
    'collect': 'COLLECT',
    'double': 'DOUBLE ×2',
    'previewGrantsReward': 'Preview mode grants the reward without a real ad.',
    'dailyBonus': 'DAILY BONUS',
    'streak': 'STREAK!',
    'dayStreak': '{streak} DAY STREAK!',
    'comeBackTomorrow': 'Come back tomorrow to grow your reward.',
    'collectReward': 'COLLECT REWARD',
    'maxLevel': 'Max Level',
    'yourCurrentBusinessScore': 'YOUR CURRENT BUSINESS SCORE',
    'postScore': 'POST SCORE',
    'challenge': 'CHALLENGE',
    'localTop10': 'LOCAL TOP 10',
    'savedOnThisDevice': 'Saved on this device',
    'podiumWaiting': 'The podium is waiting for you.',
    'postYourScore': 'Post your current score to claim the first spot.',
    'nickname': 'Nickname',
    'enterYourPlayerName': 'Enter your player name',
    'post': 'POST SCORE',
    'joinedLeaderboard':
        '{nickname} joined the leaderboard with {score} points!',
    'performanceHistory': 'PERFORMANCE HISTORY',
    'savedSnapshots': 'saved snapshots · score over time',
    'scoreOverTime': 'score over time',
    'keepPlayingChart': 'Keep playing — your performance chart is building.',
    'playTime': 'PLAY TIME',
    'actions': 'ACTIONS',
    'bestBalance': 'BEST BALANCE',
    'highScore': 'HIGH SCORE',
    'customers': 'CUSTOMERS',
    'sales': 'SALES',
    'demand': 'Demand',
    'sellingPrice': 'Price',
    'estimatedProfit': 'Profit',
    'shift': 'SHIFT',
    'shiftPreparation': 'Preparation',
    'shiftOpen': 'Open',
    'rushHour': 'Rush hour',
    'shiftClosing': 'Closing soon',
    'currentEarnings': 'Earnings',
    'satisfaction': 'Satisfaction',
    'nextRush': 'Rush in {seconds}s',
    'shiftSummary': 'Shift {shift} complete',
    'revenue': 'Revenue',
    'missedSales': 'Missed sales',
    'stockRemaining': 'Stock remaining',
    'shiftXp': 'XP earned',
    'continueShift': 'Continue shift',
    'upgradeNow': 'Upgrade now',
    'shiftMission': 'Shift mission',
    'dailyMission': 'Daily mission',
    'progressionMission': 'Progression mission',
    'serveFiveCustomers': 'Serve five customers this shift',
    'keepCustomersHappy': 'Keep customers at 80% satisfaction',
    'active': 'Active',
    'claimed': 'Claimed',
    'missionReward': 'Reward',
    'claimMission': 'Claim mission',
    'vipCustomer': 'VIP customer in store',
    'fastCheckout': 'Fast checkout moment',
    'fastCheckoutBonus': 'Earn a small bonus at checkout',
    'claimBonus': 'Claim bonus',
    'itemsStocked': 'ITEMS STOCKED',
    'upgradesCount': 'UPGRADES',
    'achievementUnlocked': 'ACHIEVEMENT UNLOCKED',
    'levelLabel': 'LEVEL',
    'storeLevel': 'STORE LEVEL',
    'coinsShort': 'COINS',
    'gemsShort': 'GEMS',
    'lowStock': 'LOW STOCK',
    'controlMode': 'Control Mode',
    'directTouchInstruction': 'Tap or drag to move',
    'floatingJoystickInstruction': 'Drag the joystick to move',
    'leftHandedJoystickInstruction': 'Drag the left joystick to move',
    'directTouch': 'Direct Touch',
    'floatingJoystick': 'Floating Joystick',
    'leftHandedJoystick': 'Left-handed Joystick',
    'yourMarketAwaits': 'YOUR MARKET AWAITS',
    'openingYourStore': 'OPENING YOUR STORE',
    'pocketSizedEmpire': 'A POCKET-SIZED BUSINESS EMPIRE',
    'welcomeToPoMarket': 'WELCOME TO POMARKET',
    'gotItNext': 'GOT IT — NEXT',
    'keepShelvesFull': 'Keep Shelves Full',
    'sellEarnGrow': 'Sell, Earn & Grow',
    'startPlaying': 'START PLAYING',
    'skip': 'SKIP',
    'tutorialSubtitle': 'Your store opens in three quick steps',
    'tutorialStep': 'STEP {current} OF {total}',
    'moveAndCollect': 'Move & Collect',
    'moveAndCollectDesc':
        'Tap a destination or drag near your player. Visit STORAGE to collect products into your bag.',
    'keepShelvesFullDesc':
        'Carry products to the SHELF. Customers can only shop while products are available.',
    'sellEarnGrowDesc':
        'Serve customers at CHECKOUT, then use earnings for upgrades, staff, and new departments.',
  };

  // ---------------------------------------------------------------------------
  // Hebrew
  // ---------------------------------------------------------------------------

  static const _hebrew = <String, String>{
    'businessHubTitle': 'מרכז עסקי',
    'businessHubSubtitle': 'ההתקדמות, ההישגים והמתנות שלך',
    'scoreLabel': 'ניקוד',
    'achievementsTabLabel': 'הישגים',
    'statsTabLabel': 'סטטיסטיקות',
    'leaderboardTabLabel': 'טבלת הובעה',
    'settingsTabLabel': 'הגדרות',
    'market': 'שוק',
    'upgrades': 'שדרוגים',
    'staff': 'צוות',
    'departments': 'מחלקות',
    'inventory': 'מלאי',
    'quests': 'משימות',
    'achievements': 'הישגים',
    'shop': 'חנות',
    'settings': 'הגדרות',
    'more': 'עוד',
    'upgradeYourBusiness': 'שדרג את העסק שלך',
    'investToServe': 'השקע כדי לשרות יותר לקוחות',
    'level': 'רמה',
    'carryProducts': 'נושא {capacity} מוצרים',
    'capacity': 'תפוסת נשיאה',
    'profitPerSale': 'רווח למכירה: {value}',
    'movementSpeed': 'מהירות תנועה +{value}%',
    'serveCustomersFaster': 'מהיר בקופה וטיפים',
    'keepShelvesFilled': 'שומר מדפים מלאים בחלק',
    'buy': 'קנה',
    'affordable': 'ניתן להרשות',
    'notEnoughCoins': 'אין לך מספיק מטבעות לשדרוג זה',
    'upgradeTitlebag': 'תיק גדול יותר',
    'upgradeTitleshelf': 'מדף מורחב',
    'upgradeTitleprice': 'מוצרי פרימיום',
    'upgradeTitlespeed': 'נעלי ריצה',
    'upgradeTitlecheckout': 'מהירות קופה',
    'upgradeTitlerestock': 'זרימת מילוי',
    'questStockProducts': 'מלאו {target} מוצרים על המדף',
    'questCompleteSales': 'השלימו {target} מכירות',
    'questBuyUpgrade': 'קנו שדרוג עסקי',
    'questCompleteMoreSales': 'השלימו עוד {target} מכירות',
    'staffManagement': 'ניהול צוות',
    'hire': 'שכור',
    'hired': 'גויס',
    'hireStaff': 'שכור עובדים',
    'upgradeStaff': 'שדרג צוות',
    'staffRoleCashier': 'קופאי',
    'staffRoleStocker': 'סדרן מדפים',
    'staffRoleCleaner': 'מנקה',
    'staffRoleBaker': 'אופה',
    'staffRoleManager': 'מנהל',
    'staffRoleCourier': 'שליח',
    'staffRolePromoter': 'מקדם מכירות',
    'staffSummaryCashier': 'מזרז את השירות בקופה',
    'staffSummaryStocker': 'ממלא מדפים מהר יותר',
    'staffSummaryCleaner': 'שומר על שביעות רצון הלקוחות',
    'staffSummaryBaker': 'מייצר מאפים טריים מהר יותר',
    'staffSummaryManager': 'מגביר את יעילות החנות',
    'staffSummaryCourier': 'מקצר את זמן משלוחי המלאי',
    'staffSummaryPromoter': 'מושך יותר לקוחות לחנות',
    'staffLocked': 'תכונת צוות נעולה',
    'staffUnlockRequirement': 'פתח ברמת חנות 3',
    'staffNeedsCoins': 'צריך {cost} מטבעות כדי לגייס את העובד הזה',
    'staffAssignment': 'שיבוץ',
    'staffStatus': 'מצב',
    'statusIdle': 'פנוי',
    'statusServing': 'משרת לקוח',
    'statusStocking': 'מסדר מדפים',
    'statusWaitingStock': 'ממתין למלאי במחסן',
    'statusWaitingShelf': 'המדף מלא',
    'statusCleaning': 'מנקה',
    'statusBaking': 'אופה',
    'statusManaging': 'מנהל',
    'statusDelivering': 'מביא משלוח',
    'statusPromoting': 'מקדם את החנות',
    'assignmentCheckout': 'קופה',
    'assignmentShelves': 'מדפים',
    'assignmentFloor': 'רצפת החנות',
    'assignmentBakery': 'מאפייה',
    'assignmentOffice': 'משרד',
    'assignmentDelivery': 'משלוחים',
    'assignmentEntrance': 'כניסה',
    'serviceTime': '{value} שנ׳ ללקוח',
    'teamOverview': 'מרכז תפעול הצוות',
    'teamMembers': '{count} עובדים גויסו',
    'teamPower': 'עוצמת צוות {power}',
    'addWorker': 'גיוס עובד נוסף',
    'maxWorkers': 'הצוות בתפוסה מלאה',
    'nextWorkerSlot': 'מקום נוסף נפתח ברמה {level}',
    'roleUnlockAtLevel': 'התפקיד נפתח ברמת חנות {level}',
    'workerRoute': 'מסלול חי: מחסן → מדף',
    'departmentsTitle': 'מחלקות',
    'departmentOperations': 'מרכז מחלקות חי',
    'departmentOperationsSubtitle':
        'כל מחלקה שנפתחת מופיעה בחנות עם מלאי, ביקוש ורווח משלה.',
    'departmentMilestones': 'בונים סופרמרקט מודרני',
    'activeDepartments': 'פעילות',
    'floorStock': 'מלאי בחנות',
    'salesBoost': 'תוספת ערך',
    'liveInStore': 'פעיל בחנות',
    'warehouseStock': 'במחסן',
    'profitPerItem': 'ערך',
    'itemsSold': 'נמכרו',
    'upgradeDepartment': 'שדרוג',
    'prepareCrate': 'הכנת ארגז',
    'crateSelected': 'הארגז נבחר',
    'orderCategoryStock': 'הזמנת מלאי',
    'deliveryInTransit': 'המשלוח בדרך',
    'starterStockAdded': 'המחלקה נפתחה עם מלאי התחלתי',
    'departmentUpgraded': 'המחלקה שודרגה',
    'unlocked': 'פתוח',
    'locked': 'נעול',
    'unlockAtLevel': 'נפתח ברמה {level}',
    'unlockCost': 'עלות פתיחה: {cost} מטבעות',
    'departmentGeneralGoods': 'סחורה כללית',
    'departmentGeneralGoodsDesc': 'יסוד של החנות שלך.',
    'departmentBakery': 'מאפייה',
    'departmentBakeryDesc': 'לחם טרי ומאפים.',
    'departmentProduce': 'ירקות ופירות',
    'departmentProduceDesc': 'פירות וירקות טריים.',
    'departmentRefrigerated': 'מקורר',
    'departmentRefrigeratedDesc': 'אחסון קרור למוצרים רגישים.',
    'departmentBeauty': 'יופי',
    'departmentBeautyDesc': 'קוסמטיקה וטיפוח אישי.',
    'departmentElectronics': 'אלקטרוניקה',
    'departmentElectronicsDesc': 'גאדג\'טים ואקססוריאות טכנולוגיים.',
    'bakeryUnlocked': 'המאפייה נפתחה!',
    'bakeryUnlockedMessage': 'לחמים ומאפים טריים זמינים עכשיו בחנות.',
    'bakeryReady': 'מוכן {current}/{capacity}',
    'bakeryBakingHint': 'המאפייה אופה מאפים טריים…',
    'bakeryCollectingHint': 'אוספים מאפים טריים מהמאפייה',
    'bakeryBagFullHint': 'התיק מלא — קחו את המאפים למדף',
    'bakeryLockedHint': 'המאפייה נפתחת ברמה {level}',
    'storageEmptyHint': 'המחסן ריק — אפשר להזמין מלאי למטה',
    'collectingStorageHint': 'אוספים מוצרים מהמחסן',
    'bagFullHint': 'התיק מלא — קחו את המוצרים למדף',
    'bagEmptyHint': 'התיק ריק',
    'shelfFullHint': 'המדף מלא',
    'stockingShelfHint': 'מסדרים מוצרים על המדף',
    'checkoutHint': 'הלקוחות משלמים כאן',
    'inventoryTitle': 'מלאי',
    'carried': 'נשיאה',
    'shelfStock': 'מלאי במדף',
    'storage': 'מחסן',
    'totalInventory': 'סה"כ מלאי',
    'inventoryCapacity': 'תפוסת מלאי',
    'pendingDeliveries': 'משלוחים בהמתנה',
    'noPendingDeliveries': 'אין משלוחים בהמתנה',
    'placeOrder': 'בצע הזמנה',
    'fulfill': 'בצע',
    'emptyInventory': 'המלאי שלך ריק',
    'orderGeneralStock': 'הזמנת 6 מוצרים כלליים',
    'emergencyStock': 'מלאי חירום חינם',
    'emergencyStockDesc': 'זמין רק כשהחנות ללא מלאי ואי אפשר לבצע הזמנה.',
    'deliveryReady': 'המשלוח מוכן',
    'quickRestock': 'הזמנת 6 מוצרים · 20',
    'quickRestockPending': 'משלוח המלאי בדרך',
    'quickRestockOrdered': 'המלאי הוזמן — המשלוח בדרך',
    'questsTitle': 'משימות',
    'activeQuest': 'משימה פעילה',
    'claimReward': 'קבל תגמול',
    'questCompleted': 'משימה הושלמה!',
    'questInProgress': 'בתהליך',
    'noActiveQuest': 'אין משימה פעילה',
    'achievementsTitle': 'הישגים',
    'achievementTitle_first_sale': 'קופה ראשונה',
    'achievementDescription_first_sale': 'השלם מכירה ראשונה ללקוח.',
    'achievementTitle_shelf_starter': 'מדף ראשון',
    'achievementDescription_shelf_starter': 'הנח 25 מוצרים על המדפים.',
    'achievementTitle_bustling_market': 'שוק שוקק',
    'achievementDescription_bustling_market': 'שרת 50 לקוחות מרוצים.',
    'achievementTitle_coin_club': 'מועדון המטבעות',
    'achievementDescription_coin_club': 'צבור 1,000 מטבעות בעסק.',
    'achievementTitle_upgrade_pro': 'מומחה שדרוגים',
    'achievementDescription_upgrade_pro': 'רכוש 10 שדרוגים עסקיים.',
    'achievementTitle_growing_business': 'עסק בצמיחה',
    'achievementDescription_growing_business': 'הגע לרמת חנות 5.',
    'achievementTitle_streak_starter': 'רצף ראשון',
    'achievementDescription_streak_starter':
        'פתח את PoMarket במשך 3 ימים ברצף.',
    'achievementTitle_market_mogul': 'איל השוק',
    'achievementDescription_market_mogul': 'החזק יתרה של 5,000 מטבעות.',
    'badgesUnlocked': 'הישגים נפתחו',
    'unlockedLabel': 'נפתח',
    'bronze': 'ארד',
    'silver': 'כסף',
    'gold': 'זהב',
    'platinum': 'פלטינה',
    'noAchievementsYet': 'אין הישגים עדיין. המשך לשחק כדי לזכות בתגמולים!',
    'shopTitle': 'חנות',
    'rewardedBonus': 'בונוס מתגמול',
    'watchAndEarn': 'צפה והרוון',
    'freeBonus': 'בונוס חינם',
    'freeBonusSubtitle': 'צפו בפרסומת • בחרו פרס',
    'rewardCenterTitle': 'מרכז הפרסים',
    'optionalAdDescription':
        'צפו בסרטון אופציונלי וקבלו את הפרס שבחרתם לאחר השלמת הצפייה.',
    'mobileFeaturePreview': 'תצוגה מקדימה של תכונה בנייד',
    'watchAndReceive': 'צפו וקבלו',
    'rewardUnavailable': 'לא זמין',
    'rewardCooldown': 'זמין בעוד {time}',
    'dailyLimitReached': 'הגעתם למגבלה היומית',
    'rewardPreviewUnavailable':
        'פרסומות מתגמלות אינן זמינות בתצוגת Web זו. לא ניתן פרס.',
    'rewardDismissed': 'לא ניתן פרס כי הצפייה לא הושלמה.',
    'rewardFailed': 'לא ניתן היה להשלים את הסרטון האופציונלי.',
    'rewardClaimsToday': 'פרסים היום',
    'rewardCoinsTitle': 'חיזוק מטבעות',
    'rewardCoinsBenefit': '+{value} מטבעות',
    'rewardOfflineTitle': 'הכפלת רווחים שהצטברו',
    'rewardOfflineBenefit': '{value} מטבעות במקום {base}',
    'rewardEmergencyTitle': 'מלאי חירום',
    'rewardEmergencyBenefit': '+{value} מוצרים',
    'starterOffers': 'הצעות פתיחה',
    'coinPacks': 'חבילות מטבעות',
    'gemPacks': 'חבילות אבני חן',
    'emergencySupplies': 'אספקת חירום',
    'permanentBenefits': 'הטבות קבועות',
    'removeAdsCategory': 'הסרת פרסומות',
    'mobileStoreAvailability': 'זמין בגרסת חנות המובייל.',
    'noAds': 'בלי פרסומות',
    'oneTimePurchase': 'רכישה חד פעמית',
    'owned': 'בבעלות',
    'starterPack': 'חבילת פתיחה',
    'starterPackDesc': '500 מטבעות, 20 חדושים, ושני שדרוגים',
    'coinPack': 'חבילת 1,000 מטבעות',
    'coinPackDesc': 'גדל את העסק שלך מהר יותר',
    'gemPack': 'חבילת 40 אבני חן',
    'gemPackDesc': 'חבילה קטנה של מטבע פרימיום',
    'emergencySupplyPack': 'חבילת אספקת חירום',
    'emergencySupplyPackDesc': 'מוסיפה 12 מוצרים כלליים למחסן',
    'previewMode': 'מצב תצוגה מקדימה',
    'setupRequired': 'נדרש הגדרה',
    'previewModeDesc':
        'גרסת תצוגה מקדימה — פריטי חנות נפתחים לאחר יצירתם בחשבונות המפתחים.',
    'rewardedPreviewDesc': 'פרסומות מתגמלות אינן זמינות בגרסת התצוגה המקדימה.',
    'purchaseComplete': 'הרכישה הושלמה — פריטים נוספו למשחק שלך',
    'productNotConfigured': 'המוצר הזה לא הוגדר בחנות עדיין',
    'purchaseCancelled': 'הרכישה בוטלה',
    'purchaseFailed': 'לא ניתן היה לאמת את הרכישה',
    'previewPrice': 'תצוגה מקדימה · US\$0.99',
    'previewPrice2': 'תצוגה מקדימה · US\$4.99',
    'previewPrice3': 'תצוגה מקדימה · US\$9.99',
    'secureStorePurchases': 'רכישות מאובטחות דרך App Store או Google Play.',
    'settingsTitle': 'הגדרות',
    'language': 'שפה',
    'sound': 'צליל',
    'soundEffects': 'אפקטי צליל',
    'soundEffectsDesc': 'לחיצות, הצלחות ואינדיקטורים של שלב',
    'reducedMotion': 'תנועה מצומצמת',
    'reducedMotionDesc': 'מזעיר אנימציות ותנועה',
    'restorePurchases': 'שחזר רכישות',
    'about': 'אודות',
    'version': 'גרסה',
    'autoSaveOn': 'שמירה אוטומטית פעילה',
    'autoSaveDesc':
        'התקדמות, מלאי, הישגים וסטטיסטיקות נשמרים באופן מאובטח במכשיר זה.',
    'quickTutorial': 'הדרכה מהירה',
    'replayTutorial': 'שחזר את מדריך ההתחלה של שלושה שלבים',
    'dailyStreak': 'רציפות יומית',
    'days': 'ימים',
    'best': 'הכי גבוה',
    'resetProgress': 'איפוס התקדמות',
    'resetConfirm':
        'פעולה זו מסירה לצמיתות מטבעות, מלאי, שדרוגים, הישגים, סטטיסטיקות, רציפות וערכי טבלת הובעה מקומית מהמכשיר זה.',
    'cancel': 'ביטול',
    'reset': 'איפוס',
    'english': 'אנגלית',
    'hebrew': 'עברית',
    'arabic': 'ערבית',
    'systemDefault': 'ברירת מערכת',
    'restorePurchasesSuccess': 'הרכישות שוחזרו בהצלחה',
    'restorePurchasesNone': 'לא נמצאו רכישות קודמות',
    'restorePurchasesUnavailable': 'שחזור רכישות אינו זמין במצב תצוגה מקדימה',
    'restorePurchasesDesc': 'שחזור רכישות קודמות',
    'replay': 'הפעל שוב',
    'yourMiniMarket': 'החנות הקטנה שלך',
    'muteSound': 'אל צליל',
    'unmuteSound': 'הפעל צליל',
    'reward': 'תגמול',
    'loading': 'טוען…',
    'unavailable': 'לא זמין',
    'retryIn': 'נסה שוב בעוד {seconds} שנ׳',
    'hub': 'מרכז',
    'coinsEarned': 'קיבלת {value} מטבעות',
    'productStocked': 'מוצר נמוסף!',
    'saleCompleted': 'מכירה! +{value} מטבעות',
    'welcomeBack': 'ברוכים שוב!',
    'businessKeptEarning': 'העסק שלך המשיך לרווח תוך כדי שהייתך מרוחק.',
    'collect': 'אסוף',
    'double': 'פי שניים',
    'previewGrantsReward':
        'מצב תצוגה מקדימה מעניק את התגמול מבלי להציג מודעיה אמיתית.',
    'dailyBonus': 'בונוס יומי',
    'streak': 'רציפות!',
    'dayStreak': '{streak} יום רצוף!',
    'comeBackTomorrow': 'חוזרי מחר כדי לגדול את התגמול שלך.',
    'collectReward': 'אסוף תגמול',
    'maxLevel': 'רמה מרבית',
    'yourCurrentBusinessScore': 'הניקוד העסקי הנוכחי שלך',
    'postScore': 'פרסם ניקוד',
    'challenge': 'אתגר',
    'localTop10': 'העשרה המקומית',
    'savedOnThisDevice': 'נשמר במכשיר זה',
    'podiumWaiting': 'הפדיום מחכה לך.',
    'postYourScore': 'פרוס את הניקוד הנוכחי שלך כדי לזכות במקום הראשון.',
    'nickname': 'שם משתמש',
    'enterYourPlayerName': 'הכנס את שם השחקן שלך',
    'post': 'פרסם ניקוד',
    'joinedLeaderboard': '{nickname} הצטרף לטבלת הובעה עם {score} נקודות!',
    'performanceHistory': 'היסטוריית ביצועים',
    'savedSnapshots': 'צפיות נשמרו · ניקוד לאורך זמן',
    'scoreOverTime': 'ניקוד לאורך זמן',
    'keepPlayingChart': 'המשך לשחק — גרף הביצועים שלך בונה עצמו.',
    'playTime': 'זמן משחק',
    'actions': 'פעולות',
    'bestBalance': 'מאזן מרבי',
    'highScore': 'ניקוד גבוה',
    'customers': 'לקוחות',
    'sales': 'מכירות',
    'demand': 'ביקוש',
    'sellingPrice': 'מחיר',
    'estimatedProfit': 'רווח',
    'shift': 'משמרת',
    'shiftPreparation': 'הכנה',
    'shiftOpen': 'פתוחה',
    'rushHour': 'שעת עומס',
    'shiftClosing': 'נסגרת בקרוב',
    'currentEarnings': 'הכנסות',
    'satisfaction': 'שביעות רצון',
    'nextRush': 'עומס בעוד {seconds} שניות',
    'shiftSummary': 'משמרת {shift} הסתיימה',
    'revenue': 'הכנסות',
    'missedSales': 'מכירות שהוחמצו',
    'stockRemaining': 'מלאי שנותר',
    'shiftXp': 'ניסיון שנצבר',
    'continueShift': 'המשך משמרת',
    'upgradeNow': 'שדרג עכשיו',
    'shiftMission': 'משימת משמרת',
    'dailyMission': 'משימה יומית',
    'progressionMission': 'משימת התקדמות',
    'serveFiveCustomers': 'שרת חמישה לקוחות במשמרת',
    'keepCustomersHappy': 'שמור על 80% שביעות רצון',
    'active': 'פעילה',
    'claimed': 'נאספה',
    'missionReward': 'פרס',
    'claimMission': 'אסוף משימה',
    'vipCustomer': 'לקוח VIP בחנות',
    'fastCheckout': 'רגע קופה מהירה',
    'fastCheckoutBonus': 'קבל בונוס קטן בקופה',
    'claimBonus': 'אסוף בונוס',
    'itemsStocked': 'פריטים נמוסים',
    'upgradesCount': 'שדרוגים',
    'achievementUnlocked': 'הישג נפתח',
    'levelLabel': 'רמה',
    'storeLevel': 'רמת חנות',
    'coinsShort': 'מטבעות',
    'gemsShort': 'אבנים',
    'lowStock': 'מלאי נמוך',
    'controlMode': 'מצב שליטה',
    'directTouchInstruction': 'לחצו או גררו כדי לזוז',
    'floatingJoystickInstruction': 'גררו את הג\'ויסטיק כדי לזוז',
    'leftHandedJoystickInstruction': 'גררו את הג\'ויסטיק השמאלי כדי לזוז',
    'directTouch': 'מגע ישיר',
    'floatingJoystick': 'ג\'ויסטיק צף',
    'leftHandedJoystick': 'ג\'ויסטיק שמאלי',
    'yourMarketAwaits': 'החנות שלך מחכה לך',
    'openingYourStore': 'פותח את החנות שלך',
    'pocketSizedEmpire': 'אימפריה עסקית בגודל כיס',
    'welcomeToPoMarket': 'ברוכים לPoMarket',
    'gotItNext': 'הבנתי — הבא',
    'keepShelvesFull': 'שמור מדפים מלאים',
    'sellEarnGrow': 'מכור, רווה, גדול',
    'startPlaying': 'התחל לשחק',
    'skip': 'דלג',
    'tutorialSubtitle': 'החנות נפתחת בשלושה צעדים קצרים',
    'tutorialStep': 'שלב {current} מתוך {total}',
    'moveAndCollect': 'תנועה ואיסוף',
    'moveAndCollectDesc':
        'לחצו על יעד או גררו ליד השחקן. הגיעו למחסן כדי לאסוף מוצרים לתיק.',
    'keepShelvesFullDesc':
        'קחו מוצרים למדף. לקוחות יכולים לקנות רק כשיש מוצרים זמינים.',
    'sellEarnGrowDesc':
        'שרתו לקוחות בקופה והשקיעו את ההכנסות בשדרוגים, צוות ומחלקות.',
  };

  // ---------------------------------------------------------------------------
  // Arabic
  // ---------------------------------------------------------------------------

  static const _arabic = <String, String>{
    'businessHubTitle': 'المركز التجاري',
    'businessHubSubtitle': 'تقدمك وسجلاتك ومكافآتك',
    'scoreLabel': 'النتيجة',
    'achievementsTabLabel': 'الإنجازات',
    'statsTabLabel': 'الإحصائيات',
    'leaderboardTabLabel': 'الترتيب',
    'settingsTabLabel': 'الإعدادات',
    'market': 'السوق',
    'upgrades': 'التحديثات',
    'staff': 'الموظفون',
    'departments': 'الأقسام',
    'inventory': 'المخزون',
    'quests': 'المهام',
    'achievements': 'الإنجازات',
    'shop': 'المتجر',
    'settings': 'الإعدادات',
    'more': 'المزيد',
    'upgradeYourBusiness': 'حسّن عملك',
    'investToServe': 'استثمر لخدمة المزيد من العملاء',
    'level': 'المستوى',
    'carryProducts': 'حمل {capacity} منتجات',
    'capacity': 'السعة',
    'profitPerSale': 'الربح لكل بيع: {value}',
    'movementSpeed': 'سرعة الحركة +{value}%',
    'serveCustomersFaster': 'يسرع الخدمة ويضيف تبريعات',
    'keepShelvesFilled': 'حافظ على الأرفف مملوءة بسلاسة',
    'buy': 'اشترِ',
    'affordable': 'متوفر',
    'notEnoughCoins': 'تحتاج المزيد من العملات لهذا التحديث',
    'upgradeTitlebag': 'حقيبة أكبر',
    'upgradeTitleshelf': 'رف موسع',
    'upgradeTitleprice': 'منتجات مميزة',
    'upgradeTitlespeed': 'حذاء جري',
    'upgradeTitlecheckout': 'سرعة الدفع',
    'upgradeTitlerestock': 'تدفق إعادة التعبئة',
    'questStockProducts': 'ضع {target} منتجات على الرف',
    'questCompleteSales': 'أكمل {target} مبيعات',
    'questBuyUpgrade': 'اشترِ ترقية للعمل',
    'questCompleteMoreSales': 'أكمل {target} مبيعات إضافية',
    'staffManagement': 'إدارة الموظفين',
    'hire': 'وظّف',
    'hired': 'موظف',
    'hireStaff': 'توظيف موظفين',
    'upgradeStaff': 'تطوير الموظفين',
    'staffRoleCashier': 'أمين صندوق',
    'staffRoleStocker': 'معبئ الأرفف',
    'staffRoleCleaner': 'عامل نظافة',
    'staffRoleBaker': 'خباز',
    'staffRoleManager': 'مدير',
    'staffRoleCourier': 'مندوب توصيل',
    'staffRolePromoter': 'مسوق',
    'staffSummaryCashier': 'يسرع الخدمة ويضيف تبريعات',
    'staffSummaryStocker': 'يعيد ملء الأرفف بسرعة',
    'staffSummaryCleaner': 'يحافظ على رضا العملاء',
    'staffSummaryBaker': 'يخبز المنتجات الطازجة بسرعة أكبر',
    'staffSummaryManager': 'يعزز الكفاءة العامة',
    'staffSummaryCourier': 'يسرع شحنات المخزون',
    'staffSummaryPromoter': 'يجذب المزيد من العملاء',
    'staffLocked': 'ميزة الموظفين مقفلة',
    'staffUnlockRequirement': 'افتح عند مستوى المتجر 3',
    'staffNeedsCoins': 'تحتاج إلى {cost} عملات لتوظيف هذا العامل',
    'staffAssignment': 'المهمة',
    'staffStatus': 'الحالة',
    'statusIdle': 'متاح',
    'statusServing': 'يخدم',
    'statusStocking': 'يرتب الأرفف',
    'statusWaitingStock': 'ينتظر المخزون',
    'statusWaitingShelf': 'الرف ممتلئ',
    'statusCleaning': 'ينظف',
    'statusBaking': 'يخبز',
    'statusManaging': 'يدير',
    'statusDelivering': 'يوصل',
    'statusPromoting': 'يسوق',
    'assignmentCheckout': 'صندوق الدفع',
    'assignmentShelves': 'الرفوف',
    'assignmentFloor': 'أرضية المتجر',
    'assignmentBakery': 'المخبز',
    'assignmentOffice': 'المكتب',
    'assignmentDelivery': 'الشحنات',
    'assignmentEntrance': 'المدخل',
    'serviceTime': '{value} ث لكل عميل',
    'teamOverview': 'مركز عمليات الفريق',
    'teamMembers': 'تم توظيف {count} عامل',
    'teamPower': 'قوة الفريق {power}',
    'addWorker': 'إضافة عامل',
    'maxWorkers': 'اكتمل الفريق',
    'nextWorkerSlot': 'مكان عامل جديد عند المستوى {level}',
    'roleUnlockAtLevel': 'يفتح الدور عند مستوى المتجر {level}',
    'workerRoute': 'مسار مباشر: المخزن → الرف',
    'departmentsTitle': 'الأقسام',
    'departmentOperations': 'مركز الأقسام المباشر',
    'departmentOperationsSubtitle':
        'كل قسم مفتوح يظهر داخل المتجر بمخزونه وطلبه وربحه الخاص.',
    'departmentMilestones': 'ابنِ سوقك الحديث',
    'activeDepartments': 'نشطة',
    'floorStock': 'مخزون المتجر',
    'salesBoost': 'زيادة القيمة',
    'liveInStore': 'نشط في المتجر',
    'warehouseStock': 'المخزن',
    'profitPerItem': 'القيمة',
    'itemsSold': 'المبيعات',
    'upgradeDepartment': 'ترقية',
    'prepareCrate': 'جهّز الصندوق',
    'crateSelected': 'تم اختيار الصندوق',
    'orderCategoryStock': 'طلب مخزون',
    'deliveryInTransit': 'الشحنة في الطريق',
    'starterStockAdded': 'تم فتح القسم مع مخزون ابتدائي',
    'departmentUpgraded': 'تمت ترقية القسم',
    'unlocked': 'مفتوح',
    'locked': 'مقفل',
    'unlockAtLevel': 'يفتح عند المستوى {level}',
    'unlockCost': 'تكلفة الفتح: {cost} عملات',
    'departmentGeneralGoods': 'بضائع عامة',
    'departmentGeneralGoodsDesc': 'أساس متجرك.',
    'departmentBakery': 'مخبز',
    'departmentBakeryDesc': 'خبز طازج ومعجنات.',
    'departmentProduce': 'منتجات نباتية',
    'departmentProduceDesc': 'فواكه وخضار طازجة.',
    'departmentRefrigerated': 'مبرد',
    'departmentRefrigeratedDesc': 'تخزين بارد للمنتجات الحساسة.',
    'departmentBeauty': 'الجمال',
    'departmentBeautyDesc': 'تجميل وعناية شخصية.',
    'departmentElectronics': 'إلكترونيات',
    'departmentElectronicsDesc': 'أجهزة وملحقات تكنولوجية.',
    'bakeryUnlocked': 'تم فتح المخبز!',
    'bakeryUnlockedMessage':
        'أصبح الخبز والمعجنات الطازجة متاحة الآن في متجرك.',
    'bakeryReady': 'جاهز {current}/{capacity}',
    'bakeryBakingHint': 'المخبز يخبز معجنات طازجة…',
    'bakeryCollectingHint': 'يتم جمع المعجنات الطازجة من المخبز',
    'bakeryBagFullHint': 'الحقيبة ممتلئة — انقل المعجنات إلى الرف',
    'bakeryLockedHint': 'يفتح المخبز عند المستوى {level}',
    'storageEmptyHint': 'المخزن فارغ — اطلب مخزونًا من الأسفل',
    'collectingStorageHint': 'يتم جمع المنتجات من المخزن',
    'bagFullHint': 'الحقيبة ممتلئة — انقل المنتجات إلى الرف',
    'bagEmptyHint': 'حقيبتك فارغة',
    'shelfFullHint': 'الرف ممتلئ',
    'stockingShelfHint': 'يتم ترتيب المنتجات على الرف',
    'checkoutHint': 'يدفع العملاء هنا',
    'inventoryTitle': 'المخزون',
    'carried': 'الحمل',
    'shelfStock': 'مخزون الأرفف',
    'storage': 'المخزن',
    'totalInventory': 'إجمالي المخزون',
    'inventoryCapacity': 'سعة المخزون',
    'pendingDeliveries': 'شحنات معلقة',
    'noPendingDeliveries': 'لا توجد شحنات معلقة',
    'placeOrder': 'إرسال طلب',
    'fulfill': 'تنفيذ',
    'emptyInventory': 'مخزونك فارغ',
    'orderGeneralStock': 'اطلب 6 منتجات عامة',
    'emergencyStock': 'مخزون طوارئ مجاني',
    'emergencyStockDesc': 'متاح فقط عندما لا يوجد مخزون ولا يمكن تقديم طلب.',
    'deliveryReady': 'الشحنة جاهزة',
    'quickRestock': 'اطلب 6 منتجات · 20',
    'quickRestockPending': 'شحنة المخزون في الطريق',
    'quickRestockOrdered': 'تم طلب المخزون — الشحنة في الطريق',
    'questsTitle': 'المهام',
    'activeQuest': 'المهمة النشطة',
    'claimReward': 'استلام المكافأة',
    'questCompleted': 'المهمة مكتملة!',
    'questInProgress': 'قيد التقدم',
    'noActiveQuest': 'لا توجد مهمة نشطة',
    'achievementsTitle': 'الإنجازات',
    'achievementTitle_first_sale': 'أول عملية بيع',
    'achievementDescription_first_sale': 'أكمل أول عملية بيع لعميل.',
    'achievementTitle_shelf_starter': 'رف البداية',
    'achievementDescription_shelf_starter': 'ضع 25 منتجاً على الرفوف.',
    'achievementTitle_bustling_market': 'سوق نابض',
    'achievementDescription_bustling_market': 'اخدم 50 عميلاً سعيداً.',
    'achievementTitle_coin_club': 'نادي العملات',
    'achievementDescription_coin_club': 'اكسب 1,000 عملة في متجرك.',
    'achievementTitle_upgrade_pro': 'محترف التطوير',
    'achievementDescription_upgrade_pro': 'اشترِ 10 ترقيات للمتجر.',
    'achievementTitle_growing_business': 'متجر نامٍ',
    'achievementDescription_growing_business': 'صل إلى مستوى المتجر 5.',
    'achievementTitle_streak_starter': 'بداية الاستمرارية',
    'achievementDescription_streak_starter':
        'افتح PoMarket ثلاثة أيام متتالية.',
    'achievementTitle_market_mogul': 'قطب السوق',
    'achievementDescription_market_mogul': 'احتفظ برصيد قدره 5,000 عملة.',
    'badgesUnlocked': 'شارات مفتوحة',
    'unlockedLabel': 'مفتوح',
    'bronze': 'برونزي',
    'silver': 'فضي',
    'gold': 'ذهبي',
    'platinum': 'بلاتيني',
    'noAchievementsYet':
        'لا توجد إنجازات بعد. استمر في اللعب للحصول على شارات!',
    'shopTitle': 'المتجر',
    'rewardedBonus': 'مكافأة مكافأة',
    'watchAndEarn': 'شاهد واكسب',
    'freeBonus': 'مكافأة مجانية',
    'freeBonusSubtitle': 'شاهد إعلانًا • اختر مكافأة',
    'rewardCenterTitle': 'مركز المكافآت',
    'optionalAdDescription':
        'شاهد فيديو اختياريًا واحصل على المكافأة التي اخترتها بعد إكمال المشاهدة.',
    'mobileFeaturePreview': 'معاينة ميزة الهاتف المحمول',
    'watchAndReceive': 'شاهد واحصل',
    'rewardUnavailable': 'غير متاح',
    'rewardCooldown': 'متاح بعد {time}',
    'dailyLimitReached': 'تم بلوغ الحد اليومي',
    'rewardPreviewUnavailable':
        'الإعلانات بمكافأة غير متاحة في معاينة الويب. لن تُمنح مكافأة.',
    'rewardDismissed': 'لم تُمنح مكافأة لأن المشاهدة لم تكتمل.',
    'rewardFailed': 'تعذر إكمال الفيديو الاختياري.',
    'rewardClaimsToday': 'المكافآت اليوم',
    'rewardCoinsTitle': 'تعزيز العملات',
    'rewardCoinsBenefit': '+{value} عملة',
    'rewardOfflineTitle': 'مضاعفة الأرباح غير المتصلة',
    'rewardOfflineBenefit': '{value} عملة بدلًا من {base}',
    'rewardEmergencyTitle': 'مخزون الطوارئ',
    'rewardEmergencyBenefit': '+{value} منتجات',
    'starterOffers': 'عروض البداية',
    'coinPacks': 'حزم العملات',
    'gemPacks': 'حزم الجواهر',
    'emergencySupplies': 'إمدادات الطوارئ',
    'permanentBenefits': 'مزايا دائمة',
    'removeAdsCategory': 'إزالة الإعلانات',
    'mobileStoreAvailability': 'متاح في إصدار متجر الهاتف المحمول.',
    'noAds': 'بدون إعلانات',
    'oneTimePurchase': 'شراء مرة واحدة',
    'owned': 'مملوك',
    'starterPack': 'حزمة البدء',
    'starterPackDesc': '500 عملات، 20 جواهر، وترقيتين',
    'coinPack': 'حزمة 1,000 عملة',
    'coinPackDesc': 'كنمو عملك بشكل أسرع',
    'gemPack': 'حزمة 40 جوهرة',
    'gemPackDesc': 'حزمة صغيرة من العملة المميزة',
    'emergencySupplyPack': 'حزمة إمدادات الطوارئ',
    'emergencySupplyPackDesc': 'تضيف 12 منتجًا عامًا إلى المخزن',
    'previewMode': 'وضع المعاينة',
    'setupRequired': 'مطلوب إعداد',
    'previewModeDesc':
        'إصدار معاينة — سلع المتجر تصبح نشطة بعد إنشائها في حسابات المطورين.',
    'rewardedPreviewDesc': 'إعلانات المكافآت غير متاحة في إصدار المعاينة.',
    'purchaseComplete': 'اكتملت العملية — تمت إضافة العناصر إلى لعبتك',
    'productNotConfigured': 'هذا المنتج لم يتم تكوينه في المتجر بعد',
    'purchaseCancelled': 'تم إلغاء الشراء',
    'purchaseFailed': 'تعذر التحقق من عملية الشراء',
    'previewPrice': 'معاينة · US\$0.99',
    'previewPrice2': 'معاينة · US\$4.99',
    'previewPrice3': 'معاينة · US\$9.99',
    'secureStorePurchases': 'مشتريات آمنة عبر App Store أو Google Play.',
    'settingsTitle': 'الإعدادات',
    'language': 'اللغة',
    'sound': 'الصوت',
    'soundEffects': 'مؤثرات الصوت',
    'soundEffectsDesc': 'نقرات، نجاحات، وإشارات المرحلة',
    'reducedMotion': 'حركة مقلوصة',
    'reducedMotionDesc': 'تقليل الرسوم المتحركة والحركة',
    'restorePurchases': 'استعادة المشتريات',
    'about': 'عن التطبيق',
    'version': 'الإصدار',
    'autoSaveOn': 'الحفظ التلقائي مفعل',
    'autoSaveDesc':
        'يتم حفظ التقدم، المخزون، الإنجازات، والإحصائيات بأمان على هذا الجهاز.',
    'quickTutorial': 'برنامج تعليمي سريع',
    'replayTutorial': 'إعادة تشغيل دليل المبتدئ ثلاث خطوات',
    'dailyStreak': 'الاستمرارية اليومية',
    'days': 'أيام',
    'best': 'أفضل',
    'resetProgress': 'إعادة تعيين التقدم',
    'resetConfirm':
        'يقوم هذا بإزالة بشكل دائم العملات، المخزون، التحديثات، الإنجازات، الإحصائيات، الاستمرارية، وإدخالات لوحة الصدارة المحلية من هذا الجهاز.',
    'cancel': 'إلغاء',
    'reset': 'إعادة تعيين',
    'english': 'الإنجليزية',
    'hebrew': 'العبرية',
    'arabic': 'العربية',
    'systemDefault': 'افتراضي النظام',
    'restorePurchasesSuccess': 'تم استعادة المشتريات بنجاح',
    'restorePurchasesNone': 'لم يتم العثور على مشتريات سابقة',
    'restorePurchasesUnavailable':
        'استعادة المشتريات غير متاحة في وضع المعاينة',
    'restorePurchasesDesc': 'استعادة المشتريات السابقة',
    'replay': 'إعادة',
    'yourMiniMarket': 'متجرك الصغير',
    'muteSound': 'كتم الصوت',
    'unmuteSound': 'إلغاء كتم الصوت',
    'reward': 'مكافأة',
    'loading': 'جارٍ التحميل…',
    'unavailable': 'غير متاح',
    'retryIn': 'أعد المحاولة خلال {seconds} ث',
    'hub': 'المركز',
    'coinsEarned': 'لقد تلقيت {value} عملات',
    'productStocked': 'تم تعبئة المنتج!',
    'saleCompleted': 'بيع! +{value} عملات',
    'welcomeBack': 'مرحبا بعودتك!',
    'businessKeptEarning': 'استمر عملك في الربح أثناء غيابك.',
    'collect': 'جمع',
    'double': 'ضاعف ×2',
    'previewGrantsReward': 'وضع المعاينة يمنح المكافأة دون إعلان حقيقي.',
    'dailyBonus': 'مكافأة يومية',
    'streak': 'استمرارية!',
    'dayStreak': '{streak} يوم متتالي!',
    'comeBackTomorrow': 'عد غدا لزيادة مكافأتك.',
    'collectReward': 'استلام المكافأة',
    'maxLevel': 'المستوى الأقصى',
    'yourCurrentBusinessScore': 'نقاط عملك الحالية',
    'postScore': 'نشر النقاط',
    'challenge': 'تحدي',
    'localTop10': 'أفضل 10 محليين',
    'savedOnThisDevice': 'محفوظ على هذا الجهاز',
    'podiumWaiting': 'المنصة تنتظرك.',
    'postYourScore': 'أرسل نقاطك الحالية للحصول على المرتبة الأولى.',
    'nickname': 'اللقب',
    'enterYourPlayerName': 'أدخل اسم اللاعب الخاص بك',
    'post': 'نشر النقاط',
    'joinedLeaderboard': '{nickname} انضم إلى لوحة الصدارة بـ {score} نقطة!',
    'performanceHistory': 'سجل الأداء',
    'savedSnapshots': 'لقطات محفوظة · النقاط على مدار الوقت',
    'scoreOverTime': 'النقاط على مدار الوقت',
    'keepPlayingChart': 'استمر في اللعب — مخطط الأداء الخاص بك قيد الإنشاء.',
    'playTime': 'وقت اللعب',
    'actions': 'إجراءات',
    'bestBalance': 'أفضل رصيد',
    'highScore': 'أعلى نقاط',
    'customers': 'عملاء',
    'sales': 'المبيعات',
    'demand': 'الطلب',
    'sellingPrice': 'السعر',
    'estimatedProfit': 'الربح',
    'shift': 'الوردية',
    'shiftPreparation': 'التحضير',
    'shiftOpen': 'مفتوحة',
    'rushHour': 'ساعة ازدحام',
    'shiftClosing': 'الإغلاق قريباً',
    'currentEarnings': 'الأرباح',
    'satisfaction': 'رضا العملاء',
    'nextRush': 'الازدحام خلال {seconds} ث',
    'shiftSummary': 'انتهت الوردية {shift}',
    'revenue': 'الإيرادات',
    'missedSales': 'المبيعات الفائتة',
    'stockRemaining': 'المخزون المتبقي',
    'shiftXp': 'الخبرة المكتسبة',
    'continueShift': 'متابعة الوردية',
    'upgradeNow': 'ترقية الآن',
    'shiftMission': 'مهمة الوردية',
    'dailyMission': 'المهمة اليومية',
    'progressionMission': 'مهمة التقدم',
    'serveFiveCustomers': 'اخدم خمسة عملاء في هذه الوردية',
    'keepCustomersHappy': 'حافظ على رضا العملاء عند 80%',
    'active': 'نشطة',
    'claimed': 'تم الاستلام',
    'missionReward': 'المكافأة',
    'claimMission': 'استلام المهمة',
    'vipCustomer': 'عميل VIP في المتجر',
    'fastCheckout': 'لحظة الدفع السريع',
    'fastCheckoutBonus': 'احصل على مكافأة صغيرة عند الدفع',
    'claimBonus': 'استلام المكافأة',
    'itemsStocked': 'منتجات مضافة',
    'upgradesCount': 'تحديثات',
    'achievementUnlocked': 'إنجاز مفتوح',
    'levelLabel': 'المستوى',
    'storeLevel': 'مستوى المتجر',
    'coinsShort': 'عملات',
    'gemsShort': 'جواهر',
    'lowStock': 'مخزون منخفض',
    'controlMode': 'وضع التحكم',
    'directTouchInstruction': 'اضغط أو اسحب للتحرك',
    'floatingJoystickInstruction': 'اسحب عصا التحكم للتحرك',
    'leftHandedJoystickInstruction': 'اسحب عصا التحكم اليسرى للتحرك',
    'directTouch': 'لمس مباشر',
    'floatingJoystick': 'عصا تحكم عائمة',
    'leftHandedJoystick': 'عصا تحكم يسرى',
    'yourMarketAwaits': 'متجرك ينتظرك',
    'openingYourStore': 'فتح متجرك',
    'pocketSizedEmpire': 'إمبراطورية تجارية بحجم الكيس',
    'welcomeToPoMarket': 'مرحبا بك في PoMarket',
    'gotItNext': 'فهمت — التالي',
    'keepShelvesFull': 'حافظ على الأرفف مملوءة',
    'sellEarnGrow': 'بع، اربح، وتنمو',
    'startPlaying': 'ابدأ اللعب',
    'skip': 'تخطي',
    'tutorialSubtitle': 'يفتح متجرك في ثلاث خطوات سريعة',
    'tutorialStep': 'الخطوة {current} من {total}',
    'moveAndCollect': 'تحرك واجمع',
    'moveAndCollectDesc':
        'اضغط على وجهة أو اسحب قرب اللاعب. توجّه إلى المخزن لجمع المنتجات في حقيبتك.',
    'keepShelvesFullDesc':
        'انقل المنتجات إلى الرف. لا يمكن للعملاء التسوق إلا عند توفر المنتجات.',
    'sellEarnGrowDesc':
        'اخدم العملاء عند صندوق الدفع ثم استثمر الأرباح في التطوير والموظفين والأقسام.',
  };
}
