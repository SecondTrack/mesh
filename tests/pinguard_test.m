// Sperrzeit nach Fehlversuchen, auch bei verstellter Uhr, nach einem Neustart und wenn der
// Speicher nicht antwortet.
#import "MeshTest.h"
#import "MeshPinGuard.h"

// Steht in der App für den Schlüsselbund. readFails/writeFails spielen einen gesperrten Schlüsselbund.
@interface MemoryStorage : NSObject <MeshPinStorage>
@property (nonatomic, copy) NSDictionary *state;
@property (nonatomic) BOOL readFails, writeFails, corrupt;
@end
@implementation MemoryStorage
- (NSDictionary *)loadPinState:(MeshPinLoad *)result {
    if (self.corrupt) { self.corrupt = NO; *result = MeshPinLoadCorrupt; return nil; }
    *result = self.readFails ? MeshPinLoadFailed : self.state ? MeshPinLoadOK : MeshPinLoadEmpty;
    return self.readFails ? nil : self.state;
}
- (BOOL)savePinState:(NSDictionary *)state {
    if (self.writeFails) return NO;
    self.state = state;
    return YES;
}
@end

int main(void) { @autoreleasepool {
    MemoryStorage *s = [MemoryStorage new];
    __block NSTimeInterval wall = 1000000, up = 500, boot = 900000;
    MeshPinGuard *(^make)(void) = ^{
        return [[MeshPinGuard alloc] initWithStorage:s wallClock:^{ return wall; }
                                         uptimeClock:^{ return up; } bootClock:^{ return boot; }];
    };
    void (^pass)(NSTimeInterval) = ^(NSTimeInterval secs) { wall += secs; up += secs; };
    MeshPinGuard *g = make();

    for (int i = 0; i < 4; i++) [g recordFailure];
    check([g waitRemaining] == 0, "4 free attempts");
    [g recordFailure];
    check([g waitRemaining] == 30, "5th: 30 s");
    pass(31);
    check([g waitRemaining] == 0, "real time unlocks");
    check([g failures] == 5, "failures stay counted");
    [g recordFailure];
    check([g waitRemaining] == 60, "6th: 60 s");
    for (int i = 0; i < 30; i++) [g recordFailure];
    check([g waitRemaining] == 3600, "capped at 1 h");

    // Neue Instanz (App-Neustart) sieht denselben Zustand
    check([make() failures] == 36 && [make() waitRemaining] == 3600, "survives restart");
    pass(3600);
    check([g waitRemaining] == 0, "1 h passes");

    // Neustart, nachdem die Sperre abgelaufen ist: bleibt offen
    wall += 7200; up = 5; boot += 7200;
    check([g waitRemaining] == 0, "reboot after expiry stays open");

    // Neustart während der Sperre (oder verstellte Uhr, die der Kernel als neue Startzeit zeigt)
    [g reset];
    for (int i = 0; i < 6; i++) [g recordFailure];
    check([g waitRemaining] == 60, "locked 60 s");
    wall += 86400; up = 3; boot += 86400;         // Neustart, Uhr dabei einen Tag vor
    check([g waitRemaining] == 60, "reboot restarts the wait");
    pass(59);
    check([g waitRemaining] == 1, "counts down after reboot");
    pass(1);
    check([g waitRemaining] == 0, "unlocks after full wait");

    // Neustart, bei dem die Zeit seit Start zufällig größer ist: erkannt an der Startzeit
    [g recordFailure];                                // 7. → 120 s
    wall += 5000; up += 1000; boot += 5000;
    check([g waitRemaining] == 120, "boot time change detected");

    // Kernel verschiebt die Startzeit beim Uhrstellen nicht: die Wanduhr hält die Sperre trotzdem
    wall -= 3000;                                 // Uhr zurück; Zeit seit Start springt mit
    check([g waitRemaining] == 120, "clock rollback capped at full wait");
    up += 500;                                    // Uhr vor, ohne dass die Startzeit wandert
    check([g waitRemaining] == 120, "wall clock still holds");
    pass(120);
    check([g waitRemaining] == 0, "both clocks expired");
    [g recordFailure];                            // 8. → 240 s für die Tests unten

    // Schlüsselbund nicht lesbar: gesperrt statt bei 0 anfangen, nichts überschreiben
    NSDictionary *stored = s.state;
    s.readFails = YES;
    MeshPinGuard *blind = make();
    check([blind waitRemaining] == MeshPinUnknownWait, "unreadable storage locks");
    [blind recordFailure];
    check([s.state isEqual:stored], "unreadable storage is not overwritten");
    s.readFails = NO;
    check([blind waitRemaining] == 240 && [blind failures] == 8, "reloads once readable");

    // Schreiben scheitert: der alte Zustand bleibt
    s.writeFails = YES;
    [g recordFailure];
    check([s.state isEqual:stored], "failed write keeps old state");
    s.writeFails = NO;

    // Beschädigter Eintrag: keine freien Versuche mehr, aber nicht dauerhaft gesperrt
    MemoryStorage *broken = [MemoryStorage new];
    broken.corrupt = YES;
    MeshPinGuard *gb = [[MeshPinGuard alloc] initWithStorage:broken];
    check([gb waitRemaining] == 0 && [gb failures] == 4, "corrupt entry: no free attempts");
    [gb recordFailure];
    check([gb waitRemaining] > 29, "corrupt entry: next failure locks");

    [g reset];
    check([g waitRemaining] == 0 && [g failures] == 0 && s.state == nil, "reset after success");

    return testsDone();
}}
