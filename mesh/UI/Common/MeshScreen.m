#import "MeshScreen.h"
#import <objc/runtime.h>
#import "MeshCompat.h"
#import "MeshTheme.h"

// Hält die Tastatur-Beobachtung einer Seite; lebt so lange wie deren View (assoziiertes Objekt).
@interface MeshKeyboardGuard : NSObject
@property (nonatomic) BOOL avoids;
@end

@implementation MeshKeyboardGuard {
    MESH_WEAK UIView *_root;
    MESH_WEAK UIScrollView *_scroll;   // dessen Einrückung gerade angepasst ist
    UIEdgeInsets _savedInset;
    CGFloat _shift;                    // so weit ist die Seite hochgerückt
}

- (instancetype)initWithView:(UIView *)root {
    if ((self = [super init])) {
        _root = root;
        _avoids = YES;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(keyboardShows:) name:UIKeyboardWillShowNotification object:nil];
        [nc addObserver:self selector:@selector(keyboardHides:) name:UIKeyboardWillHideNotification object:nil];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
        tap.cancelsTouchesInView = NO;   // Knöpfe und Zeilen bekommen den Tipp trotzdem
        [root addGestureRecognizer:tap];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)tapped { [_root endEditing:YES]; }

static UIView *firstResponderIn(UIView *v) {
    if (v.isFirstResponder) return v;
    for (UIView *sub in v.subviews) { UIView *r = firstResponderIn(sub); if (r) return r; }
    return nil;
}

- (void)keyboardShows:(NSNotification *)n {
    if (!_avoids || !_root.window) return;
    UIView *field = firstResponderIn(_root);
    if (!field) return;
    CGRect kb = [_root convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    [self restore];
    // Bewusst ein Stück Luft unter dem Feld (Knopf darunter, Fehlerzeile).
    CGRect f = [_root convertRect:field.bounds fromView:field];
    CGFloat overlap = CGRectGetMaxY(f) + 12 - CGRectGetMinY(kb);
    if (overlap <= 0) return;
    UIView *v = field.superview;
    while (v && v != _root && ![v isKindOfClass:[UIScrollView class]]) v = v.superview;
    if ([v isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scroll = (UIScrollView *)v;
        _scroll = scroll;
        _savedInset = scroll.contentInset;
        CGRect inRoot = [_root convertRect:scroll.bounds fromView:scroll];
        UIEdgeInsets inset = _savedInset;
        inset.bottom = MAX(inset.bottom, CGRectGetMaxY(inRoot) - CGRectGetMinY(kb));
        scroll.contentInset = inset;
        scroll.scrollIndicatorInsets = inset;
        [scroll scrollRectToVisible:CGRectInset([scroll convertRect:field.bounds fromView:field], 0, -12) animated:YES];
        return;
    }
    _shift = overlap;
    [UIView animateWithDuration:0.25 animations:^{ self->_root.transform = CGAffineTransformMakeTranslation(0, -self->_shift); }];
}

- (void)keyboardHides:(NSNotification *)n {
    [UIView animateWithDuration:0.25 animations:^{ [self restore]; }];
}

- (void)restore {
    if (_scroll) { _scroll.contentInset = _savedInset; _scroll.scrollIndicatorInsets = _savedInset; _scroll = nil; }
    if (_shift) { _root.transform = CGAffineTransformIdentity; _shift = 0; }
}

@end

static char kGuardKey;

@implementation UIViewController (MeshScreen)

- (void)mesh_loadScreen {
    [self mesh_useFullScreenLayout];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [MeshTheme bg];
    objc_setAssociatedObject(self.view, &kGuardKey, [[MeshKeyboardGuard alloc] initWithView:self.view], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)mesh_setAvoidsKeyboard:(BOOL)avoids {
    MeshKeyboardGuard *guard = objc_getAssociatedObject(self.view, &kGuardKey);
    guard.avoids = avoids;
}

@end
