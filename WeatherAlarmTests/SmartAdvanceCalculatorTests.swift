import XCTest
@testable import WeatherAlarm

final class SmartAdvanceCalculatorTests: XCTestCase {
    private let settings = WeatherAdjustmentSettings.default

    func testHighProbabilityLightRainIsNotHeavyRain() {
        let advance = settings.weatherAdvance(for: summary(chance: 95, millimeters: 0.2))
        XCTAssertLessThanOrEqual(advance.totalMinutes, 10)
    }

    func testProbabilityWithoutIntensityIsCappedAtTenMinutes() {
        let advance = settings.weatherAdvance(for: summary(chance: 100, millimeters: nil))
        XCTAssertEqual(advance.totalMinutes, 10)
    }

    func testConfirmedShortDurationHeavyRainCanReachFortyMinutes() {
        let advance = settings.weatherAdvance(for: summary(chance: 80, millimeters: 22))
        XCTAssertEqual(advance.totalMinutes, 40)
    }

    func testWeatherAndRouteReplaceGenericWeatherBufferInsteadOfAddingIt() {
        let weather = settings.weatherAdvance(for: summary(chance: 80, millimeters: 22))
        let decision = SmartAdvanceCalculator.calculate(
            weatherEnabled: true,
            routeAvailable: true,
            weather: weather,
            routeDelayMinutes: 34,
            residualWeatherMinutes: 0,
            arrivalAdvanceMinutes: 0
        )

        XCTAssertEqual(decision.totalMinutes, 45)
        XCTAssertLessThan(decision.totalMinutes, weather.totalMinutes + 34)
    }

    func testRouteDoesNotRemoveConfirmedWeatherSafetyBuffer() {
        let weather = settings.weatherAdvance(for: summary(chance: 80, millimeters: 22))
        let decision = SmartAdvanceCalculator.calculate(
            weatherEnabled: true,
            routeAvailable: true,
            weather: weather,
            routeDelayMinutes: 0,
            residualWeatherMinutes: 0,
            arrivalAdvanceMinutes: 0
        )

        XCTAssertEqual(decision.totalMinutes, 40)
        XCTAssertEqual(decision.weatherMinutes, 40)
        XCTAssertEqual(decision.routeMinutes, 0)
    }

    func testArrivalConstraintAndRouteDelayUseMaximum() {
        let decision = SmartAdvanceCalculator.calculate(
            weatherEnabled: false,
            routeAvailable: true,
            weather: .zero,
            routeDelayMinutes: 20,
            residualWeatherMinutes: 0,
            arrivalAdvanceMinutes: 40
        )

        XCTAssertEqual(decision.totalMinutes, 40)
    }

    func testRouteFailureKeepsWeatherOnlyDecision() {
        let weather = settings.weatherAdvance(for: summary(chance: 80, millimeters: 22))
        let decision = SmartAdvanceCalculator.calculate(
            weatherEnabled: true,
            routeAvailable: false,
            weather: weather,
            routeDelayMinutes: 50,
            residualWeatherMinutes: 10,
            arrivalAdvanceMinutes: 60
        )

        XCTAssertEqual(decision.totalMinutes, 40)
        XCTAssertEqual(decision.routeMinutes, 0)
    }

    func testStaleForecastCannotIncreaseFutureAlarm() {
        let stale = summary(chance: 100, millimeters: 22)
        let future = stale.windowEnd.addingTimeInterval(4 * 60 * 60)
        let focused = stale.focused(on: future, travelDuration: nil)

        XCTAssertEqual(settings.weatherAdvance(for: focused).totalMinutes, 0)
    }

    func testETAHistoryUsesTimeBucketPercentilesAfterFiveSamples() throws {
        let suiteName = "SmartAdvanceCalculatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CommuteETAHistoryStore(userDefaults: defaults)
        let route = CommuteRoute(
            startName: "A",
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            endName: "B",
            endLatitude: 31.2200,
            endLongitude: 121.4800,
            mode: .driving,
            city: "上海市",
            baseDurationSeconds: 20 * 60,
            baseDistanceMeters: 5_000,
            baseWalkingDistanceMeters: nil,
            coordinateSystem: "wgs84"
        )
        let departure = Date(timeIntervalSince1970: 1_800_000_000)

        for minutes in [20, 22, 21, 40, 23] {
            store.record(TimeInterval(minutes * 60), for: route, departureDate: departure)
        }

        let statistics = try XCTUnwrap(store.statistics(for: route, departureDate: departure))
        XCTAssertEqual(statistics.p50, 22 * 60)
        XCTAssertEqual(statistics.p80, 23 * 60)
    }

    func testFullPaidTestGateDoesNotCreateFakePurchaseEvidence() throws {
        let suiteName = "SmartAdvanceCalculatorTests.entitlement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PurchaseEntitlementSnapshotStore(userDefaults: defaults)

        #if SMARTWAKE_ALL_PAID_TEST
        XCTAssertTrue(store.canUseWeather)
        XCTAssertTrue(store.canUseGaode)
        #else
        XCTAssertFalse(store.canUseWeather)
        XCTAssertFalse(store.canUseGaode)
        #endif
        XCTAssertFalse(store.databaseSyncSnapshot.hasAnyEntitlement)
        XCTAssertFalse(store.hasVerifiedPurchaseEvidence)
    }

    func testVerifiedPurchaseSnapshotSurvivesStoreRecreation() throws {
        let suiteName = "SmartAdvanceCalculatorTests.purchase.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PurchaseEntitlementSnapshotStore(userDefaults: defaults)
        store.saveSnapshot(
            hasPurchasedForever: true,
            isWeatherSubscribed: false,
            hasGaodeEnhance: false,
            productIDs: ["verified.product"],
            transactionIDs: ["123"],
            originalTransactionIDs: ["100"]
        )

        let restored = PurchaseEntitlementSnapshotStore(userDefaults: defaults)
        XCTAssertTrue(restored.canUseWeather)
        XCTAssertTrue(restored.hasVerifiedPurchaseEvidence)
        XCTAssertEqual(restored.databaseSyncSnapshot.originalTransactionIDs, ["100"])
    }

    func testDeletedAlarmRestoresAtItsOriginalPosition() throws {
        let suiteName = "SmartAdvanceCalculatorTests.alarmUndo.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)

        _ = try store.saveWakeUpTime(hour: 7, minute: 0)
        let first = try store.addOrdinaryAlarm(hour: 8, minute: 0)
        let second = try store.addOrdinaryAlarm(hour: 9, minute: 0)
        let removed = try XCTUnwrap(store.removeOrdinaryAlarm(id: first.id))
        _ = try store.restoreOrdinaryAlarm(removed, at: 0)

        XCTAssertEqual(try store.loadRequiredSettings().effectiveOrdinaryAlarms.map(\.id), [first.id, second.id])
    }

    func testAlarmNamesPersistAndCanBeCleared() throws {
        let suiteName = "SmartAdvanceCalculatorTests.alarmNames.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)

        _ = try store.saveWakeUpTime(hour: 7, minute: 0)
        _ = try store.updateWakeUpTitle("晨跑")
        XCTAssertEqual(try store.loadRequiredSettings().wakeUpTitle, "晨跑")

        _ = try store.updateWakeUpTitle("   ")
        let clearedWakeUp = try store.loadRequiredSettings()
        XCTAssertNil(clearedWakeUp.wakeUpTitle)
        XCTAssertEqual(clearedWakeUp.effectiveWakeUpTitle, "起床闹钟")

        var ordinaryAlarm = try store.addOrdinaryAlarm(hour: 8, minute: 15)
        ordinaryAlarm.title = "早课"
        _ = try store.updateOrdinaryAlarm(ordinaryAlarm)
        XCTAssertEqual(try store.loadRequiredSettings().effectiveOrdinaryAlarms.first?.title, "早课")

        ordinaryAlarm.title = nil
        _ = try store.updateOrdinaryAlarm(ordinaryAlarm)
        let clearedOrdinary = try XCTUnwrap(try store.loadRequiredSettings().effectiveOrdinaryAlarms.first)
        XCTAssertNil(clearedOrdinary.title)
        XCTAssertEqual(clearedOrdinary.effectiveTitle, "其他闹钟")
    }

    func testDeletingLastOrdinaryAlarmDoesNotCreateReplacement() throws {
        let suiteName = "SmartAdvanceCalculatorTests.deleteLastAlarm.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)

        _ = try store.saveWakeUpTime(hour: 7, minute: 0)
        let alarm = try store.addOrdinaryAlarm(hour: 8, minute: 0)
        _ = try store.removeOrdinaryAlarm(id: alarm.id)

        XCTAssertTrue(try store.loadRequiredSettings().effectiveOrdinaryAlarms.isEmpty)
    }

    func testNewAlarmSequenceStaysCompactAfterRenameAndDelete() throws {
        let suiteName = "SmartAdvanceCalculatorTests.alarmSequence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)

        _ = try store.saveWakeUpTime(hour: 7, minute: 0)
        var first = try store.addOrdinaryAlarm(hour: 8, minute: 0)
        let second = try store.addOrdinaryAlarm(hour: 9, minute: 0)
        XCTAssertEqual(first.title, "其他闹钟1")
        XCTAssertEqual(second.title, "其他闹钟2")

        first.title = "晨练"
        _ = try store.updateOrdinaryAlarm(first)
        XCTAssertEqual(
            try store.loadRequiredSettings().effectiveOrdinaryAlarms.map(\.effectiveTitle),
            ["晨练", "其他闹钟1"]
        )

        let third = try store.addOrdinaryAlarm(hour: 10, minute: 0)
        XCTAssertEqual(third.title, "其他闹钟2")

        _ = try store.removeOrdinaryAlarm(id: second.id)
        XCTAssertEqual(
            try store.loadRequiredSettings().effectiveOrdinaryAlarms.map(\.effectiveTitle),
            ["晨练", "其他闹钟1"]
        )
    }

    func testLegacyLargeAlarmNumbersMigrateToCompactSequence() throws {
        let suiteName = "SmartAdvanceCalculatorTests.alarmSequenceMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)

        var settings = try store.saveWakeUpTime(hour: 7, minute: 0)
        settings.ordinaryAlarms = [
            OrdinaryAlarmSettings(hour: 8, minute: 0, title: "其他闹钟301"),
            OrdinaryAlarmSettings(hour: 9, minute: 0, title: "早课"),
            OrdinaryAlarmSettings(hour: 10, minute: 0, title: "其他闹钟999")
        ]
        try store.save(settings)
        defaults.set(1_000, forKey: "weather_alarm.next_ordinary_sequence")

        let migrated = try store.loadRequiredSettings()
        XCTAssertEqual(
            migrated.effectiveOrdinaryAlarms.map(\.effectiveTitle),
            ["其他闹钟1", "早课", "其他闹钟2"]
        )
        XCTAssertNil(defaults.object(forKey: "weather_alarm.next_ordinary_sequence"))

        let newAlarm = try store.addOrdinaryAlarm(hour: 11, minute: 0)
        XCTAssertEqual(newAlarm.title, "其他闹钟3")
    }

    func testTomorrowRouteMapRoutesByEntitlement() {
        XCTAssertEqual(
            SmartWakeRouteEntryDestination(hasRouteAccess: false),
            .subscription
        )
        XCTAssertEqual(
            SmartWakeRouteEntryDestination(hasRouteAccess: true),
            .routeEditor
        )
    }

    @MainActor
    func testOrdinaryAlarmDisplaysPersistedSystemAdvanceAfterAppReload() throws {
        let suiteName = "SmartAdvanceCalculatorTests.ordinaryStatus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStore = AlarmSettingsStore(userDefaults: defaults)
        _ = try settingsStore.saveWakeUpTime(hour: 7, minute: 0)
        var alarm = try settingsStore.addOrdinaryAlarm(hour: 8, minute: 0)
        alarm.isCommuteAdjustmentEnabled = true
        _ = try settingsStore.updateOrdinaryAlarm(alarm)

        let calendar = Calendar(identifier: .gregorian)
        let baseDate = try XCTUnwrap(alarm.nextBaseWakeUpDate(calendar: calendar))
        let scheduledDate = try XCTUnwrap(
            calendar.date(byAdding: .minute, value: -20, to: baseDate)
        )
        let statusStore = WeatherAlarmStatusStore(userDefaults: defaults)
        statusStore.save(
            WeatherAlarmStatus(
                generatedAt: Date(),
                baseWakeUpDate: baseDate,
                scheduledWakeUpDate: scheduledDate,
                advanceMinutes: 20,
                weatherBufferMinutes: 0,
                commuteDelayMinutes: 20,
                weatherCondition: "",
                precipitationChancePercent: 0
            ),
            forOrdinaryAlarmID: alarm.id
        )

        let viewModel = WeatherAlarmSettingsViewModel(
            settingsStore: settingsStore,
            statusStore: statusStore,
            calendar: calendar,
            userDefaults: defaults
        )
        let display = try XCTUnwrap(viewModel.advanceDisplay(for: alarm))

        XCTAssertEqual(display.advanceMinutes, 20)
        XCTAssertEqual(display.weatherAdvanceMinutes, 0)
        XCTAssertEqual(display.routeAdvanceMinutes, 20)
        XCTAssertEqual(display.scheduledWakeUpDate, scheduledDate)
        XCTAssertEqual(viewModel.ordinaryAlarm(id: alarm.id)?.timeText, "08:00")
    }

    func testOrdinaryAlarmStatusStoreRemovesDeletedAndDisabledEntries() throws {
        let suiteName = "SmartAdvanceCalculatorTests.ordinaryStatusCleanup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keptID = UUID()
        let removedID = UUID()
        let baseDate = Date().addingTimeInterval(3_600)
        let status = WeatherAlarmStatus(
            generatedAt: Date(),
            baseWakeUpDate: baseDate,
            scheduledWakeUpDate: baseDate.addingTimeInterval(-600),
            advanceMinutes: 10,
            weatherBufferMinutes: 0,
            commuteDelayMinutes: 10,
            weatherCondition: "",
            precipitationChancePercent: 0
        )
        let store = WeatherAlarmStatusStore(userDefaults: defaults)
        store.save(status, forOrdinaryAlarmID: keptID)
        store.save(status, forOrdinaryAlarmID: removedID)

        store.retainOrdinaryAlarmStatuses(for: [keptID])

        XCTAssertEqual(store.loadOrdinaryAlarmStatuses(), [keptID: status])
        store.removeOrdinaryAlarmStatus(for: keptID)
        XCTAssertTrue(store.loadOrdinaryAlarmStatuses().isEmpty)
    }

    func testWakeUpAlarmMasterSwitchDefaultsOnAndPersistsOff() throws {
        let suiteName = "SmartAdvanceCalculatorTests.wakeSwitch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)

        let legacyCompatibleSettings = try store.saveWakeUpTime(hour: 7, minute: 30)
        XCTAssertNil(legacyCompatibleSettings.isWakeUpAlarmEnabled)
        XCTAssertTrue(legacyCompatibleSettings.effectiveIsWakeUpAlarmEnabled)

        _ = try store.setWakeUpAlarmEnabled(false)
        XCTAssertFalse(try store.loadRequiredSettings().effectiveIsWakeUpAlarmEnabled)

        _ = try store.setWakeUpAlarmEnabled(true)
        XCTAssertTrue(try store.loadRequiredSettings().effectiveIsWakeUpAlarmEnabled)
    }

    func testInvalidAlarmMutationCannotCorruptExistingSettings() throws {
        let suiteName = "SmartAdvanceCalculatorTests.invalidAlarm.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)

        _ = try store.saveWakeUpTime(hour: 7, minute: 30)
        XCTAssertThrowsError(try store.saveWakeUpTime(hour: 24, minute: 0))

        let restored = try store.loadRequiredSettings()
        XCTAssertEqual(restored.wakeUpHour, 7)
        XCTAssertEqual(restored.wakeUpMinute, 30)
    }

    func testSmartAdvanceFuzzMaintainsAllInvariants() {
        var state: UInt64 = 0x5A17_C0DE_F00D_BAAD

        func next(_ upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state % UInt64(upperBound))
        }

        for _ in 0..<100_000 {
            let weatherEnabled = next(2) == 1
            let routeAvailable = next(2) == 1
            let preparation = next(61)
            let genericTravel = next(61)
            let weatherTotal = max(preparation, min(120, preparation + genericTravel))
            let weather = WeatherAdvanceComponents(
                risk: Double(next(1_001)) / 1_000,
                preparationMinutes: preparation,
                genericTravelMinutes: genericTravel,
                totalMinutes: weatherTotal
            )
            let decision = SmartAdvanceCalculator.calculate(
                weatherEnabled: weatherEnabled,
                routeAvailable: routeAvailable,
                weather: weather,
                routeDelayMinutes: next(181) - 30,
                residualWeatherMinutes: next(91) - 15,
                arrivalAdvanceMinutes: next(181) - 30
            )

            XCTAssertTrue((0...60).contains(decision.totalMinutes))
            XCTAssertEqual(decision.totalMinutes % 5, 0)
            XCTAssertTrue((0...decision.totalMinutes).contains(decision.weatherMinutes))
            XCTAssertEqual(decision.routeMinutes, decision.totalMinutes - decision.weatherMinutes)
            if !weatherEnabled && !routeAvailable {
                XCTAssertEqual(decision, .zero)
            }
            if !routeAvailable {
                XCTAssertEqual(decision.routeMinutes, 0)
            }
        }
    }

    func testEngagementPolicyExhaustiveBoundaries() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recent = now.addingTimeInterval(-SmartWakeEngagementPolicy.adjustmentNotificationCooldown + 1)
        let old = now.addingTimeInterval(-SmartWakeEngagementPolicy.adjustmentNotificationCooldown)

        for previous in 0...120 {
            for current in 0...120 {
                let delta = abs(previous - current)
                let transition = (previous == 0) != (current == 0)
                let expectedWithoutCooldown = previous != current
                    && (transition || delta >= SmartWakeEngagementPolicy.meaningfulAdjustmentMinutes)

                XCTAssertEqual(
                    SmartWakeEngagementPolicy.shouldNotifyAdjustment(
                        previousMinutes: previous,
                        currentMinutes: current,
                        lastNotificationDate: old,
                        now: now
                    ),
                    expectedWithoutCooldown
                )

                let expectedDuringCooldown = previous != current && transition
                XCTAssertEqual(
                    SmartWakeEngagementPolicy.shouldNotifyAdjustment(
                        previousMinutes: previous,
                        currentMinutes: current,
                        lastNotificationDate: recent,
                        now: now
                    ),
                    expectedDuringCooldown
                )
            }
        }
    }

    func testEveningPreparationWindowHasNoLateNightHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 2_000_016_000)

        for hour in 0..<24 {
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            XCTAssertEqual(
                SmartWakeEngagementPolicy.isEveningPreparationWindow(date, calendar: calendar),
                (19..<22).contains(hour)
            )
        }
    }

    func testAutomaticOfferReappearanceRequiresCooldownAndHasHardLimit() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertFalse(
            SmartWakeEngagementPolicy.canShowAutomaticOfferReappearance(
                previousReappearanceCount: 0,
                eligibleAt: nil,
                now: now
            )
        )
        XCTAssertFalse(
            SmartWakeEngagementPolicy.canShowAutomaticOfferReappearance(
                previousReappearanceCount: 0,
                eligibleAt: now.addingTimeInterval(1),
                now: now
            )
        )
        XCTAssertTrue(
            SmartWakeEngagementPolicy.canShowAutomaticOfferReappearance(
                previousReappearanceCount: SmartWakeEngagementPolicy.maximumAutomaticOfferReappearances - 1,
                eligibleAt: now,
                now: now
            )
        )
        XCTAssertFalse(
            SmartWakeEngagementPolicy.canShowAutomaticOfferReappearance(
                previousReappearanceCount: SmartWakeEngagementPolicy.maximumAutomaticOfferReappearances,
                eligibleAt: now.addingTimeInterval(-1),
                now: now
            )
        )
    }

    func testSubscriptionExpirationOverridesStaleStoredFlag() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertFalse(
            PurchaseEntitlementSnapshotStore.subscriptionIsActive(
                storedFlag: true,
                expirationDate: now.addingTimeInterval(-1),
                now: now
            )
        )
        XCTAssertTrue(
            PurchaseEntitlementSnapshotStore.subscriptionIsActive(
                storedFlag: false,
                expirationDate: now.addingTimeInterval(1),
                now: now
            )
        )
        XCTAssertTrue(
            PurchaseEntitlementSnapshotStore.subscriptionIsActive(
                storedFlag: true,
                expirationDate: nil,
                now: now
            )
        )
    }

    func testCouponEligibilityMatrixRejectsEveryWrongProduct() {
        let allProducts = Set(WeatherAlarmProductID.all)
        let cases: [(WeatherWakeCouponType, Set<String>)] = [
            (.ref100Off, [
                WeatherAlarmProductID.foreverWeatherReferral100,
                WeatherAlarmProductID.foreverWeatherReferral100Regular
            ]),
            (.ref50Universal, [
                WeatherAlarmProductID.foreverWeatherFriend50,
                WeatherAlarmProductID.foreverWeatherFriend50Regular,
                WeatherAlarmProductID.pathYearlyFriend50
            ])
        ]

        for (type, allowedProducts) in cases {
            for productID in allProducts {
                let coupon = WeatherWakeCoupon(type: type)
                if allowedProducts.contains(productID) {
                    XCTAssertNoThrow(
                        try CouponEligibilityValidator.validate(coupon: coupon, productID: productID)
                    )
                } else {
                    XCTAssertThrowsError(
                        try CouponEligibilityValidator.validate(coupon: coupon, productID: productID)
                    )
                }
            }
        }
    }

    func testAlarmSoundCatalogHasUniqueMetadataAndEveryCollectionIsPopulated() {
        let sounds = AlarmSoundChoice.allCases

        XCTAssertEqual(sounds.count, 24)
        XCTAssertEqual(Set(sounds.map(\.displayName)).count, sounds.count)
        XCTAssertEqual(Set(sounds.map(\.soundDescription)).count, sounds.count)
        XCTAssertEqual(Set(sounds.map(\.bundledFileName)).count, sounds.count)

        for collection in AlarmSoundCollection.allCases {
            XCTAssertFalse(
                sounds.filter { $0.collection == collection }.isEmpty,
                "\(collection.rawValue) 分类不应为空"
            )
        }
    }

    func testCustomSoundSelectionPersistsWithoutChangingLegacyFallback() throws {
        let suiteName = "SmartAdvanceCalculatorTests.customSound.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AlarmSettingsStore(userDefaults: defaults)
        let customSoundID = UUID()

        _ = try store.saveWakeUpTime(hour: 7, minute: 0)
        let saved = try store.updateWakeUpSoundSelection(.custom(customSoundID))

        XCTAssertEqual(saved.wakeUpCustomSoundID, customSoundID)
        XCTAssertEqual(saved.effectiveWakeUpSoundChoice, .systemDefault)

        let restored = try store.loadRequiredSettings()
        XCTAssertEqual(restored.wakeUpCustomSoundID, customSoundID)
        XCTAssertEqual(restored.effectiveWakeUpSoundChoice, .systemDefault)
    }

    func testCustomSoundImportProducesAlarmCompatibleCAF() async throws {
        let sourceURL = try XCTUnwrap(
            bundledSoundURL(named: AlarmSoundChoice.systemDefault.bundledFileName)
        )
        let imported = try await CustomAlarmSoundStore.importSound(from: sourceURL)
        defer { try? CustomAlarmSoundStore.deleteSound(id: imported.id) }

        let outputURL = try XCTUnwrap(CustomAlarmSoundStore.audioURL(for: imported.id))
        XCTAssertEqual(outputURL.pathExtension.lowercased(), "caf")
        XCTAssertGreaterThan(imported.duration, 0)
        XCTAssertLessThanOrEqual(imported.duration, CustomAlarmSoundStore.maximumDuration)
        XCTAssertGreaterThan(try Data(contentsOf: outputURL).count, 8_000)
    }

    func testAlarmThemeSwatchesKeepStableCoolToWarmDisplayOrder() {
        let order = AlarmTheme.rainbowOrderedThemeIndices

        XCTAssertEqual(order.count, 16)
        XCTAssertEqual(Set(order), Set(0..<16))
        XCTAssertEqual(Array(order.prefix(5)), [0, 5, 8, 3, 14])
        XCTAssertEqual(Array(order.suffix(5)), [12, 10, 11, 15, 13])
        XCTAssertEqual(AlarmTheme.allThemeIndices, order)
    }

    func testEveryAlarmSoundAndLoudVariantIsBundledAndHasDistinctAudioData() throws {
        var normalPayloads = Set<Data>()
        var loudPayloads = Set<Data>()

        for sound in AlarmSoundChoice.allCases {
            let normalURL = try XCTUnwrap(
                bundledSoundURL(named: sound.bundledFileName),
                "缺少铃声资源：\(sound.bundledFileName)"
            )
            let loudName = sound.bundledFileName(loudVolumeEnabled: true)
            let loudURL = try XCTUnwrap(
                bundledSoundURL(named: loudName),
                "缺少大音量铃声资源：\(loudName)"
            )
            let normalData = try Data(contentsOf: normalURL)
            let loudData = try Data(contentsOf: loudURL)

            XCTAssertGreaterThan(normalData.count, 8_000)
            XCTAssertGreaterThan(loudData.count, 8_000)
            XCTAssertNotEqual(normalData, loudData, "\(sound.displayName) 的大音量版本不能与普通版完全相同")
            normalPayloads.insert(normalData)
            loudPayloads.insert(loudData)
        }

        XCTAssertEqual(normalPayloads.count, AlarmSoundChoice.allCases.count)
        XCTAssertEqual(loudPayloads.count, AlarmSoundChoice.allCases.count)
    }

    func testWidgetChoosesEarliestActualAlarmAcrossWakeAndOrdinaryStatuses() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let wakeBase = now.addingTimeInterval(3 * 60 * 60)
        let ordinaryBase = now.addingTimeInterval(2 * 60 * 60)
        let wakeStatus = WeatherAlarmStatus(
            generatedAt: now,
            baseWakeUpDate: wakeBase,
            scheduledWakeUpDate: wakeBase.addingTimeInterval(-10 * 60),
            advanceMinutes: 10,
            weatherBufferMinutes: 10,
            commuteDelayMinutes: 0,
            weatherCondition: "小雨",
            precipitationChancePercent: 60,
            alarmTitle: "起床闹钟",
            isWakeUpAlarm: true
        )
        let ordinaryStatus = WeatherAlarmStatus(
            generatedAt: now,
            baseWakeUpDate: ordinaryBase,
            scheduledWakeUpDate: ordinaryBase.addingTimeInterval(-20 * 60),
            advanceMinutes: 20,
            weatherBufferMinutes: 0,
            commuteDelayMinutes: 20,
            weatherCondition: "",
            precipitationChancePercent: 0,
            alarmTitle: "早课",
            isWakeUpAlarm: false
        )

        let next = try XCTUnwrap(
            WeatherAlarmStatus.nextScheduled(
                from: [wakeStatus, ordinaryStatus],
                after: now
            )
        )

        XCTAssertEqual(next.alarmTitle, "早课")
        XCTAssertEqual(next.scheduledWakeUpDate, ordinaryStatus.scheduledWakeUpDate)
        XCTAssertEqual(next.advanceSummaryText, "提前 20 分钟")
    }

    func testWidgetProjectsNextWeeklyOccurrenceAfterCurrentAlarmHasPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 20,
                hour: 6,
                minute: 0
            ))
        )
        let previousBase = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 13,
                hour: 8,
                minute: 0
            ))
        )
        let previousStatus = WeatherAlarmStatus(
            generatedAt: previousBase,
            baseWakeUpDate: previousBase,
            scheduledWakeUpDate: previousBase,
            advanceMinutes: 0,
            weatherBufferMinutes: 0,
            commuteDelayMinutes: 0,
            weatherCondition: "晴",
            precipitationChancePercent: 10,
            alarmTitle: "每周晨练",
            repeatWeekdays: [2],
            isWakeUpAlarm: false
        )

        let projected = try XCTUnwrap(
            previousStatus.nextOccurrence(after: now, calendar: calendar)
        )
        let expectedBase = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 20,
                hour: 8,
                minute: 0
            ))
        )

        XCTAssertEqual(projected.baseWakeUpDate, expectedBase)
        XCTAssertEqual(projected.scheduledWakeUpDate, expectedBase)
        XCTAssertEqual(projected.alarmTitle, "每周晨练")
    }

    func testWidgetDoesNotInventNextWeeklyOccurrenceForExpiredAdjustedAlarm() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 20,
                hour: 6,
                minute: 0
            ))
        )
        let previousBase = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 13,
                hour: 8,
                minute: 0
            ))
        )
        let previousStatus = WeatherAlarmStatus(
            generatedAt: previousBase,
            baseWakeUpDate: previousBase,
            scheduledWakeUpDate: previousBase.addingTimeInterval(-15 * 60),
            advanceMinutes: 15,
            weatherBufferMinutes: 5,
            commuteDelayMinutes: 10,
            weatherCondition: "阵雨",
            precipitationChancePercent: 70,
            alarmTitle: "每周晨练",
            repeatWeekdays: [2],
            isWakeUpAlarm: false
        )

        XCTAssertNil(previousStatus.nextOccurrence(after: now, calendar: calendar))
    }

    func testWidgetStatusMigratesMainAndOrdinaryAlarmDataIntoSharedDefaults() throws {
        let sharedSuite = "SmartAdvanceCalculatorTests.widgetShared.\(UUID().uuidString)"
        let legacySuite = "SmartAdvanceCalculatorTests.widgetLegacy.\(UUID().uuidString)"
        let shared = try XCTUnwrap(UserDefaults(suiteName: sharedSuite))
        let legacy = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
        shared.removePersistentDomain(forName: sharedSuite)
        legacy.removePersistentDomain(forName: legacySuite)
        defer {
            shared.removePersistentDomain(forName: sharedSuite)
            legacy.removePersistentDomain(forName: legacySuite)
        }

        let baseDate = Date().addingTimeInterval(3_600)
        let status = WeatherAlarmStatus(
            generatedAt: Date(),
            baseWakeUpDate: baseDate,
            scheduledWakeUpDate: baseDate,
            advanceMinutes: 0,
            weatherBufferMinutes: 0,
            commuteDelayMinutes: 0,
            weatherCondition: "晴",
            precipitationChancePercent: 0,
            alarmTitle: "同步测试"
        )
        let ordinaryID = UUID()
        let legacyStore = WeatherAlarmStatusStore(userDefaults: legacy)
        legacyStore.save(status)
        legacyStore.save(status, forOrdinaryAlarmID: ordinaryID)

        let sharedStore = WeatherAlarmStatusStore(userDefaults: shared)
        XCTAssertTrue(sharedStore.migrateLegacyStatusIfNeeded(from: legacy))
        XCTAssertEqual(sharedStore.loadLatestStatus(), status)
        XCTAssertEqual(sharedStore.loadOrdinaryAlarmStatuses(), [ordinaryID: status])
        XCTAssertFalse(sharedStore.migrateLegacyStatusIfNeeded(from: legacy))
    }

    private func bundledSoundURL(named fileName: String) -> URL? {
        Bundle.main.url(forResource: fileName, withExtension: nil)
            ?? Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "AlarmSounds")
    }

    private func summary(chance: Double, millimeters: Double?) -> MorningWeatherSummary {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = HourlyWeatherSummary(
            date: start,
            weatherCondition: "雨",
            precipitationChancePercent: chance,
            precipitationAmountMillimeters: millimeters
        )
        return MorningWeatherSummary(
            weatherCondition: "雨",
            precipitationChancePercent: chance,
            precipitationAmountMillimeters: millimeters,
            windowStart: start,
            windowEnd: start.addingTimeInterval(60 * 60),
            hourlyForecast: [sample]
        )
    }
}
