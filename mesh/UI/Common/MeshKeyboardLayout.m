#import "MeshKeyboardLayout.h"
#import "MeshCustomEmoji.h"

@implementation MeshKeySpec
@end

static const CGFloat kPadX = 3, kPadY = 5;   // halbe Lücke zwischen den Tasten

static MeshKeySpec *spec(MeshKeyKind kind, NSString *text, CGRect frame) {
    MeshKeySpec *k = [[MeshKeySpec alloc] init];
    k.kind = kind;
    k.text = text;
    k.frame = frame;
    return k;
}

// Trefferflächen einer Reihe: senkrecht die ganze Reihe, waagerecht bis zur Mitte der Lücke zum Nachbarn
// und an den Rändern bis zum Rand. So geht kein Tipp zwischen zwei Tasten verloren.
static void fillHitFrames(NSArray *row, CGFloat top, CGFloat height, CGFloat width) {
    for (NSUInteger i = 0; i < row.count; i++) {
        MeshKeySpec *k = row[i];
        CGFloat left = i ? (CGRectGetMaxX([row[i - 1] frame]) + CGRectGetMinX(k.frame)) / 2 : 0;
        CGFloat right = i + 1 < row.count ? (CGRectGetMaxX(k.frame) + CGRectGetMinX([row[i + 1] frame])) / 2 : width;
        k.hitFrame = CGRectMake(left, top, right - left, height);
    }
}

// Zeichentasten gleicher Breite, waagerecht zentriert.
static NSMutableArray *charRow(NSString *chars, CGFloat unit, CGFloat top, CGFloat rowH, CGFloat width) {
    NSMutableArray *row = [NSMutableArray array];
    NSUInteger n = chars.length;
    CGFloat x = (width - n * unit) / 2;
    for (NSUInteger i = 0; i < n; i++) {
        NSString *c = [chars substringWithRange:NSMakeRange(i, 1)];
        [row addObject:spec(MeshKeyChar, c, CGRectMake(x + i * unit + kPadX, top + kPadY, unit - 2 * kPadX, rowH - 2 * kPadY))];
    }
    return row;
}

@implementation MeshKeyboardLayout

+ (NSArray *)keysForPage:(MeshKeyPage)page language:(NSString *)lang size:(CGSize)size decimal:(NSString *)decimal {
    CGFloat W = size.width, H = size.height, rowH = floorf(H / 4);
    NSMutableArray *all = [NSMutableArray array];

    if (page == MeshKeyPagePad || page == MeshKeyPageDecimalPad || page == MeshKeyPagePhonePad) {
        CGFloat cw = W / 3;
        NSString *left = page == MeshKeyPageDecimalPad ? (decimal.length ? decimal : @".") : page == MeshKeyPagePhonePad ? @"+" : nil;
        for (int r = 0; r < 4; r++) {
            NSMutableArray *row = [NSMutableArray array];
            for (int c = 0; c < 3; c++) {
                CGRect f = CGRectMake(c * cw + kPadX, r * rowH + kPadX, cw - 2 * kPadX, rowH - 2 * kPadX);
                if (r < 3) [row addObject:spec(MeshKeyChar, [NSString stringWithFormat:@"%d", r * 3 + c + 1], f)];
                else if (c == 0 && left) [row addObject:spec(MeshKeyChar, left, f)];
                else if (c == 1) [row addObject:spec(MeshKeyChar, @"0", f)];
                else if (c == 2) [row addObject:spec(MeshKeyDelete, nil, f)];
            }
            // Trefferfläche = Zelle: die leere Zelle unten links bleibt ohne Taste
            for (MeshKeySpec *k in row) k.hitFrame = CGRectInset(k.frame, -kPadX, -kPadX);
            [all addObjectsFromArray:row];
        }
        return all;
    }

    BOOL de = [lang hasPrefix:@"de"];
    NSArray *lines;
    if (page == MeshKeyPageLetters)
        lines = de ? @[@"qwertzuiopü", @"asdfghjklöä", @"yxcvbnm"] : @[@"qwertyuiop", @"asdfghjkl", @"zxcvbnm"];
    else if (page == MeshKeyPageNumbers)
        lines = @[@"1234567890", de ? @"-/:;()€&@\"" : @"-/:;()$&@\"", @".,?!'"];
    else
        lines = @[@"[]{}#%^*+=", de ? @"_\\|~<>$£¥•" : @"_\\|~<>€£¥•", @".,?!'"];
    CGFloat unit = W / MAX([lines[0] length], (NSUInteger)10);

    for (int r = 0; r < 2; r++) {
        NSMutableArray *row = charRow(lines[r], unit, r * rowH, rowH, W);
        fillHitFrames(row, r * rowH, rowH, W);
        [all addObjectsFromArray:row];
    }

    // Reihe 3: Umschalt bzw. Seitenwechsel links, ⌫ rechts, dazwischen die Zeichen
    CGFloat top = 2 * rowH, side = W / 10 * 1.5f;
    NSString *mid = lines[2];
    CGFloat midUnit = page == MeshKeyPageLetters ? unit : (W - 2 * side) / mid.length;
    if (page == MeshKeyPageLetters) side = (W - mid.length * unit) / 2;
    NSMutableArray *row = [NSMutableArray array];
    CGFloat sideW = MIN(side - 2 * kPadX - 4, unit * 1.45f);
    CGRect lf = CGRectMake(kPadX, top + kPadY, sideW, rowH - 2 * kPadY);
    if (page == MeshKeyPageLetters) [row addObject:spec(MeshKeyShift, nil, lf)];
    else if (page == MeshKeyPageNumbers) [row addObject:spec(MeshKeySymbols, @"#+=", lf)];
    else [row addObject:spec(MeshKeyNumbers, @"123", lf)];
    [row addObjectsFromArray:charRow(mid, midUnit, top, rowH, W)];
    [row addObject:spec(MeshKeyDelete, nil, CGRectMake(W - kPadX - sideW, top + kPadY, sideW, rowH - 2 * kPadY))];
    fillHitFrames(row, top, rowH, W);
    [all addObjectsFromArray:row];

    // Reihe 4: 123/ABC, Sprache, Emoji, Leertaste, Return
    top = 3 * rowH;
    CGFloat modeW = roundf(W * 0.12f), retW = roundf(W * 0.25f), h = H - top - 2 * kPadY, x = 0;
    row = [NSMutableArray array];
    MeshKeyKind first = page == MeshKeyPageLetters ? MeshKeyNumbers : MeshKeyLetters;
    [row addObject:spec(first, page == MeshKeyPageLetters ? @"123" : @"ABC", CGRectMake(x + kPadX, top + kPadY, modeW - 2 * kPadX, h))];
    x += modeW;
    [row addObject:spec(MeshKeyGlobe, nil, CGRectMake(x + kPadX, top + kPadY, modeW - 2 * kPadX, h))];
    x += modeW;
    [row addObject:spec(MeshKeyEmoji, nil, CGRectMake(x + kPadX, top + kPadY, modeW - 2 * kPadX, h))];
    x += modeW;
    [row addObject:spec(MeshKeySpace, @" ", CGRectMake(x + kPadX, top + kPadY, W - x - retW - 2 * kPadX, h))];
    [row addObject:spec(MeshKeyReturn, nil, CGRectMake(W - retW + kPadX, top + kPadY, retW - 2 * kPadX, h))];
    fillHitFrames(row, top, H - top, W);
    [all addObjectsFromArray:row];
    return all;
}

+ (NSArray *)variantsFor:(NSString *)ch language:(NSString *)lang {
    static NSDictionary *de, *en;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *common = @{
            @"a": @"àáâäæãåā", @"e": @"èéêëēėę", @"i": @"îïíīįì", @"o": @"ôöòóœøōõ", @"u": @"ûüùúū",
            @"s": @"ßśš", @"c": @"çćč", @"n": @"ñń", @"y": @"ÿ", @"z": @"žźż", @"l": @"ł",
            @"-": @"–—•", @".": @"…", @"?": @"¿", @"!": @"¡", @"'": @"‘’‚`", @"0": @"°",
            @"$": @"€£¥₩", @"€": @"$£¥₩", @"&": @"§", @"%": @"‰",
        };
        NSMutableDictionary *d = [common mutableCopy];
        d[@"a"] = @"äàáâæãåā"; d[@"o"] = @"öôòóœøōõ"; d[@"u"] = @"üûùúū"; d[@"s"] = @"ßśš";
        d[@"\""] = @"„“”«»";
        de = d;
        d = [common mutableCopy];
        d[@"\""] = @"“”„«»";
        en = d;
    });
    NSString *v = ([lang hasPrefix:@"de"] ? de : en)[ch.lowercaseString];
    if (!v) return nil;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:v.length];
    [v enumerateSubstringsInRange:NSMakeRange(0, v.length) options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *s, NSRange r, NSRange er, BOOL *stop) { [out addObject:s]; }];
    return out;
}

+ (BOOL)shouldCapitalizeAfter:(NSString *)before mode:(MeshAutoCap)mode {
    if (mode == MeshAutoCapNone) return NO;
    if (mode == MeshAutoCapAll) return YES;
    NSUInteger n = before.length;
    if (!n) return YES;
    unichar last = [before characterAtIndex:n - 1];
    if (last == '\n' || last == '\r') return YES;
    if (mode == MeshAutoCapWords) return last == ' ' || last == '\t';
    // Satzanfang: nur Leerraum davor, oder ". " / "! " / "? "
    NSUInteger i = n;
    while (i > 0 && ([before characterAtIndex:i - 1] == ' ' || [before characterAtIndex:i - 1] == '\t')) i--;
    if (i == 0) return YES;
    if (i == n) return NO;   // direkt hinter einem Zeichen
    unichar c = [before characterAtIndex:i - 1];
    return c == '.' || c == '!' || c == '?' || c == '\n';
}

#pragma mark - Löschen

static UTF32Char cpAt(NSString *s, NSUInteger i, NSUInteger end, NSUInteger *len) {
    unichar c = [s characterAtIndex:i];
    if (CFStringIsSurrogateHighCharacter(c) && i + 1 < end) {
        unichar d = [s characterAtIndex:i + 1];
        if (CFStringIsSurrogateLowCharacter(d)) { *len = 2; return CFStringGetLongCharacterForSurrogatePair(c, d); }
    }
    *len = 1;
    return c;
}

static BOOL isRegional(UTF32Char c) { return c >= 0x1F1E6 && c <= 0x1F1FF; }
static BOOL isSkinTone(UTF32Char c) { return c >= 0x1F3FB && c <= 0x1F3FF; }
static BOOL isTag(UTF32Char c)      { return c >= 0xE0020 && c <= 0xE007F; }

// Hängt am Zeichen davor: Variante, Hautfarbe, Tag, Kombinationszeichen (Akzente, Tastenkappe 20E3).
static BOOL isExtender(UTF32Char c) {
    static NSCharacterSet *marks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ marks = [NSCharacterSet nonBaseCharacterSet]; });
    return (c >= 0xFE00 && c <= 0xFE0F) || isSkinTone(c) || isTag(c) || c == 0x20E3 || [marks longCharacterIsMember:c];
}

+ (NSRange)deleteRangeIn:(NSString *)text cursor:(NSUInteger)cursor {
    cursor = MIN(cursor, text.length);
    if (!cursor) return NSMakeRange(0, 0);
    NSRange custom = [MeshCustomEmoji codeEndingIn:text at:cursor];   // eigenes Emoji: der ganze Code
    if (custom.location != NSNotFound) return custom;
    // Von vorn in Zeichen zerlegen: nur so zählen Flaggen-Paare (Regionalbuchstaben) richtig.
    NSUInteger i = 0, last = 0, l, l2;
    while (i < cursor) {
        last = i;
        UTF32Char c = cpAt(text, i, cursor, &l);
        i += l;
        if (c == '\r' && i < cursor && [text characterAtIndex:i] == '\n') { i++; continue; }
        if (isRegional(c) && i < cursor && isRegional(cpAt(text, i, cursor, &l2))) i += l2;
        while (i < cursor) {
            UTF32Char d = cpAt(text, i, cursor, &l);
            if (isExtender(d)) { i += l; continue; }
            if (d == 0x200D) {   // ZWJ verbindet mit dem nächsten Zeichen
                i += l;
                if (i < cursor) { cpAt(text, i, cursor, &l2); i += l2; }
                continue;
            }
            break;
        }
    }
    return NSMakeRange(last, cursor - last);
}

#pragma mark - Emojis

+ (NSArray *)codepointsForEmojiKey:(NSString *)key {
    NSMutableArray *out = [NSMutableArray array];
    if ([MeshCustomEmoji isName:key]) return out;   // kein Unicode
    for (NSString *part in [key componentsSeparatedByString:@"_"]) {
        if (!part.length) continue;
        unsigned long v = strtoul(part.UTF8String, NULL, 16);
        if (v && v <= 0x10FFFF) [out addObject:@((UTF32Char)v)];
    }
    return out;
}

// Wie in MeshEmoji: Zeichen im BMP, die auch ohne FE0F als Emoji erscheinen.
static BOOL defaultEmoji(UTF32Char c) {
    static const UTF32Char list[] = { 0x231A, 0x231B, 0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23F0, 0x23F3, 0x25FD, 0x25FE,
        0x2614, 0x2615, 0x267F, 0x2693, 0x26A1, 0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26D4, 0x26EA,
        0x26F2, 0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A, 0x270B, 0x2728, 0x274C, 0x274E, 0x2753, 0x2754, 0x2755,
        0x2757, 0x2795, 0x2796, 0x2797, 0x27B0, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B55 };
    if (c >= 0x2648 && c <= 0x2653) return YES;
    for (size_t i = 0; i < sizeof(list) / sizeof(list[0]); i++) if (list[i] == c) return YES;
    return NO;
}

// Emojis ab U+1F000, die ohne FE0F als Text gelten (Emoji_Presentation=No).
static BOOL textDefaultWide(UTF32Char c) {
    static const UTF32Char r[][2] = { {0x1F170, 0x1F171}, {0x1F17E, 0x1F17F}, {0x1F202, 0x1F202}, {0x1F237, 0x1F237},
        {0x1F321, 0x1F321}, {0x1F324, 0x1F32C}, {0x1F336, 0x1F336}, {0x1F37D, 0x1F37D}, {0x1F396, 0x1F397},
        {0x1F399, 0x1F39B}, {0x1F39E, 0x1F39F}, {0x1F3CB, 0x1F3CE}, {0x1F3D4, 0x1F3DF}, {0x1F3F3, 0x1F3F3},
        {0x1F3F5, 0x1F3F5}, {0x1F3F7, 0x1F3F7}, {0x1F43F, 0x1F43F}, {0x1F441, 0x1F441}, {0x1F4FD, 0x1F4FD},
        {0x1F549, 0x1F54A}, {0x1F56F, 0x1F570}, {0x1F573, 0x1F579}, {0x1F587, 0x1F587}, {0x1F58A, 0x1F58D},
        {0x1F590, 0x1F590}, {0x1F5A5, 0x1F5A5}, {0x1F5A8, 0x1F5A8}, {0x1F5B1, 0x1F5B2}, {0x1F5BC, 0x1F5BC},
        {0x1F5C2, 0x1F5C4}, {0x1F5D1, 0x1F5D3}, {0x1F5DC, 0x1F5DE}, {0x1F5E1, 0x1F5E1}, {0x1F5E3, 0x1F5E3},
        {0x1F5E8, 0x1F5E8}, {0x1F5EF, 0x1F5EF}, {0x1F5F3, 0x1F5F3}, {0x1F5FA, 0x1F5FA}, {0x1F6CB, 0x1F6CB},
        {0x1F6CD, 0x1F6CF}, {0x1F6E0, 0x1F6E5}, {0x1F6E9, 0x1F6E9}, {0x1F6F0, 0x1F6F0}, {0x1F6F3, 0x1F6F3} };
    for (size_t i = 0; i < sizeof(r) / sizeof(r[0]); i++) if (c >= r[i][0] && c <= r[i][1]) return YES;
    return NO;
}

static BOOL needsVariation(UTF32Char c) {
    if (c == 0x200D || c == 0x20E3 || isTag(c) || isRegional(c) || isSkinTone(c)) return NO;
    if (c < 0x1F000) return c >= 0xA9 && !defaultEmoji(c);
    return textDefaultWide(c);
}

static void appendCodepoint(NSMutableString *s, UTF32Char c) {
    if (c > 0xFFFF) {
        unichar pair[2] = { (unichar)(0xD800 + ((c - 0x10000) >> 10)), (unichar)(0xDC00 + ((c - 0x10000) & 0x3FF)) };
        [s appendString:[NSString stringWithCharacters:pair length:2]];
    } else {
        unichar u = (unichar)c;
        [s appendString:[NSString stringWithCharacters:&u length:1]];
    }
}

+ (NSString *)stringForEmojiKey:(NSString *)key {
    if ([MeshCustomEmoji isName:key]) return [MeshCustomEmoji codeForName:key];
    NSArray *cps = [self codepointsForEmojiKey:key];
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < cps.count; i++) {
        UTF32Char c = [cps[i] unsignedIntValue];
        UTF32Char next = i + 1 < cps.count ? [cps[i + 1] unsignedIntValue] : 0;
        appendCodepoint(s, c);
        // Vollständige Form: Tastenkappe "1 FE0F 20E3", Text-Standardzeichen mit FE0F (nicht vor Hautfarbe)
        if (next == 0x20E3 || (needsVariation(c) && !isSkinTone(next))) appendCodepoint(s, 0xFE0F);
    }
    return s;
}

+ (BOOL)isHiddenEmojiKey:(NSString *)key {
    if ([MeshCustomEmoji isName:key]) return NO;
    NSArray *cps = [self codepointsForEmojiKey:key];
    if (!cps.count) return YES;
    for (NSNumber *n in cps) if (isSkinTone([n unsignedIntValue])) return YES;
    if (cps.count > 1) return NO;
    UTF32Char c = [cps[0] unsignedIntValue];
    return c < 0xA9 || c == 0x20E3 || c == 0x200D || isRegional(c) || (c >= 0x1F9B0 && c <= 0x1F9B3);   // Ziffern, Bausteine, Regionalbuchstaben, Haar
}

// Gruppe nach dem ersten Codepunkt; die erste passende Zeile gilt (enge Ausnahmen vor weiten Bereichen).
+ (MeshEmojiGroup)groupForEmojiKey:(NSString *)key {
    enum { S = MeshEmojiSmileys, N = MeshEmojiNature, F = MeshEmojiFood, A = MeshEmojiActivities,
           T = MeshEmojiTravel, O = MeshEmojiObjects, Y = MeshEmojiSymbols };
    static const UTF32Char table[][3] = {
        // BMP
        {0x231A, 0x231B, O}, {0x2328, 0x2328, O}, {0x23F0, 0x23F3, O}, {0x2600, 0x2604, N}, {0x260E, 0x260E, O},
        {0x2614, 0x2614, N}, {0x2615, 0x2615, F}, {0x2618, 0x2618, N}, {0x261D, 0x261D, S}, {0x2620, 0x2620, S},
        {0x2639, 0x263A, S}, {0x265F, 0x265F, A}, {0x2692, 0x2697, O}, {0x2699, 0x269C, O}, {0x26A1, 0x26A1, N},
        {0x26B0, 0x26B1, O}, {0x26BD, 0x26BE, A}, {0x26C4, 0x26C8, N}, {0x26CF, 0x26CF, O}, {0x26D1, 0x26D1, O},
        {0x26D3, 0x26D3, O}, {0x26E9, 0x26EA, T}, {0x26F0, 0x26F2, T}, {0x26F3, 0x26F3, A}, {0x26F4, 0x26F5, T},
        {0x26F7, 0x26F8, A}, {0x26F9, 0x26F9, S}, {0x26FA, 0x26FA, T}, {0x26FD, 0x26FD, T}, {0x2702, 0x2702, O},
        {0x2708, 0x2708, T}, {0x2709, 0x2709, O}, {0x270A, 0x270D, S}, {0x270F, 0x270F, O}, {0x2712, 0x2712, O},
        {0x2728, 0x2728, N}, {0x2744, 0x2744, N}, {0x2B50, 0x2B50, N},
        {0x1F004, 0x1F004, A}, {0x1F0CF, 0x1F0CF, A},
        // Wetter, Himmel, Pflanzen, Essen
        {0x1F301, 0x1F301, T}, {0x1F303, 0x1F307, T}, {0x1F309, 0x1F309, T}, {0x1F30B, 0x1F310, T},
        {0x1F300, 0x1F32C, N}, {0x1F32D, 0x1F330, F}, {0x1F336, 0x1F336, F}, {0x1F33D, 0x1F33D, F},
        {0x1F331, 0x1F344, N}, {0x1F345, 0x1F37F, F},
        {0x1F380, 0x1F393, A}, {0x1F396, 0x1F3D3, A}, {0x1F3D4, 0x1F3F0, T}, {0x1F3F5, 0x1F3F7, O},
        {0x1F3F8, 0x1F3F9, A}, {0x1F3FA, 0x1F3FA, O},
        // Tiere, Menschen, Dinge
        {0x1F400, 0x1F43F, N}, {0x1F440, 0x1F450, S}, {0x1F451, 0x1F462, O}, {0x1F463, 0x1F487, S},
        {0x1F488, 0x1F48E, O}, {0x1F48F, 0x1F491, S}, {0x1F492, 0x1F492, T}, {0x1F493, 0x1F49F, Y},
        {0x1F4A1, 0x1F4A1, O}, {0x1F4A3, 0x1F4A3, O}, {0x1F4A9, 0x1F4AA, S}, {0x1F4A0, 0x1F4AF, Y}, {0x1F4B0, 0x1F4FF, O},
        {0x1F500, 0x1F53D, Y}, {0x1F549, 0x1F54E, Y}, {0x1F550, 0x1F567, Y}, {0x1F574, 0x1F575, S},
        {0x1F57A, 0x1F57A, S}, {0x1F590, 0x1F590, S}, {0x1F595, 0x1F596, S}, {0x1F5A4, 0x1F5A4, Y},
        {0x1F5E3, 0x1F5E3, S}, {0x1F5E8, 0x1F5EF, Y}, {0x1F5FA, 0x1F5FF, T}, {0x1F56F, 0x1F5FF, O},
        {0x1F600, 0x1F64F, S},
        // Verkehr
        {0x1F6A3, 0x1F6A3, A}, {0x1F680, 0x1F6A8, T}, {0x1F6AA, 0x1F6AA, O}, {0x1F6AC, 0x1F6AC, O},
        {0x1F6B4, 0x1F6B5, A}, {0x1F6B6, 0x1F6B6, S}, {0x1F6BD, 0x1F6BD, O}, {0x1F6BF, 0x1F6C1, O},
        {0x1F6CC, 0x1F6CC, S}, {0x1F6AB, 0x1F6C5, Y}, {0x1F6CB, 0x1F6D2, O}, {0x1F6D5, 0x1F6FF, T},
        {0x1F7E0, 0x1F7FF, Y},
        // Ergänzungen
        {0x1F90D, 0x1F90E, Y}, {0x1F90C, 0x1F939, S}, {0x1F93A, 0x1F93F, A}, {0x1F940, 0x1F940, N},
        {0x1F941, 0x1F941, O}, {0x1F942, 0x1F944, F}, {0x1F945, 0x1F94F, A}, {0x1F950, 0x1F96F, F},
        {0x1F970, 0x1F97A, S}, {0x1F97B, 0x1F97F, O}, {0x1F980, 0x1F9AE, N}, {0x1F9AF, 0x1F9AF, O},
        {0x1F9BA, 0x1F9BA, O}, {0x1F9BC, 0x1F9BD, T}, {0x1F9B0, 0x1F9BF, S}, {0x1F9C0, 0x1F9CB, F},
        {0x1F9CC, 0x1F9E0, S}, {0x1F9E1, 0x1F9E1, Y}, {0x1F9E2, 0x1F9FF, O},
        {0x1FA75, 0x1FA77, Y}, {0x1FA70, 0x1FA7F, O}, {0x1FA80, 0x1FA8F, A}, {0x1FA90, 0x1FAAF, O},
        {0x1FAB0, 0x1FABF, N}, {0x1FAC0, 0x1FAC5, S}, {0x1FAC6, 0x1FACF, N}, {0x1FAD0, 0x1FADF, F},
        {0x1FAE0, 0x1FAFF, S},
    };
    if ([MeshCustomEmoji isName:key]) return MeshEmojiFrog;
    NSArray *cps = [self codepointsForEmojiKey:key];
    if (!cps.count) return MeshEmojiSymbols;
    UTF32Char c = [cps[0] unsignedIntValue];
    if (isRegional(c) || c == 0x1F3F3 || c == 0x1F3F4 || c == 0x1F6A9 || c == 0x1F38C) return MeshEmojiFlags;
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++)
        if (c >= table[i][0] && c <= table[i][1]) return (MeshEmojiGroup)table[i][2];
    return MeshEmojiSymbols;
}

+ (NSArray *)groupEmojiKeys:(NSArray *)keys {
    NSMutableArray *groups = [NSMutableArray arrayWithCapacity:MeshEmojiGroupCount];
    for (int g = 0; g < MeshEmojiGroupCount; g++) [groups addObject:[NSMutableArray array]];
    for (NSString *k in keys) {
        if ([self isHiddenEmojiKey:k] || [MeshCustomEmoji isName:k]) continue;
        // Sortierschlüssel: Flaggen ohne Ländercode zuerst, dann die Codepunkte der Reihe nach
        NSArray *cps = [self codepointsForEmojiKey:k];
        [groups[[self groupForEmojiKey:k]] addObject:@[@(isRegional([cps[0] unsignedIntValue]) ? 1 : 0), cps, k]];
    }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:MeshEmojiGroupCount];
    for (NSMutableArray *g in groups) {
        [g sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            NSComparisonResult r = [a[0] compare:b[0]];
            if (r != NSOrderedSame) return r;
            NSArray *x = a[1], *y = b[1];
            for (NSUInteger i = 0; i < x.count && i < y.count; i++) {
                r = [x[i] compare:y[i]];
                if (r != NSOrderedSame) return r;
            }
            return x.count < y.count ? NSOrderedAscending : x.count > y.count ? NSOrderedDescending : NSOrderedSame;
        }];
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:g.count];
        for (NSArray *e in g) [list addObject:e[2]];
        [out addObject:list];
    }
    out[MeshEmojiFrog] = [MeshCustomEmoji names];
    return out;
}

@end
