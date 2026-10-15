#import "MeshKeyboard.h"
#import <QuartzCore/QuartzCore.h>
#import "MeshKeyboardLayout.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshEmoji.h"
#import "MeshL10n.h"

static const CGFloat kHeight = 216, kKeyRadius = 5;
static const CGFloat kEmojiBar = 40, kEmojiSize = 30;
static const int kEmojiCols = 8, kEmojiRows = 4, kRecentMax = kEmojiCols * kEmojiRows;
static NSString *const kLayoutDefault = @"MeshKeyboardLayout";   // nur "de"/"en" – nie Getipptes
NSString *const MeshKeyTargetDidBeginEditingNotification = @"MeshKeyTargetDidBeginEditing";
NSString *const MeshKeyTargetDidEndEditingNotification = @"MeshKeyTargetDidEndEditing";

typedef NS_ENUM(NSInteger, MeshShift) { MeshShiftOff, MeshShiftOnce, MeshShiftLock };

static UIFont *font(NSString *name, CGFloat size) {
    return [UIFont fontWithName:name size:size] ?: [UIFont systemFontOfSize:size];
}

static void click(void) {
    UIDevice *d = [UIDevice currentDevice];
    if ([d respondsToSelector:@selector(playInputClick)]) [d playInputClick];
}

#pragma mark - Emojis

// Sichtbare Schlüssel je Gruppe; einmal berechnet (beim ersten Anhängen im Hintergrund vorgewärmt).
static NSArray *emojiGroups(void) {
    static NSArray *groups;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ groups = [MeshKeyboardLayout groupEmojiKeys:[MeshEmoji allKeys]]; });
    return groups;
}

// Zuletzt benutzte Emojis: nur im Speicher, nie gesichert.
static NSMutableArray *recentEmojis(void) {
    static NSMutableArray *recent;
    if (!recent) recent = [NSMutableArray array];
    return recent;
}

// Eine Seite Emojis als ein Bild (im Hintergrund gezeichnet: am A4 dauert das Auspacken ~1 ms je Emoji).
static UIImage *renderEmojiPage(NSArray *keys, CGSize size, CGFloat scale) {
    CGFloat cw = size.width / kEmojiCols, ch = size.height / kEmojiRows;
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    for (NSUInteger i = 0; i < keys.count; i++) {
        UIImage *img = [MeshEmoji imageForKey:keys[i]];
        if (!img) continue;
        CGFloat x = (i % kEmojiCols) * cw, y = (i / kEmojiCols) * ch;
        [img drawInRect:CGRectMake(roundf(x + (cw - kEmojiSize) / 2), roundf(y + (ch - kEmojiSize) / 2), kEmojiSize, kEmojiSize)];
    }
    UIImage *page = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return page;
}

// Emoji-Fläche: waagerecht blätterndes Raster, unten Gruppen, ABC und ⌫. Gezeichnet werden nur die
// sichtbare Seite und ihre Nachbarn; fertige Seitenbilder hält ein kleiner Cache.
@interface MeshEmojiPane : UIView <UIScrollViewDelegate>
@property (nonatomic, copy) void (^onEmoji)(NSString *text);
@property (nonatomic, copy) void (^onLetters)(void);
@property (nonatomic, copy) void (^onDeleteDown)(void);
@property (nonatomic, copy) void (^onDeleteUp)(void);
- (void)prepare;          // beim Zeigen
- (void)releaseImages;    // Tastatur weg: Speicher frei
@end

@implementation MeshEmojiPane {
    UIScrollView *_scroll;
    UIView *_flash;
    NSMutableArray *_tabs;
    NSMutableArray *_pageGroup, *_pageKeys;    // je Seite: Gruppe (0 = zuletzt, 1… = Gruppen) und Schlüssel
    NSInteger _groupFirstPage[MeshEmojiGroupCount + 1];
    NSMutableDictionary *_pageViews;           // Seite -> UIImageView (nur sichtbar ± 1)
    NSMutableArray *_spareViews;
    NSCache *_pageCache;
    NSInteger _current, _recentGeneration;
    NSArray *_shownRecent;                     // was die Seite "Zuletzt" gerade zeigt (Tipps treffen das Bild)
    dispatch_queue_t _queue;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [MeshTheme bg];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _pageViews = [NSMutableDictionary dictionary];
        _spareViews = [NSMutableArray array];
        _pageCache = [[NSCache alloc] init];
        _pageCache.countLimit = 4;
        _queue = dispatch_queue_create("mesh.keyboard.emoji", DISPATCH_QUEUE_SERIAL);
        _current = -1;

        CGFloat W = frame.size.width, gridH = frame.size.height - kEmojiBar;
        _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, W, gridH)];
        _scroll.pagingEnabled = YES;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.scrollsToTop = NO;
        _scroll.delegate = self;
        [_scroll addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
        [self addSubview:_scroll];
        _flash = [[UIView alloc] init];
        _flash.backgroundColor = [MeshTheme line];
        _flash.layer.cornerRadius = 6;
        _flash.alpha = 0;
        [_scroll addSubview:_flash];

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, gridH, W, kEmojiBar)];
        bar.backgroundColor = [MeshTheme surface];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        [bar addSubview:line];
        [self addSubview:bar];

        CGFloat side = 44, tabW = (W - 2 * side) / (MeshEmojiGroupCount + 1);
        UIButton *abc = [UIButton buttonWithType:UIButtonTypeCustom];
        abc.frame = CGRectMake(0, 0, side, kEmojiBar);
        abc.titleLabel.font = font(@"HelveticaNeue-Medium", 14);
        [abc setTitle:@"ABC" forState:UIControlStateNormal];
        [abc setTitleColor:[MeshTheme ink] forState:UIControlStateNormal];
        [abc setTitleColor:[MeshTheme accent] forState:UIControlStateHighlighted];
        [abc addTarget:self action:@selector(tapLetters) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:abc];

        NSArray *icons = @[@"1f600", @"1f43b", @"1f354", @"26bd", @"1f697", @"1f4a1", @"2764", @"1f3f3"];
        _tabs = [NSMutableArray array];
        for (int t = 0; t <= MeshEmojiGroupCount; t++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(side + t * tabW, 4, tabW, kEmojiBar - 8);
            b.tag = t;
            b.layer.cornerRadius = 6;
            b.adjustsImageWhenHighlighted = NO;
            UIImage *img = t ? [MeshEmoji imageForKey:icons[t - 1]] : [MeshGlyphs icon:@"timer" color:[MeshTheme ink] size:20];
            UIImageView *iv = [[UIImageView alloc] initWithImage:img];
            iv.frame = CGRectMake((tabW - 20) / 2, (kEmojiBar - 8 - 20) / 2, 20, 20);
            iv.userInteractionEnabled = NO;
            [b addSubview:iv];
            [b addTarget:self action:@selector(tapTab:) forControlEvents:UIControlEventTouchUpInside];
            [bar addSubview:b];
            [_tabs addObject:b];
        }

        UIButton *del = [UIButton buttonWithType:UIButtonTypeCustom];
        del.frame = CGRectMake(W - side, 0, side, kEmojiBar);
        [del setImage:[MeshGlyphs icon:@"backspace" color:[MeshTheme ink] size:22] forState:UIControlStateNormal];
        [del setImage:[MeshGlyphs icon:@"backspace" color:[MeshTheme accent] size:22] forState:UIControlStateHighlighted];
        [del addTarget:self action:@selector(deleteDown) forControlEvents:UIControlEventTouchDown];
        [del addTarget:self action:@selector(deleteUp)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [bar addSubview:del];
    }
    return self;
}

- (void)dealloc { _scroll.delegate = nil; mesh_dispatch_release(_queue); }

- (CGSize)pageSize { return _scroll.bounds.size; }

// Seiten: "Zuletzt" immer als erste, dann jede Gruppe ab einer neuen Seite.
- (void)buildPages {
    if (_pageGroup) return;
    _pageGroup = [NSMutableArray array];
    _pageKeys = [NSMutableArray array];
    _groupFirstPage[0] = 0;
    [_pageGroup addObject:@0];
    [_pageKeys addObject:@[]];
    NSArray *groups = emojiGroups();
    for (int g = 0; g < MeshEmojiGroupCount; g++) {
        NSArray *keys = groups[g];
        _groupFirstPage[g + 1] = (NSInteger)_pageGroup.count;
        for (NSUInteger i = 0; i < keys.count; i += kRecentMax) {
            [_pageGroup addObject:@(g + 1)];
            [_pageKeys addObject:[keys subarrayWithRange:NSMakeRange(i, MIN((NSUInteger)kRecentMax, keys.count - i))]];
        }
    }
    _scroll.contentSize = CGSizeMake(_pageGroup.count * _scroll.bounds.size.width, _scroll.bounds.size.height);
}

- (void)prepare {
    [self buildPages];
    [_pageCache removeObjectForKey:@0];
    _recentGeneration++;
    // Mit Verlauf auf "Zuletzt", sonst bei den Smileys
    NSInteger page = recentEmojis().count ? 0 : _groupFirstPage[1];
    _current = -1;
    _scroll.contentOffset = CGPointMake(page * _scroll.bounds.size.width, 0);
    [self showPagesAround:page];
}

- (void)releaseImages {
    for (UIImageView *v in [_pageViews allValues]) { v.image = nil; [v removeFromSuperview]; [_spareViews addObject:v]; }
    [_pageViews removeAllObjects];
    [_pageCache removeAllObjects];
    _current = -1;
}

- (NSArray *)keysForPage:(NSInteger)page {
    return page == 0 ? _shownRecent : _pageKeys[page];
}

- (void)showPagesAround:(NSInteger)page {
    if (page == _current) return;
    _current = page;
    for (UIButton *b in _tabs) {
        BOOL on = b.tag == [_pageGroup[page] integerValue];
        b.backgroundColor = on ? [MeshTheme surfaceHi] : [UIColor clearColor];
        b.alpha = on ? 1 : 0.5f;
    }
    for (NSNumber *n in [_pageViews allKeys]) {
        if (labs([n integerValue] - page) <= 1) continue;
        UIImageView *v = _pageViews[n];
        v.image = nil;
        [v removeFromSuperview];
        [_spareViews addObject:v];
        [_pageViews removeObjectForKey:n];
    }
    // Erst die sichtbare Seite, dann die Nachbarn
    NSInteger order[3] = { page, page + 1, page - 1 };
    for (int i = 0; i < 3; i++) {
        NSInteger p = order[i];
        if (p < 0 || p >= (NSInteger)_pageGroup.count || _pageViews[@(p)]) continue;
        UIImageView *v = [_spareViews lastObject];
        if (v) [_spareViews removeLastObject]; else v = [[UIImageView alloc] init];
        CGSize ps = [self pageSize];
        v.frame = CGRectMake(p * ps.width, 0, ps.width, ps.height);
        [_scroll insertSubview:v belowSubview:_flash];
        _pageViews[@(p)] = v;
        [self fillPage:p view:v];
    }
}

- (void)fillPage:(NSInteger)page view:(UIImageView *)v {
    UIImage *cached = [_pageCache objectForKey:@(page)];
    v.image = cached;
    if (cached) return;
    if (page == 0) _shownRecent = [recentEmojis() copy];
    NSArray *keys = [self keysForPage:page];
    if (!keys.count) return;
    CGSize size = [self pageSize];
    CGFloat scale = [UIScreen mainScreen].scale;
    NSInteger generation = _recentGeneration;
    MESH_WEAK MeshEmojiPane *weakSelf = self;
    dispatch_async(_queue, ^{
        UIImage *img = renderEmojiPage(keys, size, scale);
        dispatch_async(dispatch_get_main_queue(), ^{
            MeshEmojiPane *me = weakSelf;
            if (!me || !img || (page == 0 && generation != me->_recentGeneration)) return;
            [me->_pageCache setObject:img forKey:@(page)];
            UIImageView *view = me->_pageViews[@(page)];
            if (view) view.image = img;
        });
    });
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    CGFloat w = sv.bounds.size.width;
    if (w <= 0 || !_pageGroup.count) return;
    NSInteger page = (NSInteger)floorf((sv.contentOffset.x + w / 2) / w);
    [self showPagesAround:MAX(0, MIN(page, (NSInteger)_pageGroup.count - 1))];
}

- (void)tapTab:(UIButton *)b {
    click();
    NSInteger page = _groupFirstPage[b.tag];
    [_scroll setContentOffset:CGPointMake(page * _scroll.bounds.size.width, 0) animated:NO];
    [self showPagesAround:page];
}

- (void)tap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:_scroll];
    CGSize ps = [self pageSize];
    NSInteger page = (NSInteger)(p.x / ps.width);
    if (page < 0 || page >= (NSInteger)_pageGroup.count) return;
    CGFloat cw = ps.width / kEmojiCols, ch = ps.height / kEmojiRows;
    NSInteger col = (NSInteger)((p.x - page * ps.width) / cw), row = (NSInteger)(p.y / ch);
    if (col < 0 || col >= kEmojiCols || row < 0 || row >= kEmojiRows) return;
    NSArray *keys = [self keysForPage:page];
    NSUInteger i = (NSUInteger)(row * kEmojiCols + col);
    if (i >= keys.count) return;
    NSString *key = keys[i];
    click();
    _flash.frame = CGRectMake(page * ps.width + col * cw + 2, row * ch + 2, cw - 4, ch - 4);
    _flash.alpha = 1;
    [UIView animateWithDuration:0.25 animations:^{ self->_flash.alpha = 0; }];

    NSMutableArray *recent = recentEmojis();
    [recent removeObject:key];
    [recent insertObject:key atIndex:0];
    if (recent.count > kRecentMax) [recent removeLastObject];
    // "Zuletzt" neu zeichnen, aber nicht unter dem Finger umsortieren
    if (page != 0) {
        [_pageCache removeObjectForKey:@0];
        _recentGeneration++;
        UIImageView *rv = _pageViews[@0];
        if (rv) [self fillPage:0 view:rv];
    }

    if (_onEmoji) _onEmoji([MeshKeyboardLayout stringForEmojiKey:key]);
}

- (void)tapLetters { click(); if (_onLetters) _onLetters(); }
- (void)deleteDown { if (_onDeleteDown) _onDeleteDown(); }
- (void)deleteUp   { if (_onDeleteUp) _onDeleteUp(); }

@end

#pragma mark - Tastatur

// Ein Finger auf einer Taste.
@interface MeshKeyTouch : NSObject {
@public
    __unsafe_unretained UITouch *touch;   // nur zum Vergleichen, UIKit hält die Berührung
    NSInteger key;
    BOOL done;
    NSTimer *hold;                        // langer Druck -> Varianten
}
@end
@implementation MeshKeyTouch
@end

@implementation MeshKeyboard {
    MESH_WEAK UIResponder<UIKeyInput> *_target;   // UITextField, UITextView oder MeshKeyTarget
    NSString *_lang;
    MeshKeyPage _page;
    MeshShift _shift;
    CFTimeInterval _lastShiftTap;
    BOOL _secure, _sawChange, _emojiShown;
    MeshAutoCap _autoCap;
    NSUInteger _capsLen, _capsHash;       // Stand, zu dem die Groß-Automatik zuletzt entschied (kein Text)
    NSString *_returnTitle, *_built;
    NSArray *_keys;                       // MeshKeySpec
    NSMutableArray *_keyViews;
    UIView *_keysView;
    MeshEmojiPane *_emoji;
    NSMutableArray *_touches;             // MeshKeyTouch
    NSTimer *_repeat;
    int _repeatCount;
    UIView *_preview;
    UILabel *_previewLabel;
    UIView *_variantBar;
    NSArray *_variants;
    NSInteger _variantIndex;
    MeshKeyTouch *_variantTouch;
}

+ (MeshKeyboard *)shared {
    static MeshKeyboard *kb;
    if (!kb) {
        CGFloat W = [UIScreen mainScreen].bounds.size.width;
        kb = [[MeshKeyboard alloc] initWithFrame:CGRectMake(0, 0, W, kHeight)];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{ emojiGroups(); });
    }
    return kb;
}

+ (void)attachTo:(UIResponder<UIKeyInput> *)field {
    if ([field respondsToSelector:@selector(setInputView:)]) [(id)field setInputView:[self shared]];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [MeshTheme bg];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.multipleTouchEnabled = YES;
        self.clipsToBounds = NO;   // Vorschau und Varianten ragen über die oberste Reihe hinaus
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self addSubview:line];
        _keysView = [[UIView alloc] initWithFrame:self.bounds];
        _keysView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _keysView.userInteractionEnabled = NO;   // Berührungen wertet die Tastatur selbst aus
        [self addSubview:_keysView];
        _keyViews = [NSMutableArray array];
        _touches = [NSMutableArray array];

        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kLayoutDefault];
        NSArray *loc = [[NSBundle mainBundle] preferredLocalizations];
        NSString *app = loc.count ? loc[0] : @"en";
        _lang = [saved isEqualToString:@"de"] || [saved isEqualToString:@"en"] ? saved : ([app hasPrefix:@"de"] ? @"de" : @"en");

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(beganEditing:) name:UITextFieldTextDidBeginEditingNotification object:nil];
        [nc addObserver:self selector:@selector(beganEditing:) name:UITextViewTextDidBeginEditingNotification object:nil];
        [nc addObserver:self selector:@selector(endedEditing:) name:UITextFieldTextDidEndEditingNotification object:nil];
        [nc addObserver:self selector:@selector(endedEditing:) name:UITextViewTextDidEndEditingNotification object:nil];
        [nc addObserver:self selector:@selector(textChanged:) name:UITextFieldTextDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(textChanged:) name:UITextViewTextDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(beganEditing:) name:MeshKeyTargetDidBeginEditingNotification object:nil];
        [nc addObserver:self selector:@selector(endedEditing:) name:MeshKeyTargetDidEndEditingNotification object:nil];
    }
    return self;
}

- (BOOL)enableInputClicksWhenVisible { return YES; }

#pragma mark - Feld

- (void)beganEditing:(NSNotification *)n {
    id field = n.object;
    if (![field respondsToSelector:@selector(inputView)] || [field inputView] != self) return;
    [self cancelTouches];
    _target = field;
    _secure = [field respondsToSelector:@selector(isSecureTextEntry)] && [field isSecureTextEntry];
    _autoCap = [field respondsToSelector:@selector(autocapitalizationType)] ? (MeshAutoCap)[field autocapitalizationType] : MeshAutoCapSentences;
    UIReturnKeyType rt = [field respondsToSelector:@selector(returnKeyType)] ? [field returnKeyType] : UIReturnKeyDefault;
    _returnTitle = [self titleForReturn:rt];
    UIKeyboardType kt = [field respondsToSelector:@selector(keyboardType)] ? [field keyboardType] : UIKeyboardTypeDefault;
    _page = kt == UIKeyboardTypeNumberPad ? MeshKeyPagePad
          : kt == UIKeyboardTypeDecimalPad ? MeshKeyPageDecimalPad
          : kt == UIKeyboardTypePhonePad ? MeshKeyPagePhonePad
          : kt == UIKeyboardTypeNumbersAndPunctuation ? MeshKeyPageNumbers : MeshKeyPageLetters;
    _shift = MeshShiftOff;
    [self showEmoji:NO];
    [self rebuild];
    [self updateAutoShift];
}

- (void)endedEditing:(NSNotification *)n {
    if (n.object != _target) return;
    [self cancelTouches];
    _target = nil;
}

- (void)textChanged:(NSNotification *)n {
    if (n.object == _target) _sawChange = YES;
}

- (NSString *)titleForReturn:(UIReturnKeyType)t {
    switch (t) {
        case UIReturnKeyGo:            return L(@"Go");
        case UIReturnKeyGoogle:
        case UIReturnKeyYahoo:
        case UIReturnKeySearch:        return L(@"Search");
        case UIReturnKeyJoin:          return L(@"Join");
        case UIReturnKeyNext:          return L(@"Next");
        case UIReturnKeyRoute:         return L(@"Route");
        case UIReturnKeySend:          return L(@"Send");
        case UIReturnKeyDone:          return L(@"Done");
        case UIReturnKeyEmergencyCall: return L(@"Emergency call");
        default:                       return L(@"return");
    }
}

#pragma mark - Text ändern (wie UIKit: erst den Delegate fragen)

- (NSString *)fieldText {
    id t = _target;
    NSString *s = [t respondsToSelector:@selector(text)] ? [t text] : nil;
    return s ?: @"";
}

- (BOOL)ownTarget { return [_target conformsToProtocol:@protocol(MeshKeyTarget)]; }

- (NSRange)selection {
    NSUInteger len = [self fieldText].length;
    if ([self ownTarget]) {
        NSRange r = [(id<MeshKeyTarget>)_target selectedRange];
        return NSMaxRange(r) <= len ? r : NSMakeRange(len, 0);
    }
    UIResponder<UITextInput> *t = (UIResponder<UITextInput> *)_target;
    UITextRange *r = t.selectedTextRange;
    if (!r) return NSMakeRange(len, 0);
    NSInteger a = [t offsetFromPosition:t.beginningOfDocument toPosition:r.start];
    NSInteger b = [t offsetFromPosition:t.beginningOfDocument toPosition:r.end];
    a = MAX(0, MIN(a, (NSInteger)len));
    b = MAX(a, MIN(b, (NSInteger)len));
    return NSMakeRange((NSUInteger)a, (NSUInteger)(b - a));
}

// Wie UIKit beim Tippen: erst den Delegate fragen. NO = abgelehnt (oder Feld gewechselt).
- (BOOL)mayReplace:(NSRange)range with:(NSString *)s {
    UIResponder<UIKeyInput> *t = _target;
    if (!t) return NO;
    if ([t isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)t;
        id<UITextFieldDelegate> d = tf.delegate;
        if ([d respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)]
            && ![d textField:tf shouldChangeCharactersInRange:range replacementString:s]) { [self updateAutoShift]; return NO; }
    } else if ([t isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)t;
        id<UITextViewDelegate> d = tv.delegate;
        if ([d respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]
            && ![d textView:tv shouldChangeTextInRange:range replacementText:s]) { [self updateAutoShift]; return NO; }
    }
    return _target == t;   // der Delegate kann das Feld gewechselt haben
}

// Meldungen wie beim Tippen, falls UIKit sie nicht selbst schickt
- (void)didChange {
    UIResponder<UIKeyInput> *t = _target;
    if (!_sawChange) {
        if ([t isKindOfClass:[UITextField class]]) {
            [(UITextField *)t sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:t];
        } else if ([t isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)t;
            if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) [tv.delegate textViewDidChange:tv];
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
        }
    }
    [self updateAutoShift];
}

// Einfügen und Löschen an der Auswahl laufen über UIKeyInput wie echtes Tippen: der Feld-Editor von
// iOS 6 zählt Positionen nicht in UTF-16, nach einem Emoji (2 Einheiten) liefen Offsets ins Leere
// und weder Text noch ein weiteres Emoji kam an.
- (void)insert:(NSString *)s {
    UIResponder<UIKeyInput> *t = _target;
    if (!t || !s.length || ![self mayReplace:[self selection] with:s]) return;
    _sawChange = NO;
    [t insertText:s];
    [self didChange];
}

- (void)deleteBackward {
    UIResponder<UIKeyInput> *t = _target;
    if (!t) return;
    if ([self ownTarget]) { [t deleteBackward]; [self didChange]; return; }   // löscht selbst ganze Zeichen
    NSRange sel = [self selection];
    if (!sel.length) {
        if (!sel.location) return;
        NSRange r = [MeshKeyboardLayout deleteRangeIn:[self fieldText] cursor:sel.location];
        if (!r.length) return;
        if (r.length > 2) {   // Emoji-Folge (ZWJ, Hautfarbe): als Ganzes, über Offsets
            [self replaceRange:r with:@""];
            return;
        }
        sel = r;
    }
    if (![self mayReplace:sel with:@""]) return;
    _sawChange = NO;
    [t deleteBackward];
    [self didChange];
}

// Beliebigen Bereich ersetzen (über UITextInput-Offsets)
- (void)replaceRange:(NSRange)range with:(NSString *)s {
    UIResponder<UITextInput> *t = (UIResponder<UITextInput> *)_target;
    if (![t conformsToProtocol:@protocol(UITextInput)]) return;
    if (![self mayReplace:range with:s]) return;
    UITextPosition *a = [t positionFromPosition:t.beginningOfDocument offset:(NSInteger)range.location];
    UITextPosition *b = a ? [t positionFromPosition:a offset:(NSInteger)range.length] : nil;
    if (!a || !b) return;
    _sawChange = NO;
    [t replaceRange:[t textRangeFromPosition:a toPosition:b] withText:s];
    UITextPosition *caret = [t positionFromPosition:t.beginningOfDocument offset:(NSInteger)(range.location + s.length)];
    if (caret) t.selectedTextRange = [t textRangeFromPosition:caret toPosition:caret];
    [self didChange];
}

- (void)pressReturn {
    UIResponder<UIKeyInput> *t = _target;
    if ([self ownTarget]) {
        [(id<MeshKeyTarget>)t returnPressed];
        [self recheckAutoShift];
    } else if ([t isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)t;
        id<UITextFieldDelegate> d = tf.delegate;
        BOOL ok = [d respondsToSelector:@selector(textFieldShouldReturn:)] ? [d textFieldShouldReturn:tf] : YES;
        if (ok && _target == tf) {
            [tf sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
            if ([tf allControlEvents] & UIControlEventEditingDidEndOnExit) [tf resignFirstResponder];
        }
    } else if (t) {
        [self insert:@"\n"];
    }
}

// Groß-Automatik nach Feldeinstellung (Satz-/Wortanfang); Feststellen bleibt.
- (void)updateAutoShift {
    if (_page != MeshKeyPageLetters || _shift == MeshShiftLock) return;
    NSRange sel = [self selection];
    NSString *before = [[self fieldText] substringToIndex:sel.location];
    MeshShift old = _shift;
    _shift = _target && [MeshKeyboardLayout shouldCapitalizeAfter:before mode:_autoCap] ? MeshShiftOnce : MeshShiftOff;
    _capsLen = before.length;
    _capsHash = before.hash;
    if (_shift != old) [self refreshKeys];   // sonst nichts neu zeichnen (A4)
}

// Text von außen geändert (z. B. nach dem Senden geleert)? Dann vor dem nächsten Zeichen neu entscheiden.
- (void)recheckAutoShift {
    if (_page != MeshKeyPageLetters || _shift == MeshShiftLock || !_target) return;
    NSString *before = [[self fieldText] substringToIndex:[self selection].location];
    if (before.length != _capsLen || before.hash != _capsHash) [self updateAutoShift];
}

#pragma mark - Tasten

- (void)rebuild {
    CGSize size = self.bounds.size;
    NSString *decimal = [[NSLocale currentLocale] objectForKey:NSLocaleDecimalSeparator];
    NSString *sig = [NSString stringWithFormat:@"%d|%@|%.0f|%@", (int)_page, _lang, size.width, decimal];
    if (![sig isEqualToString:_built]) {
        _built = sig;
        for (UIView *v in _keyViews) [v removeFromSuperview];
        [_keyViews removeAllObjects];
        _keys = [MeshKeyboardLayout keysForPage:_page language:_lang size:size decimal:decimal];
        for (MeshKeySpec *k in _keys) {
            UIView *v = [[UIView alloc] initWithFrame:k.frame];
            v.layer.cornerRadius = kKeyRadius;
            v.userInteractionEnabled = NO;
            UILabel *l = [[UILabel alloc] initWithFrame:v.bounds];
            l.backgroundColor = [UIColor clearColor];
            l.textAlignment = NSTextAlignmentCenter;
            l.adjustsFontSizeToFitWidth = YES;
            l.minimumFontSize = 9;
            l.tag = 1;
            [v addSubview:l];
            UIImageView *iv = [[UIImageView alloc] initWithFrame:v.bounds];
            iv.contentMode = UIViewContentModeCenter;
            iv.tag = 2;
            [v addSubview:iv];
            [_keysView addSubview:v];
            [_keyViews addObject:v];
        }
    }
    [self refreshKeys];
}

- (BOOL)isPad { return _page == MeshKeyPagePad || _page == MeshKeyPageDecimalPad || _page == MeshKeyPagePhonePad; }

- (void)styleKey:(NSUInteger)i pressed:(BOOL)pressed {
    MeshKeySpec *k = _keys[i];
    UIView *v = _keyViews[i];
    UILabel *l = (UILabel *)[v viewWithTag:1];
    UIImageView *iv = (UIImageView *)[v viewWithTag:2];
    UIColor *bg = pressed ? [MeshTheme line] : [MeshTheme surfaceHi], *ink = [MeshTheme ink];
    BOOL special = NO;
    NSString *text = nil, *glyph = nil;
    UIFont *f = font(@"HelveticaNeue", 22);
    switch (k.kind) {
        case MeshKeyChar:
            text = _shift != MeshShiftOff && _page == MeshKeyPageLetters ? [k.text uppercaseString] : k.text;
            if ([self isPad]) f = [MeshTheme keypadFont];
            break;
        case MeshKeySpace:
            text = [_lang isEqualToString:@"de"] ? @"Deutsch" : @"English";   // Belegung, nicht übersetzt
            f = font(@"HelveticaNeue", 14);
            ink = [MeshTheme muted];
            break;
        case MeshKeyReturn:
            text = _returnTitle;
            f = font(@"HelveticaNeue-Medium", 15);
            bg = pressed ? [MeshTheme accentDim] : [MeshTheme accent];
            ink = [MeshTheme bg];
            break;
        case MeshKeyShift:
            special = YES;
            glyph = _shift == MeshShiftLock ? @"capslock" : @"shift";
            if (_shift == MeshShiftOnce) { bg = [MeshTheme ink]; ink = [MeshTheme bg]; special = NO; }
            if (_shift == MeshShiftLock) { bg = [MeshTheme accent]; ink = [MeshTheme bg]; special = NO; }
            break;
        case MeshKeyDelete: special = YES; glyph = @"backspace"; break;
        case MeshKeyGlobe:  special = YES; glyph = @"globe"; break;
        case MeshKeyEmoji:  special = YES; glyph = @"smiley"; break;
        default:            // 123, ABC, #+=
            special = YES;
            text = k.text;
            f = font(@"HelveticaNeue-Medium", 15);
            break;
    }
    if (special) bg = pressed ? [MeshTheme surfaceHi] : [MeshTheme surface];
    v.backgroundColor = bg;
    v.layer.borderWidth = special ? 1 : 0;
    v.layer.borderColor = [MeshTheme line].CGColor;
    if (l.text != text && ![l.text isEqualToString:text]) l.text = text;
    if (l.font != f) l.font = f;
    l.textColor = ink;
    UIImage *img = glyph ? [MeshGlyphs icon:glyph color:ink size:22] : nil;
    if (iv.image != img) iv.image = img;
}

- (void)refreshKeys {
    for (NSUInteger i = 0; i < _keys.count; i++) [self styleKey:i pressed:[self isPressed:i]];
}

- (BOOL)isPressed:(NSUInteger)i {
    for (MeshKeyTouch *t in _touches) if (t->key == (NSInteger)i && !t->done) return YES;
    return NO;
}

- (MeshKeySpec *)spec:(NSInteger)i { return _keys[(NSUInteger)i]; }

- (NSInteger)keyAt:(CGPoint)p {
    for (NSUInteger i = 0; i < _keys.count; i++) if (CGRectContainsPoint([_keys[i] hitFrame], p)) return (NSInteger)i;
    return -1;
}

- (void)setPage:(MeshKeyPage)page {
    _page = page;
    if (page != MeshKeyPageLetters) { if (_shift != MeshShiftLock) _shift = MeshShiftOff; }
    [self rebuild];
    [self updateAutoShift];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_keys) [self rebuild];   // neue Breite: Tasten neu (Signatur verhindert unnötiges Neubauen)
}

#pragma mark - Vorschau und Varianten

- (void)showPreviewForKey:(NSInteger)i {
    MeshKeySpec *k = _keys[i];
    if (_secure || k.kind != MeshKeyChar || [self isPad]) { [self hidePreview]; return; }
    if (!_preview) {
        _preview = [[UIView alloc] init];
        _preview.backgroundColor = [MeshTheme surfaceHi];
        _preview.layer.cornerRadius = 8;
        _preview.layer.borderWidth = 1;
        _preview.layer.borderColor = [MeshTheme line].CGColor;
        _preview.userInteractionEnabled = NO;
        _previewLabel = [[UILabel alloc] init];
        _previewLabel.backgroundColor = [UIColor clearColor];
        _previewLabel.textAlignment = NSTextAlignmentCenter;
        _previewLabel.font = font(@"HelveticaNeue", 32);
        _previewLabel.textColor = [MeshTheme ink];
        [_preview addSubview:_previewLabel];
    }
    CGRect f = k.frame;
    CGFloat w = f.size.width + 22, h = 50;
    CGFloat x = MAX(1, MIN(CGRectGetMidX(f) - w / 2, self.bounds.size.width - w - 1));
    _preview.frame = CGRectMake(x, CGRectGetMinY(f) - h - 2, w, h);
    _previewLabel.frame = _preview.bounds;
    _previewLabel.text = [(UILabel *)[_keyViews[i] viewWithTag:1] text];
    [self addSubview:_preview];
}

- (void)hidePreview { [_preview removeFromSuperview]; }

- (void)holdFired:(NSTimer *)timer {
    MeshKeyTouch *t = timer.userInfo;
    t->hold = nil;
    if (t->done || ![_touches containsObject:t] || _secure) return;
    MeshKeySpec *k = _keys[t->key];
    NSArray *vars = [MeshKeyboardLayout variantsFor:k.text language:_lang];
    if (!vars.count) return;
    BOOL upper = _shift != MeshShiftOff && _page == MeshKeyPageLetters;
    NSMutableArray *shown = [NSMutableArray arrayWithCapacity:vars.count];
    for (NSString *s in vars) [shown addObject:upper && ![s isEqualToString:@"ß"] ? [s uppercaseString] : s];
    _variants = shown;
    _variantTouch = t;
    [self hidePreview];

    CGFloat cw = 30, h = 46, W = self.bounds.size.width, w = cw * shown.count + 8;
    CGRect f = k.frame;
    CGFloat x = MAX(2, MIN(CGRectGetMidX(f) - w / 2, W - w - 2));
    [_variantBar removeFromSuperview];
    _variantBar = [[UIView alloc] initWithFrame:CGRectMake(x, CGRectGetMinY(f) - h - 4, w, h)];
    _variantBar.backgroundColor = [MeshTheme surfaceHi];
    _variantBar.layer.cornerRadius = 8;
    _variantBar.layer.borderWidth = 1;
    _variantBar.layer.borderColor = [MeshTheme line].CGColor;
    _variantBar.userInteractionEnabled = NO;
    for (NSUInteger i = 0; i < shown.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(4 + i * cw, 4, cw, h - 8)];
        l.layer.cornerRadius = 5;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = font(@"HelveticaNeue", 22);
        l.text = shown[i];
        l.tag = 10 + (NSInteger)i;
        [_variantBar addSubview:l];
    }
    [self addSubview:_variantBar];
    [self selectVariantAt:[t->touch locationInView:self]];
}

- (void)selectVariantAt:(CGPoint)p {
    CGFloat x = p.x - _variantBar.frame.origin.x - 4;
    NSInteger i = (NSInteger)floorf(x / 30);
    _variantIndex = MAX(0, MIN(i, (NSInteger)_variants.count - 1));
    for (NSUInteger j = 0; j < _variants.count; j++) {
        UILabel *l = (UILabel *)[_variantBar viewWithTag:10 + (NSInteger)j];
        BOOL on = (NSInteger)j == _variantIndex;
        l.backgroundColor = on ? [MeshTheme accent] : [UIColor clearColor];
        l.textColor = on ? [MeshTheme bg] : [MeshTheme ink];
    }
}

- (void)hideVariants {
    [_variantBar removeFromSuperview];
    _variantBar = nil;
    _variants = nil;
    _variantTouch = nil;
}

#pragma mark - Berührungen

- (MeshKeyTouch *)trackerFor:(UITouch *)touch {
    for (MeshKeyTouch *t in _touches) if (t->touch == touch) return t;
    return nil;
}

- (void)finish:(MeshKeyTouch *)t {
    [t->hold invalidate];
    t->hold = nil;
    t->done = YES;
    [_touches removeObject:t];
    if (t->key >= 0 && t->key < (NSInteger)_keys.count) [self styleKey:(NSUInteger)t->key pressed:[self isPressed:(NSUInteger)t->key]];
}

// Zeichen schreiben. Ein einmaliges Umschalt ist danach verbraucht: nach jeder Änderung entscheidet die
// Groß-Automatik neu (updateAutoShift), nur Feststellen bleibt.
- (void)typeChar:(NSString *)s {
    MeshShift before = _shift;
    if (_shift == MeshShiftOnce) _shift = MeshShiftOff;
    [self insert:s];
    [self updateAutoShift];
    if (_shift != before) [self refreshKeys];
}

- (NSString *)charFor:(MeshKeySpec *)k {
    return _shift != MeshShiftOff && _page == MeshKeyPageLetters ? [k.text uppercaseString] : k.text;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_emojiShown) return;   // Emoji-Fläche: deren Leiste reicht freie Stellen hierher durch
    for (UITouch *touch in touches) {
        NSInteger i = [self keyAt:[touch locationInView:self]];
        if (i < 0 || _variantTouch) continue;
        MeshKeySpec *k = _keys[i];
        // Schnelles Tippen mit zwei Daumen: ein noch gehaltenes Zeichen zuerst schreiben
        for (MeshKeyTouch *o in [_touches copy]) {
            if (o->done || [self spec:o->key].kind != MeshKeyChar) continue;
            [self finish:o];
            [self typeChar:[self charFor:_keys[o->key]]];
        }
        [self recheckAutoShift];
        MeshKeyTouch *t = [[MeshKeyTouch alloc] init];
        t->touch = touch;
        t->key = i;
        [_touches addObject:t];
        [self styleKey:(NSUInteger)i pressed:YES];
        click();
        switch (k.kind) {
            case MeshKeyChar:
                [self showPreviewForKey:i];
                if (!_secure && [MeshKeyboardLayout variantsFor:k.text language:_lang])
                    t->hold = [NSTimer scheduledTimerWithTimeInterval:0.45 target:self selector:@selector(holdFired:) userInfo:t repeats:NO];
                break;
            case MeshKeyDelete:
                [self startDeleteRepeat];
                break;
            case MeshKeyShift: {
                CFTimeInterval now = CACurrentMediaTime();
                if (_shift == MeshShiftLock) _shift = MeshShiftOff;
                else if (_shift == MeshShiftOnce && now - _lastShiftTap < 0.35) _shift = MeshShiftLock;
                else _shift = _shift == MeshShiftOff ? MeshShiftOnce : MeshShiftOff;
                _lastShiftTap = now;
                [self refreshKeys];
                break;
            }
            default: break;
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        MeshKeyTouch *t = [self trackerFor:touch];
        if (!t || t->done) continue;
        CGPoint p = [touch locationInView:self];
        if (t == _variantTouch) { [self selectVariantAt:p]; continue; }
        if ([self spec:t->key].kind != MeshKeyChar) continue;
        // Über die Zeichen gleiten: die Taste unter dem Finger zählt
        NSInteger i = [self keyAt:p];
        if (i < 0 || i == t->key || [self spec:i].kind != MeshKeyChar) continue;
        NSInteger old = t->key;
        t->key = i;
        [self styleKey:(NSUInteger)old pressed:[self isPressed:(NSUInteger)old]];
        [self styleKey:(NSUInteger)i pressed:YES];
        [self showPreviewForKey:i];
        [t->hold invalidate];
        t->hold = nil;
        if (!_secure && [MeshKeyboardLayout variantsFor:[self spec:i].text language:_lang])
            t->hold = [NSTimer scheduledTimerWithTimeInterval:0.45 target:self selector:@selector(holdFired:) userInfo:t repeats:NO];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        MeshKeyTouch *t = [self trackerFor:touch];
        if (!t) continue;
        MeshKeySpec *k = _keys[t->key];
        BOOL inside = CGRectContainsPoint(CGRectInset(k.hitFrame, -12, -12), [touch locationInView:self]);
        if (t == _variantTouch) {
            NSString *v = _variants[_variantIndex];
            [self hideVariants];
            [self finish:t];
            [self typeChar:v];
            continue;
        }
        [self finish:t];
        if (k.kind == MeshKeyChar) [self hidePreview];
        switch (k.kind) {
            case MeshKeyChar:    [self typeChar:[self charFor:k]]; break;
            case MeshKeyDelete:  [self stopDeleteRepeat]; break;
            case MeshKeySpace:   if (inside) [self typeChar:@" "]; break;
            case MeshKeyReturn:  if (inside) [self pressReturn]; break;
            case MeshKeyNumbers: if (inside) [self setPage:MeshKeyPageNumbers]; break;
            case MeshKeyLetters: if (inside) [self setPage:MeshKeyPageLetters]; break;
            case MeshKeySymbols: if (inside) [self setPage:MeshKeyPageSymbols]; break;
            case MeshKeyGlobe:   if (inside) [self toggleLanguage]; break;
            case MeshKeyEmoji:   if (inside) [self showEmoji:YES]; break;
            default: break;
        }
    }
    if (!_touches.count) [self hidePreview];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        MeshKeyTouch *t = [self trackerFor:touch];
        if (!t) continue;
        if (t == _variantTouch) [self hideVariants];
        if ([self spec:t->key].kind == MeshKeyDelete) [self stopDeleteRepeat];
        [self finish:t];
    }
    if (!_touches.count) [self hidePreview];
}

- (void)cancelTouches {
    for (MeshKeyTouch *t in [_touches copy]) [self finish:t];
    [self hideVariants];
    [self hidePreview];
    [self stopDeleteRepeat];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) { if (_emojiShown) [_emoji prepare]; return; }
    [self cancelTouches];
    [_emoji releaseImages];
}

#pragma mark - Löschen mit Wiederholung

- (void)startDeleteRepeat {
    [self stopDeleteRepeat];
    [self deleteBackward];
    _repeatCount = 0;
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(repeatDelete) userInfo:nil repeats:NO];
}

- (void)repeatDelete {
    _repeat = nil;
    if (!_target) return;
    [self deleteBackward];
    click();
    _repeatCount++;
    _repeat = [NSTimer scheduledTimerWithTimeInterval:(_repeatCount > 20 ? 0.05 : 0.1) target:self selector:@selector(repeatDelete)
                                             userInfo:nil repeats:NO];
}

- (void)stopDeleteRepeat { [_repeat invalidate]; _repeat = nil; }

#pragma mark - Sprache und Emojis

- (void)toggleLanguage {
    _lang = [_lang isEqualToString:@"de"] ? @"en" : @"de";
    [[NSUserDefaults standardUserDefaults] setObject:_lang forKey:kLayoutDefault];   // nur die Belegung
    [self rebuild];
}

- (void)showEmoji:(BOOL)show {
    if (show == _emojiShown) return;
    _emojiShown = show;
    if (show && !_emoji) {
        _emoji = [[MeshEmojiPane alloc] initWithFrame:self.bounds];
        MESH_WEAK MeshKeyboard *weakSelf = self;
        _emoji.onEmoji = ^(NSString *text) { [weakSelf insert:text]; };
        _emoji.onLetters = ^{ [weakSelf showEmoji:NO]; [weakSelf setPage:MeshKeyPageLetters]; };
        _emoji.onDeleteDown = ^{ click(); [weakSelf startDeleteRepeat]; };
        _emoji.onDeleteUp = ^{ [weakSelf stopDeleteRepeat]; };
    }
    if (show) {
        [self cancelTouches];
        _emoji.frame = self.bounds;
        [self addSubview:_emoji];
        [_emoji prepare];
    } else {
        [_emoji removeFromSuperview];
        [_emoji releaseImages];
    }
    _keysView.hidden = show;
}

@end
