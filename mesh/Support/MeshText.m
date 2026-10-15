#import "MeshText.h"

// Steuerzeichen außer Zeilenumbruch/Tab und unsichtbare Formatierungszeichen. Letztere zählt
// Foundation teils als Leerraum, deshalb vor dem Zusammenfassen entfernen.
static NSCharacterSet *invisibleCharacters(void) {
    static NSCharacterSet *drop;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *s = [[NSCharacterSet controlCharacterSet] mutableCopy];
        [s removeCharactersInString:@"\t\n\r\v\f"];
        [s addCharactersInRange:NSMakeRange(0x200B, 5)];   // Zero-Width, LRM, RLM
        [s addCharactersInRange:NSMakeRange(0x202A, 5)];   // LRE … RLO
        [s addCharactersInRange:NSMakeRange(0x2066, 4)];   // LRI … PDI
        [s addCharactersInRange:NSMakeRange(0xFEFF, 1)];
        drop = s;
    });
    return drop;
}

NSString *MeshStripInvisible(NSString *raw) {
    return [[raw componentsSeparatedByCharactersInSet:invisibleCharacters()] componentsJoinedByString:@""];
}

NSString *MeshCleanName(NSString *raw) {
    NSString *visible = MeshStripInvisible(raw);
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *w in [visible componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])
        if (w.length) [words addObject:w];
    return [words componentsJoinedByString:@" "];
}

NSString *MeshTruncate(NSString *s, NSUInteger max) {
    if (s.length <= max) return s;
    return [s substringToIndex:[s rangeOfComposedCharacterSequenceAtIndex:max].location];
}

// B8.6 (docs/TEAM_GROUPS_PROTOCOL.md): Zeichen der Kategorien Cc und Cf, als feste Tabelle (Unicode 15.1),
// damit das Ergebnis nicht von der Unicode-Version des Systems abhängt (iOS 6 kennt z.B. U+061C nicht).
// U+200D (ZWJ) bleibt: Emoji-Folgen.
static BOOL isControlOrFormat(UTF32Char c) {
    if (c <= 0x1F || (c >= 0x7F && c <= 0x9F)) return YES;   // Cc
    static const UTF32Char ranges[][2] = {
        { 0x00AD, 0x00AD }, { 0x0600, 0x0605 }, { 0x061C, 0x061C }, { 0x06DD, 0x06DD }, { 0x070F, 0x070F },
        { 0x0890, 0x0891 }, { 0x08E2, 0x08E2 }, { 0x180E, 0x180E }, { 0x200B, 0x200C }, { 0x200E, 0x200F },
        { 0x202A, 0x202E }, { 0x2060, 0x2064 }, { 0x2066, 0x206F }, { 0xFEFF, 0xFEFF }, { 0xFFF9, 0xFFFB },
        { 0x110BD, 0x110BD }, { 0x110CD, 0x110CD }, { 0x13430, 0x1343F }, { 0x1BCA0, 0x1BCA3 },
        { 0x1D173, 0x1D17A }, { 0xE0001, 0xE0001 }, { 0xE0020, 0xE007F },
    };
    for (size_t i = 0; i < sizeof(ranges) / sizeof(ranges[0]); i++) if (c >= ranges[i][0] && c <= ranges[i][1]) return YES;
    return NO;
}

// Leerzeichen am Rand: Zs, Zl, Zp (wie Kotlin trim(); Cc ist da schon weg).
static BOOL isSpace(unichar c) {
    return c == 0x20 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029
        || c == 0x202F || c == 0x205F || c == 0x3000;
}

NSString *MeshCleanGroupText(NSString *raw) {
    if (![raw isKindOfClass:[NSString class]]) return @"";
    NSUInteger n = raw.length;
    unichar *in = malloc(n * sizeof(unichar) + 1), *out = malloc(n * sizeof(unichar) + 1);
    if (!in || !out) { free(in); free(out); return @""; }
    [raw getCharacters:in range:NSMakeRange(0, n)];
    NSUInteger len = 0;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = in[i];
        // Code Points, nicht Einheiten: sonst fielen Cf-Zeichen jenseits von U+FFFF (Tags) durch
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < n && CFStringIsSurrogateLowCharacter(in[i + 1])) {
            if (!isControlOrFormat(CFStringGetLongCharacterForSurrogatePair(c, in[i + 1]))) { out[len++] = c; out[len++] = in[i + 1]; }
            i++;
            continue;
        }
        if (CFStringIsSurrogateHighCharacter(c) || CFStringIsSurrogateLowCharacter(c)) continue;   // einzelne Hälfte: kein Zeichen, kein UTF-8
        if (!isControlOrFormat(c)) out[len++] = c;
    }
    NSUInteger start = 0, end = len;
    while (start < end && isSpace(out[start])) start++;
    while (end > start && isSpace(out[end - 1])) end--;
    NSString *s = [NSString stringWithCharacters:out + start length:end - start];
    free(in); free(out);
    return s;
}

NSString *MeshTruncateUTF16(NSString *s, NSUInteger max) {
    if (s.length <= max) return s;
    NSUInteger cut = max;
    if (cut > 0 && CFStringIsSurrogateHighCharacter([s characterAtIndex:cut - 1])) cut--;   // kein halbes Paar
    return [s substringToIndex:cut];
}
