#import "MeshEmojiText.h"
#import "MeshCustomEmoji.h"

static NSString *const kEmojiKeyAttribute = @"MeshEmojiKey";
static NSString *gPackDir;

#pragma mark - Pack

static NSString *packPath(NSString *ext) {
    return gPackDir ? [gPackDir stringByAppendingPathComponent:[@"emoji" stringByAppendingPathExtension:ext]]
                    : [[NSBundle mainBundle] pathForResource:@"emoji" ofType:ext];
}

// Schlüssel -> Bereich im Pack; einmal gelesen. Schlüssel ohne FE0F (wie die Suche), falls ein Pack sie trägt.
static NSDictionary *packIndex(void) {
    static NSDictionary *index;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *text = [NSString stringWithContentsOfFile:packPath(@"idx") encoding:NSUTF8StringEncoding error:NULL];
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:4096];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSArray *f = [line componentsSeparatedByString:@" "];
            if (f.count != 3) continue;
            NSString *key = f[0];
            if ([key rangeOfString:@"fe0f"].location != NSNotFound) {
                NSMutableArray *parts = [[key componentsSeparatedByString:@"_"] mutableCopy];
                [parts removeObject:@"fe0f"];
                key = [parts componentsJoinedByString:@"_"];
                if (d[key]) continue;   // die Form ohne FE0F hat Vorrang
            }
            d[key] = [NSValue valueWithRange:NSMakeRange((NSUInteger)[f[1] longLongValue], (NSUInteger)[f[2] longLongValue])];
        }
        index = d;
    });
    return index;
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

static BOOL isRegional(UTF32Char c)   { return c >= 0x1F1E6 && c <= 0x1F1FF; }
static BOOL isSkinTone(UTF32Char c)   { return c >= 0x1F3FB && c <= 0x1F3FF; }
static BOOL isTag(UTF32Char c)        { return c >= 0xE0020 && c <= 0xE007F; }
static BOOL isEmojiBlock(UTF32Char c) { return c >= 0x1F000 && c <= 0x1FAFF; }
static BOOL isSymbol(UTF32Char c)     { return (c >= 0x2190 && c <= 0x2BFF) || isEmojiBlock(c); }

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

static NSString *keyFor(NSArray *cps) {
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:cps.count];
    for (NSNumber *c in cps) [parts addObject:[NSString stringWithFormat:@"%04x", [c unsignedIntValue]]];
    return [parts componentsJoinedByString:@"_"];
}

// Symbole und Dingbats (☠ ☝ ✍ ♥ …) sind auch ohne FE0F ein Bild, wenn es eins gibt: die Schrift von iOS 6
// kennt viele davon gar nicht (Kästchen), die übrigen zeigt sie ohnehin als Emoji.
static BOOL symbolAsImage(UTF32Char c) { return c >= 0x2600 && c <= 0x27BF && packIndex()[keyFor(@[@(c)])] != nil; }

// Länge eines Emojis ab i (0 = keins) und seine Codepunkte ohne FE0F (für den Schlüssel).
static NSUInteger emojiAt(const unichar *b, NSUInteger n, NSUInteger i, NSMutableArray *cps) {
    NSUInteger l1, l2 = 0, j;
    UTF32Char c = codePointAt(b, n, i, &l1);
    UTF32Char next = i + l1 < n ? codePointAt(b, n, i + l1, &l2) : 0;
    if (next == 0xFE0E) return 0;   // ausdrücklich als Text
    BOOL keycap = (c == '#' || c == '*' || (c >= '0' && c <= '9'))
        && (next == 0x20E3 || (next == 0xFE0F && i + l1 + l2 < n && b[i + l1 + l2] == 0x20E3));
    BOOL bmp = c == 0xA9 || c == 0xAE || (c >= 0x203C && c <= 0x3299);
    BOOL start = isEmojiBlock(c) || keycap
        || (bmp && (next == 0xFE0F || isSkinTone(next) || next == 0x200D || defaultEmoji(c) || symbolAsImage(c)));
    if (!start) return 0;

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
        // Verbinder: ZWJ + weiteres Emoji (keine Schriftzeichen)
        if (j + 1 < n && b[j] == 0x200D) {
            UTF32Char d = codePointAt(b, n, j + 1, &l);
            if (isSymbol(d)) { [cps addObject:@0x200D]; [cps addObject:@(d)]; j += 1 + l; continue; }
        }
        return j - i;
    }
}

// Flaggen, die die Emoji-Schrift von iOS 6 selbst kennt (CN DE ES FR GB IT JP KR RU US): bleiben Text.
static BOOL systemFlag(UTF32Char a, UTF32Char b) {
    static const char pairs[] = "CNDEESFRGBITJPKRRUUS";
    for (size_t i = 0; i + 1 < sizeof(pairs); i += 2)
        if (a == 0x1F1E6 + (UTF32Char)(pairs[i] - 'A') && b == 0x1F1E6 + (UTF32Char)(pairs[i + 1] - 'A')) return YES;
    return NO;
}

// Schlüssel, die es im Pack gibt. Ohne Bild für die ganze Folge: Teile an den ZWJ, jeweils notfalls ohne
// Hautfarbe; Tag-Folgen fallen weg (schwarze Flagge). Fehlt ein Teil ganz, bleibt die Folge Text
// (nichts verschwindet stillschweigend). Leeres Ergebnis = Text.
static NSArray *availableKeys(NSArray *cps) {
    NSDictionary *idx = packIndex();
    NSString *key = keyFor(cps);
    if (idx[key]) return @[key];
    if (isRegional([cps[0] unsignedIntValue])) {
        if (cps.count == 2 && systemFlag([cps[0] unsignedIntValue], [cps[1] unsignedIntValue])) return @[];
        NSMutableArray *letters = [NSMutableArray array];   // unbekannte Flagge: Buchstaben einzeln
        for (NSNumber *c in cps) {
            NSString *k = keyFor(@[c]);
            if (!idx[k]) return @[];
            [letters addObject:k];
        }
        return letters;
    }
    NSMutableArray *out = [NSMutableArray array], *part = [NSMutableArray array];
    for (NSNumber *c in [cps arrayByAddingObject:@0x200D]) {
        UTF32Char v = [c unsignedIntValue];
        if (v != 0x200D) { if (!isTag(v)) [part addObject:c]; continue; }
        if (!part.count) continue;
        NSString *k = keyFor(part);
        if (!idx[k]) {
            NSMutableArray *plain = [NSMutableArray array];
            for (NSNumber *p in part) if (!isSkinTone([p unsignedIntValue]) || part.count == 1) [plain addObject:p];
            k = keyFor(plain);
        }
        if (!idx[k]) return @[];
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
        found = CFStringIsSurrogateHighCharacter(b[i]) || (b[i] >= 0x203C && b[i] <= 0x3299) || b[i] == 0xFE0F || b[i] == 0x20E3
             || (b[i] == ':' && [MeshCustomEmoji codeAt:b length:n index:i name:NULL]);   // eigenes Emoji (nicht "12:30")
    if (b != stackBuf) free(b);
    return found;
}

// Text zwischen Emojis ohne unsichtbare Reste: FE0E/FE0F, Tags, ZWJ an Symbolen (in Schriften wie
// Arabisch oder Malayalam formt ZWJ Buchstaben und bleibt).
static NSString *plainText(const unichar *b, NSUInteger n, NSUInteger from, NSUInteger to) {
    unichar *out = malloc((to - from) * sizeof(unichar) + 1);
    NSUInteger len = 0, l;
    UTF32Char prev = 0;
    for (NSUInteger i = from; i < to; i += l) {
        UTF32Char c = codePointAt(b, n, i, &l);
        BOOL drop = c == 0xFE0E || c == 0xFE0F || isTag(c);
        if (c == 0x200D) {
            NSUInteger l2;
            UTF32Char next = i + l < to ? codePointAt(b, n, i + l, &l2) : 0;
            drop = isSymbol(prev) || isSymbol(next) || isSkinTone(prev) || prev == 0xFE0F || !next;
        }
        if (!drop) { memcpy(out + len, b + i, l * sizeof(unichar)); len += l; }
        prev = c;
    }
    NSString *s = [NSString stringWithCharacters:out length:len];
    free(out);
    return s;
}

// Text in Teile: NSString für Text, NSArray (Schlüssel) für ein Emoji. Eigene Emojis ":name:" sind ein
// Teil mit dem Namen als Schlüssel; unbekannte Codes und alles andere mit ":" bleiben Text.
static NSArray *segments(NSString *text) {
    NSUInteger n = text.length;
    NSMutableArray *out = [NSMutableArray array];
    if (!mayContainEmoji(text)) { if (n) [out addObject:text]; return out; }
    unichar *b = malloc(n * sizeof(unichar));
    [text getCharacters:b range:NSMakeRange(0, n)];
    NSUInteger i = 0, plain = 0;
    while (i < n) {
        NSString *custom = nil;   // eigenes Emoji ":name:" (Schlüssel = Name)
        NSUInteger clen = b[i] == ':' ? [MeshCustomEmoji codeAt:b length:n index:i name:&custom] : 0;
        if (clen) {
            if (i > plain) { NSString *s = plainText(b, n, plain, i); if (s.length) [out addObject:s]; }
            [out addObject:@[custom]];
            i += clen;
            plain = i;
            continue;
        }
        NSMutableArray *cps = [NSMutableArray array];
        NSUInteger len = emojiAt(b, n, i, cps);
        NSArray *keys = len ? availableKeys(cps) : nil;
        if (!keys.count) { i += len ? len : (CFStringIsSurrogateHighCharacter(b[i]) && i + 1 < n) ? 2 : 1; continue; }
        if (i > plain) { NSString *s = plainText(b, n, plain, i); if (s.length) [out addObject:s]; }
        [out addObject:keys];
        i += len;
        plain = i;
    }
    if (plain < n) { NSString *s = plainText(b, n, plain, n); if (s.length) [out addObject:s]; }
    free(b);
    return out;
}

@implementation MeshEmojiText

+ (void)setPackDirectory:(NSString *)dir { gPackDir = [dir copy]; }
+ (NSDictionary *)packIndex { return packIndex(); }
+ (NSString *)packPath { return packPath(@"pack"); }
+ (NSArray *)allKeys { return [packIndex() allKeys]; }
+ (NSArray *)segmentsOf:(NSString *)text { return segments(text); }

+ (BOOL)containsEmoji:(NSString *)text {
    if (!mayContainEmoji(text)) return NO;
    for (id s in segments(text)) if ([s isKindOfClass:[NSArray class]]) return YES;
    return NO;
}

+ (NSArray *)keysIn:(NSString *)text {
    NSMutableArray *keys = [NSMutableArray array];
    for (id s in segments(text)) if ([s isKindOfClass:[NSArray class]]) [keys addObjectsFromArray:s];
    return keys;
}

@end

#pragma mark - Satz mit Platzhaltern

typedef struct { CGFloat ascent, descent, width; } EmojiMetrics;

static void metricsDealloc(void *ref) { free(ref); }
static CGFloat metricsAscent(void *ref)  { return ((EmojiMetrics *)ref)->ascent; }
static CGFloat metricsDescent(void *ref) { return ((EmojiMetrics *)ref)->descent; }
static CGFloat metricsWidth(void *ref)   { return ((EmojiMetrics *)ref)->width; }

// Platzhalter unsichtbar: zeichnet die Schrift U+FFFC als Kästchen, liegt es nicht unter dem Bild.
static CGColorRef clearColor(void) {
    static CGColorRef color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        const CGFloat c[4] = { 0, 0, 0, 0 };
        color = CGColorCreate(rgb, c);
        CGColorSpaceRelease(rgb);
    });
    return color;
}

@implementation MeshEmojiLayout {
    NSArray *_lines;      // CTLineRef
    NSArray *_heights;    // NSNumber je Zeile
    CGFloat _minLineHeight;
}

// Emoji so groß wie die Großbuchstaben plus Unterlänge, leicht breiter (wie Apple-Emojis im Text).
static CGFloat emojiSizeFor(CGFloat pointSize) { return roundf(pointSize * 1.2f); }

static NSAttributedString *attributed(NSArray *segs, CTFontRef font, CGFloat e, NSDictionary **textAttrsOut) {
    NSDictionary *textAttrs = @{ (__bridge id)kCTFontAttributeName: (__bridge id)font,
                                 (__bridge id)kCTForegroundColorFromContextAttributeName: @YES };
    if (textAttrsOut) *textAttrsOut = textAttrs;
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
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
            NSDictionary *attrs = @{ (__bridge id)kCTFontAttributeName: (__bridge id)font,
                                     (__bridge id)kCTForegroundColorAttributeName: (__bridge id)clearColor(),
                                     (__bridge id)kCTRunDelegateAttributeName: (__bridge id)delegate,
                                     kEmojiKeyAttribute: key };
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"￼" attributes:attrs]];
            CFRelease(delegate);
        }
    }
    return out;
}

static CGFloat visibleWidth(CTLineRef line) {
    return (CGFloat)(CTLineGetTypographicBounds(line, NULL, NULL, NULL) - CTLineGetTrailingWhitespaceWidth(line));
}

// Zeilen wie UILabel: umbrechen nach Wörtern, bei begrenzter Zeilenzahl die letzte mit "…" kürzen.
static NSArray *layoutLines(CTTypesetterRef ts, CFIndex length, NSDictionary *textAttrs, CGFloat width, NSInteger maxLines, BOOL *truncated) {
    NSMutableArray *lines = [NSMutableArray array];
    CFIndex start = 0;
    while (start < length) {
        BOOL last = maxLines > 0 && (NSInteger)lines.count == maxLines - 1;
        CFIndex count = last ? length - start : CTTypesetterSuggestLineBreak(ts, start, width);
        if (count <= 0) count = 1;
        CTLineRef line = CTTypesetterCreateLine(ts, CFRangeMake(start, count));
        if (last && (start + count < length || visibleWidth(line) > width)) {
            CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)
                [[NSAttributedString alloc] initWithString:@"…" attributes:textAttrs]);
            CTLineRef cut = CTLineCreateTruncatedLine(line, width, kCTLineTruncationEnd, token);
            CFRelease(token);
            if (cut) { CFRelease(line); line = cut; *truncated = YES; }
        }
        [lines addObject:(__bridge_transfer id)line];
        start += count;
        if (last) break;
    }
    return lines;
}

- (instancetype)initWithText:(NSString *)text font:(CTFontRef)font lineHeight:(CGFloat)lineHeight
                       width:(CGFloat)width height:(CGFloat)height lines:(NSInteger)maxLines {
    if (!(self = [super init])) return nil;
    _minLineHeight = lineHeight;
    _emojiSize = emojiSizeFor(CTFontGetSize(font));
    NSDictionary *textAttrs;
    NSAttributedString *as = attributed(segments(text ?: @""), font, _emojiSize, &textAttrs);
    CTTypesetterRef ts = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)as);
    BOOL truncated = NO;
    NSArray *lines = layoutLines(ts, (CFIndex)as.length, textAttrs, width, maxLines, &truncated);
    // Passen nicht alle Zeilen in die Höhe: so viele wie passen, die letzte mit "…"
    NSMutableArray *heights = [NSMutableArray array];
    CGFloat h = 0;
    for (id l in lines) {
        CGFloat lh = [self heightOf:(__bridge CTLineRef)l];
        if (h + lh > height + 1 && h > 0) break;
        [heights addObject:@(lh)];
        h += lh;
    }
    if (heights.count < lines.count) {
        truncated = NO;
        lines = layoutLines(ts, (CFIndex)as.length, textAttrs, width, (NSInteger)heights.count, &truncated);
        [heights removeAllObjects];
        h = 0;
        for (id l in lines) { CGFloat lh = [self heightOf:(__bridge CTLineRef)l]; [heights addObject:@(lh)]; h += lh; }
    }
    CFRelease(ts);
    CGFloat w = 0;
    for (id l in lines) w = MAX(w, visibleWidth((__bridge CTLineRef)l));
    _lines = lines;
    _heights = heights;
    _truncated = truncated;
    _size = CGSizeMake(ceilf(MIN(w, width)), ceilf(h));
    _lineWidth = lines.count ? ceilf((CGFloat)CTLineGetTypographicBounds((__bridge CTLineRef)lines[0], NULL, NULL, NULL)) : 0;
    return self;
}

- (CGFloat)heightOf:(CTLineRef)line {
    CGFloat a, d, l;
    CTLineGetTypographicBounds(line, &a, &d, &l);
    return MAX(_minLineHeight, ceilf(a + d));
}

- (NSUInteger)lineCount { return _lines.count; }

- (void)drawInContext:(CGContextRef)ctx rect:(CGRect)rect alignment:(CTTextAlignment)alignment
                emoji:(void (^)(NSString *key, CGRect frame))emoji {
    CGFloat total = 0;
    for (NSNumber *h in _heights) total += [h floatValue];
    if (ctx) {
        CGContextSaveGState(ctx);
        CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1, -1));   // UIKit-Koordinaten (y nach unten)
    }
    CGFloat y = rect.origin.y + MAX(0, (rect.size.height - total) / 2), e = _emojiSize;
    for (NSUInteger i = 0; i < _lines.count; i++) {
        CTLineRef line = (__bridge CTLineRef)_lines[i];
        CGFloat a, d, l, lh = [_heights[i] floatValue];
        CTLineGetTypographicBounds(line, &a, &d, &l);
        CGFloat lw = visibleWidth(line);
        CGFloat x = rect.origin.x + (alignment == kCTCenterTextAlignment ? (rect.size.width - lw) / 2
                                   : alignment == kCTRightTextAlignment ? rect.size.width - lw : 0);
        CGFloat baseline = roundf(y + (lh - (a + d)) / 2 + a);
        if (ctx) {
            CGContextSetTextPosition(ctx, x, baseline);
            CTLineDraw(line, ctx);
        }
        // Bilder über die Platzhalter, je Glyphe (gleiche Nachbarn kann CoreText zu einem Lauf fassen)
        for (id r in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
            CTRunRef run = (__bridge CTRunRef)r;
            NSString *key = ((__bridge NSDictionary *)CTRunGetAttributes(run))[kEmojiKeyAttribute];
            if (!key || !emoji) continue;
            CFIndex count = CTRunGetGlyphCount(run);
            for (CFIndex g = 0; g < count; g++) {
                CGPoint pos;
                CTRunGetPositions(run, CFRangeMake(g, 1), &pos);
                emoji(key, CGRectMake(x + pos.x + 0.5f, baseline - e * 0.82f, e, e));
            }
        }
        y += lh;
    }
    if (ctx) CGContextRestoreGState(ctx);
}

@end
