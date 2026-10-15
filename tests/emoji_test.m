// Emoji-Erkennung und Satz (MeshEmojiText): jede Folge wird genau ein Bild oder Text, nie ein Kästchen;
// Messen und Zeichnen stimmen überein (Einfügemarke = gemessene Breite der gezeichneten Zeile).
#import "MeshTest.h"
#import "MeshEmojiText.h"

static NSString *u(UTF32Char c) {
    UTF32Char le = NSSwapHostIntToLittle(c);
    return [[NSString alloc] initWithBytes:&le length:4 encoding:NSUTF32LittleEndianStringEncoding];
}

static NSString *cat(NSArray *parts) { return [parts componentsJoinedByString:@""]; }

// Genau ein Emoji-Teil mit genau diesem einen Schlüssel, kein Text daneben
static BOOL one(NSString *text, NSString *key) {
    NSArray *s = [MeshEmojiText segmentsOf:text];
    return s.count == 1 && [s[0] isKindOfClass:[NSArray class]] && [s[0] count] == 1 && [s[0][0] isEqualToString:key]
        && [MeshEmojiText packIndex][key] != nil;
}

static void testSequences(void) {
    NSString *skull = [u(0x2620) stringByAppendingString:u(0xFE0F)];
    check(one(skull, @"2620"), "☠️ (2620 FE0F) = ein Bild");
    check(one(u(0x2620), @"2620"), "☠ (2620 ohne FE0F) = Bild, kein Kästchen");
    check(one([u(0x261D) stringByAppendingString:u(0x1F3FB)], @"261d_1f3fb"), "☝🏻 ohne FE0F = Bild mit Hautfarbe");
    check(one(cat(@[u(0x261D), u(0xFE0F), u(0x1F3FB)]), @"261d_1f3fb"), "☝️🏻 (FE0F vor Hautfarbe) = Bild mit Hautfarbe");
    check(one(cat(@[u(0x1F468), u(0x200D), u(0x1F469), u(0x200D), u(0x1F467)]), @"1f468_200d_1f469_200d_1f467"), "👨‍👩‍👧 = ein Bild");
    check(one(cat(@[@"1", u(0xFE0F), u(0x20E3)]), @"0031_20e3"), "1️⃣ = ein Bild");
    check(one(cat(@[@"1", u(0x20E3)]), @"0031_20e3"), "1⃣ ohne FE0F = ein Bild");
    NSString *scotland = cat(@[u(0x1F3F4), u(0xE0067), u(0xE0062), u(0xE0073), u(0xE0063), u(0xE0074), u(0xE007F)]);
    check(one(scotland, @"1f3f4"), "🏴󠁧󠁢󠁳󠁣󠁴󠁿 ohne eigenes Bild = schwarze Flagge, Tags fallen weg");
    check(one(u(0x1FAC8), @"1fac8"), "U+1FAC8 (neuer als iOS 6) = ein Bild");
    check(one([u(0x2764) stringByAppendingString:u(0xFE0F)], @"2764"), "❤️ = ein Bild");
    check(one([@"©" stringByAppendingString:u(0xFE0F)], @"00a9"), "©️ = ein Bild");

    // Flagge: iOS 6 kennt 🇩🇪 selbst (Text), unbekannte werden zwei Buchstaben-Bilder statt Kästchen
    NSString *de = [u(0x1F1E9) stringByAppendingString:u(0x1F1EA)];
    NSArray *s = [MeshEmojiText segmentsOf:de];
    check(s.count == 1 && [s[0] isEqual:de], "🇩🇪 = Text (Emoji-Schrift von iOS 6)");
    NSString *ua = [u(0x1F1FA) stringByAppendingString:u(0x1F1E6)];
    NSArray *k = [MeshEmojiText keysIn:ua];
    check(k.count == 2 && [k[0] isEqualToString:@"1f1fa"] && [k[1] isEqualToString:@"1f1e6"], "unbekannte Flagge = zwei Buchstaben-Bilder");

    // Text bleibt Text
    s = [MeshEmojiText segmentsOf:@"©"];
    check(s.count == 1 && [s[0] isEqual:@"©"], "© ohne FE0F bleibt Text");
    s = [MeshEmojiText segmentsOf:[u(0x2620) stringByAppendingString:u(0xFE0E)]];
    check(s.count == 1 && [s[0] isEqual:u(0x2620)], "☠︎ (FE0E) bleibt Text, ohne Variantenzeichen");
    s = [MeshEmojiText segmentsOf:[@"a" stringByAppendingString:u(0xFE0F)]];
    check(s.count == 1 && [s[0] isEqual:@"a"], "einzelnes FE0F verschwindet (sonst Kästchen)");
    check(![MeshEmojiText containsEmoji:@"Hallo Welt"], "Text ohne Emoji");
    NSString *arabic = [NSString stringWithFormat:@"%C%C%C", (unichar)0x0644, (unichar)0x200D, (unichar)0x0627];
    s = [MeshEmojiText segmentsOf:arabic];
    check(s.count == 1 && [s[0] isEqual:arabic], "ZWJ in Schrift bleibt");
}

static void testMixed(void) {
    NSString *yallah = cat(@[@"Yallah ", u(0x2620), u(0xFE0F), u(0x2620), u(0xFE0F), u(0x261D), u(0x1F3FB), u(0x261D), u(0x1F3FB)]);
    NSArray *s = [MeshEmojiText segmentsOf:yallah];
    check(s.count == 5 && [s[0] isEqual:@"Yallah "], "Gruppenname: Text + vier Emojis");
    NSArray *keys = [MeshEmojiText keysIn:yallah];
    check([keys isEqualToArray:@[@"2620", @"2620", @"261d_1f3fb", @"261d_1f3fb"]], "Gruppenname: ☠️☠️☝🏻☝🏻 je ein Bild");
    NSString *mixed = cat(@[@"Hi ", u(0x1F44D), u(0x1F3FD), @" und ", u(0x1FAC8), @"!"]);
    s = [MeshEmojiText segmentsOf:mixed];
    check(s.count == 5 && [s[0] isEqual:@"Hi "] && [s[2] isEqual:@" und "] && [s[4] isEqual:@"!"], "Text zwischen Emojis bleibt");
    check([[MeshEmojiText keysIn:mixed] isEqualToArray:@[@"1f44d_1f3fd", @"1fac8"]], "gemischt: richtige Schlüssel");
}

static void testLayout(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 16, NULL);
    NSString *yallah = cat(@[@"Yallah ", u(0x2620), u(0xFE0F), u(0x2620), u(0xFE0F), u(0x261D), u(0x1F3FB), u(0x261D), u(0x1F3FB)]);
    MeshEmojiLayout *one = [[MeshEmojiLayout alloc] initWithText:yallah font:font lineHeight:19 width:CGFLOAT_MAX height:CGFLOAT_MAX lines:1];
    MeshEmojiLayout *text = [[MeshEmojiLayout alloc] initWithText:@"Yallah " font:font lineHeight:19 width:CGFLOAT_MAX height:CGFLOAT_MAX lines:1];
    CGFloat slot = one.emojiSize + 1;
    check(fabs(one.lineWidth - ceil(text.lineWidth - 0.001 + 4 * slot)) <= 1, "Breite = Text + vier Emoji-Plätze");
    __block NSUInteger n = 0;
    __block CGFloat lastRight = 0, right = 0;
    __block BOOL ordered = YES;
    [one drawInContext:NULL rect:CGRectMake(0, 0, 1000, 30) alignment:kCTLeftTextAlignment emoji:^(NSString *key, CGRect f) {
        n++;
        ordered &= f.origin.x >= lastRight - 0.01;
        lastRight = CGRectGetMaxX(f);
        right = MAX(right, CGRectGetMaxX(f));
    }];
    check(n == 4, "vier Bilder gezeichnet");
    check(ordered, "Bilder überlappen nicht");
    check(right <= one.lineWidth + 0.5 && right >= one.lineWidth - slot, "letztes Bild endet an der gemessenen Breite (Einfügemarke)");

    // Gekürzt: passt nicht, endet mit "…" innerhalb der Breite
    MeshEmojiLayout *cut = [[MeshEmojiLayout alloc] initWithText:yallah font:font lineHeight:19 width:80 height:CGFLOAT_MAX lines:1];
    check(cut.truncated && cut.size.width <= 80 && cut.lineCount == 1, "zu lang: eine Zeile mit …");
    // Mehrzeilig in begrenzter Höhe: so viele Zeilen wie passen, die letzte gekürzt
    NSString *longText = [[@[yallah, yallah, yallah, yallah] componentsJoinedByString:@" "] stringByAppendingString:@" Ende"];
    MeshEmojiLayout *two = [[MeshEmojiLayout alloc] initWithText:longText font:font lineHeight:19 width:120 height:45 lines:0];
    check(two.lineCount == 2 && two.truncated && two.size.height <= 46, "Höhe für zwei Zeilen: zwei, letzte gekürzt");
    MeshEmojiLayout *empty = [[MeshEmojiLayout alloc] initWithText:@"" font:font lineHeight:19 width:100 height:100 lines:1];
    check(empty.size.width == 0 && empty.lineWidth == 0, "leer: Breite 0");
    MeshEmojiLayout *space = [[MeshEmojiLayout alloc] initWithText:@"a " font:font lineHeight:19 width:CGFLOAT_MAX height:CGFLOAT_MAX lines:1];
    MeshEmojiLayout *a = [[MeshEmojiLayout alloc] initWithText:@"a" font:font lineHeight:19 width:CGFLOAT_MAX height:CGFLOAT_MAX lines:1];
    check(space.lineWidth > a.lineWidth, "Leerzeichen am Ende zählt für die Einfügemarke");
    CFRelease(font);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [MeshEmojiText setPackDirectory:@"Resources"];
        check([MeshEmojiText packIndex].count > 3000, "Pack-Index gelesen");
        testSequences();
        testMixed();
        testLayout();
        return testsDone();
    }
}
