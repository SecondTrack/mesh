#import "MeshChatInputBar.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshL10n.h"

static const CGFloat kBarHeight = 54, kActionSize = 46, kFieldHeight = 36;

@implementation MeshChatInputBar {
    UITextField *_field;
    UIButton *_action;
    UIView *_recBar;
    UILabel *_recLabel;
}

+ (CGFloat)height { return kBarHeight; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CGFloat W = frame.size.width;
        self.backgroundColor = [MeshTheme surface];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        [self addSubview:line];

        UIButton *attach = [UIButton buttonWithType:UIButtonTypeCustom];
        attach.frame = CGRectMake(8, (kBarHeight - 36) / 2, 36, 36);
        [attach setImage:[MeshGlyphs icon:@"add" color:[MeshTheme muted] size:24] forState:UIControlStateNormal];   // Anhänge, wie Android
        [attach addTarget:self action:@selector(tapCamera) forControlEvents:UIControlEventTouchUpInside];
        [attach addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdCamera:)]];
        [self addSubview:attach];

        _field = [[UITextField alloc] initWithFrame:CGRectMake(48, (kBarHeight - kFieldHeight) / 2, W - 48 - 60, kFieldHeight)];
        _field.backgroundColor = [MeshTheme field];
        _field.textColor = [MeshTheme ink];
        _field.font = [MeshTheme bodyFont];
        _field.layer.cornerRadius = kFieldHeight / 2;
        _field.delegate = self;
        _field.returnKeyType = UIReturnKeySend;
        _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _field.keyboardAppearance = UIKeyboardAppearanceAlert;
        _field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, kFieldHeight)];
        _field.leftViewMode = UITextFieldViewModeAlways;
        _field.placeholder = L(@"Message");
        [_field addTarget:self action:@selector(refresh) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_field];

        _action = [UIButton buttonWithType:UIButtonTypeCustom];
        _action.frame = CGRectMake(W - kActionSize - 6, (kBarHeight - kActionSize) / 2, kActionSize, kActionSize);
        _action.layer.cornerRadius = kActionSize / 2;
        [_action addTarget:self action:@selector(tapAction) forControlEvents:UIControlEventTouchUpInside];
        [_action addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdAction:)]];
        [self addSubview:_action];

        [self buildRecordingBar];
        [self refresh];
    }
    return self;
}

// Roter Punkt, laufende Zeit, "abbrechen", liegt während der Aufnahme über dem Feld.
- (void)buildRecordingBar {
    _recBar = [[UIView alloc] initWithFrame:CGRectMake(8, (kBarHeight - 40) / 2, self.bounds.size.width - 8 - 58, 40)];
    _recBar.backgroundColor = [MeshTheme field];
    _recBar.layer.cornerRadius = kFieldHeight / 2;
    _recBar.hidden = YES;
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(14, 15, 11, 11)];
    dot.backgroundColor = [MeshTheme danger];
    dot.layer.cornerRadius = dot.frame.size.height / 2;
    [_recBar addSubview:dot];
    _recLabel = [[UILabel alloc] initWithFrame:CGRectMake(34, 0, 160, 40)];
    _recLabel.font = [MeshTheme monoBigFont];
    _recLabel.textColor = [MeshTheme ink];
    _recLabel.backgroundColor = [UIColor clearColor];
    [_recBar addSubview:_recLabel];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake(_recBar.bounds.size.width - 96, 0, 88, 40);
    cancel.titleLabel.font = [MeshTheme labelFont];
    [cancel setTitle:L(@"cancel") forState:UIControlStateNormal];
    [cancel setTitleColor:[MeshTheme danger] forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(tapCancel) forControlEvents:UIControlEventTouchUpInside];
    [_recBar addSubview:cancel];
    [self addSubview:_recBar];
}

- (void)dealloc { _field.delegate = nil; }   // iOS 4: Delegates sind nicht nil-sicher

- (NSString *)text { return _field.text; }
- (void)setText:(NSString *)text { _field.text = text; [self refresh]; }

- (BOOL)hasText {
    return [[_field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
}

- (void)setRecording:(BOOL)recording { _recording = recording; _recBar.hidden = !recording; [self refresh]; }
- (void)setMicrophoneAvailable:(BOOL)available { _microphoneAvailable = available; [self refresh]; }
- (void)setRecordingText:(NSString *)text { _recLabel.text = text; }
- (void)endEditing { [_field resignFirstResponder]; }

- (void)refresh {
    if (_recording) {
        _action.backgroundColor = [MeshTheme danger];
        [_action setImage:[MeshGlyphs stopIcon:20 color:[MeshTheme bg]] forState:UIControlStateNormal];
        return;
    }
    _action.backgroundColor = [MeshTheme accent];
    BOOL mic = !self.hasText && _microphoneAvailable;
    [_action setImage:[MeshGlyphs icon:(mic ? @"mic" : @"send") color:[MeshTheme bg] size:20] forState:UIControlStateNormal];
}

- (void)tapCamera  { [_delegate inputBarTappedCamera:self]; }
- (void)tapAction  { [_delegate inputBarTappedAction:self]; }
- (void)tapCancel  { [_delegate inputBarCancelledRecording:self]; }
- (void)holdCamera:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) [_delegate inputBarHeldCamera:self]; }
- (void)holdAction:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) [_delegate inputBarHeldAction:self]; }

// Return sendet nur vorhandenen Text (startet keine Aufnahme).
- (BOOL)textFieldShouldReturn:(UITextField *)tf { if (self.hasText) [_delegate inputBarTappedAction:self]; return NO; }

@end
