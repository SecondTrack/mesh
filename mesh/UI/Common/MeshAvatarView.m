#import "MeshAvatarView.h"
#import "MeshSession.h"
#import "MeshIdenticon.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshImageCodec.h"
#import "MeshProfile.h"
#import "MeshNotifications.h"
#import "MeshChat.h"

@implementation MeshAvatarView {
    UIImage *_image;     // aufgelöstes Profilbild; einmal je Pubkey/Bild, nicht bei jedem Zeichnen
    BOOL _resolved;
}

- (instancetype)initWithFrame:(CGRect)frame source:(MeshAvatarSource)source {
    if ((self = [super initWithFrame:frame])) {
        _source = source;
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        if (source != MeshAvatarIdenticon)
            [nc addObserver:self selector:@selector(profilesChanged:) name:MeshProfilesChangedNotification object:nil];
        [nc addObserver:self selector:@selector(forget) name:MeshWillLockNotification object:nil];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame { return [self initWithFrame:frame source:MeshAvatarContact]; }

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)setPubkey:(NSString *)pubkey {
    if ([pubkey isEqualToString:_pubkey]) return;   // Zellen setzen beim Scrollen oft denselben
    _pubkey = [pubkey copy];
    [self invalidate];
}
- (void)setPicture:(NSString *)picture {
    if (picture == _picture || [picture isEqualToString:_picture]) return;   // gleiches Bild: nicht neu zeichnen
    _picture = [picture copy];
    [self invalidate];
}

- (void)invalidate {
    _image = nil;
    _resolved = NO;
    [self setNeedsDisplay];
}

- (void)forget { _image = nil; _resolved = NO; }   // beim Sperren: kein entschlüsseltes Bild halten

// Nur neu zeichnen, wenn es um diesen Pubkey geht (bzw. ums eigene Profil); ohne Angabe immer.
- (void)profilesChanged:(NSNotification *)n {
    NSString *pk = n.userInfo[MeshProfilePubkey];
    if (!pk || [pk isEqualToString:_pubkey] || (_source == MeshAvatarSelf && [pk isEqualToString:[[MeshSession shared] myPubkeyHex]]))
        [self invalidate];
}

// Rund zeichnet drawRect selbst (Bild, Platzhalter und Identicon clippen auf den Kreis). Der Radius bleibt
// für Rahmen (Plakette mit Ring), aber ohne clipsToBounds: Ausschneiden hieße am A4 einen eigenen
// Offscreen-Durchgang pro Avatar und Frame.
- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    self.layer.cornerRadius = MIN(frame.size.width, frame.size.height) / 2;
}

static const CGFloat kLargeSide = 640;   // Vollbild-Avatar: Bildschirmbreite in Pixeln

// Aufgelöste Profilbilder je Quelle und Pubkey (NSNull = keins), damit wiederverwendete Zellen
// nicht bei jedem Scrollen Datenbank, Entschlüsseln und Dekodieren anstoßen; dazu die fertig
// runden Bitmaps je Größe, damit drawRect nicht bei jeder Wiederverwendung skaliert und clippt.
// Beim Sperren, Identitätswechsel und bei Speicherwarnung geleert; nach Pixeln begrenzt. Eine
// Profiländerung erhöht nur die Generation dieses Pubkeys (steht im Schlüssel): dessen alte
// Einträge gelten nicht mehr, alle anderen bleiben.
static NSCache *ResolvedCache, *CircleCache;
static NSMutableDictionary *Generations;   // Pubkey -> NSNumber
static NSUInteger SelfGeneration;          // eigenes Profil (Quelle MeshAvatarSelf)

static void SetUpCaches(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ResolvedCache = [[NSCache alloc] init];
        ResolvedCache.countLimit = 64;
        ResolvedCache.totalCostLimit = 8 * 1024 * 1024;
        CircleCache = [[NSCache alloc] init];
        CircleCache.countLimit = 96;
        CircleCache.totalCostLimit = 4 * 1024 * 1024;
        Generations = [NSMutableDictionary dictionary];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[MeshWillLockNotification, MeshIdentityChangedNotification, UIApplicationDidReceiveMemoryWarningNotification])
            [nc addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
                [ResolvedCache removeAllObjects];
                [CircleCache removeAllObjects];
                [Generations removeAllObjects];
            }];
        [nc addObserverForName:MeshProfilesChangedNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
            NSString *pk = n.userInfo[MeshProfilePubkey];
            if (!pk) { [ResolvedCache removeAllObjects]; [CircleCache removeAllObjects]; return; }
            Generations[pk] = @([Generations[pk] unsignedIntegerValue] + 1);
            if ([pk isEqualToString:[[MeshSession shared] myPubkeyHex]]) SelfGeneration++;
        }];
    });
}

static NSString *CacheKey(MeshAvatarSource source, NSString *pubkey) {
    SetUpCaches();
    NSUInteger gen = source == MeshAvatarSelf ? SelfGeneration : [Generations[pubkey ?: @""] unsignedIntegerValue];
    return [NSString stringWithFormat:@"%ld|%@|%lu", (long)source, pubkey ?: @"", (unsigned long)gen];
}

static NSUInteger PixelCost(UIImage *img) {
    return img ? (NSUInteger)(img.size.width * img.size.height * img.scale * img.scale * 4) : 0;
}

+ (UIImage *)pictureForSource:(MeshAvatarSource)source pubkey:(NSString *)pubkey {
    NSString *key = CacheKey(source, pubkey);
    id hit = [ResolvedCache objectForKey:key];
    if (hit) return hit == [NSNull null] ? nil : hit;
    UIImage *img = [MeshImageCodec imageFromPicture:[self storedPictureForSource:source pubkey:pubkey]];
    [ResolvedCache setObject:(img ?: (id)[NSNull null]) forKey:key cost:PixelCost(img)];
    return img;
}

// Gespeicherte Form (Base64/data:) des Profilbilds, nil = keins oder (noch) nicht zu zeigen.
+ (NSString *)storedPictureForSource:(MeshAvatarSource)source pubkey:(NSString *)pubkey {
    switch (source) {
        case MeshAvatarContact:
        case MeshAvatarMember:    return [[MeshSession shared] pictureFor:pubkey];   // auch Gruppen ("g:<gid>"); nur angenommene
        case MeshAvatarSelf:      return [[MeshSession shared] profile].picture;
        case MeshAvatarIdenticon:
        case MeshAvatarPreview:   return nil;
    }
    return nil;
}

+ (UIImage *)largeImageForSource:(MeshAvatarSource)source pubkey:(NSString *)pubkey {
    // Der Cache hält nur die Avatar-Fassung; fürs Vollbild einmal größer dekodieren (höchstens 640 px).
    UIImage *img = [self pictureForSource:source pubkey:pubkey];
    if (img) img = [MeshImageCodec imageFromPicture:[self storedPictureForSource:source pubkey:pubkey] longestSide:kLargeSide] ?: img;
    if (img) return img;
    CGRect r = CGRectMake(0, 0, 512, 512);
    UIGraphicsBeginImageContextWithOptions(r.size, YES, 1);
    [[MeshTheme surfaceHi] setFill];
    UIRectFill(r);
    if ([self drawChatKey:pubkey inRect:r context:UIGraphicsGetCurrentContext()]) {}
    else if (source == MeshAvatarIdenticon || source == MeshAvatarMember) [MeshIdenticon drawSeed:pubkey inRect:r context:UIGraphicsGetCurrentContext()];
    else [self drawPlaceholderInRect:r context:UIGraphicsGetCurrentContext()];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    // Team-Chat: immer das Logo. Gruppe: ihr Bild (B7), sonst das Identicon mit Gruppen-Symbol.
    BOOL group = MeshGroupOfChat(_pubkey) != nil;
    if (!group && [MeshAvatarView drawChatKey:_pubkey inRect:b context:ctx]) return;
    if (!_resolved && [MeshSession shared].unlocked) {
        _image = _picture.length ? [MeshImageCodec imageFromPicture:_picture]
                                 : [MeshAvatarView pictureForSource:_source pubkey:_pubkey];
        _resolved = YES;
    }
    UIImage *img = _image;
    if (!img && group) { [MeshAvatarView drawChatKey:_pubkey inRect:b context:ctx]; return; }
    if (!img && _source == MeshAvatarIdenticon) { [MeshIdenticon drawSeed:_pubkey inRect:b context:ctx]; return; }
    if (!img && _source != MeshAvatarMember) { [MeshAvatarView drawPlaceholderInRect:b context:ctx]; return; }

    // Fertiger Kreis aus dem Cache (nicht für eine Vorschau mit gesetztem picture). Mitglied ohne Bild:
    // das Identicon, ebenfalls fertig gecacht (Absenderbilder im Gruppenchat zeichnen sich beim Scrollen oft).
    NSString *key = _picture.length ? nil : [NSString stringWithFormat:@"%@|%@|%.0f|%.0f", CacheKey(_source, _pubkey), img ? @"p" : @"i",
                                             b.size.width, b.size.height];
    UIImage *circle = key ? [CircleCache objectForKey:key] : nil;
    if (!circle) {
        UIGraphicsBeginImageContextWithOptions(b.size, NO, 0);   // gleiche Auflösung wie die Ansicht
        CGRect r = CGRectMake(0, 0, b.size.width, b.size.height);
        if (img) [MeshAvatarView drawCircle:img inRect:r context:UIGraphicsGetCurrentContext()];
        else [MeshIdenticon drawSeed:_pubkey inRect:r context:UIGraphicsGetCurrentContext()];
        circle = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        if (key && circle) [CircleCache setObject:circle forKey:key cost:PixelCost(circle)];
    }
    [circle drawInRect:b];
}

// Gruppe ohne Bild: Identicon aus der gid mit Gruppen-Symbol darüber; Team-Chat: das Mesh-Logo. NO für Kontakte.
+ (BOOL)drawChatKey:(NSString *)key inRect:(CGRect)b context:(CGContextRef)ctx {
    NSString *gid = MeshGroupOfChat(key);
    if (gid) {
        [MeshIdenticon drawSeed:gid inRect:b context:ctx];
        CGFloat d = b.size.width * 0.56f;
        CGRect c = CGRectMake(b.origin.x + (b.size.width - d) / 2, b.origin.y + (b.size.height - d) / 2, d, d);
        [[[MeshTheme bg] colorWithAlphaComponent:0.72f] setFill];
        CGContextFillEllipseInRect(ctx, c);
        [[MeshGlyphs icon:@"group" color:[MeshTheme ink] size:floorf(d * 0.62f)] drawInRect:CGRectInset(c, d * 0.19f, d * 0.19f)];
        return YES;
    }
    if (MeshIsTeamChat(key)) {
        CGContextSaveGState(ctx);
        CGContextAddEllipseInRect(ctx, b);
        CGContextClip(ctx);
        [[MeshTheme surfaceHi] setFill];
        CGContextFillRect(ctx, b);
        CGFloat d = b.size.width * 0.66f;
        [[MeshGlyphs logo:d] drawInRect:CGRectMake(b.origin.x + (b.size.width - d) / 2, b.origin.y + (b.size.height - d) / 2, d, d)];
        CGContextRestoreGState(ctx);
        return YES;
    }
    return NO;
}

// Aspect-fill in den Kreis.
+ (void)drawCircle:(UIImage *)img inRect:(CGRect)b context:(CGContextRef)ctx {
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, b);
    CGContextClip(ctx);
    CGFloat s = MAX(b.size.width / img.size.width, b.size.height / img.size.height);
    CGSize ds = CGSizeMake(img.size.width * s, img.size.height * s);
    [img drawInRect:CGRectMake(b.origin.x + (b.size.width - ds.width) / 2, b.origin.y + (b.size.height - ds.height) / 2, ds.width, ds.height)];
    CGContextRestoreGState(ctx);
}

// Ohne (sichtbares) Bild: neutrale Silhouette aus Kopf und Schultern. Gilt auch für Anfragen,
// deren Bild erst nach dem Annehmen gezeigt wird.
+ (void)drawPlaceholderInRect:(CGRect)b context:(CGContextRef)ctx {
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, b);
    CGContextClip(ctx);
    [[MeshTheme surfaceHi] setFill];
    CGContextFillRect(ctx, b);
    CGFloat w = b.size.width, h = b.size.height;
    [[MeshTheme faint] setFill];
    CGFloat head = w * 0.36f;
    CGContextFillEllipseInRect(ctx, CGRectMake(b.origin.x + (w - head) / 2, b.origin.y + h * 0.2f, head, head));
    CGFloat body = w * 0.72f;
    CGContextFillEllipseInRect(ctx, CGRectMake(b.origin.x + (w - body) / 2, b.origin.y + h * 0.62f, body, body));
    CGContextRestoreGState(ctx);
}

+ (UIButton *)badgeWithGlyph:(NSString *)glyph diameter:(CGFloat)d forAvatarFrame:(CGRect)avatar {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(CGRectGetMaxX(avatar) - d + 2, CGRectGetMaxY(avatar) - d + 2, d, d);
    b.backgroundColor = [MeshTheme accent];
    b.layer.cornerRadius = d / 2;
    b.layer.borderWidth = 3;
    b.layer.borderColor = [MeshTheme bg].CGColor;
    b.adjustsImageWhenHighlighted = NO;
    b.userInteractionEnabled = NO;
    [b setImage:[MeshGlyphs icon:glyph color:[MeshTheme bg] size:floorf(d / 2)] forState:UIControlStateNormal];
    return b;
}

@end
