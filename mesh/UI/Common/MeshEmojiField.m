#import "MeshEmojiField.h"
#import <QuartzCore/QuartzCore.h>
#import "MeshEmoji.h"
#import "MeshLineText.h"
#import "MeshClipboard.h"
#import "MeshL10n.h"

static const CGFloat kRightPadding = 6, kCaretWidth = 2, kClearWidth = 29, kClearSize = 19;

// Farben wie UITextField unter iOS 6 (Einfügemarke, Auswahl, Platzhalter, Löschknopf)
static UIColor *caretColor(void)       { return [UIColor colorWithRed:0.26f green:0.42f blue:0.95f alpha:1]; }
static UIColor *selectionColor(void)   { return [UIColor colorWithRed:0.26f green:0.42f blue:0.95f alpha:0.35f]; }
static UIColor *placeholderColor(void) { return [UIColor colorWithWhite:0.7f alpha:1]; }

// Löschknopf: grauer Kreis mit ausgestanztem ×, einmal gezeichnet.
static UIImage *clearImage(void) {
    static UIImage *img;
    if (img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(kClearSize, kClearSize), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor colorWithWhite:0.6f alpha:1] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, kClearSize, kClearSize));
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    CGContextSetLineWidth(ctx, 2);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGFloat a = 6, b = kClearSize - 6;
    CGContextMoveToPoint(ctx, a, a); CGContextAddLineToPoint(ctx, b, b);
    CGContextMoveToPoint(ctx, b, a); CGContextAddLineToPoint(ctx, a, b);
    CGContextStrokePath(ctx);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation MeshEmojiField {
    MeshLineText *_model;
    MeshEmojiLayout *_layout;   // gesetzt bei jeder Änderung; gezeichnet wird genau dieser Satz
    CGFloat _textWidth;         // dessen Breite samt Leerzeichen am Ende = Platz der Einfügemarke
    UIView *_caret;
    UIButton *_clear;       // erst bei clearButtonMode angelegt
}

@synthesize inputView = _inputView;

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _model = [[MeshLineText alloc] init];
        MESH_WEAK MeshEmojiField *weakSelf = self;   // das Modell gehört dem Feld, lebt nicht länger
        _model.shouldChange = ^BOOL(NSRange range, NSString *s) { return [weakSelf askChange:range with:s]; };
        _font = [UIFont systemFontOfSize:15];
        _textColor = [UIColor blackColor];
        _textAlignment = NSTextAlignmentLeft;
        _autocapitalizationType = UITextAutocapitalizationTypeSentences;   // wie UITextField
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = YES;
        _caret = [[UIView alloc] initWithFrame:CGRectZero];
        _caret.backgroundColor = caretColor();
        _caret.userInteractionEnabled = NO;
        _caret.hidden = YES;
        [self addSubview:_caret];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
        tap.delegate = self; hold.delegate = self;
        [self addGestureRecognizer:tap];
        [self addGestureRecognizer:hold];
    }
    return self;
}

#pragma mark - Text

- (NSString *)text { return _model.text; }

- (void)setText:(NSString *)text {
    _model.text = text;
    [self textDidChange:NO];
}

- (void)setFont:(UIFont *)font { _font = font ?: [UIFont systemFontOfSize:15]; [self textDidChange:NO]; }
- (void)setTextColor:(UIColor *)color { _textColor = color; [self setNeedsDisplay]; }
- (void)setPlaceholder:(NSString *)placeholder { _placeholder = [placeholder copy]; [self setNeedsDisplay]; }
- (void)setLeftPadding:(CGFloat)padding { _leftPadding = padding; [self setNeedsDisplay]; [self placeCaret]; }
- (void)setTextAlignment:(NSTextAlignment)a { _textAlignment = a; [self setNeedsDisplay]; [self placeCaret]; }

- (void)setClearButtonMode:(UITextFieldViewMode)mode {
    _clearButtonMode = mode;
    if (mode != UITextFieldViewModeNever && !_clear) {
        _clear = [UIButton buttonWithType:UIButtonTypeCustom];
        [_clear setImage:clearImage() forState:UIControlStateNormal];
        _clear.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight;
        _clear.accessibilityLabel = L(@"Delete");
        [_clear addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_clear];
    }
    [self updateClear];
}

- (NSRange)selectedRange { return _model.selectedRange; }
- (NSString *)accessibilityValue { return _model.text.length ? _model.text : _placeholder; }

// Delegate fragen wie UITextField (Bereich in UTF-16 des bisherigen Texts).
- (BOOL)askChange:(NSRange)range with:(NSString *)s {
    id<MeshEmojiFieldDelegate> d = _delegate;
    if (![d respondsToSelector:@selector(emojiField:shouldChangeCharactersInRange:replacementString:)]) return YES;
    return [d emojiField:self shouldChangeCharactersInRange:range replacementString:s];
}

// Neu messen und zeichnen; user = durch Tippen/Einfügen (meldet EditingChanged wie UITextField).
- (void)textDidChange:(BOOL)user {
    _layout = _model.text.length ? [MeshEmoji layoutFor:_model.text font:_font width:CGFLOAT_MAX height:CGFLOAT_MAX lines:1] : nil;
    _textWidth = _layout.lineWidth;
    [self updateClear];
    [self setNeedsDisplay];
    [self placeCaret];
    if (user) [self sendActionsForControlEvents:UIControlEventEditingChanged];
}

- (void)setFrame:(CGRect)frame { [super setFrame:frame]; [self placeCaret]; }

#pragma mark - Löschknopf

- (BOOL)clearShown {
    if (!_clear || !_model.text.length) return NO;
    switch (_clearButtonMode) {
        case UITextFieldViewModeAlways:        return YES;
        case UITextFieldViewModeWhileEditing:  return self.isFirstResponder;
        case UITextFieldViewModeUnlessEditing: return !self.isFirstResponder;
        default:                               return NO;
    }
}

- (void)updateClear {
    if (!_clear) return;
    BOOL show = [self clearShown];
    if (show == !_clear.hidden && _clear.superview) return;
    _clear.hidden = !show;
    _clear.frame = CGRectMake(self.bounds.size.width - kClearWidth, 0, kClearWidth, self.bounds.size.height);
    [self setNeedsDisplay];   // die Textfläche wird schmaler oder breiter
}

- (void)clearTapped {
    id<MeshEmojiFieldDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(emojiFieldShouldClear:)] && ![d emojiFieldShouldClear:self]) { [self updateClear]; return; }
    if (!_model.text.length) return;
    _model.text = @"";
    [self textDidChange:YES];
}

#pragma mark - Zeichnen (nur bei Änderung; die Schicht behält das Bild)

- (CGFloat)rightInset { return _clear && !_clear.hidden ? kClearWidth : kRightPadding; }
- (CGFloat)innerWidth { return MAX(0, self.bounds.size.width - _leftPadding - [self rightInset]); }

// Passt der Text, steht er nach textAlignment; sonst so weit links, dass sein Ende samt Einfügemarke sichtbar bleibt.
- (CGFloat)textX {
    CGFloat inner = [self innerWidth], over = _textWidth + kCaretWidth - inner;
    if (over > 0) return _leftPadding - over;
    if (_textAlignment == NSTextAlignmentCenter) return _leftPadding + roundf((inner - _textWidth) / 2);
    if (_textAlignment == NSTextAlignmentRight) return _leftPadding - over;
    return _leftPadding;
}

- (void)drawRect:(CGRect)rect {
    CGSize size = self.bounds.size;
    CGFloat lh = _font.lineHeight, inner = [self innerWidth];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, CGRectMake(_leftPadding, 0, inner, size.height));
    NSString *text = _model.text;
    if (!text.length) {
        // Platzhalter (oft der bisherige Name) wie Text: Emojis als Bilder, zu lang mit "…"
        if (_placeholder.length)
            [MeshEmoji draw:_placeholder font:_font color:placeholderColor() alignment:_textAlignment lines:1
                     inRect:CGRectMake(_leftPadding, 0, inner, size.height)];
    } else {
        CGFloat x = [self textX];
        if (_model.allSelected) {
            [selectionColor() set];
            UIRectFill(CGRectMake(x, roundf((size.height - lh) / 2) - 1, _textWidth, lh + 2));
        }
        [MeshEmoji drawLayout:_layout color:_textColor alignment:NSTextAlignmentLeft
                       inRect:CGRectMake(x, 0, _textWidth + 4, size.height)];
    }
    CGContextRestoreGState(ctx);
}

#pragma mark - Einfügemarke (blinkt per Core Animation, ohne Timer)

- (void)placeCaret {
    [self updateClear];
    CGFloat h = roundf(_font.lineHeight) + 2;
    CGFloat x = MIN([self textX] + _textWidth, self.bounds.size.width - [self rightInset] - kCaretWidth);
    _caret.frame = CGRectMake(roundf(x), roundf((self.bounds.size.height - h) / 2), kCaretWidth, h);
    BOOL show = self.isFirstResponder && !_model.allSelected;
    _caret.hidden = !show;
    [_caret.layer removeAnimationForKey:@"blink"];
    if (!show) return;
    CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    blink.values = @[@1, @0, @1];
    blink.keyTimes = @[@0, @0.5, @1];
    blink.calculationMode = kCAAnimationDiscrete;
    blink.duration = 1.0;
    blink.beginTime = CACurrentMediaTime() + 0.5;   // nach dem Tippen erst kurz stehen lassen
    blink.repeatCount = HUGE_VALF;
    [_caret.layer addAnimation:blink forKey:@"blink"];
}

#pragma mark - Ersthelfer

- (BOOL)canBecomeFirstResponder { return YES; }

- (BOOL)becomeFirstResponder {
    BOOL was = self.isFirstResponder;
    id<MeshEmojiFieldDelegate> d = _delegate;
    if (!was && [d respondsToSelector:@selector(emojiFieldShouldBeginEditing:)] && ![d emojiFieldShouldBeginEditing:self]) return NO;
    if (![super becomeFirstResponder]) return NO;
    if (!was) {
        [self placeCaret];
        [[NSNotificationCenter defaultCenter] postNotificationName:MeshKeyTargetDidBeginEditingNotification object:self];
        [self sendActionsForControlEvents:UIControlEventEditingDidBegin];
        if ([d respondsToSelector:@selector(emojiFieldDidBeginEditing:)]) [d emojiFieldDidBeginEditing:self];
    }
    return YES;
}

- (BOOL)resignFirstResponder {
    BOOL was = self.isFirstResponder;
    if (![super resignFirstResponder]) return NO;
    if (was) {
        if (_model.allSelected) { _model.allSelected = NO; [self setNeedsDisplay]; }
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
        [self placeCaret];
        [[NSNotificationCenter defaultCenter] postNotificationName:MeshKeyTargetDidEndEditingNotification object:self];
        [self sendActionsForControlEvents:UIControlEventEditingDidEnd];
        id<MeshEmojiFieldDelegate> d = _delegate;
        if ([d respondsToSelector:@selector(emojiFieldDidEndEditing:)]) [d emojiFieldDidEndEditing:self];
    }
    return YES;
}

#pragma mark - UIKeyInput

- (BOOL)hasText { return _model.text.length > 0; }

- (void)insertText:(NSString *)s {
    if ([s isEqualToString:@"\n"]) { [self returnPressed]; return; }
    if ([_model insert:s]) [self textDidChange:YES];
}

- (void)deleteBackward {
    if ([_model deleteBackward]) [self textDidChange:YES];
}

- (void)returnPressed {
    id<MeshEmojiFieldDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(emojiFieldReturned:)]) [d emojiFieldReturned:self];
}

#pragma mark - Tippen und Menü

// Der Löschknopf bekommt seine Berührungen selbst.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return !_clear || _clear.hidden || ![touch.view isDescendantOfView:_clear];
}

- (void)tap:(UITapGestureRecognizer *)g {
    UIMenuController *menu = [UIMenuController sharedMenuController];
    if (menu.menuVisible) [menu setMenuVisible:NO animated:YES];
    if (_model.allSelected) { _model.allSelected = NO; [self setNeedsDisplay]; [self placeCaret]; }
    if (!self.isFirstResponder) [self becomeFirstResponder];
}

- (void)hold:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!self.isFirstResponder && ![self becomeFirstResponder]) return;
    [self showMenu];
}

- (void)showMenu {
    UIMenuController *menu = [UIMenuController sharedMenuController];
    CGRect target = _model.allSelected
        ? CGRectMake(MAX(_leftPadding, [self textX]), _caret.frame.origin.y, MIN(_textWidth, [self innerWidth]), _caret.frame.size.height)
        : _caret.frame;
    [menu setTargetRect:target inView:self];
    [menu setMenuVisible:YES animated:YES];
}

// Nur die drei eigenen Einträge. Einfügen fragt nur nach der Art des Inhalts, gelesen wird erst in paste:.
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:))
        return [[UIPasteboard generalPasteboard] containsPasteboardTypes:UIPasteboardTypeListString];
    if (action == @selector(copy:)) return _model.allSelected;
    if (action == @selector(selectAll:)) return _model.text.length && !_model.allSelected;
    return NO;
}

- (void)paste:(id)sender {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if ([_model paste:s]) [self textDidChange:YES];
}

// Kopierter Nachrichtentext verschwindet beim Sperren wieder aus der Zwischenablage (MeshClipboard).
- (void)copy:(id)sender {
    if (_model.allSelected) [MeshClipboard copyMessage:_model.text];
}

- (void)selectAll:(id)sender {
    _model.allSelected = YES;
    [self setNeedsDisplay];
    [self placeCaret];
    if (_model.allSelected) [self performSelector:@selector(showMenu) withObject:nil afterDelay:0];   // wie UITextField: Menü bleibt
}

@end
