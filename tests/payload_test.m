// Nachrichtenformat: Erkennen, Rundweg, ältere iPod-Formate, kaputte und feindliche Eingaben.
#import "MeshTest.h"
#import "MeshPayload.h"

int main(void) { @autoreleasepool {
    NSData *jpeg = [NSData dataWithBytes:"\xff\xd8\xff\xe0 fake" length:9];
    NSData *aac  = [NSData dataWithBytes:"\x00\x00\x00\x1c" "ftypM4A " length:12];

    MeshPayload *t = [MeshPayload parse:@"Hallo"];
    check(t.kind == MeshPayloadText && [t.text isEqualToString:@"Hallo"] && !t.data, "text");
    check([MeshPayload parse:nil].kind == MeshPayloadText, "nil is text");

    // Format der Android-App (MeshState.kt: IMG_MARKER, VOICE_MARKER, FILE_MARKER, CONTACT_MARKER)
    NSString *ic = [MeshPayload contentWithImage:jpeg];
    check([ic isEqualToString:@"mesh:img/9j/4CBmYWtl"], "image wire format");
    MeshPayload *i = [MeshPayload parse:ic];
    check(i.kind == MeshPayloadImage && [i.data isEqual:jpeg] && !i.text, "image roundtrip");

    NSString *vc = [MeshPayload contentWithVoice:aac seconds:7];
    check([vc hasPrefix:@"mesh:voc:7|"], "voice wire format");
    MeshPayload *v = [MeshPayload parse:vc];
    check(v.kind == MeshPayloadVoice && v.seconds == 7 && [v.data isEqual:aac], "voice roundtrip");

    NSString *fc = [MeshPayload contentWithFile:jpeg name:@"Bericht\n.pdf" mime:@"application/pdf"];
    check([fc hasPrefix:@"\1mesh:file:Bericht.pdf\1application/pdf\n"], "file wire format");
    MeshPayload *f = [MeshPayload parse:fc];
    check(f.kind == MeshPayloadFile && [f.fileName isEqualToString:@"Bericht.pdf"]
          && [f.fileMime isEqualToString:@"application/pdf"] && [f.data isEqual:jpeg], "file roundtrip");
    check([[MeshPayload parse:@"\1mesh:file:a.txt\nAAAA"].fileMime isEqualToString:@""], "file without mime");

    NSString *cc = [MeshPayload contentWithContactName:@"Caro" code:@"mesh:npub1xyz?node=abc"];
    MeshPayload *c = [MeshPayload parse:cc];
    check(c.kind == MeshPayloadContact && [c.text isEqualToString:@"Caro"] && [c.code isEqualToString:@"mesh:npub1xyz?node=abc"], "contact card");

    MeshPayload *n = [MeshPayload parseNotice:[MeshPayload noticeTimer:300 byMe:YES]];
    check(n.kind == MeshPayloadNotice && n.seconds == 300 && n.byMe, "notice");
    check([MeshPayload parse:@"ttl:300:1"].kind == MeshPayloadText, "notice text from peer stays text");

    // ältere iPod-Versionen
    check([[MeshPayload parse:@"mesh:img:/9j/4CBmYWtl"].data isEqual:jpeg], "old image");
    MeshPayload *ov = [MeshPayload parse:@"mesh:voice:3:AAAAHGZ0eXBNNEEg"];
    check(ov.seconds == 3 && [ov.data isEqual:aac], "old voice");

    // Kaputtes und Feindliches
    check([MeshPayload parse:@"mesh:img"].data == nil, "empty image");
    check([MeshPayload parse:@"mesh:voc:"].data == nil, "voice without separator");
    check([MeshPayload parse:@"mesh:voc:-5|AAAA"].seconds == 0, "negative seconds clamped");
    check([MeshPayload parse:@"mesh:voc:99999999999|AAAA"].seconds == 3600, "huge seconds clamped");
    check([MeshPayload parse:@"mesh:voc:x|AAAA"].seconds == 0, "non-numeric seconds");
    check([MeshPayload parse:@"\1mesh:file:kein-umbruch"].data == nil, "file without body");
    check([MeshPayload kindOf:@"MESH:IMG:abc"] == MeshPayloadText, "marker is case-sensitive");
    check([MeshPayload kindOf:@" mesh:img:abc"] == MeshPayloadText, "marker must be at start");

    return testsDone();
}}
