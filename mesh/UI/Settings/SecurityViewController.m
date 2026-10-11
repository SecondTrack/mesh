#import "SecurityViewController.h"
#import "MeshScreen.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshPageHeader.h"
#import "MeshPopup.h"
#import "MeshGlyphs.h"
#import "MeshSession.h"
#import "MeshL10n.h"
#import "MeshClipboard.h"
#import "MeshMenuRow.h"
#import "MeshFormat.h"
#import "MeshSecretPrompt.h"
#import "WordsSetupViewController.h"
#import "LockViewController.h"
#import "PassphraseLockViewController.h"
#import "SetupProtectionViewController.h"
#import "EntryViewController.h"

@implementation SecurityViewController {
    MeshMenuRow *_panicPinRow, *_codewordRow;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;

    UIScrollView *scroll = [self mesh_addPageTitled:L(@"Security")];
    CGFloat y = 18;

    // Status-Karte: tatsächlicher Zustand, Einschränkungen in Rot
    MeshSession *s = [MeshSession shared];
    NSMutableArray *lines = [NSMutableArray array];   // @[text, warnung?]
    [lines addObject:@[L(@"Messages use Signal (forward secrecy) as soon as a contact's key bundle is known, NIP-44 before that."), @NO]];
    [lines addObject:@[L(@"Keys stay on this device only, no cloud backup."), @NO]];
    if (s.usesTor && s.torReady) [lines addObject:@[L(@"Over Tor: relays don't see your IP address."), @NO]];
    else if (s.usesTor) [lines addObject:@[L(@"Tor is starting. Until it is ready, Mesh stays offline instead of connecting directly."), @YES]];
    else           [lines addObject:@[L(@"Not anonymous: relays see your IP address and your contact list."), @YES]];
    [lines addObject:s.keyBoundToDevice ? @[L(@"Key bound to this device"), @NO]
                                        : @[L(@"Key not bound to device (keychain unavailable)"), @YES]];
    if (!s.clockPlausible) [lines addObject:@[L(@"Device clock is wrong: certificates can only be checked partially."), @YES]];
    if ([s secretKind] == MeshSecretWords)
        [lines addObject:@[L(@"Locked with random words (scrypt): strong even if someone copies this device."), @NO]];
    else
        [lines addObject:@[L(@"The 6-digit PIN is only as strong as the iOS passcode: whoever can read this device (jailbreak) can try all PINs. Words are safer: Change protection."), @YES]];

    CGFloat inner = W - 32, textWidth = inner - 32;
    UIView *card = [MeshControls cardWithFrame:CGRectMake(16, y, inner, 0)];
    card.backgroundColor = [MeshTheme surface];
    UIImageView *shield = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, 22, 22)];
    shield.image = [MeshGlyphs icon:@"shield" color:[MeshTheme accent] size:22];
    [card addSubview:shield];
    UILabel *headline = [MeshControls labelWithFrame:CGRectMake(44, 13, inner - 56, 24) font:[MeshTheme nameFont] color:[MeshTheme ink]];
    headline.text = L(@"End-to-end encrypted");
    [card addSubview:headline];
    CGFloat ly = 44;
    for (NSArray *line in lines) {
        UIColor *color = [line[1] boolValue] ? [MeshTheme danger] : [MeshTheme muted];
        CGFloat h = [line[0] sizeWithFont:[MeshTheme timeFont] constrainedToSize:CGSizeMake(textWidth, 200)
                            lineBreakMode:NSLineBreakByWordWrapping].height;
        UILabel *l = [MeshControls labelWithFrame:CGRectMake(16, ly, textWidth, h) font:[MeshTheme timeFont] color:color];
        l.text = line[0];
        l.numberOfLines = 0;
        [card addSubview:l];
        ly += h + 4;
    }
    card.frame = CGRectMake(16, y, inner, ly + 10);
    [scroll addSubview:card];
    y += card.frame.size.height + 18;

    // Zeilen
    y = [MeshMenuRow addTo:scroll y:y width:W icon:@"key" title:L(@"Change protection")
                  subtitle:[s secretKind] == MeshSecretWords ? L(@"Now: words · PIN or new words") : L(@"Now: 6-digit PIN · words are safer")
                    target:self action:@selector(changeProtection)];
    y = [MeshMenuRow addTo:scroll y:y width:W icon:@"scan" title:L(@"Public key") subtitle:L(@"npub — shareable") target:self action:@selector(copyNpub)];
    y = [MeshMenuRow addTo:scroll y:y width:W icon:@"shield" title:L(@"Show secret key")
                  subtitle:[self words] ? L(@"nsec — words required") : L(@"nsec — PIN required") target:self action:@selector(revealNsec)];
    _panicPinRow = [MeshMenuRow rowAtY:y width:W icon:@"alert" title:[self panicName]
                              subtitle:[self words] ? L(@"Second code that deletes everything") : L(@"Second PIN that deletes everything")];
    [_panicPinRow addTarget:self action:@selector(panicPin) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:_panicPinRow];
    y += [MeshMenuRow height];
    _codewordRow = [MeshMenuRow rowAtY:y width:W icon:@"close" title:L(@"Emergency wipe") subtitle:L(@"A codeword by message deletes everything")];
    [_codewordRow addTarget:self action:@selector(codeword) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:_codewordRow];
    y += [MeshMenuRow height];
    [self updatePanicRows];

    // Warnhinweis
    y += 6;
    UILabel *warn = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 54) font:[MeshTheme timeFont] color:[MeshTheme danger]];
    warn.text = L(@"Share your secret key (nsec) with no one. Whoever has it can take over your identity and read along.");
    warn.numberOfLines = 0;
    [scroll addSubview:warn];
    y += 60;

    scroll.contentSize = CGSizeMake(W, y + 20);
}

#pragma mark - Aktionen

- (BOOL)words { return [[MeshSession shared] secretKind] == MeshSecretWords; }
- (NSString *)panicName { return [self words] ? L(@"Panic code") : L(@"Panic PIN"); }

// Bestätigen mit dem Bildschirm vom Öffnen der App; danach ist der Code geprüft.
- (void)confirmThen:(void (^)(void))next { [MeshSecretPrompt verifyFrom:self then:^(NSString *secret) { next(); }]; }

// Schutz ändern, Seite für Seite: jetzigen Code prüfen, Art wählen (wie bei der Einrichtung),
// neue PIN mit dem Ziffernblock oder neue Wörter festlegen.
- (void)changeProtection {
    [self confirmThen:^{ [self showProtectionChoice]; }];
}

- (void)showProtectionChoice {
    SetupProtectionViewController *choose = [[SetupProtectionViewController alloc] init];
    choose.pageTitle = L(@"Change protection");
    MESH_WEAK SecurityViewController *weakSelf = self;
    choose.onChoose = ^(MeshSecretKind kind, NSUInteger words) { [weakSelf chooseNew:kind words:words]; };
    [self.navigationController pushViewController:choose animated:YES];
}

// Die Panik-PIN passt nicht zur anderen Eingabe am Sperrbildschirm und fällt beim Wechsel weg.
- (void)chooseNew:(MeshSecretKind)kind words:(NSUInteger)words {
    if (kind != [[MeshSession shared] secretKind] && [MeshSession shared].hasPanicPin) {
        [MeshPopup confirm:[self panicName] message:L(@"Switching between PIN and words removes your panic code. Set a new one afterwards.")
                    action:L(@"Continue") destructive:NO handler:^(BOOL yes) { if (yes) [self pushNew:kind words:words]; }];
        return;
    }
    [self pushNew:kind words:words];
}

- (void)pushNew:(MeshSecretKind)kind words:(NSUInteger)words {
    MESH_WEAK SecurityViewController *weakSelf = self;
    UIViewController *page;
    if (kind == MeshSecretPin) {
        LockViewController *pin = [[LockViewController alloc] init];
        pin.setupMode = YES;
        pin.pageTitle = L(@"New PIN");
        pin.onPinChosen = ^MeshPinResult(NSString *p) {
            MeshPinResult r = [[MeshSession shared] setNewSecret:p kind:MeshSecretPin];
            if (r == MeshPinOK) [weakSelf protectionChanged:L(@"PIN changed")];
            return r;
        };
        page = pin;
    } else {
        WordsSetupViewController *setup = [[WordsSetupViewController alloc] initWithWords:words];
        setup.onConfirmed = ^MeshPinResult(NSString *phrase) {
            MeshPinResult r = [[MeshSession shared] setNewSecret:phrase kind:MeshSecretWords];
            if (r == MeshPinOK) [weakSelf protectionChanged:L(@"Now locked with your words.")];
            return r;
        };
        page = setup;
    }
    [self.navigationController pushViewController:page animated:YES];
}

// Zurück zu den Einstellungen; die Seite neu aufbauen, damit Status und Zeilen zur neuen Art passen.
- (void)protectionChanged:(NSString *)message {
    UINavigationController *nav = self.navigationController;
    NSMutableArray *stack = [nav.viewControllers mutableCopy];
    NSUInteger at = [stack indexOfObject:self];
    if (at == NSNotFound) return;
    [stack replaceObjectsInRange:NSMakeRange(at, stack.count - at) withObjectsFromArray:@[[[SecurityViewController alloc] init]]];
    [nav setViewControllers:stack animated:YES];
    [MeshPopup info:message];
}

- (void)revealNsec {
    [self confirmThen:^{
        NSString *nsec = [[MeshSession shared] myNsec];
        if (!nsec) { [MeshPopup info:L(@"Locked")]; return; }
        // Bewusst ohne Kopieren: Die Zwischenablage kann jede App lesen.
        [MeshPopup info:[NSString stringWithFormat:@"%@\n\n%@\n\n%@", L(@"Secret key"), nsec,
                         L(@"Write it down on paper. It can't be copied, so it never lands in the clipboard.")]];
    }];
}

#pragma mark - Notlöschung

- (void)updatePanicRows {
    MeshSession *s = [MeshSession shared];
    _panicPinRow.detail = s.hasPanicPin ? L(@"On") : L(@"Off");
    _codewordRow.detail = s.hasPanicCodeword ? L(@"On") : s.panicCodewordNeedsRenewal ? L(@"Set again") : L(@"Off");
}

// Notlöschung ändern oder abschalten nur mit der PIN: wer das entsperrte Gerät entreißt, soll sie
// nicht als Erstes ausschalten können.
- (void)panicPin {
    [self confirmThen:^{ [self openPanicPage]; }];
}

// Seite zur Panik-PIN: bei Wörtern direkt mit Feld, bei der PIN eine Erklärung, deren Knopf zum
// Ziffernblock führt.
- (void)openPanicPage {
    BOOL words = [self words], set = [MeshSession shared].hasPanicPin;
    NSString *text = words
        ? L(@"A second code, typed instead of your words, that does not unlock but deletes the app at once and for good, in case you are forced to unlock. At least 4 characters; two short words are harder to guess. It works on this device, offline too.")
        : L(@"A second PIN that does not unlock but deletes the app at once and for good, in case you are forced to unlock. It works on this device, offline too. It must not be your real PIN.");
    EntryViewController *page = [[EntryViewController alloc] initWithTitle:[self panicName] text:text];
    page.status = set ? L(@"IS ON") : L(@"IS OFF");
    page.removeTitle = set ? (words ? L(@"Remove panic code") : L(@"Remove panic PIN")) : nil;
    MESH_WEAK SecurityViewController *weakSelf = self;
    page.onRemove = ^{ [[MeshSession shared] clearPanicPin]; [weakSelf backHere:words ? L(@"Panic code removed") : L(@"Panic PIN removed")]; };
    if (words) {
        page.secure = YES;
        page.repeat = YES;
        page.placeholder = L(@"Panic code (4+ characters, two words are better)");
        page.saveTitle = set ? L(@"Set a new panic code") : L(@"Set panic code");
        page.onSave = ^NSString *(NSString *code) {
            MeshPinResult r = [[MeshSession shared] setPanicPin:code];
            if (r == MeshPinOK) { [weakSelf backHere:L(@"Panic code set")]; return nil; }
            return r == MeshPinFailed ? L(@"At least 4 characters") : [MeshFormat pinError:r wait:0];
        };
    } else {
        page.fieldless = YES;
        page.saveTitle = set ? L(@"Set a new panic PIN") : L(@"Set panic PIN");
        page.onSave = ^NSString *(NSString *unused) { [weakSelf pushPanicKeypad]; return nil; };
    }
    [self.navigationController pushViewController:page animated:YES];
}

- (void)pushPanicKeypad {
    LockViewController *pin = [[LockViewController alloc] init];
    pin.setupMode = YES;
    pin.pageTitle = L(@"Panic PIN");
    pin.chooseTitle = L(@"Set panic PIN");
    MESH_WEAK SecurityViewController *weakSelf = self;
    pin.onPinChosen = ^MeshPinResult(NSString *p) {
        MeshPinResult r = [[MeshSession shared] setPanicPin:p];
        if (r == MeshPinOK) [weakSelf backHere:L(@"Panic PIN set")];
        return r;
    };
    [self.navigationController pushViewController:pin animated:YES];
}

- (void)codeword {
    [self confirmThen:^{ [self openCodewordPage]; }];
}

- (void)openCodewordPage {
    BOOL set = [MeshSession shared].hasPanicCodeword;
    EntryViewController *page = [[EntryViewController alloc] initWithTitle:L(@"Emergency wipe")
        text:L(@"If a contact sends this codeword, the app is deleted at once and for good: identity, contacts, all messages. Only the hash travels, never the codeword. Give it only to people you trust completely: whoever knows it can wipe you. Once used, choose a new codeword.")];
    page.status = set ? L(@"IS ON") : [MeshSession shared].panicCodewordNeedsRenewal ? L(@"SET AGAIN FOR THE NEW IDENTITY") : L(@"IS OFF");
    page.placeholder = L(@"Codeword");
    page.repeat = YES;
    page.saveTitle = set ? L(@"Save new codeword") : L(@"Turn on");
    page.removeTitle = set ? L(@"Turn emergency wipe off") : nil;
    MESH_WEAK SecurityViewController *weakSelf = self;
    page.onSave = ^NSString *(NSString *word) {
        if (![word stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return L(@"Enter a codeword");
        if (![[MeshSession shared] setPanicCodeword:word]) return L(@"Failed");
        [weakSelf backHere:L(@"Codeword saved")];
        return nil;
    };
    page.onRemove = ^{
        [[MeshSession shared] setPanicCodeword:@""];
        [weakSelf backHere:L(@"Emergency wipe off")];
    };
    [self.navigationController pushViewController:page animated:YES];
}

// Zurück zu dieser Seite (Zeilen aktualisiert), kurze Bestätigung.
- (void)backHere:(NSString *)message {
    [self updatePanicRows];
    [self.navigationController popToViewController:self animated:YES];
    [MeshPopup info:message];
}

- (void)copyNpub {
    [MeshClipboard copyPublic:[[MeshSession shared] myNpub] confirmation:L(@"npub copied")];
}

@end
