// Namen bereinigen, Kürzen ohne zerschnittene Emoji.
#import "MeshTest.h"
#import "MeshText.h"

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

    return testsDone();
}}
