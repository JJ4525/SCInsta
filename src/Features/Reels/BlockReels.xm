#import <objc/runtime.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static char kSCIBlockedReelsControllerKey;

static BOOL SCIShouldHardBlockReels() {
    return YES;
}

static BOOL SCIIsReelsController(id vc) {
    Class sundialClass = %c(IGSundialFeedViewController);
    return vc && sundialClass && [vc isKindOfClass:sundialClass];
}

static BOOL SCIContainsReelsController(id vc) {
    if (!vc) return NO;
    if (SCIIsReelsController(vc)) return YES;

    if ([vc isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *child in ((UINavigationController *)vc).viewControllers) {
            if (SCIContainsReelsController(child)) return YES;
        }
    }

    if ([vc isKindOfClass:[UITabBarController class]]) {
        for (UIViewController *child in ((UITabBarController *)vc).viewControllers) {
            if (SCIContainsReelsController(child)) return YES;
        }
    }

    if ([vc respondsToSelector:@selector(childViewControllers)]) {
        for (UIViewController *child in [vc childViewControllers]) {
            if (SCIContainsReelsController(child)) return YES;
        }
    }

    return NO;
}

static void SCIDisableReelsViewTree(UIView *root) {
    if (!root) return;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];

        view.userInteractionEnabled = NO;

        if ([view isKindOfClass:%c(IGUnifiedVideoCollectionView)] || [view isKindOfClass:[UIScrollView class]]) {
            ((UIScrollView *)view).scrollEnabled = NO;
            ((UIScrollView *)view).pagingEnabled = NO;
        }

        for (UIView *subview in view.subviews) {
            [stack addObject:subview];
        }
    }
}

static void SCIEscapeReelsController(UIViewController *vc) {
    if (!SCIShouldHardBlockReels() || !SCIIsReelsController(vc)) return;

    NSNumber *alreadyBlocked = objc_getAssociatedObject(vc, &kSCIBlockedReelsControllerKey);
    if (alreadyBlocked.boolValue) return;
    objc_setAssociatedObject(vc, &kSCIBlockedReelsControllerKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    SCILog(@"Blocking reels controller: %@", vc);

    if (vc.isViewLoaded) {
        SCIDisableReelsViewTree(vc.view);
        vc.view.hidden = YES;
        vc.view.alpha = 0.0;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (vc.navigationController && vc.navigationController.topViewController == vc && vc.navigationController.viewControllers.count > 1) {
            [vc.navigationController popViewControllerAnimated:NO];
            return;
        }

        if (vc.presentingViewController) {
            [vc dismissViewControllerAnimated:NO completion:nil];
            return;
        }

        if (vc.parentViewController && vc.parentViewController.navigationController && vc.parentViewController.navigationController.viewControllers.count > 1) {
            [vc.parentViewController.navigationController popViewControllerAnimated:NO];
        }
    });
}

%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    if (SCIShouldHardBlockReels() && SCIContainsReelsController(viewControllerToPresent)) {
        SCILog(@"Blocked modal presentation of reels controller");
        return;
    }

    %orig(viewControllerToPresent, flag, completion);
}
%end

%hook UINavigationController
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (SCIShouldHardBlockReels() && SCIContainsReelsController(viewController)) {
        SCILog(@"Blocked navigation push of reels controller");
        return;
    }

    %orig(viewController, animated);
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    if (SCIShouldHardBlockReels()) {
        NSMutableArray<UIViewController *> *filtered = [NSMutableArray array];
        for (UIViewController *controller in viewControllers) {
            if (!SCIContainsReelsController(controller)) {
                [filtered addObject:controller];
            }
        }
        return %orig(filtered, animated);
    }

    %orig(viewControllers, animated);
}
%end

%hook IGSundialFeedViewController
- (void)viewDidLoad {
    %orig;

    if (SCIShouldHardBlockReels()) {
        SCIDisableReelsViewTree(self.view);
        self.view.hidden = YES;
        self.view.alpha = 0.0;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    if (SCIShouldHardBlockReels()) {
        SCIEscapeReelsController(self);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (SCIShouldHardBlockReels()) {
        SCIEscapeReelsController(self);
    }
}
%end

%hook IGUnifiedVideoCollectionView
- (void)didMoveToWindow {
    %orig;

    if (SCIShouldHardBlockReels()) {
        UIViewController *owner = [SCIUtils nearestViewControllerForView:self];
        if (SCIIsReelsController(owner)) {
            self.scrollEnabled = NO;
            self.pagingEnabled = NO;
            self.userInteractionEnabled = NO;
        }
    }
}

- (void)setScrollEnabled:(BOOL)enabled {
    if (SCIShouldHardBlockReels()) {
        UIViewController *owner = [SCIUtils nearestViewControllerForView:self];
        if (SCIIsReelsController(owner)) {
            return %orig(NO);
        }
    }

    %orig(enabled);
}
%end
