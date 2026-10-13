#import "ChatViewController.h"
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
    NSMutableDictionary *_quotes;       // cmid -> @[Autor, Zeile] der zitierten Nachricht, je Neuladen
    NSUInteger _limit;                  // so viele der neuesten Nachrichten sind geladen (wächst beim Hochscrollen)
    NSMutableDictionary *_heights;      // Zeilenhöhe je Nachricht (rowId, Reaktionen, Art, Breite) – Messen kostet am iPod viel
    BOOL _loadingOlder;
    int _acceptedState;                 // 0 unbekannt, 1 nein, 2 ja – ändert sich die Annahme, ändern sich Kontaktkarten-Höhen

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
    }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    [self mesh_setAvoidsKeyboard:NO];   // die Eingabeleiste rückt selbst mit der Tastatur
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    CGFloat top = [MeshTheme topInset], headH = top + 52, inH = [MeshChatInputBar height];

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
    [self updateBadge];
    [self updateTitle];

    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, headH, W, H - headH - inH) style:UITableViewStylePlain];
    _table.backgroundColor = [MeshTheme bg];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self; _table.delegate = self;
    [self.view addSubview:_table];

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
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[MeshSession shared] setOpenChat:_peerHex];   // startet die Uhren gelesener Nachrichten
    [self updateBadge];   // z.B. nach Verifizieren im Kontakt-Profil
    if (_stale) [self reload];
    else [self updateTitle];
}

// Verdeckt (Kontaktprofil, Bildanzeige darüber) nur vormerken: neu laden heißt alles neu entschlüsseln.
- (void)messagesChanged {
    if (self.isViewLoaded && self.view.window) [self reload];
    else _stale = YES;
}

// Timer halten den Controller fest, beim Verlassen Aufnahme und Wiedergabe beenden.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[MeshSession shared] setOpenChat:nil];
    [self stopMedia];
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

// Langes Drücken auf den Aktionsknopf: Stimmeffekt wählen.
- (void)inputBarHeldAction:(MeshChatInputBar *)bar {
    if (_voice.recording) return;
    NSArray *effects = [MeshVoiceSettings allEffects];
    [MeshPopup sheet:L(@"Voice effect") options:[MeshVoiceSettings effectLabels] destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx >= 0) {
            [MeshVoiceSettings setCurrentEffect:effects[idx]];
            [MeshPopup info:LF(@"Voice effect: %@", [MeshVoiceSettings effectLabel:effects[idx]])];
        }
    }];
}

#pragma mark - Wiedergabe

- (void)voicePlaybackFinished { _playingRowId = 0; [self stopPlayTimer]; [_table reloadData]; }

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
    [MeshChatMenu showForPeer:_peerHex changed:^{ [weakSelf updateBadge]; }];
}

- (void)updateTitle {
    MeshSession *s = [MeshSession shared];
    _titleLabel.text = [MeshFormat contactName:[s displayNameFor:_peerHex] accepted:[s isAccepted:_peerHex]];
}

- (void)openPeer { [self.navigationController pushViewController:[[PeerProfileViewController alloc] initWithPeer:_peerHex] animated:YES]; }

- (void)openAvatar {
    UIImage *big = [MeshAvatarView largeImageForSource:MeshAvatarContact pubkey:_peerHex];
    [self mesh_present:[[MeshImageViewer alloc] initWithImage:big] animated:YES];
}

#pragma mark - Medien

// Bilder werden erst für sichtbare Zeilen aus der DB geladen und begrenzt gecacht.
// Entschlüsseln (Store) auf dem Main-Thread, Dekodieren im Hintergrund: Öffnen und Scrollen ruckeln nicht.
- (UIImage *)imageForMessage:(MeshMessage *)m {
    id hit = [_imgCache objectForKey:@(m.rowId)];
    if (hit) return hit == [NSNull null] ? nil : hit;
    return [self mayShowMediaOf:m] ? [self decodeNow:m] : nil;
}

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
    MESH_WEAK ChatViewController *weakSelf = self;
    // Eine Warteschlange, niedrige Priorität: der A4 hat einen Kern, die Wechsel-Animation geht vor.
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("mesh.chat.images", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(q, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    });
    dispatch_async(q, ^{
        UIImage *decoded = [MeshImageCodec imageFromData:jpeg formats:MeshImageJPEG];
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf imageReady:decoded row:rowId]; });
    });
    return nil;
}

static NSUInteger pixelCost(UIImage *img) { return (NSUInteger)(img.size.width * img.size.height * img.scale * img.scale * 4); }

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_imgCache removeAllObjects];
    [_thumbCache removeAllObjects];
    [_fileCache removeAllObjects];
}

- (UIImage *)decodeNow:(MeshMessage *)m {
    UIImage *img = [MeshImageCodec imageFromData:[[MeshSession shared] mediaOf:m] formats:MeshImageJPEG];
    if (img) [_imgCache setObject:img forKey:@(m.rowId) cost:pixelCost(img)];
    return img;
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

// Name, Art und Größe einer Datei; dafür wird die Nachricht einmal ganz entschlüsselt.
// Videos erscheinen als Kachel (wie Android), andere Dateien als Zeile. Ob Video, steht im Kopf des
// gespeicherten Inhalts ("<SOH>mesh:file:Name<SOH>video/…"), ohne die Daten zu entschlüsseln.
- (BOOL)isVideo:(MeshMessage *)m {
    NSRange nl = [m.content rangeOfString:@"\n"];
    NSString *head = nl.location == NSNotFound ? m.content : [m.content substringToIndex:nl.location];
    return [head hasSuffix:@"\1video/mp4"];
}

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
    MESH_WEAK ChatViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        UIImage *thumb = [MeshFileViewer isVideo:mp4 mime:@"video/mp4"] ? [MeshVideoCodec thumbnailOfMP4:mp4 maxSide:440] : nil;
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
    return @[name.length ? name : L(@"Contact"), pk, @(pk.length && [s isAccepted:pk])];
}

- (void)offerContactCard:(MeshMessage *)m {
    NSArray *card = [self cardOf:m];
    NSString *pk = card[1];
    MeshSession *s = [MeshSession shared];
    if (m.fromMe || !pk.length) return;
    if ([card[2] boolValue]) { [self openChatWith:pk]; return; }
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

- (void)openChatWith:(NSString *)pk {
    [self.navigationController pushViewController:[[ChatViewController alloc] initWithPeer:pk] animated:YES];
}

#pragma mark - Liste

- (void)reload {
    _stale = NO;
    [self updateTitle];
    [self updateBadge];   // der Kontakt kann den Timer geändert haben
    BOOL wasAtBottom = [self nearBottom];
    if (!_limit) _limit = 80;
    if (!_heights) _heights = [NSMutableDictionary dictionary];
    int acc = [[MeshSession shared] isAccepted:_peerHex] ? 2 : 1;
    if (acc != _acceptedState) { [_heights removeAllObjects]; _acceptedState = acc; }
    _messages = [[MeshSession shared] messagesWith:_peerHex limit:_limit];
    [_quotes removeAllObjects];
    [_table reloadData];
    if (wasAtBottom) [self scrollToBottom];   // nur ans Ende, wenn man eh unten war (kein Zurückspringen)
}

// YES, wenn die Tabelle nahe am unteren Ende steht (dann darf auto-gescrollt werden).
- (BOOL)nearBottom {
    UITableView *t = _table;
    if (t.contentSize.height <= t.bounds.size.height) return YES;   // passt komplett rein
    CGFloat dist = t.contentSize.height - (t.contentOffset.y + t.bounds.size.height);
    return dist < 90;
}

// Ganz oben angekommen: die nächsten 80 älteren Nachrichten nachladen, die Ansicht bleibt an derselben Stelle
- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (sv != _table || _loadingOlder || sv.contentOffset.y > 40 || _messages.count < _limit) return;
    _loadingOlder = YES;
    CGFloat oldH = sv.contentSize.height, oldY = sv.contentOffset.y;
    _limit += 80;
    _messages = [[MeshSession shared] messagesWith:_peerHex limit:_limit];
    [_table reloadData];
    [_table layoutIfNeeded];
    sv.contentOffset = CGPointMake(0, oldY + (sv.contentSize.height - oldH));
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
    if (kind == MeshPayloadNotice) { *text = [MeshFormat notice:m.content peer:[[MeshSession shared] displayNameFor:_peerHex]]; return kind; }
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
        quote = @[ !q ? @"" : q.fromMe ? L(@"You") : [[MeshSession shared] displayNameFor:_peerHex], [self snippetOf:q] ];
        _quotes[m.replyTo] = quote;
    }
    *author = quote[0];
    *text = quote[1];
    return YES;
}

static NSString *reactionsOf(MeshMessage *m) {
    return [NSString stringWithFormat:@"%@%@", m.reactPeer ?: @"", m.reactMine ?: @""];
}

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    MeshMessage *m = _messages[ip.row];
    NSString *hk = [NSString stringWithFormat:@"%lld|%d|%d|%@|%.0f|%d", m.rowId, (int)m.kind, m.status, reactionsOf(m), t.bounds.size.width, m.width];
    NSNumber *known = _heights[hk];
    if (known) return known.floatValue;
    CGFloat h = [self measureRow:m width:t.bounds.size.width];
    _heights[hk] = @(h);
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
            BOOL action = !m.fromMe && [card[1] length] && ([card[2] boolValue] || [[MeshSession shared] isAccepted:_peerHex]);
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
    if ([self quoteFor:m author:&qa text:&qt]) [cell setQuoteAuthor:qa text:qt];
    else [cell setQuoteAuthor:nil text:nil];
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
            BOOL known = [card[2] boolValue], action = !m.fromMe && [card[1] length] && (known || [[MeshSession shared] isAccepted:_peerHex]);
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
        if (m.rowId == _playingRowId) { [_voice stop]; _playingRowId = 0; [self stopPlayTimer]; }
        else {
            [_voice play:[[MeshSession shared] mediaOf:m]];
            _playingRowId = m.rowId;
            _playDur = MAX(1, [MeshPayload parse:m.content].seconds);
            _playStartDate = [NSDate date];
            [self startPlayTimer];
        }
        [t reloadData];
        return;
    }
    if (kind == MeshPayloadImage) {
        UIImage *img = [self imageForMessage:m];   // Bild antippen -> Vollbild
        if (img) [self mesh_present:[[MeshImageViewer alloc] initWithImage:img] animated:YES];
    }
}

@end
