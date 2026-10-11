// Chatliste: Suche, Chats mit letzter Nachricht, Knopf zum Hinzufügen
// (mit Kamera als QR-Scanner).
#import "ChatsListViewController.h"
#import "MeshScreen.h"
#import "MeshChatCell.h"
#import "MeshAvatarView.h"
#import "MeshTabBar.h"
#import "MeshTopBar.h"
#import "MeshFormat.h"
#import "MeshCaps.h"
#import "ChatViewController.h"
#import "AddContactViewController.h"
#import "MeInViewController.h"
#import "QRScannerViewController.h"
#import "MeshTheme.h"
#import "MeshChat.h"
#import "MeshSession.h"
#import "MeshGlyphs.h"
#import "MeshL10n.h"
#import "MeshPopup.h"
#import "MeshIdentityInfo.h"

@interface ChatsListViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@end

@implementation ChatsListViewController {
    UITableView *_table;
    NSArray *_allChats;
    NSArray *_chats;          // _allChats, gefiltert nach dem Suchtext
    UITextField *_search;
    UILabel *_searchHint;
    NSDictionary *_identityPictures;   // Nummer -> Profilbild der eigenen Identität
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    MeshTopBar *topBar = [[MeshTopBar alloc] initWithWidth:W title:@"Mesh" subtitle:L(@"Encrypted · Nostr")];
    [self.view addSubview:topBar];

    // Suchleiste: filtert die Liste nach Namen
    CGFloat sy = [MeshTopBar height] + 8;
    UIView *search = [[UIView alloc] initWithFrame:CGRectMake(12, sy, W - 24, 42)];
    search.backgroundColor = [MeshTheme field]; search.layer.cornerRadius = search.bounds.size.height / 2;
    search.layer.borderWidth = 1; search.layer.borderColor = [MeshTheme line].CGColor;
    UIImageView *si = [[UIImageView alloc] initWithFrame:CGRectMake(14, 12, 18, 18)];
    si.image = [MeshGlyphs icon:@"search" color:[MeshTheme muted] size:18];
    [search addSubview:si];
    // Eigener Platzhalter: attributedPlaceholder (für die Farbe) gibt es erst ab iOS 6.
    _searchHint = [[UILabel alloc] initWithFrame:CGRectMake(42, 0, W - 84, 42)];
    _searchHint.text = L(@"Search contacts"); _searchHint.font = [MeshTheme bodyFont]; _searchHint.textColor = [MeshTheme faint];
    _searchHint.backgroundColor = [UIColor clearColor]; [search addSubview:_searchHint];
    _search = [[UITextField alloc] initWithFrame:CGRectMake(42, 0, W - 24 - 42 - 10, 42)];
    _search.font = [MeshTheme bodyFont]; _search.textColor = [MeshTheme ink];
    _search.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    _search.keyboardAppearance = UIKeyboardAppearanceAlert;
    _search.returnKeyType = UIReturnKeyDone;
    _search.clearButtonMode = UITextFieldViewModeWhileEditing;
    _search.delegate = self;
    [_search addTarget:self action:@selector(applyFilter) forControlEvents:UIControlEventEditingChanged];
    [search addSubview:_search];
    [self.view addSubview:search];

    // Tabelle
    CGFloat listTop = sy + 50, barH = [MeshTabBar height];
    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, listTop, W, H - listTop - barH) style:UITableViewStylePlain];
    _table.backgroundColor = [MeshTheme bg];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = 70;
    _table.dataSource = self; _table.delegate = self;
    [_table addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    [self.view addSubview:_table];

    // Scan-FAB
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(W - 78, H - barH - 78, 58, 58);
    fab.backgroundColor = [MeshTheme accent]; fab.layer.cornerRadius = fab.bounds.size.height / 2;
    // Mit Kamera direkt in den QR-Scanner, sonst Kontakt per eingefügtem npub hinzufügen.
    BOOL cam = [MeshCaps hasCamera];
    [fab setImage:[MeshGlyphs icon:(cam ? @"scan" : @"add") color:[MeshTheme bg] size:26] forState:UIControlStateNormal];
    [fab addTarget:self action:(cam ? @selector(tapScan) : @selector(tapAdd)) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fab];

    MeshTabBar *bar = [[MeshTabBar alloc] initWithFrame:CGRectMake(0, H - barH, W, barH) selected:MeshTabChats];
    MESH_WEAK ChatsListViewController *weakSelf = self;
    bar.onSelect = ^(MeshTab tab) { [weakSelf tapMe]; };
    [self.view addSubview:bar];
}

// Unter iOS 4 sind Delegates unsafe_unretained, hier selbst lösen.
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil;
    _table.dataSource = nil;
    _search.delegate = nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    for (NSString *name in @[MeshMessagesChangedNotification, MeshIdentityChangedNotification, MeshProfilesChangedNotification])
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messagesChanged) name:name object:nil];
}

// Geladen wird beim Erscheinen; verdeckt (ein Chat liegt darüber) muss die Liste nicht mitlaufen.
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }

- (void)messagesChanged {
    if (self.isViewLoaded && self.view.window) [self reload];
}

- (void)reload {
    MeshSession *s = [MeshSession shared];
    _allChats = [s chatList];
    // Profilbilder der eigenen Identitäten für die Plaketten im gemeinsamen Posteingang
    NSMutableDictionary *pictures = [NSMutableDictionary dictionary];
    if (s.unifiedInbox) for (MeshIdentityInfo *i in [s identities]) if (i.picture.length) pictures[@(i.slot)] = i.picture;
    _identityPictures = pictures;
    [self applyFilter];
}

- (int)activeSlot {
    for (MeshIdentityInfo *i in [[MeshSession shared] identities]) if (i.active) return i.slot;
    return 0;
}

// Ein Chat einer anderen eigenen Identität: erst zu ihr wechseln (wie Android switchAndOpen).
- (void)switchFor:(MeshChat *)c {
    if (c.identitySlot != [self activeSlot]) [[MeshSession shared] switchToIdentity:c.identitySlot];
}

- (void)applyFilter {
    NSString *q = [_search.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _searchHint.hidden = (_search.text.length > 0);
    if (!q.length) { _chats = _allChats; [_table reloadData]; return; }
    NSMutableArray *hits = [NSMutableArray array];
    for (MeshChat *c in _allChats)
        if ([c.name rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [hits addObject:c];
    _chats = hits;
    [_table reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return NO; }
- (BOOL)textFieldShouldClear:(UITextField *)tf { tf.text = @""; [self applyFilter]; return NO; }   // Löschknopf meldet kein EditingChanged
- (void)scrollViewWillBeginDragging:(UIScrollView *)sv { [_search resignFirstResponder]; }

- (void)tapAdd { [self.navigationController pushViewController:[[AddContactViewController alloc] init] animated:YES]; }
- (void)tapMe  { [self.navigationController pushViewController:[[MeInViewController alloc] init] animated:YES]; }

// Hinzufügen-Knopf → QR-Scanner. Ein gescannter Schlüssel legt den Kontakt an und öffnet den Chat.
// „Code einfügen" im Scanner öffnet stattdessen die manuelle Eingabe.
- (void)tapScan {
    QRScannerViewController *sc = [[QRScannerViewController alloc] init];
    MESH_WEAK ChatsListViewController *weakSelf = self;
    sc.onScan = ^(NSString *payload) {
        NSString *hex = [[MeshSession shared] addContact:payload name:nil];
        if (hex) [weakSelf.navigationController pushViewController:[[ChatViewController alloc] initWithPeer:hex] animated:YES];
        else     [MeshPopup info:L(@"This QR code doesn't contain a contact key.")];
    };
    sc.onManual = ^{ [weakSelf.navigationController pushViewController:[[AddContactViewController alloc] init] animated:YES]; };
    [self mesh_present:sc animated:YES];
}

#pragma mark - Tabelle

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _chats.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *rid = @"chat";
    MeshChatCell *cell = [t dequeueReusableCellWithIdentifier:rid];
    if (!cell) cell = [[MeshChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
    MeshChat *c = _chats[ip.row];
    cell.avatar.pubkey = c.pubkey;
    cell.nameLabel.text = [MeshFormat contactName:c.name accepted:!c.unknown];
    cell.nameLabel.textColor = c.unknown ? [MeshTheme muted] : [MeshTheme ink];
    NSString *preview = [MeshFormat preview:c.lastContent kind:c.lastKind];
    cell.previewLabel.text = c.fromMe ? [L(@"You: ") stringByAppendingString:preview] : preview;
    cell.timeLabel.text = [MeshFormat shortTime:c.ts];
    cell.identityBadge.hidden = ![MeshSession shared].unifiedInbox;
    cell.identityBadge.picture = _identityPictures[@(c.identitySlot)];
    cell.identityBadge.pubkey = c.identityPubkey;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    [_search resignFirstResponder];
    MeshChat *c = _chats[ip.row];
    [self switchFor:c];
    [self.navigationController pushViewController:[[ChatViewController alloc] initWithPeer:c.pubkey] animated:YES];
}

// Langes Drücken auf einen Chat: löschen oder den Absender blockieren.
- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [_table indexPathForRowAtPoint:[g locationInView:_table]];
    if (!ip || ip.row >= (NSInteger)_chats.count) return;
    [self switchFor:_chats[ip.row]];
    NSString *peer = [_chats[ip.row] pubkey];
    [MeshPopup sheet:[[MeshSession shared] displayNameFor:peer] options:@[L(@"Delete chat"), L(@"Block")]
     destructiveIndex:1 handler:^(NSInteger idx) {
        if (idx == 0) [[MeshSession shared] deleteChat:peer];
        if (idx == 1) [[MeshSession shared] blockContact:peer];
    }];
}

@end
