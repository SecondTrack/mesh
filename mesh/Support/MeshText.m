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
