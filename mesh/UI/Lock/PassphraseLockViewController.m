#import "PassphraseLockViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshControls.h"
#import "MeshGlyphs.h"
#import "MeshPopup.h"
#import "MeshSession.h"
#import "MeshFormat.h"
#import "MeshL10n.h"

// Alles über der Tastatur (sie beginnt bei 264 pt): Schild, Titel, Feld, Fehlerzeile, Knopf, "Vergessen?".
static const CGFloat kShieldTop = 20, kShieldSize = 54, kShieldIcon = 30, kFieldHeight = 44;

@implementation PassphraseLockViewController {
    UITextField *_field;
    UILabel *_errorLabel;
    UIButton *_unlockBtn;
    NSTimer *_waitTimer;
    BOOL _checking;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, y = kShieldTop;

    UIView *shield = [[UIView alloc] initWithFrame:CGRectMake((W - kShieldSize) / 2, y, kShieldSize, kShieldSize)];
    shield.backgroundColor = [[MeshTheme accent] colorWithAlphaComponent:0.14f];
    shield.layer.cornerRadius = kShieldSize / 2;
    shield.layer.borderWidth = 1.5f;
    shield.layer.borderColor = [MeshTheme accent].CGColor;
    CGFloat inset = (kShieldSize - kShieldIcon) / 2;
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(inset, inset, kShieldIcon, kShieldIcon)];
    icon.image = [MeshGlyphs icon:@"shield" color:[MeshTheme accent] size:kShieldIcon];
    [shield addSubview:icon];
    [self.view addSubview:shield];
    y += kShieldSize + 8;

    UILabel *title = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 28) font:[MeshTheme titleFont] color:[MeshTheme ink]];
    title.text = L(@"Enter your words");
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];
    y += 34;

    _field = [MeshControls fieldWithFrame:CGRectMake(16, y, W - 32, kFieldHeight) placeholder:L(@"word word word …") mono:YES delegate:self];
    if ([_field respondsToSelector:@selector(setSpellCheckingType:)]) _field.spellCheckingType = UITextSpellCheckingTypeNo;   // ab iOS 5
    _field.secureTextEntry = YES;
    _field.returnKeyType = UIReturnKeyGo;
    [self.view addSubview:_field];
    y += kFieldHeight + 4;

    _errorLabel = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme timeFont] color:[MeshTheme danger]];
    _errorLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_errorLabel];
    y += 22;

    _unlockBtn = [MeshControls primaryButtonWithFrame:CGRectMake(16, y, W - 32, kFieldHeight) title:self.verifyMode ? L(@"Confirm") : L(@"Unlock") target:self action:@selector(unlock)];
    [self.view addSubview:_unlockBtn];
    y += kFieldHeight + 2;

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeCustom];
    reset.frame = CGRectMake((W - 200) / 2, y, 200, 24);
    reset.titleLabel.font = [MeshTheme timeFont];
    [reset setTitle:self.verifyMode ? L(@"Cancel") : L(@"Forgot the words?") forState:UIControlStateNormal];
    [reset setTitleColor:[MeshTheme faint] forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(tapReset) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reset];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discardInput)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updateWait];
    [self focus];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_waitTimer invalidate]; _waitTimer = nil;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)discardInput {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(check) object:nil];
    _checking = NO;
    _unlockBtn.enabled = YES;
    _field.text = @"";
    if (!_waitTimer) _errorLabel.text = @"";   // kein hängendes "Prüfe …"
}

// Sichere Felder leeren sich sonst beim Weitertippen nach einem Fokuswechsel.
- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)s {
    tf.text = [tf.text stringByReplacingCharactersInRange:range withString:s];
    if (!_waitTimer) _errorLabel.text = @"";
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self unlock]; return NO; }

- (void)updateWait {
    NSTimeInterval left = [[MeshSession shared] pinWaitRemaining];
    if (left <= 0) {
        if (_waitTimer) { _errorLabel.text = @""; [_waitTimer invalidate]; _waitTimer = nil; }
        return;
    }
    _errorLabel.text = [MeshFormat pinWait:left];
    if (!_waitTimer) _waitTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                       selector:@selector(updateWait) userInfo:nil repeats:YES];
}

- (void)unlock {
    if (_checking || _waitTimer || !_field.text.length) return;
    _checking = YES;
    _unlockBtn.enabled = NO;
    _errorLabel.textColor = [MeshTheme muted];
    _errorLabel.text = L(@"Checking …");
    [self performSelector:@selector(check) withObject:nil afterDelay:0.05];   // Text erst zeichnen, dann scrypt
}

// Nur bei aktiver App (wie beim Ziffernblock): kein Entsperren im Hintergrund.
- (void)check {
    _checking = NO;
    _unlockBtn.enabled = YES;
    _errorLabel.textColor = [MeshTheme danger];
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) { [self discardInput]; return; }
    NSString *secret = _field.text ?: @"";
    _field.text = @"";
    MeshPinResult r = self.verifyMode ? [[MeshSession shared] verifyPin:secret] : [[MeshSession shared] unlockWithPin:secret];
    if (r == MeshPinOK) { if (self.verifyMode) [self verified:secret]; else [self done]; return; }
    if (r == MeshPinWiped) { if (!self.verifyMode) [self startOver]; return; }   // beim Prüfen übernimmt die App (MeshWipedNotification)
    _errorLabel.text = [MeshFormat pinError:r wait:[[MeshSession shared] pinWaitRemaining]];
    [self updateWait];
}

- (void)focus { [_field becomeFirstResponder]; }

- (void)tapReset {
    if (!self.verifyMode) { [self askReset]; return; }
    [_field resignFirstResponder];
    if (self.onCancel) self.onCancel();
}

- (void)verified:(NSString *)secret {
    [_field resignFirstResponder];
    if (self.onVerified) self.onVerified(secret);
}

- (void)askReset {
    [_field resignFirstResponder];
    [MeshPopup confirm:L(@"Reset Mesh?")
               message:L(@"Without your words the key cannot be opened. Resetting deletes your key, all messages and contacts on this device. You start with a new identity.")
                action:L(@"Continue") destructive:YES handler:^(BOOL yes) {
        if (!yes) { [self focus]; return; }
        [MeshPopup confirm:L(@"Delete everything?") message:L(@"This cannot be undone.")
                    action:L(@"Delete") destructive:YES handler:^(BOOL sure) {
            if (!sure) { [self focus]; return; }
            [[MeshSession shared] resetEverything];
            [self startOver];
        }];
    }];
}

- (void)startOver {
    [_field resignFirstResponder];
    if (self.onStartOver) self.onStartOver();
}

- (void)done {
    [_waitTimer invalidate]; _waitTimer = nil;
    [_field resignFirstResponder];
    if (self.onUnlocked) self.onUnlocked();
}

@end
