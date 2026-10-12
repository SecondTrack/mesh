#import "AddContactViewController.h"
#import "MeshScreen.h"
#import "MeshCaps.h"
#import "MeshPopup.h"
#import "MeshTheme.h"
#import "MeshPageHeader.h"
#import "MeshSession.h"
#import "QRScannerViewController.h"
#import "MeshL10n.h"
#import "MeshControls.h"

@interface AddContactViewController ()
@property (nonatomic, strong) UITextField *keyField;   // Property, weil der Scanner-Block es schwach füllt
@end

@implementation AddContactViewController {
    UITextField *_nameField;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;

    MeshPageHeader *header = [[MeshPageHeader alloc] initWithWidth:W title:L(@"Add contact") target:self back:@selector(mesh_goBack)];
    [self.view addSubview:header];

    CGFloat y = [MeshPageHeader height] + 24;
    [self.view addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 16) text:L(@"NPUB, LINK OR 4 WORDS")]];
    y += 22;
    _keyField = [MeshControls fieldWithFrame:CGRectMake(16, y, W - 32, 46) placeholder:L(@"npub1… or 4 words") mono:YES delegate:self];
    _keyField.autocorrectionType = UITextAutocorrectionTypeNo;          // Wörter nicht „verbessern“
    _keyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _keyField.returnKeyType = UIReturnKeyNext;
    [self.view addSubview:_keyField];
    y += 58;

    // QR scannen (füllt das npub-Feld), nur auf Geräten mit Kamera
    if ([MeshCaps hasCamera]) {
        UIButton *scan = [MeshControls secondaryButtonWithFrame:CGRectMake(16, y, W - 32, 44) title:L(@"⌗  Scan QR") target:self action:@selector(tapScan)];
        scan.layer.borderColor = [MeshTheme accentDim].CGColor;
        [scan setTitleColor:[MeshTheme accent] forState:UIControlStateNormal];
        [self.view addSubview:scan];
        y += 60;
    }

    [self.view addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 16) text:L(@"NAME (OPTIONAL)")]];
    y += 22;
    _nameField = [MeshControls fieldWithFrame:CGRectMake(16, y, W - 32, 46) placeholder:L(@"Display name") mono:NO delegate:self];
    _nameField.returnKeyType = UIReturnKeyGo;   // Return fügt hinzu: der Knopf liegt bei offener Tastatur darunter
    [self.view addSubview:_nameField];
    y += 76;

    [self.view addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(16, y, W - 32, 50) title:L(@"Add") target:self action:@selector(tapAdd)]];
}

- (void)tapScan {
    QRScannerViewController *sc = [[QRScannerViewController alloc] init];
    MESH_WEAK AddContactViewController *weakSelf = self;
    sc.onScan = ^(NSString *payload) {
        weakSelf.keyField.text = payload;   // "nostr:"-Präfix entfernt MeshSession addContact:
    };
    [self mesh_present:sc animated:YES];
}

- (void)tapAdd {
    if ([MeshSession looksLikePairingWords:self.keyField.text]) {   // 4 Wörter statt npub (Kontakt ohne Kamera)
        [self.keyField resignFirstResponder]; [_nameField resignFirstResponder];
        [MeshPopup info:L(@"Looking up the 4 words …")];
        __weak AddContactViewController *ws = self;
        [[MeshSession shared] addContactByWords:self.keyField.text name:_nameField.text done:^(NSString *hex, NSString *error) {
            [MeshPopup dismissAll];
            if (hex) { [ws.navigationController popViewControllerAnimated:YES]; return; }
            [MeshPopup confirm:L(@"Not added") message:error action:L(@"OK") destructive:NO handler:nil];
        }];
        return;
    }
    NSString *hex = [[MeshSession shared] addContact:self.keyField.text name:_nameField.text];
    if (hex) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [MeshPopup confirm:L(@"Invalid") message:L(@"Please enter a valid npub or 64-character hex pubkey.")
                    action:L(@"OK") destructive:NO handler:nil];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (tf == self.keyField) { [_nameField becomeFirstResponder]; return NO; }
    [tf resignFirstResponder];
    [self tapAdd];
    return NO;
}

// Unter iOS 4 sind Delegates unsafe_unretained, hier selbst lösen.
- (void)dealloc { self.keyField.delegate = nil; _nameField.delegate = nil; }

@end
