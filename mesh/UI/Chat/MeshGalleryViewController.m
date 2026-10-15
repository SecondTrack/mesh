#import "MeshGalleryViewController.h"
#import "MeshScreen.h"
#import "MeshCompat.h"
#import "MeshPageHeader.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshControls.h"
#import "MeshSession.h"
#import "MeshMessage.h"
#import "MeshImageCodec.h"
#import "MeshVideoCodec.h"
#import "MeshMediaViewer.h"
#import "MeshNotifications.h"
#import "MeshL10n.h"

static const NSUInteger kPerRow = 4;
static const CGFloat kGap = 3, kSide = 8, kThumbPixels = 160, kTileRadius = 6;

@interface MeshGalleryViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MeshGalleryViewController {
    NSString *_peer;
    NSArray *_items;               // MeshMessage, neueste zuerst
    NSCache *_thumbs;              // rowId -> UIImage (NSNull: keins)
    NSMutableSet *_pending;        // vorgemerkt oder in Arbeit
    NSMutableArray *_wanted;       // vorgemerkte MeshMessage, noch nicht entschlüsselt
    BOOL _draining, _busy;         // Abarbeiten angestoßen / eine Vorschau entsteht gerade
    UITableView *_table;
    UILabel *_empty;
    MeshPageHeader *_header;
    BOOL _stale;
}

// Bilder und Videos; Dateien unbekannter Art einmal prüfen (danach gemerkt).
+ (NSArray *)itemsFor:(NSString *)peer {
    MeshSession *s = [MeshSession shared];
    BOOL accepted = [s isAccepted:peer];
    NSMutableArray *out = [NSMutableArray array];
    for (MeshMessage *m in [s mediaWith:peer]) {
        if (!m.fromMe && !accepted) continue;
        if (m.kind == MeshPayloadFile && ![s isVideo:m]) continue;
        [out addObject:m];
    }
    return out;
}

// Nur zählen (SELECT COUNT), keine Zeilen laden; Dateien unbekannter Art werden dabei einmal eingeordnet.
+ (NSUInteger)countFor:(NSString *)peerHex {
    MeshSession *s = [MeshSession shared];
    return [s mediaCountWith:peerHex onlyMine:![s isAccepted:peerHex]];
}

- (instancetype)initWithPeer:(NSString *)peerHex {
    if ((self = [super init])) {
        _peer = [peerHex copy];
        _thumbs = [[NSCache alloc] init];
        _thumbs.countLimit = 120;   // 160 px Kacheln: rund 100 KB je Stück
        _pending = [NSMutableSet set];
        _wanted = [NSMutableArray array];
    }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    _header = [[MeshPageHeader alloc] initWithWidth:W title:L(@"Media") target:self back:@selector(mesh_goBack)];
    [self.view addSubview:_header];
    CGFloat top = [MeshPageHeader height];
    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, top, W, H - top) style:UITableViewStylePlain];
    _table.backgroundColor = [MeshTheme bg];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self; _table.delegate = self;
    _table.rowHeight = [self tileSide] + kGap;
    _table.contentInset = UIEdgeInsetsMake(kSide, 0, kSide, 0);
    [self.view addSubview:_table];
    _empty = [MeshControls labelWithFrame:CGRectMake(30, top + 80, W - 60, 60) font:[MeshTheme previewFont] color:[MeshTheme muted]];
    _empty.text = L(@"No photos or videos in this chat yet");
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.numberOfLines = 0;
    [self.view addSubview:_empty];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changed) name:MeshMessagesChangedNotification object:nil];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_stale) [self reload];   // z.B. im Vollbild gelöscht
}

- (void)changed {
    if (self.isViewLoaded && self.view.window) [self reload];
    else _stale = YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil; _table.dataSource = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_thumbs removeAllObjects];
}

- (void)reload {
    _stale = NO;
    _items = [MeshGalleryViewController itemsFor:_peer];
    _header.titleLabel.text = _items.count ? [NSString stringWithFormat:@"%@ · %lu", L(@"Media"), (unsigned long)_items.count] : L(@"Media");
    _empty.hidden = _items.count > 0;
    [_table reloadData];
}

- (CGFloat)tileSide {
    CGFloat W = self.view.bounds.size.width;
    return floorf((W - 2 * kSide - (kPerRow - 1) * kGap) / kPerRow);
}

#pragma mark - Kacheln

// Vorschau: Bild dekodieren und klein rechnen, im Hintergrund, eins nach dem anderen.
// Videos nur, wenn sie von mir sind (fremde MP4 liest iOS erst beim Abspielen).
// Hier wird nur vorgemerkt: Entschlüsseln (Main-Thread) und Dekodieren erst, wenn die Kachel
// beim Abarbeiten noch sichtbar ist – schnelles Scrollen stapelt so keine Arbeit für Weggescrolltes.
- (UIImage *)thumbFor:(MeshMessage *)m {
    NSNumber *k = @(m.rowId);
    id hit = [_thumbs objectForKey:k];
    if (hit) return hit == [NSNull null] ? nil : hit;
    if ([_pending containsObject:k]) return nil;
    if (m.kind == MeshPayloadFile && !m.fromMe) { [_thumbs setObject:[NSNull null] forKey:k]; return nil; }
    [_pending addObject:k];
    [_wanted addObject:m];
    [self drainSoon];
    return nil;
}

// Je Runloop-Durchlauf höchstens ein Schritt, und nie mehr als eine Vorschau gleichzeitig in Arbeit.
- (void)drainSoon {
    if (_draining || _busy || !_wanted.count) return;
    _draining = YES;
    MESH_WEAK MeshGalleryViewController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf drainOne]; });
}

- (void)drainOne {
    _draining = NO;
    if (_busy) return;
    // Zuletzt angefragte zuerst: das sind die, auf die gerade gescrollt wurde.
    MeshMessage *m = nil;
    while (_wanted.count) {
        MeshMessage *x = [_wanted lastObject];
        [_wanted removeLastObject];
        if ([self isVisible:x.rowId]) { m = x; break; }
        [_pending removeObject:@(x.rowId)];   // weggescrollt: beim nächsten Anzeigen neu anfragen
    }
    if (!m) return;
    NSNumber *k = @(m.rowId);
    BOOL video = m.kind == MeshPayloadFile;
    if (video && !m.fromMe) { [_pending removeObject:k]; [self drainSoon]; return; }
    NSData *data = [[MeshSession shared] mediaOf:m];   // Store nur auf dem Main-Thread
    if (!data.length) { [_pending removeObject:k]; [self drainSoon]; return; }
    _busy = YES;
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("mesh.gallery.thumbs", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(q, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    });
    MESH_WEAK MeshGalleryViewController *weakSelf = self;
    CGFloat radius = kTileRadius * kThumbPixels / [self tileSide];   // in Pixeln des Vorschaubilds
    UIColor *corner = [MeshTheme bg];                                // Zellen-Hintergrund hinter den Ecken
    dispatch_async(q, ^{
        UIImage *big = video ? [MeshVideoCodec thumbnailOfMP4:data maxSide:kThumbPixels * 2]
                             : [MeshImageCodec imageFromData:data formats:MeshImageJPEG];
        UIImage *small = big ? squareThumb(big, kThumbPixels, radius, corner) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf thumb:small readyFor:k]; });
    });
}

- (BOOL)isVisible:(long long)rowId {
    for (NSIndexPath *ip in [_table indexPathsForVisibleRows])
        for (NSUInteger c = 0; c < kPerRow; c++) {
            NSUInteger i = ip.row * kPerRow + c;
            if (i < _items.count && [_items[i] rowId] == rowId) return YES;
        }
    return NO;
}

// Mittiges Quadrat, auf side Pixel verkleinert. Die Ecken (Radius der Kachel, umgerechnet auf side)
// sind schon rund auf die Hintergrundfarbe gemalt: die Kachel braucht kein clipsToBounds.
static UIImage *squareThumb(UIImage *img, CGFloat side, CGFloat radius, UIColor *corner) {
    CGSize s = img.size;
    CGFloat scale = side / MAX(1, MIN(s.width, s.height));
    CGSize d = CGSizeMake(s.width * scale, s.height * scale);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 1);
    [corner setFill];
    UIRectFill(CGRectMake(0, 0, side, side));
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:radius] addClip];
    [img drawInRect:CGRectMake((side - d.width) / 2, (side - d.height) / 2, d.width, d.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

- (void)thumb:(UIImage *)img readyFor:(NSNumber *)rowId {
    _busy = NO;
    [self drainSoon];
    [_pending removeObject:rowId];
    [_thumbs setObject:img ?: (id)[NSNull null] forKey:rowId];
    for (NSIndexPath *ip in [_table indexPathsForVisibleRows])
        for (NSUInteger c = 0; c < kPerRow; c++) {
            NSUInteger i = ip.row * kPerRow + c;
            if (i < _items.count && [_items[i] rowId] == rowId.longLongValue) {
                [_table reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
                return;
            }
        }
}

#pragma mark - Tabelle (eine Zeile = vier Kacheln)

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)((_items.count + kPerRow - 1) / kPerRow);
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"row"];
    CGFloat side = [self tileSide];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
        cell.backgroundColor = [MeshTheme bg];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        for (NSUInteger c = 0; c < kPerRow; c++) {
            UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
            tile.frame = CGRectMake(kSide + c * (side + kGap), 0, side, side);
            tile.backgroundColor = [MeshTheme surfaceHi];
            tile.layer.cornerRadius = kTileRadius;   // rundet nur die Fläche; Vorschaubilder kommen schon rund
            tile.imageView.contentMode = UIViewContentModeScaleAspectFill;
            [tile addTarget:self action:@selector(openTile:) forControlEvents:UIControlEventTouchUpInside];
            tile.tag = 100 + c;
            UIImageView *badge = [[UIImageView alloc] initWithFrame:CGRectMake(side - 26, side - 26, 22, 22)];
            badge.tag = 200;
            badge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55f];
            badge.layer.cornerRadius = 11;
            badge.contentMode = UIViewContentModeCenter;
            badge.image = [MeshGlyphs icon:@"play" color:[MeshTheme ink] size:12];
            [tile addSubview:badge];
            [cell.contentView addSubview:tile];
        }
    }
    for (NSUInteger c = 0; c < kPerRow; c++) {
        UIButton *tile = (UIButton *)[cell.contentView viewWithTag:100 + c];
        NSUInteger i = ip.row * kPerRow + c;
        tile.hidden = i >= _items.count;
        if (tile.hidden) continue;
        MeshMessage *m = _items[i];
        BOOL video = m.kind == MeshPayloadFile;
        UIImage *thumb = [self thumbFor:m];
        // Vorschau als Hintergrundbild: füllt die Kachel genau (quadratisch, Ecken schon rund), ohne Ausschneiden
        [tile setBackgroundImage:thumb forState:UIControlStateNormal];
        [tile setImage:(!thumb && video) ? [MeshGlyphs icon:@"play" color:[MeshTheme accent] size:26] : nil forState:UIControlStateNormal];
        [tile viewWithTag:200].hidden = !video || !thumb;
    }
    return cell;
}

- (void)openTile:(UIButton *)tile {
    NSIndexPath *ip = [_table indexPathForRowAtPoint:[tile convertPoint:CGPointMake(tile.bounds.size.width / 2, tile.bounds.size.height / 2) toView:_table]];
    NSUInteger i = ip.row * kPerRow + (NSUInteger)(tile.tag - 100);
    if (!ip || i >= _items.count) return;
    [self mesh_present:[[MeshMediaViewer alloc] initWithItems:_items index:i peer:_peer] animated:YES];
}

@end
