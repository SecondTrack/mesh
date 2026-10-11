// Kontakt-Codes: npub, nostr:-URI, Hex, Mesh-Code der Android-App mit .onion und Bundle,
// Großschreibung aus QR-Codes, Ungültiges.
#import "MeshTest.h"
#import "MeshContactCode.h"

int main(void) { @autoreleasepool {
    NSString *npub = @"npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6";
    NSString *hex = MeshPubkeyFromContactInput(npub);
    check(hex.length == 64, "npub");
    check([MeshPubkeyFromContactInput([@"nostr:" stringByAppendingString:npub]) isEqualToString:hex], "nostr: URI");
    check([MeshPubkeyFromContactInput([[@"nostr:" stringByAppendingString:npub] uppercaseString]) isEqualToString:hex], "uppercase QR");
    check([MeshPubkeyFromContactInput([NSString stringWithFormat:@"  %@\n", npub]) isEqualToString:hex], "whitespace trimmed");
    check([MeshPubkeyFromContactInput([hex uppercaseString]) isEqualToString:hex], "hex, any case");
    check(!MeshPubkeyFromContactInput([npub stringByReplacingCharactersInRange:NSMakeRange(10, 1) withString:@"q"]), "bad checksum");
    check(!MeshPubkeyFromContactInput(@"nsec180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"), "nsec rejected");
    check(!MeshPubkeyFromContactInput([hex substringToIndex:63]) && !MeshPubkeyFromContactInput(@"zz"), "short or garbage");
    check(!MeshPubkeyFromContactInput([[hex substringToIndex:63] stringByAppendingString:@"g"]), "non-hex");

    // Mesh-Code der Android-App
    NSString *onion = @"abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion";
    NSString *bundle = @"AAAx_Yz-QWErty";
    NSString *code = [NSString stringWithFormat:@"mesh:%@?node=%@&sig=%@", npub, onion, bundle];   // wie Android
    check([[MeshContactCode codeWithNpub:npub bundle:bundle] isEqualToString:[NSString stringWithFormat:@"mesh:%@?sig=%@", npub, bundle]], "build code");
    MeshContactCode *c = [MeshContactCode parse:code];
    check([c.pubkey isEqualToString:hex] && [c.bundle isEqualToString:bundle], "parse Android code, bundle case kept");
    check([[MeshContactCode codeWithNpub:npub bundle:nil] isEqualToString:[@"mesh:" stringByAppendingString:npub]], "code without extras");
    c = [MeshContactCode parse:[NSString stringWithFormat:@"MESH:%@?sig=%@", npub, bundle]];
    check([c.pubkey isEqualToString:hex] && [c.bundle isEqualToString:bundle], "only bundle");
    c = [MeshContactCode parse:[NSString stringWithFormat:@"mesh:%@?node=../../evil.onion", npub]];
    check(c && !c.bundle, "node ignored");
    check(![MeshContactCode parse:[code stringByPaddingToLength:1100 withString:@"x" startingAtIndex:0]], "too long");
    return testsDone();
}}
