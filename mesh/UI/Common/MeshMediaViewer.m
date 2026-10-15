#import "MeshMediaViewer.h"
#import "MeshCompat.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshSession.h"
#import "MeshMessage.h"
#import "MeshImageCodec.h"
#import "MeshVideoCodec.h"
#import "MeshFileViewer.h"
#import "MeshNotifications.h"
#import "MeshFormat.h"
#import "MeshPopup.h"
#import "MeshL10n.h"

static const CGFloat kBar = 50;
static const CGFloat kMaxPixels = 1280;   // gecachte Bilder höchstens so groß (Bildschirm 640x960, 4x Zoom bleibt scharf genug)

static NSUInteger pixelCost(UIImage *img) { return (NSUInteger)(img.size.width * img.size.height * img.scale * img.scale * 4); }

// Eine Warteschlange, niedrige Priorität: der A4 hat einen Kern, Wischen und Zoomen gehen vor.
static dispatch_queue_t ViewerQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("mesh.viewer.images", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(q, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    });
    return q;
}
enum { kTagImage = 1, kTagPlay = 2 };

@interface MeshMediaViewer () <UIScrollViewDelegate>
@end

@implementation MeshMediaViewer {
    NSMutableArray *_items;
    NSUInteger _index;
    NSString *_peer;
    UIScrollView *_pager;
    NSMutableDictionary *_pages;   // @(index) -> Zoom-Seite; nur die gezeigte und ihre Nachbarn
    NSCache *_images;              // rowId -> UIImage bzw. Video-Vorschau (NSNull: nicht darstellbar), nach Pixeln begrenzt
    NSMutableSet *_pending;
    NSMutableSet *_reduced;        // rowIds, deren gecachtes Bild verkleinert ist (Speichern dekodiert neu)
    UIView *_top, *_bottom;
    UILabel *_who, *_count;
    UIButton *_save;
}

- (instancetype)initWithItems:(NSArray *)items index:(NSUInteger)index peer:(NSString *)peerHex {
    if ((self = [super init])) {
        _items = [items mutableCopy];
        _index = MIN(index, items.count ? items.count - 1 : 0);
        _peer = [peerHex copy];
        _pages = [NSMutableDictionary dictionary];
        _images = [[NSCache alloc] init];
        _images.countLimit = 4;
        _images.totalCostLimit = 12 * 1024 * 1024;
        _pending = [NSMutableSet set];
        _reduced = [NSMutableSet set];
    }
    return self;
}

- (void)loadView {
    [self mesh_useFullScreenLayout];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [UIColor blackColor];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;

    _pager = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _pager.pagingEnabled = YES;
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.delegate = self;
    [self.view addSubview:_pager];

    // Oben: Schließen, Absender und Datum, Position
    _top = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, kBar)];
    _top.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6f];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(2, 3, 44, 44);
    [close setImage:[MeshGlyphs icon:@"close" color:[MeshTheme ink] size:20] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_top addSubview:close];
    _who = [[UILabel alloc] initWithFrame:CGRectMake(50, 6, W - 50 - 70, 38)];
    _who.numberOfLines = 2;
    _who.font = [MeshTheme previewFont];
    _who.textColor = [MeshTheme ink];
    _who.backgroundColor = [UIColor clearColor];
    [_top addSubview:_who];
    _count = [[UILabel alloc] initWithFrame:CGRectMake(W - 70, 6, 58, 38)];
    _count.textAlignment = NSTextAlignmentRight;
    _count.font = [MeshTheme timeFont];
    _count.textColor = [MeshTheme muted];
    _count.backgroundColor = [UIColor clearColor];
    [_top addSubview:_count];
    [self.view addSubview:_top];

    // Unten: Speichern (nur Bilder), Löschen
    _bottom = [[UIView alloc] initWithFrame:CGRectMake(0, H - kBar, W, kBar)];
    _bottom.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6f];
    _save = [self barButton:@"save" title:L(@"Save") frame:CGRectMake(12, 3, W / 2 - 24, 44) action:@selector(saveCurrent)];
    [_bottom addSubview:_save];
    [_bottom addSubview:[self barButton:@"trash" title:L(@"Delete") frame:CGRectMake(W / 2 + 12, 3, W / 2 - 24, 44) action:@selector(deleteCurrent)]];
    [self.view addSubview:_bottom];

    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    dbl.numberOfTapsRequired = 2;
    [_pager addGestureRecognizer:dbl];
    UITapGestureRecognizer *one = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleBars)];
    [one requireGestureRecognizerToFail:dbl];
    [_pager addGestureRecognizer:one];

    [self rebuild];
}

- (UIButton *)barButton:(NSString *)glyph title:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    [b setImage:[MeshGlyphs icon:glyph color:[MeshTheme ink] size:20] forState:UIControlStateNormal];
    [b setTitle:[@"  " stringByAppendingString:title] forState:UIControlStateNormal];
    [b setTitleColor:[MeshTheme ink] forState:UIControlStateNormal];
    b.titleLabel.font = [MeshTheme previewFont];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(close) name:MeshWillLockNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _pager.delegate = nil;
    for (UIScrollView *p in _pages.allValues) p.delegate = nil;
}

- (void)close { [self mesh_dismissAnimated:YES]; }

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_images removeAllObjects];
}

#pragma mark - Seiten

// Nach dem Öffnen oder Löschen: alle Seiten neu, an der aktuellen Stelle.
- (void)rebuild {
    for (UIScrollView *p in _pages.allValues) { p.delegate = nil; [p removeFromSuperview]; }
    [_pages removeAllObjects];
    CGFloat W = _pager.bounds.size.width;
    _pager.contentSize = CGSizeMake(W * _items.count, _pager.bounds.size.height);
    _pager.contentOffset = CGPointMake(W * _index, 0);
    [self showPagesAround];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)sv {
    if (sv != _pager) return;
    NSUInteger i = (NSUInteger)lroundf(sv.contentOffset.x / MAX(1, sv.bounds.size.width));
    if (i >= _items.count || i == _index) return;
    // Zoom der verlassenen Seite zurücksetzen
    [(UIScrollView *)_pages[@(_index)] setZoomScale:1 animated:NO];
    _index = i;
    [self showPagesAround];
}

- (void)showPagesAround {
    NSInteger lo = (NSInteger)_index - 1, hi = (NSInteger)_index + 1;
    for (NSNumber *k in [_pages allKeys])
        if (k.integerValue < lo || k.integerValue > hi) {
            UIScrollView *p = _pages[k];
            p.delegate = nil;
            [p removeFromSuperview];
            [_pages removeObjectForKey:k];
        }
    for (NSInteger i = MAX(0, lo); i <= hi && i < (NSInteger)_items.count; i++)
        if (!_pages[@(i)]) [self addPage:(NSUInteger)i];
    [self updateBars];
}

- (void)addPage:(NSUInteger)i {
    CGSize s = _pager.bounds.size;
    UIScrollView *page = [[UIScrollView alloc] initWithFrame:CGRectMake(s.width * i, 0, s.width, s.height)];
    page.delegate = self;
    page.minimumZoomScale = 1;
    page.maximumZoomScale = 4;
    page.showsHorizontalScrollIndicator = page.showsVerticalScrollIndicator = NO;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:page.bounds];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.tag = kTagImage;
    [page addSubview:iv];
    MeshMessage *m = _items[i];
    if (m.kind == MeshPayloadFile) {
        page.maximumZoomScale = 1;
        // Vorschaubild nur von eigenen Videos (fremde MP4 liest iOS erst beim Abspielen)
        if (m.fromMe) {
            iv.image = [self imageFor:m];   // sonst im Hintergrund, kommt nach
            iv.alpha = 0.6f;
        }
        UIButton *play = [UIButton buttonWithType:UIButtonTypeCustom];
        play.frame = CGRectMake((s.width - 76) / 2, (s.height - 76) / 2, 76, 76);
        play.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5f];
        play.layer.cornerRadius = 38;
        play.layer.borderWidth = 1.5f;
        play.layer.borderColor = [MeshTheme accent].CGColor;
        [play setImage:[MeshGlyphs icon:@"play" color:[MeshTheme accent] size:30] forState:UIControlStateNormal];
        play.tag = kTagPlay;
        [play addTarget:self action:@selector(playCurrent) forControlEvents:UIControlEventTouchUpInside];
        [page addSubview:play];
    } else {
        iv.image = [self imageFor:m];
    }
    [_pager addSubview:page];
    _pages[@(i)] = page;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv {
    return sv == _pager ? nil : [sv viewWithTag:kTagImage];
}

// Aus dem Zwischenspeicher, sonst der Reihe nach im Hintergrund: Bilder dekodieren, eigene Videos als
// Vorschaubild. Ist die Seite an der Reihe, aber schon weggewischt, entfällt die Arbeit.
- (UIImage *)imageFor:(MeshMessage *)m {
    NSNumber *k = @(m.rowId);
    id hit = [_images objectForKey:k];
    if (hit) return hit == [NSNull null] ? nil : hit;
    if ([_pending containsObject:k]) return nil;
    [_pending addObject:k];
    MESH_WEAK MeshMediaViewer *weakSelf = self;
    dispatch_async(ViewerQueue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf startLoading:k]; });
    });
    return nil;
}

// Seite (gezeigte oder Nachbar) mit dieser rowId, sonst nil.
- (MeshMessage *)shownItem:(NSNumber *)rowId {
    for (NSNumber *i in _pages) {
        MeshMessage *m = i.unsignedIntegerValue < _items.count ? _items[i.unsignedIntegerValue] : nil;
        if (m.rowId == rowId.longLongValue) return m;
    }
    return nil;
}

// Main-Thread: noch gebraucht? Dann entschlüsseln (Store nur hier) und im Hintergrund dekodieren.
- (void)startLoading:(NSNumber *)k {
    MeshMessage *m = [self shownItem:k];
    BOOL video = m.kind == MeshPayloadFile;
    if (!m || (video && !m.fromMe)) { [_pending removeObject:k]; return; }   // fremde MP4 liest iOS erst beim Abspielen
    NSData *data = [[MeshSession shared] mediaOf:m];
    if (!data.length) { [_pending removeObject:k]; return; }
    MESH_WEAK MeshMediaViewer *weakSelf = self;
    dispatch_async(ViewerQueue(), ^{
        UIImage *img = video ? [MeshVideoCodec thumbnailOfMP4:data maxSide:640]
                             : [MeshImageCodec imageFromData:data formats:MeshImageJPEG];
        UIImage *small = video ? img : [MeshImageCodec shrink:img longestSide:kMaxPixels];
        BOOL reduced = small != img;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf image:small reduced:reduced readyFor:k]; });
    });
}

- (void)image:(UIImage *)img reduced:(BOOL)reduced readyFor:(NSNumber *)rowId {
    [_pending removeObject:rowId];
    if (reduced) [_reduced addObject:rowId]; else [_reduced removeObject:rowId];
    [_images setObject:img ?: (id)[NSNull null] forKey:rowId cost:img ? pixelCost(img) : 0];
    [_pages enumerateKeysAndObjectsUsingBlock:^(NSNumber *i, UIScrollView *page, BOOL *stop) {
        if ([_items[i.unsignedIntegerValue] rowId] == rowId.longLongValue) [(UIImageView *)[page viewWithTag:kTagImage] setImage:img];
    }];
}

#pragma mark - Leisten

- (void)updateBars {
    if (!_items.count) return;
    MeshMessage *m = _items[_index];
    NSString *name = m.fromMe ? L(@"You") : [[MeshSession shared] displayNameFor:_peer];
    _who.text = [NSString stringWithFormat:@"%@\n%@", name, [MeshFormat shortTime:m.ts]];
    _count.text = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)_index + 1, (unsigned long)_items.count];
    _save.hidden = m.kind != MeshPayloadImage;
}

- (void)toggleBars {
    BOOL hide = _top.alpha > 0.5f;
    [UIView animateWithDuration:0.2 animations:^{ _top.alpha = _bottom.alpha = hide ? 0 : 1; }];
}

- (void)doubleTap:(UITapGestureRecognizer *)g {
    UIScrollView *page = _pages[@(_index)];
    if (!page || page.maximumZoomScale <= 1) return;
    if (page.zoomScale > 1) { [page setZoomScale:1 animated:YES]; return; }
    CGPoint p = [g locationInView:[page viewWithTag:kTagImage]];
    CGSize s = page.bounds.size;
    [page zoomToRect:CGRectMake(p.x - s.width / 5, p.y - s.height / 5, s.width / 2.5f, s.height / 2.5f) animated:YES];
}

#pragma mark - Aktionen

- (void)playCurrent {
    MeshMessage *m = _items[_index];
    MeshPayload *p = [[MeshSession shared] payloadOf:m];
    if (p.data) [MeshFileViewer open:p.data name:p.fileName mime:p.fileMime from:self];
}

// In die Fotos: es geht das dekodierte Bild (neu kodiert, ohne Metadaten), nie die empfangene Datei.
// Ist das gezeigte Bild verkleinert (oder schon aus dem Cache verdrängt), in voller Größe neu dekodieren.
- (void)saveCurrent {
    MeshMessage *m = _items[_index];
    if (m.kind != MeshPayloadImage) return;
    NSNumber *k = @(m.rowId);
    id img = [_images objectForKey:k];
    if ([img isKindOfClass:[UIImage class]] && ![_reduced containsObject:k]) { [self saveToPhotos:img]; return; }
    UIImageView *shown = (UIImageView *)[_pages[@(_index)] viewWithTag:kTagImage];
    if (img == [NSNull null] || !shown.image) return;   // nicht darstellbar oder noch nicht da
    NSData *jpeg = [[MeshSession shared] mediaOf:m];   // Store nur auf dem Main-Thread
    if (!jpeg.length) return;
    MESH_WEAK MeshMediaViewer *weakSelf = self;
    dispatch_async(ViewerQueue(), ^{
        UIImage *full = [MeshImageCodec imageFromData:jpeg formats:MeshImageJPEG];
        if (full) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf saveToPhotos:full]; });
    });
}

- (void)saveToPhotos:(UIImage *)img {
    UIImageWriteToSavedPhotosAlbum(img, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)info {
    [MeshPopup info:error ? L(@"Could not save. Allow access to Photos in Settings → Privacy.") : L(@"Saved to Photos")];
}

- (void)deleteCurrent {
    MeshMessage *m = _items[_index];
    NSString *peer = _peer;
    NSArray *opts = m.fromMe ? @[L(@"Delete for me"), L(@"Delete for everyone")] : @[L(@"Delete for me")];
    MESH_WEAK MeshMediaViewer *weakSelf = self;
    [MeshPopup sheet:L(@"Delete message?") options:opts destructiveIndex:0 handler:^(NSInteger idx) {
        if (idx < 0) return;
        if (idx == 1) { if (![[MeshSession shared] deleteForEveryone:m in:peer]) { [MeshPopup info:L(@"Failed")]; return; } }
        else [[MeshSession shared] deleteMessage:m];
        [weakSelf removeItem:m];
    }];
}

- (void)removeItem:(MeshMessage *)m {
    [_items removeObject:m];
    if (!_items.count) { [self close]; return; }
    if (_index >= _items.count) _index = _items.count - 1;
    [self rebuild];
}

@end
