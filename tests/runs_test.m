// Folgen im Gruppenchat (MeshRunPositionAt): Name über der ersten Blase, Bild neben der letzten.
#import "MeshTest.h"
#import "MeshMessage.h"
#import "MeshPayload.h"

static MeshMessage *msg(NSString *sender, long long ts, BOOL fromMe, MeshPayloadKind kind) {
    MeshMessage *m = [MeshMessage new];
    m.sender = sender; m.ts = ts; m.fromMe = fromMe; m.kind = kind;
    return m;
}
static MeshMessage *in(NSString *sender, long long ts) { return msg(sender, ts, NO, MeshPayloadText); }

int main(void) {
    @autoreleasepool {
        // Mittag Ortszeit, damit ein paar Minuten nie über Mitternacht gehen
        struct tm t = { .tm_year = 126, .tm_mon = 9, .tm_mday = 15, .tm_hour = 12, .tm_isdst = -1 };
        long long noon = (long long)mktime(&t);
        NSString *a = @"aa", *b = @"bb";
        NSArray *l = @[ in(a, noon), in(a, noon + 60), in(a, noon + 120),   // 0-2: eine Folge
                        in(b, noon + 130),                                    // 3: allein
                        in(a, noon + 140),                                    // 4: neue Folge (anderer Absender dazwischen)
                        in(a, noon + 140 + kMeshRunGap + 1),                  // 5: zu großer Abstand
                        msg(nil, noon + 400, NO, MeshPayloadNotice),          // 6: Systemzeile
                        in(a, noon + 410),                                    // 7: nach Systemzeile neu
                        msg(nil, noon + 420, YES, MeshPayloadText),           // 8: eigene
                        in(a, noon + 430), in(a, noon + 440) ];               // 9-10
        check(MeshRunPositionAt(l, 0) == (MeshRunIn | MeshRunFirst), "first of run");
        check(MeshRunPositionAt(l, 1) == MeshRunIn, "middle of run");
        check(MeshRunPositionAt(l, 2) == (MeshRunIn | MeshRunLast), "last of run");
        check(MeshRunPositionAt(l, 3) == (MeshRunIn | MeshRunFirst | MeshRunLast), "other sender: own run");
        check(MeshRunPositionAt(l, 4) & MeshRunFirst && MeshRunPositionAt(l, 4) & MeshRunLast, "gap ends run");
        check(MeshRunPositionAt(l, 5) == (MeshRunIn | MeshRunFirst | MeshRunLast), "after gap: new run");
        check(MeshRunPositionAt(l, 6) == MeshRunNone, "notice: no run");
        check(MeshRunPositionAt(l, 7) == (MeshRunIn | MeshRunFirst | MeshRunLast), "notice and own message end runs");
        check(MeshRunPositionAt(l, 8) == MeshRunNone, "own message: no run");
        check(MeshRunPositionAt(l, 9) == (MeshRunIn | MeshRunFirst) && MeshRunPositionAt(l, 10) == (MeshRunIn | MeshRunLast), "run after own message");
        check(MeshRunPositionAt(l, 11) == MeshRunNone && MeshRunPositionAt(@[], 0) == MeshRunNone, "out of range");

        // Exakt am Abstand: noch dieselbe Folge
        NSArray *edge = @[ in(a, noon), in(a, noon + kMeshRunGap) ];
        check(MeshRunPositionAt(edge, 0) == (MeshRunIn | MeshRunFirst), "gap limit inclusive");

        // Tageswechsel (Ortszeit) trennt, auch bei kurzem Abstand
        struct tm m = { .tm_year = 126, .tm_mon = 9, .tm_mday = 15, .tm_hour = 23, .tm_min = 59, .tm_isdst = -1 };
        long long late = (long long)mktime(&m);
        NSArray *day = @[ in(a, late), in(a, late + 90) ];
        check(MeshRunPositionAt(day, 0) == (MeshRunIn | MeshRunFirst | MeshRunLast), "day change ends run");

        // Ungelesen-Trenner (Notice ohne Datenbankzeile) trennt
        MeshMessage *div = msg(nil, 0, NO, MeshPayloadNotice); div.rowId = -1;
        NSArray *d = @[ in(a, noon), div, in(a, noon + 10) ];
        check(MeshRunPositionAt(d, 0) & MeshRunLast && MeshRunPositionAt(d, 2) & MeshRunFirst, "unread divider ends run");

        // Ohne Absender (1:1-Chat): keine Folgen
        check(MeshRunPositionAt(@[ in(nil, noon), in(nil, noon + 1) ], 0) == MeshRunNone, "no sender: no run");
    }
    return testsDone();
}
