// Namen bereinigen, Kürzen ohne zerschnittene Emoji.
#import "MeshTest.h"
#import "MeshText.h"

// Ein Code Point als Text (auch über U+FFFF); CAT fügt Stücke zusammen.
static NSString *U(uint32_t cp) {
    if (cp < 0x10000) { unichar c = (unichar)cp; return [NSString stringWithCharacters:&c length:1]; }
    cp -= 0x10000;
    unichar pair[2] = { (unichar)(0xD800 + (cp >> 10)), (unichar)(0xDC00 + (cp & 0x3FF)) };
    return [NSString stringWithCharacters:pair length:2];
}
#define CAT(...) [@[__VA_ARGS__] componentsJoinedByString:@""]

int main(void) { @autoreleasepool {
    check([MeshCleanName(@"  Alice  ") isEqualToString:@"Alice"], "trim");
    check([MeshCleanName(@"Al‮ecila") isEqualToString:@"Alecila"], "RLO removed");
    check([MeshCleanName(@"Bo​b⁦⁩") isEqualToString:@"Bob"], "zero width + isolates");
    check([MeshCleanName(@"A\nB\tC\x01") isEqualToString:@"A B C"], "control chars");
    check([MeshCleanName(@"Grüße 👋") isEqualToString:@"Grüße 👋"], "keeps normal text");

    NSString *e = @"ab👋cd";                       // 👋 = 2 UTF-16-Einheiten an Index 2–3
    NSString *t = MeshTruncate(e, 3);
    check([t isEqualToString:@"ab"] && [t dataUsingEncoding:NSUTF8StringEncoding], "no half emoji");
    check([MeshTruncate(e, 4) isEqualToString:@"ab👋"], "whole emoji kept");
    check([MeshTruncate(@"kurz", 10) isEqualToString:@"kurz"], "short unchanged");
    NSString *flags = @"🇩🇪🇩🇪";                     // je 4 UTF-16-Einheiten
    check([MeshTruncate(flags, 5) isEqualToString:@"🇩🇪"], "flag not split");

    check([MeshStripInvisible(@"a\u202Eb\nc\u200Bd") isEqualToString:@"ab\ncd"], "strip invisible keeps lines");

    // B8.6: Cc + Cf weg (außer ZWJ), Rand-Leerzeichen weg, Folgen innen bleiben; Länge in UTF-16
    check([MeshCleanGroupText(@"  Anna  Ben \t") isEqualToString:@"Anna  Ben"], "B8.6 trim, inner runs kept");
    check([MeshCleanGroupText(CAT(@"An", U(0xAD), @"na")) isEqualToString:@"Anna"], "B8.6 U+00AD soft hyphen removed");
    check([MeshCleanGroupText(CAT(@"An", U(0x2060), @"na", U(0x2061), U(0x2064))) isEqualToString:@"Anna"], "B8.6 U+2060-2064 removed");
    check([MeshCleanGroupText(CAT(U(0x61C), @"A", U(0x180E), @"B", U(0x200B), @"C", U(0x200C), @"D", U(0x200E), @"E", U(0x200F), @"F", U(0x202A), @"G", U(0x202E), @"H", U(0x2066), @"I", U(0x2069), @"J", U(0xFEFF), @"K")) isEqualToString:@"ABCDEFGHIJK"],
          "B8.6 ALM, MVS, ZW*, LRM/RLM, embeddings, isolates, BOM removed");
    NSString *family = CAT(U(0x1F468), U(0x200D), U(0x1F469), U(0x200D), U(0x1F467));
    check(family.length == 8 && [MeshCleanGroupText(family) isEqualToString:family], "B8.6 ZWJ kept (emoji sequence)");
    check([MeshCleanGroupText(CAT(@"A", U(0x0A), @"B", U(0x0D), @"C", U(0x01), U(0x7F), U(0x85), @"D")) isEqualToString:@"ABCD"], "B8.6 Cc removed, not replaced by spaces");
    check([MeshCleanGroupText(CAT(U(0xA0), U(0x3000), @" X ", U(0x2028))) isEqualToString:@"X"], "B8.6 Zs/Zl at the edges trimmed");
    check([MeshCleanGroupText(CAT(U(0x200B), @"  ", U(0xAD), @" ")) isEqualToString:@""], "B8.6 only invisible -> empty");
    check([MeshCleanGroupText(CAT(@"a", U(0xE0041), @"b")) isEqualToString:@"ab"], "B8.6 Cf above U+FFFF (tag) removed");
    check([MeshCleanGroupText(CAT(@"a", U(0x1D173), @"b")) isEqualToString:@"ab"], "B8.6 musical format char removed");
    check([MeshCleanGroupText(@"Grüße 👋") isEqualToString:@"Grüße 👋"], "B8.6 normal text kept");
    unichar lone[] = { 'a', 0xD83D, 'b' };
    NSString *half = MeshCleanGroupText([NSString stringWithCharacters:lone length:3]);
    check([half isEqualToString:@"ab"] && [half dataUsingEncoding:NSUTF8StringEncoding], "lone surrogate dropped");
    check([MeshTruncateUTF16(@"ab👋cd", 3) isEqualToString:@"ab"], "B8.6 cut not inside a surrogate pair");
    check([MeshTruncateUTF16(@"ab👋cd", 4) isEqualToString:@"ab👋"], "B8.6 cut after the pair");
    check([MeshTruncateUTF16(CAT(@"ab", U(0x301), @"cd"), 3) isEqualToString:CAT(@"ab", U(0x301))] && MeshTruncateUTF16(@"x", 5).length == 1,
          "B8.6 counts UTF-16 units only");
    check(MeshCleanGroupText((NSString *)@12).length == 0, "non-string -> empty");

    return testsDone();
}}
