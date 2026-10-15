#import "MeshEmoji.h"
#import <CoreText/CoreText.h>
#import "MeshEmojiText.h"
#import <objc/runtime.h>

@implementation MeshEmoji

+ (void)setPackDirectory:(NSString *)dir { [MeshEmojiText setPackDirectory:dir]; }

static NSData *packData(void) {
    static NSData *data;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ data = [NSData dataWithContentsOfFile:[MeshEmojiText packPath] options:NSDataReadingMappedIfSafe error:NULL]; });
    return data;
}

+ (UIImage *)imageForKey:(NSString *)key {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 200; });
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    NSValue *v = [MeshEmojiText packIndex][key];
    NSData *pack = packData();
    if (!v || NSMaxRange(v.rangeValue) > pack.length) return nil;
    UIImage *raw = [UIImage imageWithData:[pack subdataWithRange:v.rangeValue]];
    if (!raw) return nil;
    img = [UIImage imageWithCGImage:raw.CGImage scale:2 orientation:UIImageOrientationUp];
    [cache setObject:img forKey:key];
    return img;
}

+ (BOOL)containsEmoji:(NSString *)text { return [MeshEmojiText containsEmoji:text]; }
+ (NSArray *)allKeys { return [MeshEmojiText allKeys]; }
+ (NSArray *)keysIn:(NSString *)text { return [MeshEmojiText keysIn:text]; }

#pragma mark - Satz (zwischengespeichert)

// CTFont je Schrift und Größe, einmal angelegt.
static CTFontRef ctFont(UIFont *font) {
    static NSMutableDictionary *fonts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fonts = [NSMutableDictionary dictionary]; });
    NSString *k = [NSString stringWithFormat:@"%@ %g", font.fontName, font.pointSize];
    @synchronized (fonts) {
        id f = fonts[k];
        if (!f) {
            CTFontRef ct = CTFontCreateWithName((__bridge CFStringRef)font.fontName, font.pointSize, NULL);
            if (!ct) ct = CTFontCreateWithName(CFSTR("Helvetica"), font.pointSize, NULL);
            f = (__bridge_transfer id)ct;
            fonts[k] = f;
        }
        return (__bridge CTFontRef)f;   // bleibt im Wörterbuch, lebt also weiter
    }
}

// Satz je Text, Schrift und Fläche: Chatliste und Blasen setzen denselben Text beim Scrollen nicht neu.
+ (MeshEmojiLayout *)layoutFor:(NSString *)text font:(UIFont *)font width:(CGFloat)width height:(CGFloat)height lines:(NSInteger)lines {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 400; });
    text = text ?: @"";
    NSString *k = [NSString stringWithFormat:@"%@|%g|%g|%g|%ld|%@", font.fontName, font.pointSize, width, height, (long)lines, text];
    MeshEmojiLayout *layout = [cache objectForKey:k];
    if (layout) return layout;
    layout = [[MeshEmojiLayout alloc] initWithText:text font:ctFont(font) lineHeight:font.lineHeight width:width height:height lines:lines];
    [cache setObject:layout forKey:k];
    return layout;
}

+ (void)drawLayout:(MeshEmojiLayout *)layout color:(UIColor *)color alignment:(NSTextAlignment)alignment inRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx || !layout) return;
    CGContextSaveGState(ctx);
    [(color ?: [UIColor blackColor]) setFill];
    CTTextAlignment align = alignment == NSTextAlignmentCenter ? kCTCenterTextAlignment
                          : alignment == NSTextAlignmentRight ? kCTRightTextAlignment : kCTLeftTextAlignment;
    [layout drawInContext:ctx rect:rect alignment:align emoji:^(NSString *key, CGRect frame) {
        [[MeshEmoji imageForKey:key] drawInRect:frame];
    }];
    CGContextRestoreGState(ctx);
}

+ (CGSize)textSize:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size {
    if (![self containsEmoji:text])
        return [text sizeWithFont:font constrainedToSize:size lineBreakMode:NSLineBreakByWordWrapping];
    return [self sizeOf:text font:font constrainedTo:size lines:size.height < font.lineHeight * 1.5f ? 1 : 0];
}

+ (CGSize)sizeOf:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size lines:(NSInteger)maxLines {
    return [self layoutFor:text font:font width:size.width height:size.height lines:maxLines].size;
}

+ (CGFloat)lineWidth:(NSString *)text font:(UIFont *)font {
    if (!text.length) return 0;
    return [self layoutFor:text font:font width:CGFLOAT_MAX height:CGFLOAT_MAX lines:1].lineWidth;
}

+ (void)draw:(NSString *)text font:(UIFont *)font color:(UIColor *)color alignment:(NSTextAlignment)alignment
       lines:(NSInteger)maxLines inRect:(CGRect)rect {
    // Nur Emojis in einer zu schmalen Zeile (Knöpfe, die UIKit nach den alten Emojis bemessen hat):
    // verkleinern statt abschneiden, das Label zeichnet nur in seine eigene Fläche.
    if (maxLines == 1 && rect.size.width > 4) {
        BOOL onlyEmoji = YES;
        for (id s in [MeshEmojiText segmentsOf:text])
            onlyEmoji &= [s isKindOfClass:[NSArray class]] || ![[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length];
        CGFloat w = onlyEmoji ? [self layoutFor:text font:font width:CGFLOAT_MAX height:CGFLOAT_MAX lines:1].size.width : 0;
        if (w > rect.size.width) font = [font fontWithSize:font.pointSize * rect.size.width / w * 0.97f];
    }
    MeshEmojiLayout *layout = [self layoutFor:text font:font width:rect.size.width height:rect.size.height lines:maxLines];
    [self drawLayout:layout color:color alignment:alignment inRect:rect];
}

#pragma mark - In UIKit einhängen

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (![MeshEmojiText packIndex].count) return;   // ohne Pack bleibt alles beim System
        method_exchangeImplementations(class_getInstanceMethod([UILabel class], @selector(drawTextInRect:)),
                                       class_getInstanceMethod([UILabel class], @selector(mesh_drawTextInRect:)));
    });
}

@end

// Nach dem Tausch rufen die mesh_-Namen die Originale auf.
@implementation UILabel (MeshEmoji)
// Die Tastatur (eigenes Fenster von UIKit, auch die Emoji-Tasten) bleibt beim System.
static BOOL inSystemWindow(UIView *v) {
    static Class textEffects;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ textEffects = NSClassFromString(@"UITextEffectsWindow"); });
    UIWindow *w = v.window;
    return w && ((textEffects && [w isKindOfClass:textEffects]) || [NSStringFromClass([w class]) rangeOfString:@"Keyboard"].location != NSNotFound);
}

- (void)mesh_drawTextInRect:(CGRect)rect {
    NSString *text = self.text;
    if (inSystemWindow(self) || ![MeshEmoji containsEmoji:text]) { [self mesh_drawTextInRect:rect]; return; }
    // Mit Schatten bleibt es beim System (selten, und CoreText hier ohne Schatten).
    if (self.shadowColor && !CGSizeEqualToSize(self.shadowOffset, CGSizeZero)) { [self mesh_drawTextInRect:rect]; return; }
    UIColor *color = self.highlighted && self.highlightedTextColor ? self.highlightedTextColor : self.textColor;
    [MeshEmoji draw:text font:self.font color:color alignment:self.textAlignment lines:self.numberOfLines inRect:rect];
}
@end

