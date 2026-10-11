#import "MeshPopup.h"
#import "MeshTheme.h"
#import "MeshL10n.h"
#import "MeshEmoji.h"
#import "MeshNotifications.h"

static NSMutableArray *gAlive;   // hält die aktiven Popups am Leben
static NSUInteger gLocks;        // zählt Sperrungen: Handler aus der Zeit davor laufen nicht mehr

@implementation MeshPopup {
    UIView *_overlay;
    UITextField *_field;
    void (^_indexHandler)(NSInteger);
    void (^_inputHandler)(NSString *, BOOL);
}

+ (void)keep:(MeshPopup *)p {
    if (!gAlive) {
        gAlive = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissAll)
                                                     name:MeshWillLockNotification object:nil];
    }
    [gAlive addObject:p];
}

// Beim Sperren: sofort entfernen, ohne Handler aufzurufen (ein offener nsec-Dialog darf nicht bleiben).
+ (void)dismissAll {
    gLocks++;
    for (MeshPopup *p in gAlive) { [p->_field resignFirstResponder]; [p->_overlay removeFromSuperview]; }
    [gAlive removeAllObjects];
}
// Der Handler läuft erst nach der Ausblend-Animation. Wird in dieser Zeit gesperrt, entfällt er,
// sonst ginge etwa der nächste Schritt von "PIN ändern" über dem Sperrbildschirm auf.
- (void)dismissWithIndex:(NSInteger)idx {
    if (!_overlay.userInteractionEnabled) return;   // schon beim Schließen: Doppeltippen zählt einmal
    _overlay.userInteractionEnabled = NO;
    void (^ih)(NSInteger) = _indexHandler;
    NSUInteger locks = gLocks;
    [UIView animateWithDuration:0.18 animations:^{ _overlay.alpha = 0; }
                     completion:^(BOOL f) { [_overlay removeFromSuperview]; [gAlive removeObject:self];
                         if (ih && locks == gLocks) ih(idx); }];
}

- (void)dismissInput:(BOOL)ok {
    if (!_overlay.userInteractionEnabled) return;
    _overlay.userInteractionEnabled = NO;
    NSString *txt = _field.text ?: @"";
    void (^ih)(NSString *, BOOL) = _inputHandler;
    NSUInteger locks = gLocks;
    [_field resignFirstResponder];
    [UIView animateWithDuration:0.18 animations:^{ _overlay.alpha = 0; }
                     completion:^(BOOL f) { [_overlay removeFromSuperview]; [gAlive removeObject:self];
                         if (ih && locks == gLocks) ih(txt, ok); }];
}

- (UIView *)makeOverlay {
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    UIView *ov = [[UIView alloc] initWithFrame:win.bounds];
    ov.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6f];
    ov.alpha = 0;
    [win addSubview:ov];
    return ov;
}
- (UIView *)cardWithWidth:(CGFloat)w {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0)];
    card.backgroundColor = [MeshTheme surface];
    card.layer.cornerRadius = [MeshTheme sheetRadius];
    card.layer.borderWidth = 0.5f;
    card.layer.borderColor = [MeshTheme line].CGColor;
    return card;
}
typedef enum { MeshPopupButtonPlain, MeshPopupButtonAccent, MeshPopupButtonDanger } MeshPopupButtonStyle;

- (UIButton *)button:(NSString *)title style:(MeshPopupButtonStyle)style frame:(CGRect)f {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.layer.cornerRadius = [MeshTheme fieldRadius];
    b.titleLabel.font = [MeshTheme bodyFont];
    [b setTitle:title forState:UIControlStateNormal];
    b.backgroundColor = style == MeshPopupButtonAccent ? [MeshTheme accent] : [MeshTheme surfaceHi];
    UIColor *ink = style == MeshPopupButtonAccent ? [MeshTheme bg] : style == MeshPopupButtonDanger ? [MeshTheme danger] : [MeshTheme ink];
    [b setTitleColor:ink forState:UIControlStateNormal];
    return b;
}
- (UILabel *)label:(NSString *)text frame:(CGRect)f font:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    l.backgroundColor = [UIColor clearColor];
    return l;
}

- (UILabel *)titleLabel:(NSString *)t frame:(CGRect)f { return [self label:t frame:f font:[MeshTheme nameFont] color:[MeshTheme ink]]; }
- (UILabel *)msgLabel:(NSString *)t frame:(CGRect)f   { return [self label:t frame:f font:[MeshTheme bodyFont] color:[MeshTheme muted]]; }
- (void)animateIn:(UIView *)card {
    card.transform = CGAffineTransformMakeScale(0.9f, 0.9f);
    [UIView animateWithDuration:0.2 animations:^{ _overlay.alpha = 1; card.transform = CGAffineTransformIdentity; }];
}

#pragma mark - Hinweis / Bestätigung

// Maße der Karten (Hinweis, Bestätigung, Eingabe) und des Auswahl-Sheets.
static const CGFloat kCardMaxWidth = 300, kCardMargin = 24, kPad = 18;
static const CGFloat kTitleHeight = 24, kTitleStep = 32;
static const CGFloat kButtonHeight = 46, kButtonGap = 10, kFieldHeight = 44, kInputTop = 70;
static const CGFloat kSheetMargin = 10, kSheetRowHeight = 48, kSheetRowGap = 8, kSheetCancelHeight = 50;

static CGFloat cardWidth(CGFloat screen) { return MIN(kCardMaxWidth, screen - 2 * kCardMargin); }

// Zwei Knöpfe nebeneinander (Abbrechen links), Rückgabe: y unter der Reihe.
- (CGFloat)addButtons:(UIView *)card y:(CGFloat)y cancel:(SEL)cancel ok:(SEL)ok title:(NSString *)title style:(MeshPopupButtonStyle)style {
    CGFloat bw = (card.bounds.size.width - 2 * kPad - kButtonGap) / 2;
    UIButton *c = [self button:L(@"Cancel") style:MeshPopupButtonPlain frame:CGRectMake(kPad, y, bw, kButtonHeight)];
    [c addTarget:self action:cancel forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:c];
    UIButton *o = [self button:title style:style frame:CGRectMake(kPad + bw + kButtonGap, y, bw, kButtonHeight)];
    [o addTarget:self action:ok forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:o];
    return y + kButtonHeight;
}

+ (void)info:(NSString *)message {
    [self confirm:nil message:message action:L(@"OK") destructive:NO handler:nil];
}

+ (void)confirm:(NSString *)title message:(NSString *)message
         action:(NSString *)actionTitle destructive:(BOOL)destructive
        handler:(void(^)(BOOL))handler {
    MeshPopup *p = [[MeshPopup alloc] init];
    [MeshPopup keep:p];
    p->_overlay = [p makeOverlay];
    CGFloat W = p->_overlay.bounds.size.width, cw = cardWidth(W), inner = cw - 2 * kPad;
    UIView *card = [p cardWithWidth:cw];
    CGFloat y = 22;
    if (title.length) {
        [card addSubview:[p titleLabel:title frame:CGRectMake(kPad, y, inner, kTitleHeight)]];
        y += kTitleStep;
    }
    CGSize ms = [message sizeWithFont:[MeshTheme bodyFont] constrainedToSize:CGSizeMake(inner, 400) lineBreakMode:NSLineBreakByWordWrapping];
    [card addSubview:[p msgLabel:message frame:CGRectMake(kPad, y, inner, ms.height)]];
    y += ms.height + 20;

    if (handler) {   // Bestätigung: Abbrechen und Aktion
        y = [p addButtons:card y:y cancel:@selector(cancelTap) ok:@selector(okTap) title:actionTitle
                    style:(destructive ? MeshPopupButtonDanger : MeshPopupButtonAccent)];
    } else {         // Hinweis: ein Knopf
        UIButton *ok = [p button:actionTitle style:MeshPopupButtonAccent frame:CGRectMake(kPad, y, inner, kButtonHeight)];
        [ok addTarget:p action:@selector(cancelTap) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:ok];
        y += kButtonHeight;
    }
    card.frame = CGRectMake((W - cw) / 2, 0, cw, y + 20);
    card.center = CGPointMake(W / 2, p->_overlay.bounds.size.height * 0.42f);
    [p->_overlay addSubview:card];
    p->_indexHandler = [^(NSInteger idx) { if (handler) handler(idx == 1); } copy];
    [p animateIn:card];
}

- (void)cancelTap { [self dismissWithIndex:0]; }
- (void)okTap { [self dismissWithIndex:1]; }

#pragma mark - Auswahl-Sheet

+ (void)sheet:(NSString *)title options:(NSArray *)options
 destructiveIndex:(NSInteger)destructiveIndex handler:(void(^)(NSInteger))handler {
    NSIndexSet *red = destructiveIndex >= 0 ? [NSIndexSet indexSetWithIndex:destructiveIndex] : [NSIndexSet indexSet];
    [self sheet:title emojis:nil options:options destructive:red handler:^(NSInteger idx, NSString *emoji) {
        if (handler) handler(idx);
    }];
}

+ (void)sheet:(NSString *)title emojis:(NSArray *)emojis options:(NSArray *)options
 destructiveFrom:(NSInteger)destructiveFrom handler:(void(^)(NSInteger, NSString *))handler {
    NSInteger from = MAX(0, MIN(destructiveFrom, (NSInteger)options.count));
    [self sheet:title emojis:emojis options:options
    destructive:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(from, options.count - from)] handler:handler];
}

static const NSInteger kEmojiTag = 1000;
static const CGFloat kEmojiRowHeight = 50;

+ (void)sheet:(NSString *)title emojis:(NSArray *)emojis options:(NSArray *)options
    destructive:(NSIndexSet *)destructive handler:(void(^)(NSInteger, NSString *))handler {
    MeshPopup *p = [[MeshPopup alloc] init];
    [MeshPopup keep:p];
    NSArray *em = [emojis copy];
    p->_indexHandler = [^(NSInteger idx) {
        if (!handler) return;
        if (idx >= kEmojiTag) handler(-1, em[idx - kEmojiTag]);
        else handler(idx, nil);
    } copy];
    p->_overlay = [p makeOverlay];
    CGFloat W = p->_overlay.bounds.size.width, H = p->_overlay.bounds.size.height, cw = W - 2 * kSheetMargin;
    UIView *card = [p cardWithWidth:cw];
    CGFloat y = 14;
    if (title.length) {
        UILabel *tl = [p titleLabel:title frame:CGRectMake(16, y, cw - 32, 22)];
        tl.font = [MeshTheme labelFont];
        tl.textColor = [MeshTheme muted];
        [card addSubview:tl];
        y += 30;
    }
    if (em.count) {
        CGFloat step = (cw - 24) / em.count;
        for (NSUInteger i = 0; i < em.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(12 + i * step, y, step, kEmojiRowHeight);
            // Noto-Bild statt Titel: die Knopfbeschriftung misst UIKit für die alten, schmaleren Emojis.
            NSString *key = [[MeshEmoji keysIn:em[i]] firstObject];
            UIImage *img = key ? [MeshEmoji imageForKey:key] : nil;
            if (img) {
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0);
                [img drawInRect:CGRectMake(0, 0, 30, 30)];
                [b setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal];
                UIGraphicsEndImageContext();
            }
            else { b.titleLabel.font = [UIFont systemFontOfSize:28]; [b setTitle:em[i] forState:UIControlStateNormal]; }
            b.tag = kEmojiTag + i;
            [b addTarget:p action:@selector(optionTap:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:b];
        }
        y += kEmojiRowHeight + kSheetRowGap;
    }
    for (NSInteger i = 0; i < (NSInteger)options.count; i++) {
        MeshPopupButtonStyle style = [destructive containsIndex:i] ? MeshPopupButtonDanger : MeshPopupButtonPlain;
        UIButton *b = [p button:options[i] style:style frame:CGRectMake(12, y, cw - 24, kSheetRowHeight)];
        b.tag = i;
        [b addTarget:p action:@selector(optionTap:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:b];
        y += kSheetRowHeight + kSheetRowGap;
    }
    // Liste unten am Rand, Abbrechen getrennt darunter
    CGFloat cardH = y + 4, total = cardH + kSheetMargin + kSheetCancelHeight;
    card.frame = CGRectMake(kSheetMargin, H - total - 12, cw, cardH);
    UIButton *cancel = [p button:L(@"Cancel") style:MeshPopupButtonAccent
                           frame:CGRectMake(kSheetMargin, CGRectGetMaxY(card.frame) + kSheetMargin, cw, kSheetCancelHeight)];
    [cancel addTarget:p action:@selector(sheetCancel) forControlEvents:UIControlEventTouchUpInside];
    [p->_overlay addSubview:card];
    [p->_overlay addSubview:cancel];
    [p->_overlay addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:p action:@selector(sheetCancel)]];
    [p animateIn:card];
}

- (void)optionTap:(UIButton *)b { [self dismissWithIndex:b.tag]; }
- (void)sheetCancel { [self dismissWithIndex:-1]; }

#pragma mark - Eingabe

+ (void)input:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder
       secure:(BOOL)secure numeric:(BOOL)numeric handler:(void(^)(NSString *, BOOL))handler {
    MeshPopup *p = [[MeshPopup alloc] init];
    [MeshPopup keep:p];
    p->_inputHandler = [handler copy];
    p->_overlay = [p makeOverlay];
    CGFloat W = p->_overlay.bounds.size.width, cw = cardWidth(W), inner = cw - 2 * kPad;
    UIView *card = [p cardWithWidth:cw];
    CGFloat y = 20;
    if (title.length) {
        [card addSubview:[p titleLabel:title frame:CGRectMake(kPad, y, inner, kTitleHeight)]];
        y += kTitleStep;
    }
    if (message.length) {
        CGSize ms = [message sizeWithFont:[MeshTheme timeFont] constrainedToSize:CGSizeMake(inner, 200) lineBreakMode:NSLineBreakByWordWrapping];
        UILabel *ml = [p msgLabel:message frame:CGRectMake(kPad, y, inner, ms.height)];
        ml.font = [MeshTheme timeFont];
        [card addSubview:ml];
        y += ms.height + 12;
    }
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(kPad, y, inner, kFieldHeight)];
    tf.backgroundColor = [MeshTheme field];
    tf.textColor = [MeshTheme ink];
    tf.font = [MeshTheme bodyFont];
    tf.layer.cornerRadius = [MeshTheme fieldRadius];
    tf.textAlignment = NSTextAlignmentCenter;
    tf.secureTextEntry = secure;
    if (secure) {   // Passphrasen: nichts verbessern, nichts großschreiben
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }
    tf.keyboardType = numeric ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
    tf.keyboardAppearance = UIKeyboardAppearanceAlert;
    tf.placeholder = placeholder;
    p->_field = tf;
    [card addSubview:tf];
    y += kFieldHeight + 16;

    y = [p addButtons:card y:y cancel:@selector(inputCancel) ok:@selector(inputOk) title:L(@"OK") style:MeshPopupButtonAccent];
    card.frame = CGRectMake((W - cw) / 2, kInputTop, cw, y + 18);   // oben, damit die Tastatur nicht verdeckt
    [p->_overlay addSubview:card];
    [p animateIn:card];
    [tf becomeFirstResponder];
}

- (void)inputCancel { [self dismissInput:NO]; }
- (void)inputOk { [self dismissInput:YES]; }

@end
