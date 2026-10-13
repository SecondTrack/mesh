#import "MeshAvatarView.h"
#import "MeshSession.h"
#import "MeshIdenticon.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshImageCodec.h"
#import "MeshProfile.h"

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
            [nc addObserver:self selector:@selector(invalidate) name:MeshProfilesChangedNotification object:nil];
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

// Rund zeichnet drawRect selbst (Bild, Platzhalter und Identicon clippen auf den Kreis). Der Radius bleibt
// für Rahmen (Plakette mit Ring), aber ohne clipsToBounds: Ausschneiden hieße am A4 einen eigenen
// Offscreen-Durchgang pro Avatar und Frame.
- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    self.layer.cornerRadius = MIN(frame.size.width, frame.size.height) / 2;
}

// Aufgelöste Profilbilder je Quelle und Pubkey (NSNull = keins), damit wiederverwendete Zellen
// nicht bei jedem Scrollen Datenbank, Entschlüsseln und Dekodieren anstoßen. Beim Sperren und bei
// Profiländerungen geleert.
static NSCache *ResolvedCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 64;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[MeshWillLockNotification, MeshProfilesChangedNotification])
            [nc addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) { [cache removeAllObjects]; }];
    });
    return cache;
}

+ (UIImage *)pictureForSource:(MeshAvatarSource)source pubkey:(NSString *)pubkey {
    NSString *key = [NSString stringWithFormat:@"%ld|%@", (long)source, pubkey ?: @""];
    id hit = [ResolvedCache() objectForKey:key];
    if (hit) return hit == [NSNull null] ? nil : hit;
    UIImage *img = [self resolvePictureForSource:source pubkey:pubkey];
    [ResolvedCache() setObject:(img ?: (id)[NSNull null]) forKey:key];
    return img;
}

+ (UIImage *)resolvePictureForSource:(MeshAvatarSource)source pubkey:(NSString *)pubkey {
    switch (source) {
        case MeshAvatarContact:   return [MeshImageCodec imageFromPicture:[[MeshSession shared] pictureFor:pubkey]];
        case MeshAvatarSelf:      return [MeshImageCodec imageFromPicture:[[MeshSession shared] profile].picture];
        case MeshAvatarIdenticon:
        case MeshAvatarPreview:   return nil;
    }
    return nil;
}

+ (UIImage *)largeImageForSource:(MeshAvatarSource)source pubkey:(NSString *)pubkey {
    UIImage *img = [self pictureForSource:source pubkey:pubkey];
    if (img) return img;
    CGRect r = CGRectMake(0, 0, 512, 512);
    UIGraphicsBeginImageContextWithOptions(r.size, YES, 1);
    [[MeshTheme surfaceHi] setFill];
    UIRectFill(r);
    if (source == MeshAvatarIdenticon) [MeshIdenticon drawSeed:pubkey inRect:r context:UIGraphicsGetCurrentContext()];
    else [self drawPlaceholderInRect:r context:UIGraphicsGetCurrentContext()];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!_resolved && [MeshSession shared].unlocked) {
        _image = _picture.length ? [MeshImageCodec imageFromPicture:_picture]
                                 : [MeshAvatarView pictureForSource:_source pubkey:_pubkey];
        _resolved = YES;
    }
    UIImage *img = _image;
    if (!img && _source == MeshAvatarIdenticon) { [MeshIdenticon drawSeed:_pubkey inRect:b context:ctx]; return; }
    if (!img) { [MeshAvatarView drawPlaceholderInRect:b context:ctx]; return; }

    // Aspect-fill in den Kreis.
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, b);
    CGContextClip(ctx);
    CGFloat s = MAX(b.size.width / img.size.width, b.size.height / img.size.height);
    CGSize ds = CGSizeMake(img.size.width * s, img.size.height * s);
    [img drawInRect:CGRectMake((b.size.width - ds.width) / 2, (b.size.height - ds.height) / 2, ds.width, ds.height)];
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
