// Eingabefelder (MeshEmojiField): Einfügen, ⌫ ganzer Emoji-Folgen, Alles auswählen, Einfügen aus der
// Zwischenablage, Delegate-Frage vor jeder Änderung (Bereiche in UTF-16, Längengrenzen).
#import "MeshTest.h"
#import "MeshLineText.h"

static NSString *u(UTF32Char c) {
    UTF32Char le = NSSwapHostIntToLittle(c);
    return [[NSString alloc] initWithBytes:&le length:4 encoding:NSUTF32LittleEndianStringEncoding];
}

static void testInsertDelete(void) {
    MeshLineText *t = [[MeshLineText alloc] init];
    check([t.text isEqualToString:@""], "leer, nie nil");
    check(![t deleteBackward], "⌫ auf leerem Feld ändert nichts");
    check([t insert:@"Hi "], "einfügen");
    NSString *bigfoot = u(0x1FAC8);   // neuer als die iOS-6-Schrift
    check([t insert:bigfoot], "neues Emoji einfügen");
    check([t.text isEqualToString:[@"Hi " stringByAppendingString:bigfoot]], "Text am Ende");
    check(t.selectedRange.location == t.text.length && t.selectedRange.length == 0, "Einfügemarke am Ende");
    check([t deleteBackward] && [t.text isEqualToString:@"Hi "], "⌫ löscht Ersatzpaar ganz");

    NSString *family = [@[u(0x1F468), @"‍", u(0x1F469), @"‍", u(0x1F467)] componentsJoinedByString:@""];
    [t insert:family];
    check([t deleteBackward] && [t.text isEqualToString:@"Hi "], "⌫ löscht ZWJ-Familie ganz");
    NSString *thumb = [u(0x1F44D) stringByAppendingString:u(0x1F3FD)];
    [t insert:thumb];
    check([t deleteBackward] && [t.text isEqualToString:@"Hi "], "⌫ löscht Emoji mit Hautfarbe ganz");
    NSString *flag = [u(0x1F1E9) stringByAppendingString:u(0x1F1EA)];
    [t insert:[flag stringByAppendingString:flag]];
    check([t deleteBackward] && [t.text isEqualToString:[@"Hi " stringByAppendingString:flag]], "⌫ löscht ein Flaggenpaar");
    NSString *heart = @"❤️";
    t.text = heart;
    check([t deleteBackward] && !t.text.length, "⌫ löscht Zeichen mit Variantenwahl ganz");
    t.text = @"ab";
    check([t deleteBackward] && [t.text isEqualToString:@"a"], "⌫ löscht einen Buchstaben");

    // Eigenes Emoji: ein Code ist eine Einheit
    t.text = @"Hi ";
    check([t insert:@":frosch_kuss:"] && [t insert:@":frosch_cool:"], "Frosch-Codes einfügen");
    check([t deleteBackward] && [t.text isEqualToString:@"Hi :frosch_kuss:"], "⌫ löscht den ganzen Frosch-Code");
    check([t deleteBackward] && [t.text isEqualToString:@"Hi "], "⌫ löscht auch den nächsten ganz");
    t.text = @"Hi :frosch_x:";
    check([t deleteBackward] && [t.text isEqualToString:@"Hi :frosch_x"], "unbekannter Code: ⌫ löscht ein Zeichen");
}

static void testSelection(void) {
    MeshLineText *t = [[MeshLineText alloc] init];
    t.allSelected = YES;
    check(!t.allSelected, "ohne Text keine Auswahl");
    t.text = @"alt";
    t.allSelected = YES;
    check(t.selectedRange.location == 0 && t.selectedRange.length == 3, "Auswahl umfasst alles");
    [t insert:@"n"];
    check([t.text isEqualToString:@"n"] && !t.allSelected, "Tippen ersetzt die Auswahl");
    t.allSelected = YES;
    check([t deleteBackward] && !t.text.length, "⌫ leert die Auswahl");
    t.text = @"x";
    t.allSelected = YES;
    t.text = @"y";
    check(!t.allSelected, "neuer Text hebt Auswahl auf");
}

static void testLines(void) {
    MeshLineText *t = [[MeshLineText alloc] init];
    t.text = @"a\nb\r\nc\td";
    check([t.text isEqualToString:@"a b c d"], "Setter macht einzeilig");
    check(![t insert:@""], "leeres Einfügen ändert nichts");
    NSString *ls = [NSString stringWithFormat:@"x%Cy%Cz", (unichar)0x2028, (unichar)0x85];
    check([[MeshLineText singleLine:ls] isEqualToString:@"x y z"], "LS und NEL werden Leerzeichen");
}

static void testPaste(void) {
    NSString *rlo = [NSString stringWithFormat:@"ab%Ccd%C%C", (unichar)0x202E, (unichar)0x200B, (unichar)0xFEFF];
    check([[MeshLineText pasteText:rlo max:100] isEqualToString:@"abcd"], "Schreibrichtung und Unsichtbares raus");
    NSString *ctl = [NSString stringWithFormat:@"a%Cb%Cc\nd", (unichar)0x07, (unichar)0x1B];
    check([[MeshLineText pasteText:ctl max:100] isEqualToString:@"abc d"], "Steuerzeichen raus, Zeilen zu Leerzeichen");
    NSString *family = [@[u(0x1F468), @"‍", u(0x1F469)] componentsJoinedByString:@""];
    check([[MeshLineText pasteText:family max:100] isEqualToString:family], "ZWJ bleibt");
    NSString *england = [@[u(0x1F3F4), u(0xE0067), u(0xE0062), u(0xE0065), u(0xE006E), u(0xE0067), u(0xE007F)] componentsJoinedByString:@""];
    check([[MeshLineText pasteText:england max:100] isEqualToString:england], "Tag-Folge (Flagge England) bleibt");
    check([[MeshLineText pasteText:nil max:100] isEqualToString:@""], "nil ergibt leer");
    check([[MeshLineText pasteText:(id)@42 max:100] isEqualToString:@""], "kein String ergibt leer");
    NSString *two = [u(0x1F600) stringByAppendingString:u(0x1F600)];
    check([[MeshLineText pasteText:two max:3] isEqualToString:u(0x1F600)], "Kürzen zerschneidet kein Emoji");

    MeshLineText *t = [[MeshLineText alloc] init];
    t.text = @"Hallo ";
    check([t paste:@"Welt\n!"] && [t.text isEqualToString:@"Hallo Welt !"], "Einfügen hängt bereinigt an");
    t.allSelected = YES;
    check([t paste:@"neu"] && [t.text isEqualToString:@"neu"], "Einfügen ersetzt die Auswahl");
    check(![t paste:[NSString stringWithFormat:@"%C", (unichar)0x202E]], "nur Unsichtbares ändert nichts");

    NSUInteger max = [MeshLineText maxLength];
    NSString *big = [@"" stringByPaddingToLength:max + 50 withString:@"x" startingAtIndex:0];
    t.text = @"";
    [t paste:big];
    check(t.text.length == max, "Feld bleibt unter der Obergrenze");
    check(![t insert:@"y"], "voll: Tippen ändert nichts");
}

// Wie textField:shouldChangeCharactersInRange:replacementString: (UTF-16 des bisherigen Texts)
static void testShouldChange(void) {
    MeshLineText *t = [[MeshLineText alloc] init];
    __block NSRange lastRange = NSMakeRange(NSNotFound, 0);
    __block NSString *lastRepl = nil;
    __block int asks = 0;
    MeshLineText *__weak wt = t;
    // Grenze von 5 UTF-16-Einheiten, wie ein Aufrufer sie prüfen würde
    t.shouldChange = ^BOOL(NSRange r, NSString *s) {
        asks++; lastRange = r; lastRepl = s;
        return [wt.text stringByReplacingCharactersInRange:r withString:s].length <= 5;
    };
    t.text = @"ab";
    check(asks == 0, "Setzen von text fragt nicht");
    check([t insert:@"c"] && [t.text isEqualToString:@"abc"], "erlaubtes Tippen");
    check(lastRange.location == 2 && lastRange.length == 0 && [lastRepl isEqualToString:@"c"], "Bereich am Ende, Länge 0");
    NSString *bigfoot = u(0x1FAC8);
    check([t insert:bigfoot] && t.text.length == 5, "Emoji (2 Einheiten) passt noch");
    check(lastRange.location == 3 && [lastRepl isEqualToString:bigfoot], "Bereich zählt UTF-16");
    check(![t insert:@"d"] && t.text.length == 5, "über der Grenze abgelehnt");
    check([t deleteBackward] && [t.text isEqualToString:@"abc"], "⌫ erlaubt");
    check(lastRange.location == 3 && lastRange.length == 2 && [lastRepl isEqualToString:@""], "⌫ fragt nach dem ganzen Ersatzpaar");
    check(![t insert:[bigfoot stringByAppendingString:@"x"]] && [t.text isEqualToString:@"abc"], "zu langes Emoji+Text abgelehnt, Text bleibt");
    t.allSelected = YES;
    check([t insert:@"neu"] && [t.text isEqualToString:@"neu"], "Auswahl ersetzen");
    check(lastRange.location == 0 && lastRange.length == 3, "Bereich umfasst die Auswahl");
    t.allSelected = YES;
    check([t deleteBackward] && !t.text.length && lastRange.length == 3, "⌫ auf Auswahl fragt nach allem");
    check([t paste:@"a\nb"] && [t.text isEqualToString:@"a b"], "Einfügen erlaubt");
    check([lastRepl isEqualToString:@"a b"], "Einfügen fragt mit bereinigtem Text");
    check(![t paste:@"12345"] && [t.text isEqualToString:@"a b"], "Einfügen über der Grenze abgelehnt");

    // Alles ablehnen: nichts ändert sich
    t.shouldChange = ^BOOL(NSRange r, NSString *s) { return NO; };
    check(![t insert:@"x"] && ![t deleteBackward] && ![t paste:@"y"] && [t.text isEqualToString:@"a b"], "abgelehnt: Text bleibt");

    // Delegate setzt selbst (wie die sicheren Felder) und lehnt ab: dessen Stand gilt, keine doppelte Änderung
    t.shouldChange = ^BOOL(NSRange r, NSString *s) {
        wt.text = [[wt.text stringByReplacingCharactersInRange:r withString:s] uppercaseString];
        return NO;
    };
    check(![t insert:@"c"] && [t.text isEqualToString:@"A BC"], "selbst gesetzter Text gilt");
    t.shouldChange = ^BOOL(NSRange r, NSString *s) { wt.text = @"z"; return YES; };
    check(![t insert:@"q"] && [t.text isEqualToString:@"z"], "gesetzt und YES: nicht zusätzlich anhängen");
    t.shouldChange = nil;
    check([t insert:@"!"] && [t.text isEqualToString:@"z!"], "ohne Block alles erlaubt");
}

int main(void) {
    @autoreleasepool {
        testInsertDelete();
        testSelection();
        testLines();
        testPaste();
        testShouldChange();
        return testsDone();
    }
}
