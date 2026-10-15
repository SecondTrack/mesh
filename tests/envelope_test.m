// Umschlag einer DM im Format der Android-App: Kopfzeilen, Steueranweisungen, Rundweg,
// feindliche Eingaben. Die Beispiele entsprechen dem, was MeshNostr.kt baut.
#import "MeshTest.h"
#import "MeshEnvelope.h"

static void testMessages(void) {
    MeshEnvelope *e = [MeshEnvelope parse:@"Hallo"];
    check(e.type == MeshEnvelopeMessage && [e.content isEqualToString:@"Hallo"] && !e.cmid.length, "plain text");

    // encryptFor: META + Bundle + .onion + Text
    e = [MeshEnvelope parse:@"\1mesh:x:0123456789abcdef|r=fedcba9876543210|tr=300\n\1mesh:mb:QUJD\nmesh:on:abc.onion\nHi"];
    check(e.type == MeshEnvelopeMessage && [e.content isEqualToString:@"Hi"], "android message");
    check([e.cmid isEqualToString:@"0123456789abcdef"] && [e.replyTo isEqualToString:@"fedcba9876543210"], "cmid and reply");
    check(e.timer == 300 && e.timerMode == MeshTimerFromRead, "timer from read");
    check([e.bundle isEqualToString:@"QUJD"], "bundle read, onion line stripped");
    check([MeshEnvelope parse:@"\1mesh:x:aa|t=60\nx"].timerMode == MeshTimerFromSent, "timer from sent");

    NSString *built = [MeshEnvelope message:@"Text\nmit Umbruch" cmid:@"1111222233334444" replyTo:@"5555666677778888"
                                      timer:86400 mode:MeshTimerFromSent bundle:@"BUNDLE"];
    check([built isEqualToString:@"\1mesh:x:1111222233334444|r=5555666677778888|t=86400\n\1mesh:mb:BUNDLE\nText\nmit Umbruch"], "build message");
    e = [MeshEnvelope parse:built];
    check([e.content isEqualToString:@"Text\nmit Umbruch"] && e.timer == 86400 && [e.bundle isEqualToString:@"BUNDLE"], "message roundtrip");
    check([[MeshEnvelope message:@"x" cmid:@"" replyTo:@"" timer:0 mode:MeshTimerFromRead bundle:nil] isEqualToString:@"x"], "no header");

    e = [MeshEnvelope parse:@"\1mesh:file:a.pdf\1application/pdf\nAAAA"];
    check(e.type == MeshEnvelopeMessage, "file is a message");
    check([MeshEnvelope newMessageId].length == 16 && ![[MeshEnvelope newMessageId] isEqualToString:[MeshEnvelope newMessageId]], "message id");
}

static void testControls(void) {
    MeshEnvelope *e = [MeshEnvelope parse:[MeshEnvelope reactionTo:@"abcd" emoji:@"👍"]];
    check(e.type == MeshEnvelopeReaction && [e.target isEqualToString:@"abcd"] && [e.emoji isEqualToString:@"👍"], "reaction");
    e = [MeshEnvelope parse:@"\1mesh:rx:abcd|"];
    check(e.type == MeshEnvelopeReaction && e.emoji.length == 0, "reaction removed");
    check([MeshEnvelope parse:@"\1mesh:rx:abcd"].type == MeshEnvelopeIgnored, "reaction without bar");

    e = [MeshEnvelope parse:[MeshEnvelope deletionOf:@"abcd"]];
    check(e.type == MeshEnvelopeDelete && [e.target isEqualToString:@"abcd"], "delete");
    check([MeshEnvelope parse:@"\1mesh:del:"].type == MeshEnvelopeIgnored, "delete without target");
    check([MeshEnvelope parse:[MeshEnvelope clearChat]].type == MeshEnvelopeClear, "clear");

    e = [MeshEnvelope parse:[MeshEnvelope timer:3600 mode:MeshTimerFromSent]];
    check(e.type == MeshEnvelopeTimer && e.timer == 3600 && e.timerMode == MeshTimerFromSent, "timer");
    e = [MeshEnvelope parse:@"\1mesh:ttls:30"];
    check(e.type == MeshEnvelopeTimer && e.timer == 30 && e.timerMode == MeshTimerFromRead, "timer old form");
    check([MeshEnvelope parse:@"\1mesh:ttls:-9|read"].timer == 0, "negative timer");

    e = [MeshEnvelope parse:[MeshEnvelope helloWithBundle:@"QUJD"]];
    check(e.type == MeshEnvelopeHello && [e.bundle isEqualToString:@"QUJD"], "hello");
    check([MeshEnvelope parse:@"mesh:hi:"].type == MeshEnvelopeHello, "hello without bundle");
    e = [MeshEnvelope parse:[MeshEnvelope picture:@"/9j/AAAA"]];
    check(e.type == MeshEnvelopePicture && [e.picture isEqualToString:@"/9j/AAAA"], "picture");
    check([[MeshEnvelope picture:@"QQ=="] isEqualToString:@"\1mesh:pic:QQ=="], "picture marker like android");
    e = [MeshEnvelope parse:@"\1mesh:pic:"];
    check(e.type == MeshEnvelopePicture && e.picture.length == 0, "picture removed");
    e = [MeshEnvelope parse:@"\1mesh:mb:QUJD\nmesh:on:abc.onion\n\1mesh:pic:QQ=="];
    check(e.type == MeshEnvelopePicture && [e.bundle isEqualToString:@"QUJD"], "picture after android prefix");

    // Steueranweisung hinter einem Bundle (Android über NIP-44 ohne Session)
    e = [MeshEnvelope parse:@"\1mesh:mb:QUJD\n\1mesh:rx:abcd|❤️"];
    check(e.type == MeshEnvelopeReaction && [e.bundle isEqualToString:@"QUJD"], "control after bundle");
}

static void testChunks(void) {
    // sendFileChunks: fileId|index|total|b64(mime)|b64(name)|thumb\n<chunk>
    MeshEnvelope *e = [MeshEnvelope parse:@"\1mesh:fc:00112233aabbccdd|0|3|dmlkZW8vbXA0|Y2xpcC5tcDQ=|THUMB\nQ0hVTks="];
    check(e.type == MeshEnvelopeFileChunk, "chunk");
    check([e.fileId isEqualToString:@"00112233aabbccdd"] && e.chunkIndex == 0 && e.chunkCount == 3, "chunk header");
    check([e.fileMime isEqualToString:@"video/mp4"] && [e.fileName isEqualToString:@"clip.mp4"], "chunk name");
    check([e.thumbnail isEqualToString:@"THUMB"] && [e.chunk isEqualToString:@"Q0hVTks="], "chunk body");
    check([MeshEnvelope parse:@"\1mesh:fc:../../db|0|1|eA==|eA==\nAA=="].type == MeshEnvelopeIgnored, "path in file id");
    check([MeshEnvelope parse:@"\1mesh:fc:00112233aabbccdd|3|3|eA==|eA==\nAA=="].type == MeshEnvelopeIgnored, "index beyond count");
    check([MeshEnvelope parse:@"\1mesh:fc:00112233aabbccdd|0|1\nAA=="].type == MeshEnvelopeIgnored, "short header");
}

static void testHostile(void) {
    check([MeshEnvelope parse:@""].type == MeshEnvelopeIgnored, "empty");
    check([MeshEnvelope parse:nil].type == MeshEnvelopeIgnored, "nil");
    check([MeshEnvelope parse:@"\1mesh:x:abc\n"].type == MeshEnvelopeIgnored, "only header");
    check([MeshEnvelope parse:@"Text mit \1mesh:rx: drin"].type == MeshEnvelopeIgnored, "marker inside text");
    check([MeshEnvelope parse:@"\1mesh:unbekannt:xyz"].type == MeshEnvelopeIgnored, "unknown control");
    check([MeshEnvelope parse:@"mesh:x:kein-soh\nText"].type == MeshEnvelopeMessage, "without SOH is text");
    MeshEnvelope *e = [MeshEnvelope parse:@"\1mesh:x:abc"];   // ohne Zeilenende kein Kopf
    check(e.type == MeshEnvelopeIgnored, "header without newline");
}

int main(void) {
    @autoreleasepool {
        testMessages();
        testControls();
        testChunks();
        testHostile();
    }
    return testsDone();
}
