#import "ChatViewController.h"
#import "VoiceEffectViewController.h"
#import "MeshScreen.h"
#import "MeshCaps.h"
#import "MeshAvatarView.h"
#import "MeshPayload.h"
#import "MeshBubbleCell.h"
#import "MeshPageHeader.h"
#import "MeshChatInputBar.h"
#import "MeshTheme.h"
#import "MeshSession.h"
#import "MeshMessage.h"
#import "MeshGlyphs.h"
#import "PeerProfileViewController.h"
#import "MeshImageViewer.h"
#import "MeshMediaViewer.h"
#import "MeshVoice.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshVoiceSettings.h"
#import "MeshText.h"
#import "MeshFormat.h"
#import "MeshImageCodec.h"
#import "MeshMediaCheck.h"
#import "MeshNoticeCell.h"
#import "MeshReplyBar.h"
#import "MeshMessageMenu.h"
#import "MeshChatMenu.h"
#import "MeshAttachMenu.h"
#import "MeshFileViewer.h"
#import "MeshVideoCodec.h"
#import "MeshGalleryViewController.h"
#import "MeshNotifications.h"

static const long long kDividerRow = -1;      // Hinweiszeile "Neue Nachrichten" (keine Datenbankzeile)
static const CGFloat kStripRow = 26;          // Zeilen unter dem Kopf: offline, Selbstlöschen
static const NSUInteger kPage = 80;           // so viele Nachrichten je Laden (Öffnen, Hochscrollen)
static const NSUInteger kFirstPage = 20;      // beim Öffnen zuerst nur so viele, der Rest bis kPage nach der Animation
static const NSUInteger kJumpMax = 1000;      // Zitat antippen lädt höchstens so viele (jede kostet Entschlüsseln und Messen)

@interface ChatViewController () <MeshVoiceDelegate, MeshChatInputBarDelegate>
@end

@implementation ChatViewController {
    NSString *_peerHex;
    NSArray *_messages;
    NSCache *_imgCache;                 // rowId -> UIImage, begrenzt
    NSCache *_fileCache;                // rowId -> @[Name, MIME, Bytes] von Dateien
    NSCache *_thumbCache;               // rowId -> Vorschaubild eines Videos (NSNull: keins möglich)
    NSMutableSet *_thumbPending;        // rowIds, deren Vorschaubild gerade entsteht
    NSMutableSet *_imgPending;          // rowIds, deren Bild gerade im Hintergrund dekodiert wird
    NSMutableDictionary *_quotes;       // cmid -> @[Autor, Zeile, gefunden?] der zitierten Nachricht; beim Neuladen geprüft
    NSArray *_media;                    // Bilder und Videos fürs Vollbild (Galerie-Reihenfolge), je Neuladen
    NSUInteger _limit;                  // so viele der neuesten Nachrichten sind geladen (wächst beim Hochscrollen)
    BOOL _loadingOlder;
    int _acceptedState;                 // 0 unbekannt, 1 nein, 2 ja – je Neuladen einmal abgefragt, nicht je Zeile
    NSString *_peerName;                // Anzeigename des Kontakts, je Neuladen einmal
    NSString *_identity;                // eigener Pubkey: Zeilennummern gelten je Identität (eigene Datenbank)
    NSMutableDictionary *_cardKnown;    // Pubkey einer Kontaktkarte -> schon angenommener Kontakt? je Neuladen
    BOOL _appeared;                     // erstes viewDidAppear vorbei: ältere nachladen erlaubt

    UITableView *_table;
    MeshChatInputBar *_inputBar;
    CGFloat      _baseInputY;
    UIImageView *_verifiedBadge;
    UIImageView *_timerBadge;           // Selbstlöschen aktiv
    UILabel     *_titleLabel;
    MeshReplyBar *_replyBar;            // sichtbar, solange _replyTo gesetzt ist
    MeshMessage *_replyTo;
    CGFloat      _keyboardHeight;

    MeshVoice *_voice;
    NSTimer   *_recTimer;
    int        _recSecs;
    long long  _playingRowId; // rowId der spielenden Sprachnachricht (0 = keine); Zeilen verschieben sich beim Neuladen
    NSTimer   *_playTimer;    // bewegt die Wellenform während der Wiedergabe
    NSDate    *_playStartDate;
    int        _playDur;
    BOOL       _stale;        // Nachrichten haben sich geändert, während der Chat verdeckt war

    long long  _readAt, _openedAt;   // beim Öffnen: bis hier war gelesen / Zeitpunkt (für die Trennlinie)
    BOOL       _initialScroll;       // erstes Laden: zur Trennlinie statt ans Ende
    CGFloat    _headH;
    UIButton  *_offlineRow, *_timerRow;   // unter dem Kopf
    int        _stripOffline;             // zuletzt gezeigt: 0 verbunden, 1 offline, 2 Tor startet (-1 noch nie)
    int        _stripTimer;               // Selbstlöschen des Chats (aus updateStrip)
    BOOL       _stripFromSent;
}

#pragma mark - Lebenszyklus

- (instancetype)initWithPeer:(NSString *)peerHex {
    if ((self = [super init])) {
        _peerHex = [peerHex copy];
        _imgCache = [[NSCache alloc] init]; _imgCache.countLimit = 12;
        _imgCache.totalCostLimit = 16 * 1024 * 1024;   // dekodierte Pixel (w*h*4): fremde Clients dürfen bis 2048 px schicken
        _fileCache = [[NSCache alloc] init]; _fileCache.countLimit = 32;
        _thumbCache = [[NSCache alloc] init]; _thumbCache.countLimit = 24;
        _thumbPending = [NSMutableSet set];
        _imgPending = [NSMutableSet set];
        _quotes = [NSMutableDictionary dictionary];
        _cardKnown = [NSMutableDictionary dictionary];
        _stripOffline = -1;
    }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    [self mesh_setAvoidsKeyboard:NO];   // die Eingabeleiste rückt selbst mit der Tastatur
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    CGFloat top = [MeshTheme topInset], headH = top + 52, inH = [MeshChatInputBar height];
    _headH = headH;

    // Kopf: Zurück, Avatar (antippen: groß), Name (antippen: Kontaktprofil), Verifiziert-Schild
    MeshPageHeader *header = [[MeshPageHeader alloc] initWithWidth:W height:headH target:self back:@selector(mesh_goBack)];
    MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake(46, top + 8, 36, 36) source:MeshAvatarContact];
    av.pubkey = _peerHex;
    av.userInteractionEnabled = YES;
    [av addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatar)]];
    [header addSubview:av];
    _titleLabel = header.titleLabel;
    _titleLabel.frame = CGRectMake(92, top + 10, W - 92 - 104, 32);
    // Verifiziert-Schild und Selbstlöschen: nur Anzeige; verifiziert wird im Kontaktprofil.
    _timerBadge = [[UIImageView alloc] initWithFrame:CGRectMake(W - 104, top + 10, 26, 32)];
    _timerBadge.contentMode = UIViewContentModeCenter;
    [header addSubview:_timerBadge];
    _verifiedBadge = [[UIImageView alloc] initWithFrame:CGRectMake(W - 80, top + 10, 30, 32)];
    _verifiedBadge.contentMode = UIViewContentModeCenter;
    [header addSubview:_verifiedBadge];
    UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
    more.frame = CGRectMake(W - 48, top + 4, 44, 44);
    [more setImage:[MeshGlyphs icon:@"more" color:[MeshTheme ink] size:22] forState:UIControlStateNormal];
    [more addTarget:self action:@selector(openChatMenu) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:more];
    UIButton *titleTap = [UIButton buttonWithType:UIButtonTypeCustom];
    titleTap.frame = CGRectMake(88, top, W - 88 - 108, headH - top);
    [titleTap addTarget:self action:@selector(openPeer) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:titleTap];
    [self.view addSubview:header];

    // Unter dem Kopf wie bei Android: ohne Verbindung ein Hinweis, mit Selbstlöschen die Dauer (antippen: ändern)
    _offlineRow = [self stripRowWithColor:[UIColor colorWithRed:1.0f green:0x7A / 255.0f blue:0x33 / 255.0f alpha:0.16f] text:[MeshTheme ink]];
    _offlineRow.userInteractionEnabled = NO;
    [_offlineRow setImage:[MeshGlyphs icon:@"alert" color:[MeshTheme ink] size:14] forState:UIControlStateNormal];
    _timerRow = [self stripRowWithColor:[MeshTheme surface] text:[MeshTheme muted]];
    [_timerRow setImage:[MeshGlyphs icon:@"timer" color:[MeshTheme muted] size:14] forState:UIControlStateNormal];
    [_timerRow addTarget:self action:@selector(changeTimer) forControlEvents:UIControlEventTouchUpInside];

    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, headH, W, H - headH - inH) style:UITableViewStylePlain];
    _table.backgroundColor = [MeshTheme bg];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self; _table.delegate = self;
    [self.view addSubview:_table];
    [self.view addSubview:_offlineRow];
    [self.view addSubview:_timerRow];

    _baseInputY = H - inH;
    _inputBar = [[MeshChatInputBar alloc] initWithFrame:CGRectMake(0, _baseInputY, W, inH)];
    _inputBar.delegate = self;
    _inputBar.microphoneAvailable = [MeshCaps hasMicrophone];
    [self.view addSubview:_inputBar];

    _replyBar = [[MeshReplyBar alloc] initWithFrame:CGRectMake(0, _baseInputY - [MeshReplyBar height], W, [MeshReplyBar height])];
    _replyBar.hidden = YES;
    [_replyBar.closeButton addTarget:self action:@selector(cancelReply) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_replyBar];

    _voice = [[MeshVoice alloc] init];
    _voice.delegate = self;

    // Tippen in den Nachrichtenbereich schließt die Tastatur.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO; [_table addGestureRecognizer:tap];
    // Lang-drücken auf eine Nachricht: Reaktionen, Antworten, Kopieren, Löschen.
    [_table addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)]];
    // Kopf, Plaketten und Zeilen darunter setzt reload (viewDidLoad) einmal
}

- (UIButton *)stripRowWithColor:(UIColor *)bg text:(UIColor *)fg {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = bg;
    b.titleLabel.font = [MeshTheme timeFont];
    [b setTitleColor:fg forState:UIControlStateNormal];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 10);
    b.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
    b.hidden = YES;
    return b;
}

// Zeilen unter dem Kopf ein- oder ausblenden, die Liste rückt nach.
- (void)updateStrip {
    BOOL fromSent = NO;
    _stripTimer = [[MeshSession shared] timerFor:_peerHex fromSent:&fromSent];
    _stripFromSent = fromSent;
    [self layoutStrip];
}

// Verbindung geändert (beim Tor-Start je Prozentschritt): nur die Offline-Zeile, der Timer bleibt;
// ohne Änderung nichts tun.
- (void)connectionChanged {
    MeshSession *s = [MeshSession shared];
    int offline = s.anyRelayConnected ? 0 : (s.usesTor && !s.torReady) ? 2 : 1;
    if (offline == _stripOffline) return;
    [self layoutStrip];
}

- (void)layoutStrip {
    if (!_table) return;
    MeshSession *s = [MeshSession shared];
    CGFloat W = self.view.bounds.size.width, y = _headH;
    _stripOffline = s.anyRelayConnected ? 0 : (s.usesTor && !s.torReady) ? 2 : 1;
    _offlineRow.hidden = _stripOffline == 0;
    if (!_offlineRow.hidden) {
        [_offlineRow setTitle:_stripOffline == 2 ? L(@"Connecting to Tor… messages are sent once connected.")
                                                 : L(@"Offline – messages are sent once connected.") forState:UIControlStateNormal];
        _offlineRow.frame = CGRectMake(0, y, W, kStripRow);
        y += kStripRow;
    }
    BOOL fromSent = _stripFromSent;
    int timer = _stripTimer;
    _timerRow.hidden = timer == 0;
    if (timer) {
        [_timerRow setTitle:fromSent ? LF(@"Messages disappear %@ after sending", [MeshFormat timer:timer])
                                     : LF(@"Messages disappear %@ after reading", [MeshFormat timer:timer]) forState:UIControlStateNormal];
        _timerRow.frame = CGRectMake(0, y, W, kStripRow);
        y += kStripRow;
    }
    CGRect t = _table.frame;
    if (t.origin.y == y) return;
    BOOL bottom = [self nearBottom];
    t.origin.y = y;
    _table.frame = t;
    [self layoutBottom];   // Höhe der Liste
    if (bottom) [self scrollToBottom];
}

- (void)changeTimer {
    MESH_WEAK ChatViewController *weakSelf = self;
    [MeshChatMenu chooseTimerFor:_peerHex changed:^{ [weakSelf updateBadge]; }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messagesChanged)
                                                 name:MeshMessagesChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopMedia)
                                                 name:MeshWillLockNotification object:nil];
    // Der Chat gehört zur bisherigen Identität: bei einem Wechsel zurück zur Liste.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(identityChanged)
                                                 name:MeshIdentityChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionChanged)
                                                 name:MeshConnectionChangedNotification object:nil];
    _readAt = [[MeshSession shared] readAtIn:_peerHex];
    _openedAt = (long long)[[NSDate date] timeIntervalSince1970];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_stale) [self reload];
    else if (_appeared) {   // zurück aus Kontaktprofil o.ä. (beim ersten Mal hat reload das schon gesetzt)
        [self refreshPeer];
        [self updateBadge];   // z.B. nach Verifizieren im Kontakt-Profil
        [self updateTitle];
    }
}

// Erst nach der Wechsel-Animation: Schreiben in die Datenbank (Uhren starten, gelesen merken) und
// die älteren Nachrichten bis kPage, damit die Animation nicht darauf wartet.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[MeshSession shared] setOpenChat:_peerHex];   // startet die Uhren gelesener Nachrichten
    [[MeshSession shared] markReadIn:_peerHex];
    if (!_appeared) {
        _appeared = YES;
        if (_limit < kPage && [self rowCount] >= _limit) [self loadOlderKeepingPosition:kPage - _limit];
    }
}

// Verdeckt (Kontaktprofil, Bildanzeige darüber) nur vormerken: neu laden heißt alles neu entschlüsseln.
- (void)messagesChanged {
    if (self.isViewLoaded && self.view.window) [self reload];
    else _stale = YES;
}

// Timer halten den Controller fest, beim Verlassen Aufnahme und Wiedergabe beenden.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopMedia];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [[MeshSession shared] setOpenChat:nil];
    [[MeshSession shared] markReadIn:_peerHex];   // auch, was während des Lesens kam
}

// Aufnahme verwerfen (nicht senden), Wiedergabe stoppen, auch beim Sperren.
- (void)stopMedia {
    if (_voice.recording) [self cancelRecording];
    if (_playingRowId) { [_voice stop]; _playingRowId = 0; }
    [self stopPlayTimer];
}

- (void)identityChanged {
    [self stopMedia];
    [self.navigationController popToRootViewControllerAnimated:NO];
}

// Unter iOS 4 sind Delegates unsafe_unretained, hier selbst lösen.
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _voice.delegate = nil;
    _table.delegate = nil; _table.dataSource = nil;
    _inputBar.delegate = nil;
}

#pragma mark - Eingabeleiste

// Aktionsknopf: Aufnahme beenden und senden, Text senden oder Aufnahme starten.
- (void)inputBarTappedAction:(MeshChatInputBar *)bar {
    if (_voice.recording) { [self stopAndSend]; return; }
    if (bar.hasText) {
        NSString *text = [bar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([[MeshSession shared] sendTo:_peerHex text:text replyTo:_replyTo.cmid]) { bar.text = @""; [self cancelReply]; }
    } else if (bar.microphoneAvailable) {
        [self startRecording];
    }
}

- (void)inputBarCancelledRecording:(MeshChatInputBar *)bar { [self cancelRecording]; }

// Anhängen wie in der Android-App; langes Drücken: gleich die Mediathek.
- (void)inputBarTappedCamera:(MeshChatInputBar *)bar {
    [_inputBar endEditing];
    MESH_WEAK ChatViewController *weakSelf = self;
    [MeshAttachMenu showFrom:self peer:_peerHex replyTo:^{ return [weakSelf replyCmid]; } sent:^{ [weakSelf cancelReply]; }];
}

- (void)inputBarHeldCamera:(MeshChatInputBar *)bar {
    [_inputBar endEditing];
    MESH_WEAK ChatViewController *weakSelf = self;
    [MeshAttachMenu pickImageFrom:self source:UIImagePickerControllerSourceTypePhotoLibrary peer:_peerHex
                          replyTo:^{ return [weakSelf replyCmid]; } sent:^{ [weakSelf cancelReply]; }];
}

#pragma mark - Sprachaufnahme (Tippen startet, erneutes Tippen sendet)

- (void)startRecording {
    [_inputBar endEditing];
    _voice.effect = [MeshVoiceSettings currentEffect];
    if (![_voice startRecording]) { [MeshPopup info:L(@"Microphone unavailable")]; return; }
    _recSecs = 0;
    [_inputBar setRecordingText:[MeshFormat duration:0]];
    _inputBar.recording = YES;
    _recTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(recordingTick) userInfo:nil repeats:YES];
}

- (void)recordingTick {
    _recSecs++;
    if (_recSecs >= MeshVoiceMaxSeconds) { [self stopAndSend]; return; }
    [_inputBar setRecordingText:[MeshFormat duration:_recSecs]];
}

- (void)stopAndSend {
    [_recTimer invalidate]; _recTimer = nil;
    [_inputBar setRecordingText:L(@"Sending…")];
    [_voice stopRecording];      // asynchron → voiceRecordingFinished:seconds:
}

- (void)cancelRecording {
    [_recTimer invalidate]; _recTimer = nil;
    [_voice cancelRecording];
    _inputBar.recording = NO;
}

// Async, nachdem Effekt+AAC fertig sind.
- (void)voiceRecordingFinished:(NSData *)audio seconds:(int)seconds {
    _inputBar.recording = NO;
    if (audio.length && [[MeshSession shared] sendVoiceTo:_peerHex audio:audio seconds:seconds replyTo:_replyTo.cmid]) [self cancelReply];
    else if (!audio.length) [MeshPopup info:L(@"Recording too short")];
}

// Langes Drücken auf den Aktionsknopf: Stimmverzerrer-Seite öffnen.
- (void)inputBarHeldAction:(MeshChatInputBar *)bar {
    if (_voice.recording) return;
    [self.navigationController pushViewController:[[VoiceEffectViewController alloc] init] animated:YES];
}

#pragma mark - Wiedergabe

// Zu Ende gehört: folgt direkt eine Sprachnachricht des Kontakts, spielt sie gleich weiter (wie Android).
- (void)voicePlaybackFinished {
    long long done = _playingRowId;
    _playingRowId = 0;
    [self stopPlayTimer];
    [_table reloadData];
    NSUInteger i = [_messages indexOfObjectPassingTest:^BOOL(MeshMessage *m, NSUInteger idx, BOOL *stop) { return m.rowId == done; }];
    for (NSUInteger j = (i == NSNotFound ? _messages.count : i + 1); j < _messages.count; j++) {
        MeshMessage *next = _messages[j];
        if (next.kind == MeshPayloadNotice) continue;
        if (next.kind == MeshPayloadVoice && !next.fromMe && [self mayShowMediaOf:next]) [self playVoice:next];
        break;
    }
}

- (void)playVoice:(MeshMessage *)m {
    [_voice play:[[MeshSession shared] mediaOf:m]];
    _playingRowId = m.rowId;
    _playDur = MAX(1, [MeshPayload parse:m.content].seconds);
    _playStartDate = [NSDate date];
    [self startPlayTimer];
    [_table reloadData];
}

- (void)startPlayTimer {
    [self stopPlayTimer];
    _playTimer = [NSTimer scheduledTimerWithTimeInterval:0.08 target:self selector:@selector(playTick) userInfo:nil repeats:YES];
}
- (void)stopPlayTimer { [_playTimer invalidate]; _playTimer = nil; }
- (void)playTick {
    if (!_playingRowId) { [self stopPlayTimer]; return; }
    CGFloat prog = [[NSDate date] timeIntervalSinceDate:_playStartDate] / (CGFloat)_playDur;
    if (prog > 1) prog = 1;
    NSUInteger row = [_messages indexOfObjectPassingTest:^BOOL(MeshMessage *m, NSUInteger i, BOOL *stop) { return m.rowId == _playingRowId; }];
    UITableViewCell *c = (row == NSNotFound) ? nil : [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    if ([c isKindOfClass:[MeshBubbleCell class]]) [(MeshBubbleCell *)c setVoiceProgress:prog];
    if (prog >= 1) [self stopPlayTimer];
}

#pragma mark - Aktionen

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [_table indexPathForRowAtPoint:[g locationInView:_table]];
    if (!ip || ip.row >= (NSInteger)_messages.count) return;
    MeshMessage *m = _messages[ip.row];
    if (m.kind == MeshPayloadNotice) return;
    [_inputBar endEditing];
    MESH_WEAK ChatViewController *weakSelf = self;
    [MeshMessageMenu showFor:m peer:_peerHex reply:^{ [weakSelf replyTo:m]; }];
}

#pragma mark - Antworten

- (NSString *)replyCmid { return _replyTo.cmid; }

- (void)replyTo:(MeshMessage *)m {
    _replyTo = m;
    [_replyBar setAuthor:LF(@"Reply to %@", [[MeshSession shared] displayNameFor:_peerHex]) text:[self snippetOf:m]];
    _replyBar.hidden = NO;
    [self layoutBottom];
    [self scrollToBottom];
}

- (void)cancelReply {
    if (!_replyTo) return;
    _replyTo = nil;
    _replyBar.hidden = YES;
    [self layoutBottom];
}

// Eine Zeile Vorschau für Zitate.
- (NSString *)snippetOf:(MeshMessage *)m {
    if (!m) return L(@"Message deleted");
    return [MeshFormat preview:m.content kind:m.kind];
}

// Eingabe über der Tastatur, Antwortleiste darüber, die Liste füllt den Rest.
- (void)layoutBottom {
    CGRect f = _inputBar.frame; f.origin.y = _baseInputY - _keyboardHeight; _inputBar.frame = f;
    CGRect r = _replyBar.frame; r.origin.y = f.origin.y - r.size.height; _replyBar.frame = r;
    CGRect t = _table.frame; t.size.height = (_replyBar.hidden ? f.origin.y : r.origin.y) - t.origin.y; _table.frame = t;
}

#pragma mark - Chat-Menü

- (void)openChatMenu {
    [_inputBar endEditing];
    MESH_WEAK ChatViewController *weakSelf = self;
    [MeshChatMenu showForPeer:_peerHex media:^{ [weakSelf openGallery]; } changed:^{ [weakSelf updateBadge]; }];
}

- (void)openGallery {
    [self.navigationController pushViewController:[[MeshGalleryViewController alloc] initWithPeer:_peerHex] animated:YES];
}

- (void)updateTitle {
    _titleLabel.text = [MeshFormat contactName:_peerName accepted:_acceptedState == 2];
}

// Name und Annahme des Kontakts einmal je Neuladen (Zeilen, Zitate und Titel brauchen sie oft).
// Zitate bleiben über das Neuladen erhalten, solange Name und Annahme gleich sind.
- (void)refreshPeer {
    MeshSession *s = [MeshSession shared];
    NSString *name = [s displayNameFor:_peerHex] ?: @"";
    int acc = [s isAccepted:_peerHex] ? 2 : 1;
    NSString *me = [s myPubkeyHex] ?: @"";
    if (acc != _acceptedState || ![name isEqualToString:_peerName] || ![me isEqualToString:_identity]) [_quotes removeAllObjects];
    _peerName = name;
    _acceptedState = acc;
    _identity = me;
    [_cardKnown removeAllObjects];
}

- (void)openPeer { [self.navigationController pushViewController:[[PeerProfileViewController alloc] initWithPeer:_peerHex] animated:YES]; }

- (void)openAvatar {
    UIImage *big = [MeshAvatarView largeImageForSource:MeshAvatarContact pubkey:_peerHex];
    [self mesh_present:[[MeshImageViewer alloc] initWithImage:big] animated:YES];
}

#pragma mark - Medien

// Bilder werden erst für sichtbare Zeilen aus der DB geladen und begrenzt gecacht.
// Entschlüsseln (Store) auf dem Main-Thread, Dekodieren im Hintergrund: Öffnen und Scrollen ruckeln nicht.
// Für Zellen: fehlt das Bild noch, nil zurück und im Hintergrund dekodieren; die Zeile lädt danach neu.
- (UIImage *)cachedImageFor:(MeshMessage *)m loading:(BOOL *)loading {
    NSNumber *k = @(m.rowId);
    id hit = [_imgCache objectForKey:k];
    *loading = NO;
    if (hit) return hit == [NSNull null] ? nil : hit;
    if (![self mayShowMediaOf:m]) return nil;
    *loading = YES;
    if ([_imgPending containsObject:k]) return nil;
    NSData *jpeg = [[MeshSession shared] mediaOf:m];   // Store nur auf dem Main-Thread
    if (!jpeg.length) { *loading = NO; return nil; }   // nichts da: Platzhalter, aber nicht dauerhaft merken
    [_imgPending addObject:k];
    long long rowId = m.rowId;
    BOOL fromMe = m.fromMe;
    CGFloat width = _table.bounds.size.width, scale = [UIScreen mainScreen].scale;
    MESH_WEAK ChatViewController *weakSelf = self;
    // Eine Warteschlange, niedrige Priorität: der A4 hat einen Kern, die Wechsel-Animation geht vor.
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("mesh.chat.images", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(q, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    });
    dispatch_async(q, ^{
        UIImage *decoded = [MeshImageCodec imageFromData:jpeg formats:MeshImageJPEG];
        // gleich in Anzeigegröße mit runden Ecken: die Zelle muss weder skalieren noch ausschneiden
        UIImage *shown = decoded ? [MeshBubbleCell photoForBubble:decoded tableWidth:width fromMe:fromMe scale:scale] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf imageReady:shown row:rowId]; });
    });
    return nil;
}

static NSUInteger pixelCost(UIImage *img) { return (NSUInteger)(img.size.width * img.size.height * img.scale * img.scale * 4); }

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_imgCache removeAllObjects];
    [_thumbCache removeAllObjects];
    [_fileCache removeAllObjects];
    _media = nil;
}

- (void)imageReady:(UIImage *)img row:(long long)rowId {
    [_imgPending removeObject:@(rowId)];
    if (img) [_imgCache setObject:img forKey:@(rowId) cost:pixelCost(img)];
    else [_imgCache setObject:[NSNull null] forKey:@(rowId)];
    [self reloadVisibleRow:rowId];
}

- (void)reloadVisibleRow:(long long)rowId {
    for (NSUInteger i = 0; i < _messages.count; i++)
        if ([_messages[i] rowId] == rowId) {
            NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)i inSection:0];
            if ([[_table indexPathsForVisibleRows] containsObject:ip]) [_table reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
            break;
        }
}

// Bilder und Sprachnachrichten eines nicht angenommenen Kontakts erst nach Bestätigung dekodieren.
- (BOOL)mayShowMediaOf:(MeshMessage *)m { return m.fromMe || _acceptedState == 2; }   // je reload einmal abgefragt, nicht pro Zeile

- (void)askAcceptPeer {
    NSString *peer = _peerHex;
    [MeshPopup confirm:L(@"Show media from this contact?")
               message:L(@"Only accept contacts you know. Images, voice messages and the profile picture from this contact will then be shown.")
                action:L(@"Show") destructive:NO handler:^(BOOL yes) {
        if (yes) [[MeshSession shared] acceptContact:peer];
    }];
}

// Videos erscheinen als Kachel (wie Android), andere Dateien als Zeile. Ob Video, steht nur im
// verschlüsselten Inhalt: einmal nachsehen, danach merkt es sich die Datenbank (MeshSession isVideo:).
- (BOOL)isVideo:(MeshMessage *)m { return [[MeshSession shared] isVideo:m]; }

// Vorschaubild: aus dem Zwischenspeicher, sonst im Hintergrund erzeugen und die Zeile neu laden.
// Nur für eigene Videos: ein empfangenes MP4 läse sonst der Video-Teil von iOS 6 (mit bekannten
// Lücken) ohne jedes Antippen; das passiert erst beim Abspielen.
- (UIImage *)videoThumbOf:(MeshMessage *)m {
    if (!m.fromMe) return nil;
    id hit = [_thumbCache objectForKey:@(m.rowId)];
    if (hit) return hit == [NSNull null] ? nil : hit;
    if ([_thumbPending containsObject:@(m.rowId)]) return nil;
    [_thumbPending addObject:@(m.rowId)];
    NSData *mp4 = [[MeshSession shared] payloadOf:m].data;   // Store nur auf dem Main-Thread
    long long rowId = m.rowId;
    BOOL fromMe = m.fromMe;
    CGFloat scale = [UIScreen mainScreen].scale;
    MESH_WEAK ChatViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        UIImage *thumb = [MeshFileViewer isVideo:mp4 mime:@"video/mp4"] ? [MeshVideoCodec thumbnailOfMP4:mp4 maxSide:440] : nil;
        if (thumb) thumb = [MeshBubbleCell videoThumbForBubble:thumb fromMe:fromMe scale:scale];
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf thumbReady:thumb row:rowId]; });
    });
    return nil;
}

- (void)thumbReady:(UIImage *)thumb row:(long long)rowId {
    [_thumbPending removeObject:@(rowId)];
    [_thumbCache setObject:thumb ?: (id)[NSNull null] forKey:@(rowId)];
    [self reloadVisibleRow:rowId];
}

- (NSArray *)fileInfoOf:(MeshMessage *)m {
    NSArray *info = [_fileCache objectForKey:@(m.rowId)];
    if (info) return info;
    MeshPayload *p = [[MeshSession shared] payloadOf:m];
    info = @[MeshStripInvisible(p.fileName ?: @""), p.fileMime ?: @"", @(p.data.length)];
    [_fileCache setObject:info forKey:@(m.rowId)];
    return info;
}

// Text für Bild-Nachrichten, die (noch) nicht angezeigt werden.
- (NSString *)imagePlaceholderFor:(MeshMessage *)m {
    return [self mayShowMediaOf:m] ? L(@"Image can't be shown") : L(@"Image from unknown contact. Tap to show.");
}

// Für die Zeilenhöhe genügen die gespeicherten Maße; beim ersten Anzeigen liest sie der Dateikopf
// und die Datenbank merkt sie sich. Dekodiert wird erst, wenn die Zeile sichtbar wird.
- (BOOL)imageSize:(CGSize *)size ofMessage:(MeshMessage *)m {
    if (![self mayShowMediaOf:m]) return NO;
    if (!m.width || !m.height) {
        NSData *jpeg = [[MeshSession shared] mediaOf:m];
        if (![MeshMediaCheck isAcceptableImage:jpeg formats:MeshImageJPEG]) return NO;
        CGSize s = [MeshMediaCheck imageSize:jpeg formats:MeshImageJPEG];
        [[MeshSession shared] rememberImageWidth:(int)s.width height:(int)s.height of:m];
    }
    *size = CGSizeMake(m.width, m.height);
    return YES;
}

// Kontaktkarte antippen: den Kontakt hinzufügen (Name aus der Karte, änderbar über das Profil).
// Geteilter Kontakt: @[Name, Pubkey|"", schon Kontakt?]. "Hinzufügen" legt den Kontakt (nicht
// verifiziert) nach einer Rückfrage an und öffnet seinen Chat; ist er schon da, öffnet die Karte ihn.
// Nur in Chats mit angenommenen Kontakten: sonst könnte ein Fremder per Karte "Mama" mit seinem
// eigenen Schlüssel unterschieben.
- (NSArray *)cardOf:(MeshMessage *)m {
    MeshPayload *card = [MeshPayload parse:m.content];
    MeshSession *s = [MeshSession shared];
    NSString *pk = [s pubkeyOfContactCode:card.code] ?: @"";
    NSString *name = MeshCleanName(card.text);
    NSNumber *known = pk.length ? _cardKnown[pk] : @NO;
    if (!known) _cardKnown[pk] = known = @([s isAccepted:pk]);   // je Neuladen einmal je Kontakt
    return @[name.length ? name : L(@"Contact"), pk, known];
}

- (void)offerContactCard:(MeshMessage *)m {
    NSArray *card = [self cardOf:m];
    NSString *pk = card[1];
    MeshSession *s = [MeshSession shared];
    if (!pk.length || [pk isEqualToString:[s myPubkeyHex]]) return;
    // Schon Kontakt (auch bei selbst geschickten Karten): gleich in den Chat mit der Person
    if ([card[2] boolValue]) { [self openChatWith:pk]; return; }
    if (m.fromMe) return;
    if (![s isAccepted:_peerHex]) { [self askAcceptPeer]; return; }
    NSString *npub = [s npubFor:pk];
    NSString *key = npub.length > 20 ? [NSString stringWithFormat:@"%@…%@", [npub substringToIndex:12], [npub substringFromIndex:npub.length - 6]] : npub;
    [MeshPopup confirm:L(@"Add contact?")
               message:LF(@"%@\nshared by %@\n%@\n\nOnly add people you know.", card[0], [s displayNameFor:_peerHex], key)
                action:L(@"Add") destructive:NO handler:^(BOOL yes) {
        if (!yes) return;
        if (![s addContact:[MeshPayload parse:m.content].code name:card[0]]) { [MeshPopup info:L(@"This QR code doesn't contain a contact key.")]; return; }
        [self openChatWith:pk];
    }];
}

// Bild antippen: Vollbild mit allen Bildern und Videos des Chats, wischen wie in der Galerie
// (dort neueste zuerst, hier in Chat-Reihenfolge: nach links ältere).
- (void)openViewerAt:(MeshMessage *)m {
    if (!_media) _media = [[[MeshGalleryViewController itemsFor:_peerHex] reverseObjectEnumerator] allObjects];
    NSArray *media = _media;
    NSUInteger i = [media indexOfObjectPassingTest:^BOOL(MeshMessage *x, NSUInteger idx, BOOL *stop) { return x.rowId == m.rowId; }];
    if (i == NSNotFound) { media = @[m]; i = 0; }
    [self mesh_present:[[MeshMediaViewer alloc] initWithItems:media index:i peer:_peerHex] animated:YES];
}

- (void)openChatWith:(NSString *)pk {
    [self.navigationController pushViewController:[[ChatViewController alloc] initWithPeer:pk] animated:YES];
}

#pragma mark - Liste

- (void)reload {
    _stale = NO;
    [self refreshPeer];
    [self updateTitle];
    [self updateBadge];   // der Kontakt kann den Timer geändert haben
    BOOL wasAtBottom = [self nearBottom];
    if (!_limit) {
        // Öffnen: erst wenige (schnell durch die Animation), den Rest bis kPage lädt viewDidAppear.
        // Liegt die Trennlinie weiter zurück, gleich kPage, damit sie wie bisher oben stehen kann.
        NSUInteger unread = _readAt > 0 ? [[MeshSession shared] messageCountAfter:_readAt in:_peerHex] : 0;
        _limit = unread + 1 <= kFirstPage ? kFirstPage : kPage;
    } else if (wasAtBottom && _initialScroll) {
        _limit = kPage;   // unten angekommen: wieder nur die neuesten, sonst entschlüsselt jedes Neuladen alles Nachgeladene
    }
    _messages = [self withDivider:[[MeshSession shared] messagesWith:_peerHex limit:_limit]];
    [self checkQuotes];
    _media = nil;
    [_table reloadData];
    if (!_initialScroll) {
        _initialScroll = YES;
        // Beim Öffnen mit Ungelesenem: die Trennlinie oben zeigen statt ans Ende zu springen
        NSUInteger d = [_messages indexOfObjectPassingTest:^BOOL(MeshMessage *m, NSUInteger i, BOOL *stop) { return m.rowId == kDividerRow; }];
        if (d != NSNotFound && d > 0) {
            [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)d inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
            return;
        }
    }
    if (wasAtBottom) [self scrollToBottom];   // nur ans Ende, wenn man eh unten war (kein Zurückspringen)
}

// Trennlinie "N neue Nachrichten" vor der ersten Nachricht des Kontakts, die beim Öffnen noch
// ungelesen war (wie Android). Eine Hinweiszeile ohne Datenbankzeile; sie bleibt, solange der Chat offen ist.
- (NSArray *)withDivider:(NSArray *)list {
    if (_readAt <= 0) return list;   // erster Start nach dem Update: kein Stand bekannt
    NSUInteger first = NSNotFound, n = 0;
    for (NSUInteger i = 0; i < list.count; i++) {
        MeshMessage *m = list[i];
        if (m.fromMe || m.kind == MeshPayloadNotice || m.ts <= _readAt || m.ts > _openedAt) continue;
        if (first == NSNotFound) first = i;
        n++;
    }
    if (first == NSNotFound) return list;
    MeshMessage *d = [[MeshMessage alloc] init];
    d.rowId = kDividerRow;
    d.kind = MeshPayloadNotice;
    d.content = n == 1 ? L(@"1 new message") : LF(@"%lu new messages", (unsigned long)n);
    NSMutableArray *out = [list mutableCopy];
    [out insertObject:d atIndex:first];
    return out;
}

// Gemerkte Zitate prüfen, ohne zu entschlüsseln: gelöschte oder abgelaufene Nachrichten dürfen nicht
// weiter im Zitat stehen, eine inzwischen angekommene soll erscheinen.
- (void)checkQuotes {
    MeshSession *s = [MeshSession shared];
    for (NSString *key in [_quotes allKeys])
        if (![_quotes[key][2] boolValue] || ![s hasMessage:key in:_peerHex]) [_quotes removeObjectForKey:key];
}

// Geladene Datenbankzeilen (ohne die Trennlinie).
- (NSUInteger)rowCount {
    NSUInteger n = 0;
    for (MeshMessage *m in _messages) if (m.rowId != kDividerRow) n++;
    return n;
}

// count ältere Nachrichten vor die geladenen setzen: nur diese werden entschlüsselt, gemessene Höhen bleiben.
- (void)prependOlder:(NSUInteger)count {
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:_messages.count + count];
    for (MeshMessage *m in _messages) if (m.rowId != kDividerRow) [rows addObject:m];
    NSUInteger had = rows.count;
    NSArray *older = [[MeshSession shared] messagesWith:_peerHex before:rows.firstObject limit:count];
    [rows replaceObjectsInRange:NSMakeRange(0, 0) withObjectsFromArray:older];
    _limit = had + count;   // weniger gekommen als verlangt: es gibt keine älteren mehr
    _messages = [self withDivider:rows];
}

- (NSUInteger)indexOfKey:(NSString *)key {
    return [_messages indexOfObjectPassingTest:^BOOL(MeshMessage *m, NSUInteger i, BOOL *stop) {
        return m.rowId != kDividerRow && ([m.cmid isEqualToString:key] || [m.eventId isEqualToString:key]);
    }];
}

// Zitat antippen: zur zitierten Nachricht scrollen und sie kurz aufleuchten lassen; ältere werden nachgeladen.
// Wie weit zurück, zählt die Datenbank: einmal nachladen statt in Runden alles neu zu entschlüsseln.
- (void)jumpToMessage:(NSString *)key {
    NSUInteger i = [self indexOfKey:key];
    if (i == NSNotFound) {
        NSUInteger need = [[MeshSession shared] messageCountFrom:key in:_peerHex], have = [self rowCount];
        if (!need) { [MeshPopup info:L(@"The quoted message is no longer there.")]; return; }
        // Ein paar ältere dazu: sonst stünde das Ziel ganz oben, und das Scrollen dorthin löste gleich
        // das Nachladen aus (das die Animation unterbricht).
        NSUInteger want = MIN(need + 20, kJumpMax);
        if (want > have) {
            [self prependOlder:want - have];
            [_table reloadData];
        }
        i = [self indexOfKey:key];
        if (i == NSNotFound) {   // weiter zurück als kJumpMax: bis zur ältesten geladenen
            if (_messages.count)
                [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:YES];
            return;
        }
    }
    [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    MESH_WEAK ChatViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf glowMessage:key]; });
}

// Zeile erst jetzt suchen: in den 0,4 s kann ein Neuladen die Zeilen verschoben haben.
- (void)glowMessage:(NSString *)key {
    NSUInteger i = [self indexOfKey:key];
    UITableViewCell *c = i == NSNotFound ? nil : [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    if (!c) return;
    UIView *glow = [[UIView alloc] initWithFrame:c.contentView.bounds];
    glow.backgroundColor = [[MeshTheme accent] colorWithAlphaComponent:0.18f];
    glow.userInteractionEnabled = NO;
    [c.contentView addSubview:glow];
    [UIView animateWithDuration:0.9 delay:0.3 options:0 animations:^{ glow.alpha = 0; }
                     completion:^(BOOL done) { [glow removeFromSuperview]; }];
}

// YES, wenn die Tabelle nahe am unteren Ende steht (dann darf auto-gescrollt werden).
- (BOOL)nearBottom {
    UITableView *t = _table;
    if (t.contentSize.height <= t.bounds.size.height) return YES;   // passt komplett rein
    CGFloat dist = t.contentSize.height - (t.contentOffset.y + t.bounds.size.height);
    return dist < 90;
}

// Ganz oben angekommen: die nächsten 80 älteren Nachrichten davorsetzen, die Ansicht bleibt an derselben Stelle
- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (sv != _table || !_appeared || _loadingOlder || sv.contentOffset.y > 40 || [self rowCount] < _limit) return;
    [self loadOlderKeepingPosition:kPage];
}

- (void)loadOlderKeepingPosition:(NSUInteger)count {
    _loadingOlder = YES;
    CGFloat oldH = _table.contentSize.height, oldY = _table.contentOffset.y;
    [self prependOlder:count];
    [_table reloadData];
    [_table layoutIfNeeded];
    _table.contentOffset = CGPointMake(0, oldY + (_table.contentSize.height - oldH));
    _loadingOlder = NO;
}

- (void)scrollToBottom {
    NSInteger n = _messages.count;
    if (n > 0) {
        [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:n - 1 inSection:0]
                          atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }
}

- (void)updateBadge {
    MeshSession *s = [MeshSession shared];
    _verifiedBadge.image = [s isVerified:_peerHex] ? [MeshGlyphs icon:@"shield" color:[MeshTheme accent] size:22] : nil;
    _timerBadge.image = [s timerFor:_peerHex fromSent:NULL] ? [MeshGlyphs icon:@"timer" color:[MeshTheme muted] size:20] : nil;
    [self updateStrip];
}

#pragma mark - Tastatur

- (void)dismissKeyboard { [self.view endEditing:YES]; }

- (void)keyboardWillShow:(NSNotification *)n {
    _keyboardHeight = [[n.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
    [UIView animateWithDuration:0.25 animations:^{ [self layoutBottom]; }
                     completion:^(BOOL done) { [self scrollToBottom]; }];
}

- (void)keyboardWillHide:(NSNotification *)n {
    _keyboardHeight = 0;
    [UIView animateWithDuration:0.25 animations:^{ [self layoutBottom]; }];
}

#pragma mark - Tabelle

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _messages.count; }

// Sehr lange Texte kappen (z.B. ein versehentlich als Text empfangener Bild-Base64-Blob),
// sonst wird die Zeile riesig und das Rendern blockiert das Scrollen.
// Ohne Schreibrichtungszeichen, sonst könnte ein Fremder den angezeigten Text umdrehen.
- (NSString *)displayText:(NSString *)c {
    c = MeshStripInvisible(c);
    if (c.length > 3000) return [MeshTruncate(c, 3000) stringByAppendingString:@" …"];
    return c;
}

// Wie eine Nachricht erscheint, an einer Stelle entschieden: Sprachnachricht, Bild mit bekannter
// Größe oder Text (auch der Platzhalter für Bilder, die nicht gezeigt werden, Dateien und Kontakte).
- (MeshPayloadKind)bubbleFor:(MeshMessage *)m imageSize:(CGSize *)size text:(NSString **)text {
    MeshPayloadKind kind = m.kind;
    if (m.rowId == kDividerRow) { *text = m.content; return MeshPayloadNotice; }
    if (kind == MeshPayloadNotice) { *text = [MeshFormat notice:m.content peer:_peerName]; return kind; }
    if (kind == MeshPayloadVoice) return kind;
    if (kind == MeshPayloadImage && [self imageSize:size ofMessage:m]) return kind;
    if (kind == MeshPayloadFile && [self mayShowMediaOf:m]) return kind;
    if (kind == MeshPayloadContact) return kind;
    if (kind == MeshPayloadImage) *text = [self imagePlaceholderFor:m];
    else if (kind == MeshPayloadText) *text = [self displayText:m.content];
    else *text = [MeshFormat preview:m.content kind:kind];
    return MeshPayloadText;
}

// Zitierte Nachricht: Name und eine Zeile. Gelöschte zeigen das an.
// Je cmid einmal nachgeschlagen: Zeilenhöhen fragen bei jedem Neuladen alle Zeilen ab.
- (BOOL)quoteFor:(MeshMessage *)m author:(NSString **)author text:(NSString **)text {
    if (!m.replyTo.length) return NO;
    NSArray *quote = _quotes[m.replyTo];
    if (!quote) {
        MeshMessage *q = [[MeshSession shared] message:m.replyTo in:_peerHex];
        quote = @[ !q ? @"" : q.fromMe ? L(@"You") : _peerName, [self snippetOf:q], @(q != nil) ];
        _quotes[m.replyTo] = quote;
    }
    *author = quote[0];
    *text = quote[1];
    return YES;
}

static NSString *reactionsOf(MeshMessage *m) {
    return [NSString stringWithFormat:@"%@%@", m.reactPeer ?: @"", m.reactMine ?: @""];
}

// Zeilenhöhen für alle Chats gemeinsam: erneutes Öffnen misst nichts neu. Der Schlüssel enthält alles,
// was die Höhe ändert: Identität und Kontakt (Zeilennummern gelten je Datenbank), Zeile, Art, Status,
// Reaktionen, Breite, Bildmaße bzw. Datei-Art, Annahme; bei Hinweisen den Text, bei Kontaktkarten,
// ob es eine Aktionszeile gibt. Beim Sperren und Identitätswechsel geleert (enthält Pubkeys).
static NSCache *Heights(void) {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 3000;
        for (NSString *name in @[MeshWillLockNotification, MeshIdentityChangedNotification, MeshWipedNotification])
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                          usingBlock:^(NSNotification *n) { [cache removeAllObjects]; }];
    });
    return cache;
}

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    MeshMessage *m = _messages[ip.row];
    NSString *extra = @"";
    if (m.rowId == kDividerRow || m.kind == MeshPayloadNotice) {
        CGSize size; NSString *text = nil;
        [self bubbleFor:m imageSize:&size text:&text];
        extra = text ?: @"";
    } else if (m.kind == MeshPayloadContact) {
        NSArray *card = [self cardOf:m];
        extra = (!m.fromMe && [card[1] length] && ([card[2] boolValue] || _acceptedState == 2)) ? @"a" : @"-";
    }
    NSString *hk = [NSString stringWithFormat:@"%@|%@|%lld|%d|%d|%@|%.0f|%d|%d|%d|%d|%@", _identity, _peerHex, m.rowId, (int)m.kind,
                    m.status, reactionsOf(m), t.bounds.size.width, m.width, m.height, _acceptedState, m.replyTo.length > 0, extra];
    NSNumber *known = [Heights() objectForKey:hk];
    if (known) return known.floatValue;
    CGFloat h = [self measureRow:m width:t.bounds.size.width];
    [Heights() setObject:@(h) forKey:hk];
    return h;
}

- (CGFloat)measureRow:(MeshMessage *)m width:(CGFloat)tableWidth {
    CGSize size; NSString *text = nil, *qa = nil, *qt = nil;
    CGFloat w = tableWidth, base;
    switch ([self bubbleFor:m imageSize:&size text:&text]) {
        case MeshPayloadNotice: return [MeshNoticeCell heightForNotice:text width:w];
        case MeshPayloadVoice:  base = [MeshBubbleCell heightForVoice]; break;
        case MeshPayloadFile:   base = [self isVideo:m] ? [MeshBubbleCell heightForVideo] : [MeshBubbleCell heightForFile]; break;
        case MeshPayloadImage:  base = [MeshBubbleCell heightForImageOfSize:size width:w]; break;
        case MeshPayloadContact: {
            NSArray *card = [self cardOf:m];
            BOOL action = !m.fromMe && [card[1] length] && ([card[2] boolValue] || _acceptedState == 2);
            base = [MeshBubbleCell heightForContactCardWithAction:action];
            break;
        }
        default:                base = [MeshBubbleCell heightForText:text width:w]; break;
    }
    return base + [MeshBubbleCell extraHeightWithQuote:[self quoteFor:m author:&qa text:&qt] reactions:reactionsOf(m).length > 0];
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    MeshMessage *m = _messages[ip.row];
    CGFloat w = t.bounds.size.width;
    CGSize size; NSString *text = nil;
    MeshPayloadKind kind = [self bubbleFor:m imageSize:&size text:&text];
    if (kind == MeshPayloadNotice) {
        MeshNoticeCell *nc = [t dequeueReusableCellWithIdentifier:@"notice"];
        if (!nc) nc = [[MeshNoticeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"notice"];
        [nc setNotice:text width:w];
        return nc;
    }
    MeshBubbleCell *cell = [t dequeueReusableCellWithIdentifier:@"bubble"];
    if (!cell) cell = [[MeshBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bubble"];
    NSString *qa = nil, *qt = nil;
    if ([self quoteFor:m author:&qa text:&qt]) {
        [cell setQuoteAuthor:qa text:qt];
        NSString *key = m.replyTo;
        MESH_WEAK ChatViewController *weakSelf = self;
        cell.quoteTapped = ^{ [weakSelf jumpToMessage:key]; };
    } else {
        [cell setQuoteAuthor:nil text:nil];
        cell.quoteTapped = nil;
    }
    [cell setReactions:reactionsOf(m)];
    switch (kind) {
        case MeshPayloadVoice:
            [cell setVoice:[MeshPayload parse:m.content].seconds seed:(m.eventId.length ? m.eventId : m.content)
                   playing:(m.rowId == _playingRowId) fromMe:m.fromMe status:m.status width:w];
            break;
        case MeshPayloadFile: {
            if ([self isVideo:m]) { [cell setVideo:[self videoThumbOf:m] fromMe:m.fromMe status:m.status width:w]; break; }
            NSArray *info = [self fileInfoOf:m];
            [cell setFile:[info[0] length] ? info[0] : L(@"File") detail:[MeshFormat fileDetail:info[0] mime:info[1] bytes:[info[2] longLongValue]]
                   fromMe:m.fromMe status:m.status width:w];
            break;
        }
        case MeshPayloadContact: {
            NSArray *card = [self cardOf:m];
            BOOL known = [card[2] boolValue], action = !m.fromMe && [card[1] length] && (known || _acceptedState == 2);
            [cell setContactCard:card[0] pubkey:card[1] action:action ? (known ? L(@"Open chat") : L(@"Add")) : nil
                           glyph:known ? @"chat" : @"add" fromMe:m.fromMe status:m.status width:w];
            break;
        }
        case MeshPayloadImage: {
            // Größe bekannt, das Bild selbst kann trotzdem fehlen (nicht dekodierbar): dann der Platzhalter.
            BOOL loading = NO;
            UIImage *img = [self cachedImageFor:m loading:&loading];
            CGSize size = CGSizeMake(m.width, m.height);
            if (img) [cell setImage:img fromMe:m.fromMe status:m.status width:w];
            else if (loading && size.width > 0 && size.height > 0)
                [cell setImage:nil size:size fromMe:m.fromMe status:m.status width:w];   // Rahmen in voller Größe, Bild folgt
            else [cell setText:[self imagePlaceholderFor:m] fromMe:m.fromMe status:m.status width:w];
            break;
        }
        default:
            [cell setText:text fromMe:m.fromMe status:m.status width:w];
            break;
    }
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:NO];
    MeshMessage *m = _messages[ip.row];
    MeshPayloadKind kind = m.kind;
    if ((kind == MeshPayloadImage || kind == MeshPayloadVoice || kind == MeshPayloadFile) && ![self mayShowMediaOf:m]) { [self askAcceptPeer]; return; }
    if (kind == MeshPayloadFile) {
        MeshPayload *p = [[MeshSession shared] payloadOf:m];
        [MeshFileViewer open:p.data name:p.fileName mime:p.fileMime from:self];
        return;
    }
    if (kind == MeshPayloadContact) { [self offerContactCard:m]; return; }
    if (kind == MeshPayloadVoice) {                      // Sprachnachricht antippen -> abspielen/stoppen
        if (m.rowId == _playingRowId) { [_voice stop]; _playingRowId = 0; [self stopPlayTimer]; [t reloadData]; }
        else [self playVoice:m];
        return;
    }
    if (kind == MeshPayloadImage) {
        // Nicht hier dekodieren (blockierte den Main-Thread): das Vollbild dekodiert selbst im Hintergrund.
        CGSize size;
        if ([_imgCache objectForKey:@(m.rowId)] == [NSNull null] || ![self imageSize:&size ofMessage:m]) return;   // nicht darstellbar
        [self openViewerAt:m];
    }
}

@end
