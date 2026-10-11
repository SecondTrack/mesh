// MeshInboxPolicy auf einer echten Datenbank: Grenzen für Fremde, Verdrängung, gelöschte Chats.
#import "MeshTest.h"
#import "MeshStore.h"
#import "MeshStoreTesting.h"
#import "MeshMessage.h"
#import "MeshInboxPolicy.h"

static NSString *key(int i) { return [NSString stringWithFormat:@"%064x", i]; }

int main(void) { @autoreleasepool {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"mesh-inbox-test-%d.sqlite", getpid()]];
    MeshStore *s = [MeshStore new];
    [s openAtPath:path];
    NSMutableData *dataKey = [NSMutableData dataWithLength:32]; arc4random_buf(dataKey.mutableBytes, 32);
    [s setDataKey:dataKey];
    MeshInboxPolicy *p = [[MeshInboxPolicy alloc] initWithStore:s];
    NSString *(^big)(long long) = ^(long long n) { return [@"" stringByPaddingToLength:(NSUInteger)n withString:@"x" startingAtIndex:0]; };
    __block int eid = 0;
    BOOL (^receive)(NSString *, long long) = ^BOOL(NSString *from, long long n) {
        NSString *e = [NSString stringWithFormat:@"ev%d", ++eid];
        if (![p admitFrom:from eventId:e bytes:n]) return NO;
        return [s insertMessageChat:from fromMe:NO content:big(n) ts:eid eventId:e];
    };

    // Angenommene Kontakte: keine Grenze
    [s upsertContact:key(1) name:@"Freund" accepted:YES];
    check(receive(key(1), 100) && receive(key(1), 6 * 1024 * 1024), "accepted contact unlimited");

    // Fremder: wird angelegt, aber nicht angenommen; Grenze je Fremdem
    check(receive(key(2), 1000) && [s isContact:key(2)] && ![s isAccepted:key(2)], "stranger added unaccepted");
    check(receive(key(2), 4 * 1024 * 1024), "stranger within 5 MB");
    check(!receive(key(2), 2 * 1024 * 1024), "stranger over 5 MB rejected");
    check(![p admitFrom:key(3) eventId:@"x" bytes:6 * 1024 * 1024] && ![s isContact:key(3)], "oversized first message rejected");

    // Bekannte Fremde zählen auch zur Gesamtgrenze von 20 MB
    for (int i = 10; i < 13; i++) receive(key(i), 4 * 1024 * 1024);
    receive(key(13), 3 * 1024 * 1024);
    check([s unacceptedBytes] > 19 * 1024 * 1024, "strangers near total limit");
    check(!receive(key(13), 1536 * 1024), "existing stranger cannot exceed total");

    // Neuer Fremder verdrängt den ältesten
    check(receive(key(20), 2 * 1024 * 1024) && ![s isContact:key(2)], "oldest stranger evicted for new one");
    check([s unacceptedBytes] <= MeshMaxAllStrangerBytes, "total stays within limit");

    // Höchstzahl Fremder
    for (int i = 100; i < 100 + MeshMaxStrangers + 5; i++) receive(key(i), 10);
    check([s unacceptedContactCount] <= MeshMaxStrangers, "stranger count capped");
    for (int i = 0; i < 10; i++) {
        NSString *eid = [NSString stringWithFormat:@"tomb%d", i];
        [s insertMessageChat:key(30) fromMe:NO content:@"x" ts:i eventId:eid];
        [s deleteMessage:[s messageWithKey:eid chat:key(30)].rowId];
    }
    [s pruneTombstonesKeeping:3];
    check([s isDeleted:@"tomb9"] && [s isDeleted:@"tomb7"] && ![s isDeleted:@"tomb6"], "tombstones pruned to the newest");

    // Gelöschter Chat: alte Nachricht vom Relay legt den Kontakt nicht wieder an
    [s upsertContact:key(7) name:@"" accepted:NO];
    [s insertMessageChat:key(7) fromMe:NO content:@"alt" ts:1 eventId:@"old7"];
    [s deleteContact:key(7)];
    check(![p admitFrom:key(7) eventId:@"old7" bytes:3] && ![s isContact:key(7)], "deleted chat stays deleted");

    // Blockiert
    [s blockContact:key(8)];
    check(![p admitFrom:key(8) eventId:@"b" bytes:3] && ![s isContact:key(8)], "blocked sender ignored");
    [s unblockContact:key(8)];
    [s upsertContact:key(8) name:@"" accepted:YES];
    check([p admitFrom:key(8) eventId:@"b2" bytes:3], "unblocked sender admitted again");

    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    return testsDone();
}}
