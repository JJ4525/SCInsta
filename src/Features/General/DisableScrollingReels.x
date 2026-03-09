#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%hook IGUnifiedVideoCollectionView
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"disable_scrolling_reels"] || ([SCIUtils getBoolPref:@"reels_time_limit_enabled"] && [SCIUtils getBoolPref:@"reels_time_limit_locked"])) {
        NSLog(@"[SCInsta] Disabling scrolling reels");
        
        self.scrollEnabled = false;
    }
}

- (void)setScrollEnabled:(BOOL)arg1 {
    if ([SCIUtils getBoolPref:@"disable_scrolling_reels"] || ([SCIUtils getBoolPref:@"reels_time_limit_enabled"] && [SCIUtils getBoolPref:@"reels_time_limit_locked"])) {
        NSLog(@"[SCInsta] Disabling scrolling reels");
        
        return %orig(NO);
    }

    return %orig;
}
%end