// Passphrasen: Wortliste vollständig, Würfeln gleichverteilt genug, Eingaben vereinheitlicht.
#import "MeshTest.h"
#import "MeshPassphrase.h"

int main(void) { @autoreleasepool {
    [MeshPassphrase setWordListDirectory:@"Resources"];
    for (NSString *lang in [MeshPassphrase languages]) {
        NSArray *list = [MeshPassphrase wordListForLanguage:lang];
        check(list.count == 7776 && [NSSet setWithArray:list].count == 7776, "7776 distinct words");
        BOOL plain = YES;   // die Eingabe ignoriert alles außer Buchstaben: Listenwörter müssen das überstehen
        for (NSString *w in list) plain &= [[MeshPassphrase normalize:w] isEqualToString:w];
        check(plain, "words survive normalize");
        NSArray *five = [MeshPassphrase randomWords:5 language:lang];
        check(five.count == 5 && ![five isEqualToArray:[MeshPassphrase randomWords:5 language:lang]], "random words");
        NSMutableSet *seen = [NSMutableSet set];
        for (int i = 0; i < 400; i++) [seen addObjectsFromArray:[MeshPassphrase randomWords:5 language:lang]];
        check(seen.count > 1700, "spread over the list");
    }
    check([MeshPassphrase wordListForLanguage:@"xx"] == nil && [MeshPassphrase randomWords:5 language:@"xx"] == nil, "unknown language");
    check([MeshPassphrase knownWordsIn:@"abacus aalen quatschwort"] == 2, "known words of both lists");
    check([[MeshPassphrase normalize:@"  Aalen,  ABARBEITEN\nabartig  "] isEqualToString:@"aalen abarbeiten abartig"], "normalize");
    check([MeshPassphrase knownWordsIn:@"aalen abarbeiten quatschwort"] == 2, "known words");
    check(fabs([MeshPassphrase bitsForWords:5] - 64.62) < 0.01, "bits");
    return testsDone();
}}
