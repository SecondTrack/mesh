// Eigene Tastatur: Belegung, Großschreibung, Löschen ganzer Zeichen, Emoji-Gruppen und -Text.
#import "MeshTest.h"
#import "MeshKeyboardLayout.h"

static NSString *chars(NSArray *keys, NSUInteger fromRow, CGFloat rowH) {
    NSMutableString *s = [NSMutableString string];
    for (MeshKeySpec *k in keys)
        if (k.kind == MeshKeyChar && (NSUInteger)(CGRectGetMinY(k.hitFrame) / rowH) == fromRow) [s appendString:k.text];
    return s;
}

static NSString *u(UTF32Char c) {
    UTF32Char le = NSSwapHostIntToLittle(c);
    return [[NSString alloc] initWithBytes:&le length:4 encoding:NSUTF32LittleEndianStringEncoding];
}

static NSString *hexOf(NSString *s) {
    NSMutableArray *parts = [NSMutableArray array];
    NSData *d = [s dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    const uint32_t *p = d.bytes;
    for (NSUInteger i = 0; i < d.length / 4; i++) [parts addObject:[NSString stringWithFormat:@"%x", NSSwapLittleIntToHost(p[i])]];
    return [parts componentsJoinedByString:@" "];
}

static void testLayout(void) {
    CGSize size = CGSizeMake(320, 216);
    NSArray *de = [MeshKeyboardLayout keysForPage:MeshKeyPageLetters language:@"de" size:size decimal:nil];
    check([chars(de, 0, 54) isEqualToString:@"qwertzuiopü"], "de Reihe 1 QWERTZ mit ü");
    check([chars(de, 1, 54) isEqualToString:@"asdfghjklöä"], "de Reihe 2 mit ö ä");
    check([chars(de, 2, 54) isEqualToString:@"yxcvbnm"], "de Reihe 3");
    NSArray *en = [MeshKeyboardLayout keysForPage:MeshKeyPageLetters language:@"en" size:size decimal:nil];
    check([chars(en, 0, 54) isEqualToString:@"qwertyuiop"], "en Reihe 1 QWERTY");
    check([chars(en, 2, 54) isEqualToString:@"zxcvbnm"], "en Reihe 3");

    // Jede Seite: Tasten in der Fläche, ohne Überlappung, Trefferflächen lückenlos je Reihe
    MeshKeyPage pages[] = { MeshKeyPageLetters, MeshKeyPageNumbers, MeshKeyPageSymbols, MeshKeyPagePad, MeshKeyPageDecimalPad, MeshKeyPagePhonePad };
    for (int p = 0; p < 6; p++) for (int l = 0; l < 2; l++) {
        NSArray *keys = [MeshKeyboardLayout keysForPage:pages[p] language:l ? @"de" : @"en" size:size decimal:@","];
        BOOL inside = YES, overlap = NO, contains = YES, del = NO;
        for (NSUInteger i = 0; i < keys.count; i++) {
            MeshKeySpec *a = keys[i];
            if (a.kind == MeshKeyDelete) del = YES;
            if (!CGRectContainsRect(CGRectMake(0, 0, 320, 216), a.frame) || a.frame.size.width < 20) inside = NO;
            if (!CGRectContainsRect(a.hitFrame, a.frame)) contains = NO;
            for (NSUInteger j = i + 1; j < keys.count; j++) {
                if (CGRectIntersectsRect(a.frame, [keys[j] frame])) overlap = YES;
                if (CGRectIntersectsRect(a.hitFrame, [keys[j] hitFrame])) overlap = YES;
            }
        }
        // Jeder Punkt der Fläche trifft eine Taste (außer der leeren Zelle im Ziffernblock)
        int misses = 0;
        for (CGFloat y = 1; y < 216; y += 7) for (CGFloat x = 1; x < 320; x += 7) {
            BOOL hit = NO;
            for (MeshKeySpec *k in keys) if (CGRectContainsPoint(k.hitFrame, CGPointMake(x, y))) { hit = YES; break; }
            if (!hit) misses++;
        }
        BOOL padHole = pages[p] == MeshKeyPagePad;
        BOOL good = inside && !overlap && contains && del && (padHole ? misses > 0 && misses < 200 : misses == 0);
        if (!good) printf("  Seite %d/%d: inside %d overlap %d contains %d misses %d\n", p, l, inside, overlap, contains, misses);
        check(good, "Seite: Tasten und Trefferflächen");
    }
    NSArray *num = [MeshKeyboardLayout keysForPage:MeshKeyPageNumbers language:@"de" size:size decimal:nil];
    check([chars(num, 0, 54) isEqualToString:@"1234567890"], "Ziffernreihe");
    check([chars(num, 1, 54) rangeOfString:@"€"].location != NSNotFound, "de Zeichen mit €");
    check([chars(num, 2, 54) isEqualToString:@".,?!'"], "Zeichenreihe 3");
    NSArray *dec = [MeshKeyboardLayout keysForPage:MeshKeyPageDecimalPad language:@"de" size:size decimal:@","];
    check([chars(dec, 3, 54) isEqualToString:@",0"], "Dezimalblock");
    BOOL ret = NO, glob = NO;
    for (MeshKeySpec *k in en) { if (k.kind == MeshKeyReturn) ret = YES; if (k.kind == MeshKeyGlobe) glob = YES; }
    check(ret && glob, "Return und Sprachtaste");

    check([[MeshKeyboardLayout variantsFor:@"s" language:@"de"] containsObject:@"ß"], "ß auf s");
    check([[[MeshKeyboardLayout variantsFor:@"A" language:@"de"] firstObject] isEqualToString:@"ä"], "ä zuerst auf a (de)");
    check([MeshKeyboardLayout variantsFor:@"q" language:@"de"] == nil, "q ohne Varianten");
}

static void testCaps(void) {
    check([MeshKeyboardLayout shouldCapitalizeAfter:@"" mode:MeshAutoCapSentences], "Anfang groß");
    check(![MeshKeyboardLayout shouldCapitalizeAfter:@"Hallo" mode:MeshAutoCapSentences], "im Wort klein");
    check(![MeshKeyboardLayout shouldCapitalizeAfter:@"Hallo " mode:MeshAutoCapSentences], "nach Wort klein");
    check([MeshKeyboardLayout shouldCapitalizeAfter:@"Hallo. " mode:MeshAutoCapSentences], "nach '. ' groß");
    check([MeshKeyboardLayout shouldCapitalizeAfter:@"Echt?  " mode:MeshAutoCapSentences], "nach '?  ' groß");
    check(![MeshKeyboardLayout shouldCapitalizeAfter:@"z.B." mode:MeshAutoCapSentences], "direkt nach Punkt klein");
    check([MeshKeyboardLayout shouldCapitalizeAfter:@"a\n" mode:MeshAutoCapSentences], "nach Zeilenumbruch groß");
    check([MeshKeyboardLayout shouldCapitalizeAfter:@"Anna " mode:MeshAutoCapWords], "Wortanfang groß");
    check(![MeshKeyboardLayout shouldCapitalizeAfter:@"" mode:MeshAutoCapNone], "none nie groß");
    check([MeshKeyboardLayout shouldCapitalizeAfter:@"abc" mode:MeshAutoCapAll], "all immer groß");
}

static NSString *afterDelete(NSString *s) {
    NSRange r = [MeshKeyboardLayout deleteRangeIn:s cursor:s.length];
    return [s stringByReplacingCharactersInRange:r withString:@""];
}

static void testDelete(void) {
    check([afterDelete(@"abc") isEqualToString:@"ab"], "ein Buchstabe");
    check([afterDelete(@"") isEqualToString:@""], "leer");
    NSString *family = [NSString stringWithFormat:@"x%@‍%@‍%@", u(0x1F468), u(0x1F469), u(0x1F467)];
    check([afterDelete(family) isEqualToString:@"x"], "ZWJ-Familie ganz");
    NSString *flags = [NSString stringWithFormat:@"%@%@%@%@", u(0x1F1E9), u(0x1F1EA), u(0x1F1FA), u(0x1F1F8)];
    check([afterDelete(flags) isEqualToString:[NSString stringWithFormat:@"%@%@", u(0x1F1E9), u(0x1F1EA)]], "Flaggenpaar");
    NSString *tone = [NSString stringWithFormat:@"a%@%@", u(0x1F44D), u(0x1F3FD)];
    check([afterDelete(tone) isEqualToString:@"a"], "Hautfarbe mit");
    check([afterDelete(@"a❤️") isEqualToString:@"a"], "Herz mit FE0F");
    check([afterDelete(@"a1️⃣") isEqualToString:@"a"], "Tastenkappe");
    check([afterDelete(@"aé") isEqualToString:@"a"], "e mit Akzent");
    check([afterDelete(@"a\r\n") isEqualToString:@"a"], "CRLF");
    NSString *eng = [NSString stringWithFormat:@"b%@%@%@%@%@%@%@", u(0x1F3F4), u(0xE0067), u(0xE0062), u(0xE0065), u(0xE006E), u(0xE0067), u(0xE007F)];
    check([afterDelete(eng) isEqualToString:@"b"], "Tag-Flagge");
    NSRange mid = [MeshKeyboardLayout deleteRangeIn:@"abc" cursor:2];
    check(mid.location == 1 && mid.length == 1, "mitten im Text");
    NSString *rainbow = [NSString stringWithFormat:@"%@️‍%@", u(0x1F3F3), u(0x1F308)];
    check([afterDelete(rainbow) isEqualToString:@""], "Regenbogenflagge");
}

static void testEmoji(void) {
    check([[MeshKeyboardLayout stringForEmojiKey:@"1f600"] isEqualToString:u(0x1F600)], "Grinsen ohne FE0F");
    check([hexOf([MeshKeyboardLayout stringForEmojiKey:@"2764"]) isEqualToString:@"2764 fe0f"], "Herz mit FE0F");
    check([hexOf([MeshKeyboardLayout stringForEmojiKey:@"231a"]) isEqualToString:@"231a"], "Uhr ohne FE0F (Emoji-Standard)");
    check([hexOf([MeshKeyboardLayout stringForEmojiKey:@"0031_20e3"]) isEqualToString:@"31 fe0f 20e3"], "Tastenkappe vollständig");
    check([hexOf([MeshKeyboardLayout stringForEmojiKey:@"1f468_200d_2764_200d_1f468"]) isEqualToString:@"1f468 200d 2764 fe0f 200d 1f468"], "Paar mit Herz");
    check([hexOf([MeshKeyboardLayout stringForEmojiKey:@"1f3f3_200d_1f308"]) isEqualToString:@"1f3f3 fe0f 200d 1f308"], "Regenbogenflagge");
    check([hexOf([MeshKeyboardLayout stringForEmojiKey:@"1f1e9_1f1ea"]) isEqualToString:@"1f1e9 1f1ea"], "Flagge DE");

    check([MeshKeyboardLayout isHiddenEmojiKey:@"1f44d_1f3fd"], "Hautfarbe versteckt");
    check([MeshKeyboardLayout isHiddenEmojiKey:@"0031"], "nackte Ziffer versteckt");
    check([MeshKeyboardLayout isHiddenEmojiKey:@"1f1e9"], "halbe Flagge versteckt");
    check(![MeshKeyboardLayout isHiddenEmojiKey:@"1f44d"], "Daumen sichtbar");

    check([MeshKeyboardLayout groupForEmojiKey:@"1f600"] == MeshEmojiSmileys, "Smiley");
    check([MeshKeyboardLayout groupForEmojiKey:@"1f436"] == MeshEmojiNature, "Hund");
    check([MeshKeyboardLayout groupForEmojiKey:@"1f354"] == MeshEmojiFood, "Burger");
    check([MeshKeyboardLayout groupForEmojiKey:@"26bd"] == MeshEmojiActivities, "Fußball");
    check([MeshKeyboardLayout groupForEmojiKey:@"1f697"] == MeshEmojiTravel, "Auto");
    check([MeshKeyboardLayout groupForEmojiKey:@"1f4a1"] == MeshEmojiObjects, "Glühbirne");
    check([MeshKeyboardLayout groupForEmojiKey:@"2764"] == MeshEmojiSymbols, "Herz");
    check([MeshKeyboardLayout groupForEmojiKey:@"1f1e9_1f1ea"] == MeshEmojiFlags, "Flagge");
    check([MeshKeyboardLayout groupForEmojiKey:@"1f3f4_e0067_e0062_e0065_e006e_e0067_e007f"] == MeshEmojiFlags, "Tag-Flagge");
    check([MeshKeyboardLayout groupForEmojiKey:@"1f9d1_200d_1f4bb"] == MeshEmojiSmileys, "Person am Rechner");

    // Echter Index: jede Gruppe gefüllt, nichts doppelt, keine Hautfarben, Text zurück erkennbar
    NSString *idx = [NSString stringWithContentsOfFile:@"Resources/emoji.idx" encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *line in [idx componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@" "];
        if (f.count == 3) [keys addObject:f[0]];
    }
    check(keys.count > 3000, "emoji.idx gelesen");
    NSArray *groups = [MeshKeyboardLayout groupEmojiKeys:keys];
    check(groups.count == MeshEmojiGroupCount && MeshEmojiGroupCount == 9, "neun Gruppen (mit Frosch)");
    NSUInteger total = 0;
    BOOL filled = YES, tones = NO;
    NSMutableSet *seen = [NSMutableSet set];
    for (NSArray *g in groups) {
        if (g.count < (g == groups[MeshEmojiFlags] ? 5 : g == groups[MeshEmojiFrog] ? 18 : 20)) filled = NO;
        total += g.count;
        for (NSString *k in g) { [seen addObject:k]; if ([k rangeOfString:@"1f3fb"].location != NSNotFound || [k rangeOfString:@"1f3ff"].location != NSNotFound) tones = YES; }
    }
    check(filled, "jede Gruppe hat Emojis");
    check(!tones, "keine Hautfarben im Raster");
    check(seen.count == total && total > 1500 && total < keys.count, "sichtbare Emojis eindeutig");
    check([groups[MeshEmojiFlags] containsObject:@"1f3f3_200d_1f308"], "Flaggen da");
    printf("  Emojis je Gruppe:");
    for (NSArray *g in groups) printf(" %lu", (unsigned long)g.count);
    printf("\n");
    // Jeder Text löscht sich mit einem ⌫ ganz
    BOOL whole = YES;
    for (NSArray *g in groups) for (NSString *k in g) {
        NSString *s = [@"a" stringByAppendingString:[MeshKeyboardLayout stringForEmojiKey:k]];
        NSRange r = [MeshKeyboardLayout deleteRangeIn:s cursor:s.length];
        if (r.location != 1) { whole = NO; printf("  Löschen zerteilt %s\n", k.UTF8String); break; }
    }
    check(whole, "jedes Emoji mit einem Löschen weg");
}

// Eigene Emojis (Teil C): Gruppe "Frosch" mit der Liste v1 in ihrer Reihenfolge, Text = Code, ⌫ = ganzer Code
static void testFrog(void) {
    NSArray *spec = @[@"frosch_grinsen", @"frosch_traenenlachen", @"frosch_herzaugen", @"frosch_schmunzeln", @"frosch_kuss",
                      @"frosch_schrei", @"frosch_angstschweiss", @"frosch_grimmig", @"frosch_verliebt", @"frosch_cool",
                      @"frosch_clown", @"frosch_schnauben", @"frosch_staunen", @"frosch_heulen", @"frosch_traurig",
                      @"frosch_denken", @"frosch_invader", @"frosch_roboter"];
    NSArray *groups = [MeshKeyboardLayout groupEmojiKeys:@[@"1f600", @"frosch_cool", @"2764"]];
    check([groups[MeshEmojiFrog] isEqualToArray:spec], "Frosch-Gruppe = Liste v1 in Reihenfolge");
    check([groups[MeshEmojiSmileys] isEqualToArray:@[@"1f600"]] && [groups[MeshEmojiSymbols] isEqualToArray:@[@"2764"]],
          "Frösche nicht in anderen Gruppen");
    check([MeshKeyboardLayout groupForEmojiKey:@"frosch_kuss"] == MeshEmojiFrog, "Frosch-Schlüssel -> Gruppe Frosch");
    check(![MeshKeyboardLayout isHiddenEmojiKey:@"frosch_kuss"], "Frosch sichtbar");
    check([MeshKeyboardLayout codepointsForEmojiKey:@"frosch_kuss"].count == 0, "Frosch hat keine Codepunkte");
    check([[MeshKeyboardLayout stringForEmojiKey:@"frosch_kuss"] isEqualToString:@":frosch_kuss:"], "Tippen fügt den Code ein");

    NSString *s = @"Hi :frosch_kuss::frosch_cool:";
    NSRange r = [MeshKeyboardLayout deleteRangeIn:s cursor:s.length];
    check(NSEqualRanges(r, NSMakeRange(16, 13)), "⌫ löscht den ganzen letzten Code");
    r = [MeshKeyboardLayout deleteRangeIn:s cursor:16];
    check(NSEqualRanges(r, NSMakeRange(3, 13)), "⌫ vor dem zweiten Code löscht den ersten ganz");
    r = [MeshKeyboardLayout deleteRangeIn:@"a :frosch_x:" cursor:12];
    check(r.length == 1, "unbekannter Code: nur ein Zeichen");
    r = [MeshKeyboardLayout deleteRangeIn:@":frosch_kuss:frosch_cool:" cursor:25];
    check(r.length == 1, "\":frosch_cool:\" ohne eigenen Anfang (Rest nach erstem Code) ist Text");
    r = [MeshKeyboardLayout deleteRangeIn:@"x:)" cursor:3];
    check(r.length == 1, "\":)\" bleibt Text");
}

int main(void) {
    @autoreleasepool {
        testLayout();
        testCaps();
        testDelete();
        testEmoji();
        testFrog();
    }
    return testsDone();
}
