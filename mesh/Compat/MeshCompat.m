#import "MeshCompat.h"
#import <objc/runtime.h>

#pragma mark - Subscripting für iOS 4/5

static id dictGet(NSDictionary *self, SEL _cmd, id key)                 { return [self objectForKey:key]; }
static void dictSet(NSMutableDictionary *self, SEL _cmd, id obj, id key) {
    if (obj) [self setObject:obj forKey:key]; else [self removeObjectForKey:key];
}
static id arrayGet(NSArray *self, SEL _cmd, NSUInteger i)               { return [self objectAtIndex:i]; }
static void arraySet(NSMutableArray *self, SEL _cmd, id obj, NSUInteger i) {
    if (i == self.count) [self addObject:obj]; else [self replaceObjectAtIndex:i withObject:obj];
}

static void addIfMissing(Class c, SEL sel, IMP imp, const char *types) {
    if (![c instancesRespondToSelector:sel]) class_addMethod(c, sel, imp, types);
}

@interface MeshSubscriptingShim : NSObject
@end
@implementation MeshSubscriptingShim
+ (void)load {
    addIfMissing([NSDictionary class], @selector(objectForKeyedSubscript:), (IMP)dictGet, "@@:@");
    addIfMissing([NSMutableDictionary class], @selector(setObject:forKeyedSubscript:), (IMP)dictSet, "v@:@@");
    addIfMissing([NSArray class], @selector(objectAtIndexedSubscript:), (IMP)arrayGet, "@@:I");
    addIfMissing([NSMutableArray class], @selector(setObject:atIndexedSubscript:), (IMP)arraySet, "v@:@I");
}
@end

@implementation UISlider (MeshCompat)
- (void)mesh_tint:(UIColor *)color {
    if ([self respondsToSelector:@selector(setMinimumTrackTintColor:)]) [self setMinimumTrackTintColor:color];
    if ([self respondsToSelector:@selector(setThumbTintColor:)]) [self setThumbTintColor:color];
}
@end

@implementation UIViewController (MeshCompat)

- (void)mesh_present:(UIViewController *)vc animated:(BOOL)animated {
    if ([self respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        [self presentViewController:vc animated:animated completion:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self presentModalViewController:vc animated:animated];
#pragma clang diagnostic pop
    }
}

- (void)mesh_dismissAnimated:(BOOL)animated {
    if ([self respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        [self dismissViewControllerAnimated:animated completion:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self dismissModalViewControllerAnimated:animated];
#pragma clang diagnostic pop
    }
}

- (void)mesh_dismissPresentedAnimated:(BOOL)animated {
    UIViewController *shown;
    if ([self respondsToSelector:@selector(presentedViewController)]) {
        shown = self.presentedViewController;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        shown = self.modalViewController;
#pragma clang diagnostic pop
    }
    if (shown) [shown mesh_dismissAnimated:animated];
}

- (void)mesh_useFullScreenLayout {
    // Per KVC, weil das Property im iOS-7-SDK nicht mehr deklariert ist.
    if ([self respondsToSelector:NSSelectorFromString(@"setWantsFullScreenLayout:")])
        [self setValue:@YES forKey:@"wantsFullScreenLayout"];
}

@end
