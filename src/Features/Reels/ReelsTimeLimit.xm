#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Preference keys
static NSString * const kSCIReelsLimitEnabledKey = @"reels_time_limit_enabled";
static NSString * const kSCIReelsLimitMinutesKey = @"reels_time_limit_minutes";
static NSString * const kSCIReelsLimitLockedKey  = @"reels_time_limit_locked";
static NSString * const kSCIReelsSpentSecondsKey = @"reels_time_spent_seconds";
static NSString * const kSCIReelsSpentDayKey     = @"reels_time_spent_day";

static dispatch_source_t gReelsTimer;
static __weak UIViewController *gReelsVC;

static NSString *SCIReelsTodayString() {
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.timeZone = [NSTimeZone localTimeZone];
    df.dateFormat = @"yyyy-MM-dd";
    return [df stringFromDate:[NSDate date]];
}

static void SCIReelsResetIfNeeded() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    NSString *today = SCIReelsTodayString();
    NSString *stored = [ud stringForKey:kSCIReelsSpentDayKey] ?: @"";

    if (![stored isEqualToString:today]) {
        [ud setValue:today forKey:kSCIReelsSpentDayKey];
        [ud setDouble:0.0 forKey:kSCIReelsSpentSecondsKey];
        [ud setBool:NO forKey:kSCIReelsLimitLockedKey];
    }
}

static double SCIReelsLimitSeconds() {
    if (![SCIUtils getBoolPref:kSCIReelsLimitEnabledKey]) return 0.0;

    double mins = [SCIUtils getDoublePref:kSCIReelsLimitMinutesKey];
    if (mins <= 0.0) return 0.0;

    return mins * 60.0;
}

static BOOL SCIReelsIsLocked() {
    return [SCIUtils getBoolPref:kSCIReelsLimitEnabledKey] && [SCIUtils getBoolPref:kSCIReelsLimitLockedKey];
}

static void SCIReelsApplyRestrictions(UIViewController *vc) {
    // Force-disable scrolling for any reels collection view currently on-screen.
    // (Even if the preference wasn't enabled manually.)
    if (vc && vc.isViewLoaded) {
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:vc.view];
        while (stack.count) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];

            if ([v isKindOfClass:%c(IGUnifiedVideoCollectionView)]) {
                ((UIScrollView *)v).scrollEnabled = NO;
            }

            for (UIView *sub in v.subviews) {
                [stack addObject:sub];
            }
        }
    }

    // Ask the tab bar to re-layout so the "Hide reels tab" logic can kick in live.
    // (This might not fully remove reels from swipe navigation, depending on IG version.)
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (!root) return;

    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIViewController *c = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if ([c isKindOfClass:%c(IGTabBarController)]) {
            SEL layoutSel = NSSelectorFromString(@"_layoutTabBar");
            if ([c respondsToSelector:layoutSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [c performSelector:layoutSel];
#pragma clang diagnostic pop
            }
            break;
        }

        if (c.presentedViewController) [queue addObject:c.presentedViewController];
        for (UIViewController *child in c.childViewControllers) {
            [queue addObject:child];
        }
    }
}

static void SCIReelsLockNow(UIViewController *vc) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    if ([ud boolForKey:kSCIReelsLimitLockedKey]) return;

    [ud setBool:YES forKey:kSCIReelsLimitLockedKey];

    // Optional: also hide the tab automatically when locked.
    // We don't force-write hide_reels_tab because users may want it visible normally.

    SCILog(@"Reels limit reached. Locking reels.");
    SCIReelsApplyRestrictions(vc);
}

static void SCIReelsStopTimer() {
    if (gReelsTimer) {
        dispatch_source_cancel(gReelsTimer);
        gReelsTimer = nil;
    }
    gReelsVC = nil;
}

static void SCIReelsStartTimer(UIViewController *vc) {
    SCIReelsStopTimer();

    if (![SCIUtils getBoolPref:kSCIReelsLimitEnabledKey]) return;

    SCIReelsResetIfNeeded();

    // If already locked, apply restrictions immediately.
    if (SCIReelsIsLocked()) {
        SCIReelsApplyRestrictions(vc);
        return;
    }

    double limit = SCIReelsLimitSeconds();
    if (limit <= 0.0) return;

    gReelsVC = vc;

    // Safety: if user already exceeded the limit, lock immediately.
    double spent = [[NSUserDefaults standardUserDefaults] doubleForKey:kSCIReelsSpentSecondsKey];
    if (spent >= limit) {
        SCIReelsLockNow(vc);
        return;
    }

    gReelsTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gReelsTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), (uint64_t)(1.0 * NSEC_PER_SEC), (uint64_t)(0.1 * NSEC_PER_SEC));

    __weak UIViewController *weakVC = vc;
    dispatch_source_set_event_handler(gReelsTimer, ^{
        // Don't count time while the app is not active.
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            return;
        }

        // If user disabled the feature, stop.
        if (![SCIUtils getBoolPref:kSCIReelsLimitEnabledKey]) {
            SCIReelsStopTimer();
            return;
        }

        SCIReelsResetIfNeeded();

        UIViewController *strongVC = weakVC;
        if (!strongVC || !strongVC.isViewLoaded || strongVC.view.window == nil) {
            SCIReelsStopTimer();
            return;
        }

        double limitSec = SCIReelsLimitSeconds();
        if (limitSec <= 0.0) {
            SCIReelsStopTimer();
            return;
        }

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        double spentSec = [ud doubleForKey:kSCIReelsSpentSecondsKey];
        spentSec += 1.0;
        [ud setDouble:spentSec forKey:kSCIReelsSpentSecondsKey];

        if (spentSec >= limitSec) {
            SCIReelsLockNow(strongVC);
            SCIReelsStopTimer();
        }
    });

    dispatch_resume(gReelsTimer);
}

// Hooks

%hook IGSundialFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;

    // Only start tracking time spent if the feature is enabled.
    SCIReelsStartTimer(self);

    // If locked already (e.g., came back from background), apply instantly.
    if (SCIReelsIsLocked()) {
        SCIReelsApplyRestrictions(self);
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    SCIReelsStopTimer();
    %orig;
}
%end
