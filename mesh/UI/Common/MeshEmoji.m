#import "MeshEmoji.h"
#import <CoreText/CoreText.h>
#import <objc/runtime.h>

static NSString *const kEmojiKeyAttribute = @"MeshEmojiKey";
static NSString *gPackDir;

#pragma mark - Pack

@implementation MeshEmoji

+ (void)setPackDirectory:(NSString *)dir { gPackDir = [dir copy]; }

static NSString *packPath(NSString *ext) {
    return gPackDir ? [gPackDir stringByAppendingPathComponent:[@"emoji" stringByAppendingPathExtension:ext]]
                    : [[NSBundle mainBundle] pathForResource:@"emoji" ofType:ext];
}

// Schlüssel -> Bereich im Pack; einmal gelesen.
static NSDictionary *packIndex(void) {
    static NSDictionary *index;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *text = [NSString stringWithContentsOfFile:packPath(@"idx") encoding:NSUTF8StringEncoding error:NULL];
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:4096];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSArray *f = [line componentsSeparatedByString:@" "];
            if (f.count != 3) continue;
            d[f[0]] = [NSValue valueWithRange:NSMakeRange((NSUInteger)[f[1] longLongValue], (NSUInteger)[f[2] longLongValue])];
        }
        index = d;
    });
    return index;
}

static NSData *packData(void) {
    static NSData *data;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ data = [NSData dataWithContentsOfFile:packPath(@"pack") options:NSDataReadingMappedIfSafe error:NULL]; });
    return data;
}

+ (UIImage *)imageForKey:(NSString *)key {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 200; });
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    NSValue *v = packIndex()[key];
    NSData *pack = packData();
    if (!v || NSMaxRange(v.rangeValue) > pack.length) return nil;
    UIImage *raw = [UIImage imageWithData:[pack subdataWithRange:v.rangeValue]];
    if (!raw) return nil;
    img = [UIImage imageWithCGImage:raw.CGImage scale:2 orientation:UIImageOrientationUp];
    [cache setObject:img forKey:key];
    return img;
}

#pragma mark - Emojis im Text finden

static UTF32Char codePointAt(const unichar *b, NSUInteger n, NSUInteger i, NSUInteger *len) {
    unichar c = b[i];
    if (CFStringIsSurrogateHighCharacter(c) && i + 1 < n && CFStringIsSurrogateLowCharacter(b[i + 1])) {
        *len = 2;
        return CFStringGetLongCharacterForSurrogatePair(c, b[i + 1]);
    }
    *len = 1;
    return c;
}

static BOOL isRegional(UTF32Char c) { return c >= 0x1F1E6 && c <= 0x1F1FF; }
static BOOL isSkinTone(UTF32Char c) { return c >= 0x1F3FB && c <= 0x1F3FF; }
static BOOL isTag(UTF32Char c)      { return c >= 0xE0020 && c <= 0xE007F; }

// Zeichen, die auch ohne FE0F als Emoji erscheinen (Emoji_Presentation im BMP).
static BOOL defaultEmoji(UTF32Char c) {
    static const UTF32Char list[] = { 0x231A, 0x231B, 0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23F0, 0x23F3, 0x25FD, 0x25FE,
        0x2614, 0x2615, 0x267F, 0x2693, 0x26A1, 0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26D4, 0x26EA,
        0x26F2, 0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A, 0x270B, 0x2728, 0x274C, 0x274E, 0x2753, 0x2754, 0x2755,
        0x2757, 0x2795, 0x2796, 0x2797, 0x27B0, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B55 };
    if (c >= 0x2648 && c <= 0x2653) return YES;   // Sternzeichen
    for (size_t i = 0; i < sizeof(list) / sizeof(list[0]); i++) if (list[i] == c) return YES;
    return NO;
}

// Länge eines Emojis ab i (0 = keins) und die Codepunkte ohne FE0F für den Schlüssel.
static NSUInteger emojiAt(const unichar *b, NSUInteger n, NSUInteger i, NSMutableArray *cps) {
    NSUInteger l1, l2 = 0, j;
    UTF32Char c = codePointAt(b, n, i, &l1);
    UTF32Char next = i + l1 < n ? codePointAt(b, n, i + l1, &l2) : 0;
    BOOL keycap = (c == '#' || c == '*' || (c >= '0' && c <= '9'))
        && (next == 0x20E3 || (next == 0xFE0F && i + l1 + l2 < n && b[i + l1 + l2] == 0x20E3));
    BOOL start = (c >= 0x1F000 && c <= 0x1FAFF) || keycap
        || ((c == 0xA9 || c == 0xAE || (c >= 0x203C && c <= 0x3299)) && (next == 0xFE0F || defaultEmoji(c)));
    if (!start || next == 0xFE0E) return 0;   // FE0E: ausdrücklich als Text

    j = i + l1;
    [cps addObject:@(c)];
    if (isRegional(c)) {   // Flagge = zwei Regionalbuchstaben
        if (isRegional(next)) { [cps addObject:@(next)]; j += l2; }
        return j - i;
    }
    for (;;) {
        NSUInteger l;
        // Anhänge: Variante, Hautfarbe, Tastenkappe, Tag-Folge (Flaggen von Landesteilen)
        while (j < n) {
            UTF32Char d = codePointAt(b, n, j, &l);
            if (d == 0xFE0F) { j += l; continue; }
            if (isSkinTone(d) || d == 0x20E3 || isTag(d)) { [cps addObject:@(d)]; j += l; continue; }
            break;
        }
        // Verbinder: ZWJ + weiteres Emoji
        if (j + 1 < n && b[j] == 0x200D) {
            UTF32Char d = codePointAt(b, n, j + 1, &l);
            BOOL emojiPart = (d >= 0x1F000 && d <= 0x1FAFF) || (d >= 0x2190 && d <= 0x2BFF);   // keine Schriftzeichen
            if (emojiPart) { [cps addObject:@0x200D]; [cps addObject:@(d)]; j += 1 + l; continue; }
        }
        return j - i;
    }
}

static NSString *keyFor(NSArray *cps) {
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:cps.count];
    for (NSNumber *c in cps) [parts addObject:[NSString stringWithFormat:@"%04x", [c unsignedIntValue]]];
    return [parts componentsJoinedByString:@"_"];
}

// Schlüssel, die es im Pack gibt; eine unbekannte Verbindung zerfällt in ihre Teile. Fehlt auch nur
// ein Teil, bleibt die ganze Folge Text (nichts darf stillschweigend verschwinden).
static NSArray *availableKeys(NSArray *cps) {
    NSString *key = keyFor(cps);
    if (packIndex()[key]) return @[key];
    NSMutableArray *out = [NSMutableArray array], *part = [NSMutableArray array];
    BOOL joined = [cps containsObject:@0x200D];
    for (NSNumber *c in [cps arrayByAddingObject:@0x200D]) {
        if ([c unsignedIntValue] != 0x200D) {
            if (joined || !isSkinTone([c unsignedIntValue])) [part addObject:c];
            continue;
        }
        if (!part.count) continue;
        NSString *k = keyFor(part);
        if (!packIndex()[k]) return @[];
        [out addObject:k];
        [part removeAllObjects];
    }
    return out;
}

// Schnelltest: ohne Ersatzpaare und Symbolbereich kein Emoji (die meisten Texte).
static BOOL mayContainEmoji(NSString *text) {
    NSUInteger n = text.length;
    if (!n) return NO;
    unichar stackBuf[256];
    unichar *b = n <= 256 ? stackBuf : malloc(n * sizeof(unichar));
    [text getCharacters:b range:NSMakeRange(0, n)];
    BOOL found = NO;
    for (NSUInteger i = 0; i < n && !found; i++)
        found = CFStringIsSurrogateHighCharacter(b[i]) || (b[i] >= 0x203C && b[i] <= 0x3299) || b[i] == 0xFE0F || b[i] == 0x20E3;
    if (b != stackBuf) free(b);
    return found;
}

// Text in Teile: NSString für Text, NSArray (Schlüssel) für ein Emoji.
static NSArray *segments(NSString *text) {
    NSUInteger n = text.length;
    NSMutableArray *out = [NSMutableArray array];
    if (!mayContainEmoji(text)) { if (n) [out addObject:text]; return out; }
    unichar *b = malloc(n * sizeof(unichar));
    [text getCharacters:b range:NSMakeRange(0, n)];
    NSUInteger i = 0, plain = 0;
    while (i < n) {
        NSMutableArray *cps = [NSMutableArray array];
        NSUInteger len = emojiAt(b, n, i, cps);
        NSArray *keys = len ? availableKeys(cps) : nil;
        if (!keys.count) { i += (CFStringIsSurrogateHighCharacter(b[i]) && i + 1 < n) ? 2 : 1; continue; }
        if (i > plain) [out addObject:[text substringWithRange:NSMakeRange(plain, i - plain)]];
        [out addObject:keys];
        i += len;
        plain = i;
    }
    if (plain < n) [out addObject:[text substringFromIndex:plain]];
    free(b);
    return out;
}

+ (BOOL)containsEmoji:(NSString *)text {
    for (id s in segments(text)) if ([s isKindOfClass:[NSArray class]]) return YES;
    return NO;
}

+ (NSArray *)keysIn:(NSString *)text {
    NSMutableArray *keys = [NSMutableArray array];
    for (id s in segments(text)) if ([s isKindOfClass:[NSArray class]]) [keys addObjectsFromArray:s];
    return keys;
}

#pragma mark - Satz mit Platzhaltern

typedef struct { CGFloat ascent, descent, width; } EmojiMetrics;

static void metricsDealloc(void *ref) { free(ref); }
static CGFloat metricsAscent(void *ref)  { return ((EmojiMetrics *)ref)->ascent; }
static CGFloat metricsDescent(void *ref) { return ((EmojiMetrics *)ref)->descent; }
static CGFloat metricsWidth(void *ref)   { return ((EmojiMetrics *)ref)->width; }

// Emoji so groß wie die Großbuchstaben plus Unterlänge, leicht breiter (wie Apple-Emojis im Text).
static CGFloat emojiSize(UIFont *font) { return roundf(font.pointSize * 1.2f); }

static NSAttributedString *attributed(NSArray *segs, UIFont *font, UIColor *color, NSTextAlignment alignment) {
    CTFontRef ct = CTFontCreateWithName((__bridge CFStringRef)font.fontName, font.pointSize, NULL);
    if (!ct) ct = CTFontCreateWithName(CFSTR("Helvetica"), font.pointSize, NULL);
    CTTextAlignment align = alignment == NSTextAlignmentCenter ? kCTCenterTextAlignment
                          : alignment == NSTextAlignmentRight ? kCTRightTextAlignment : kCTLeftTextAlignment;
    CTParagraphStyleSetting setting = { kCTParagraphStyleSpecifierAlignment, sizeof(align), &align };
    CTParagraphStyleRef para = CTParagraphStyleCreate(&setting, 1);
    NSDictionary *textAttrs = @{ (__bridge id)kCTFontAttributeName: (__bridge id)ct,
                                 (__bridge id)kCTForegroundColorAttributeName: (__bridge id)(color ?: [UIColor blackColor]).CGColor,
                                 (__bridge id)kCTParagraphStyleAttributeName: (__bridge id)para };
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    CGFloat e = emojiSize(font);
    for (id s in segs) {
        if ([s isKindOfClass:[NSString class]]) {
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:s attributes:textAttrs]];
            continue;
        }
        for (NSString *key in s) {
            EmojiMetrics *m = malloc(sizeof(EmojiMetrics));
            m->ascent = e * 0.82f; m->descent = e * 0.18f; m->width = e + 1;
            CTRunDelegateCallbacks cb = { kCTRunDelegateVersion1, metricsDealloc, metricsAscent, metricsDescent, metricsWidth };
            CTRunDelegateRef delegate = CTRunDelegateCreate(&cb, m);
            NSMutableDictionary *attrs = [textAttrs mutableCopy];
            attrs[(__bridge id)kCTRunDelegateAttributeName] = (__bridge id)delegate;
            attrs[kEmojiKeyAttribute] = key;
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"￼" attributes:attrs]];
            CFRelease(delegate);
        }
    }
    CFRelease(para);
    CFRelease(ct);
    return out;
}

// Zeilen wie UILabel: umbrechen nach Wörtern, bei begrenzter Zeilenzahl die letzte mit "…" kürzen.
static NSArray *layoutLines(NSAttributedString *as, CGFloat width, NSInteger maxLines) {
    NSMutableArray *lines = [NSMutableArray array];
    CTTypesetterRef ts = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)as);
    CFIndex start = 0, length = (CFIndex)as.length;
    while (start < length) {
        BOOL last = maxLines > 0 && (NSInteger)lines.count == maxLines - 1;
        CFIndex count = last ? length - start : CTTypesetterSuggestLineBreak(ts, start, width);
        if (count <= 0) count = 1;
        CTLineRef line = CTTypesetterCreateLine(ts, CFRangeMake(start, count));
        if (last && CTLineGetTypographicBounds(line, NULL, NULL, NULL) - CTLineGetTrailingWhitespaceWidth(line) > width) {
            NSDictionary *ta = [as attributesAtIndex:(NSUInteger)start effectiveRange:NULL];
            NSMutableDictionary *tokenAttrs = [ta mutableCopy];
            [tokenAttrs removeObjectForKey:(__bridge id)kCTRunDelegateAttributeName];
            [tokenAttrs removeObjectForKey:kEmojiKeyAttribute];
            CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)
                [[NSAttributedString alloc] initWithString:@"…" attributes:tokenAttrs]);
            CTLineRef cut = CTLineCreateTruncatedLine(line, width, kCTLineTruncationEnd, token);
            CFRelease(token);
            if (cut) { CFRelease(line); line = cut; }
        }
        [lines addObject:(__bridge_transfer id)line];
        start += count;
        if (last) break;
    }
    CFRelease(ts);
    return lines;
}

static CGFloat lineHeight(CTLineRef line, UIFont *font) {
    CGFloat a, d, l;
    CTLineGetTypographicBounds(line, &a, &d, &l);
    return MAX(font.lineHeight, ceilf(a + d));
}

+ (CGSize)textSize:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size {
    if (!mayContainEmoji(text) || ![self containsEmoji:text])
        return [text sizeWithFont:font constrainedToSize:size lineBreakMode:NSLineBreakByWordWrapping];
    return [self sizeOf:text font:font constrainedTo:size lines:size.height < font.lineHeight * 1.5f ? 1 : 0];
}

+ (CGSize)sizeOf:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size lines:(NSInteger)maxLines {
    NSAttributedString *as = attributed(segments(text), font, nil, NSTextAlignmentLeft);
    CGFloat w = 0, h = 0;
    for (id l in layoutLines(as, size.width, maxLines)) {
        CTLineRef line = (__bridge CTLineRef)l;
        CGFloat lh = lineHeight(line, font);
        if (h + lh > size.height && h > 0) break;
        w = MAX(w, CTLineGetTypographicBounds(line, NULL, NULL, NULL) - CTLineGetTrailingWhitespaceWidth(line));
        h += lh;
    }
    return CGSizeMake(ceilf(MIN(w, size.width)), ceilf(h));
}

+ (void)draw:(NSString *)text font:(UIFont *)font color:(UIColor *)color alignment:(NSTextAlignment)alignment
       lines:(NSInteger)maxLines inRect:(CGRect)rect {
    NSArray *segs = segments(text);
    // Nur Emojis in einer zu schmalen Zeile (Knöpfe, die UIKit nach den alten Emojis bemessen hat):
    // verkleinern statt abschneiden, das Label zeichnet nur in seine eigene Fläche.
    BOOL onlyEmoji = YES;
    for (id s in segs) onlyEmoji &= [s isKindOfClass:[NSArray class]] || ![[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length];
    if (onlyEmoji && maxLines == 1) {
        CGFloat w = [self sizeOf:text font:font constrainedTo:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) lines:1].width;
        if (w > rect.size.width && rect.size.width > 4) font = [font fontWithSize:font.pointSize * rect.size.width / w * 0.97f];
    }
    NSAttributedString *as = attributed(segs, font, color, alignment);
    NSArray *lines = layoutLines(as, rect.size.width, maxLines);
    CGFloat total = 0;
    NSMutableArray *heights = [NSMutableArray array];
    for (id l in lines) {
        CGFloat lh = lineHeight((__bridge CTLineRef)l, font);
        if (total + lh > rect.size.height + 1 && total > 0) break;
        [heights addObject:@(lh)];
        total += lh;
    }
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1, -1));   // UIKit-Koordinaten (y nach unten)
    CGFloat y = rect.origin.y + MAX(0, (rect.size.height - total) / 2), e = emojiSize(font);
    for (NSUInteger i = 0; i < heights.count; i++) {
        CTLineRef line = (__bridge CTLineRef)lines[i];
        CGFloat a, d, l, lh = [heights[i] floatValue];
        CGFloat lw = CTLineGetTypographicBounds(line, &a, &d, &l) - CTLineGetTrailingWhitespaceWidth(line);
        CGFloat x = rect.origin.x + (alignment == NSTextAlignmentCenter ? (rect.size.width - lw) / 2
                                   : alignment == NSTextAlignmentRight ? rect.size.width - lw : 0);
        CGFloat baseline = roundf(y + (lh - (a + d)) / 2 + a);
        CGContextSetTextPosition(ctx, x, baseline);
        CTLineDraw(line, ctx);
        // Bilder über die Platzhalter
        for (id r in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
            CTRunRef run = (__bridge CTRunRef)r;
            NSString *key = ((__bridge NSDictionary *)CTRunGetAttributes(run))[kEmojiKeyAttribute];
            if (!key) continue;
            CGPoint pos;
            CTRunGetPositions(run, CFRangeMake(0, 1), &pos);
            [[MeshEmoji imageForKey:key] drawInRect:CGRectMake(x + pos.x + 0.5f, baseline - e * 0.82f, e, e)];
        }
        y += lh;
    }
    CGContextRestoreGState(ctx);
}

#pragma mark - In UIKit einhängen

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!packIndex().count) return;   // ohne Pack bleibt alles beim System
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
    if (!mayContainEmoji(text) || inSystemWindow(self) || ![MeshEmoji containsEmoji:text]) { [self mesh_drawTextInRect:rect]; return; }
    // Mit Schatten bleibt es beim System (selten, und CoreText hier ohne Schatten).
    if (self.shadowColor && !CGSizeEqualToSize(self.shadowOffset, CGSizeZero)) { [self mesh_drawTextInRect:rect]; return; }
    UIColor *color = self.highlighted && self.highlightedTextColor ? self.highlightedTextColor : self.textColor;
    [MeshEmoji draw:text font:self.font color:color alignment:self.textAlignment lines:self.numberOfLines inRect:rect];
}
@end

