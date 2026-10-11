// Bremst das Durchprobieren des Entsperr-Codes am Gerät.
// Die ersten 4 Fehlversuche sind frei, danach Wartezeit 30 s, 60 s, … bis 1 h.
// Die Wartezeit muss auf zwei Uhren ablaufen: auf der Zeit seit Gerätestart (einschließlich
// Ruhezustand) und auf der Wanduhr. Ändert sich die Startzeit des Kernels, weil das Gerät neu
// gestartet oder die Uhr gestellt wurde, beginnt eine laufende Wartezeit von vorn; die Uhr
// zurückzustellen verlängert sie höchstens bis zur vollen Dauer.
// Lässt sich der gespeicherte Zustand nicht lesen, gilt die Eingabe als gesperrt. Ist er
// beschädigt, gibt es keine freien Versuche mehr.
#import <Foundation/Foundation.h>

typedef NSTimeInterval (^MeshClock)(void);

typedef NS_ENUM(NSInteger, MeshPinLoad) {
    MeshPinLoadOK,
    MeshPinLoadEmpty,    // sicher nichts gespeichert
    MeshPinLoadCorrupt,  // gelesen, aber unbrauchbar
    MeshPinLoadFailed    // Speicher nicht lesbar: Zustand unbekannt
};

// Wo der Zustand liegt. In der App der Schlüsselbund (MeshPinStore), in Tests ein Dictionary.
@protocol MeshPinStorage <NSObject>
- (NSDictionary *)loadPinState:(MeshPinLoad *)result;
- (BOOL)savePinState:(NSDictionary *)state;   // nil = löschen
@end

extern const NSTimeInterval MeshPinUnknownWait;   // Wartezeit, solange der Zustand unbekannt ist

@interface MeshPinGuard : NSObject
- (instancetype)initWithStorage:(id<MeshPinStorage>)storage;
- (instancetype)initWithStorage:(id<MeshPinStorage>)storage wallClock:(MeshClock)wall
                    uptimeClock:(MeshClock)uptime bootClock:(MeshClock)boot;   // Tests
- (NSTimeInterval)waitRemaining;     // 0 = Eingabe erlaubt
- (int)failures;
- (void)recordFailure;
- (void)reset;
@end
