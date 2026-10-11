#import "MeshPinGuard.h"
#include <sys/sysctl.h>

const NSTimeInterval MeshPinUnknownWait = 30;

static NSString *const kFailures = @"failures";
static NSString *const kStart    = @"start";   // Zeit seit Gerätestart bei Sperrbeginn
static NSString *const kUntil    = @"until";   // Wanduhr: Ende der Sperre
static NSString *const kDelay    = @"delay";
static NSString *const kBoot     = @"boot";    // Startzeit des Kernels bei Sperrbeginn
static const int kFreeAttempts = 4;
static const NSTimeInterval kFirstDelay = 30, kMaxDelay = 3600, kBootTolerance = 2;

static NSTimeInterval bootTime(void) {
    struct timeval tv = {0, 0};
    size_t len = sizeof(tv);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &tv, &len, NULL, 0) != 0) return 0;
    return tv.tv_sec + tv.tv_usec / 1e6;
}

// Der Kernel verschiebt die Startzeit mit, wenn jemand die Uhr stellt; die Differenz läuft
// deshalb gleichmäßig weiter, auch während das Gerät schläft.
static NSTimeInterval uptime(void) {
    return [[NSDate date] timeIntervalSince1970] - bootTime();
}

@implementation MeshPinGuard {
    id<MeshPinStorage> _storage;
    NSMutableDictionary *_state;   // nil = unbekannt (Speicher nicht lesbar)
    MeshClock _wall, _uptime, _boot;
}

- (instancetype)initWithStorage:(id<MeshPinStorage>)storage {
    return [self initWithStorage:storage wallClock:^{ return [[NSDate date] timeIntervalSince1970]; }
                     uptimeClock:^{ return uptime(); } bootClock:^{ return bootTime(); }];
}

- (instancetype)initWithStorage:(id<MeshPinStorage>)storage wallClock:(MeshClock)wall
                    uptimeClock:(MeshClock)up bootClock:(MeshClock)boot {
    if ((self = [super init])) {
        _storage = storage;
        _wall = [wall copy]; _uptime = [up copy]; _boot = [boot copy];
        [self load];
    }
    return self;
}

- (BOOL)load {
    if (_state) return YES;
    MeshPinLoad result = MeshPinLoadFailed;
    NSDictionary *d = [_storage loadPinState:&result];
    if (result == MeshPinLoadFailed) return NO;
    _state = [d mutableCopy] ?: [NSMutableDictionary dictionary];
    if (result == MeshPinLoadCorrupt) {
        _state = [@{ kFailures: @(kFreeAttempts) } mutableCopy];   // weiter ohne freie Versuche
        [self save];
    }
    return YES;
}

- (double)num:(NSString *)key { return [_state[key] doubleValue]; }
- (void)save { [_storage savePinState:_state.count ? [_state copy] : nil]; }

- (int)failures { return (int)[self num:kFailures]; }

- (NSTimeInterval)waitRemaining {
    if (![self load]) return MeshPinUnknownWait;
    NSTimeInterval delay = MIN([self num:kDelay], kMaxDelay);
    if (delay <= 0) return 0;

    NSTimeInterval start = [self num:kStart], now = _uptime();
    if (fabs(_boot() - [self num:kBoot]) > kBootTolerance || now < start) {
        // Neustart (oder verstellte Uhr) seit Sperrbeginn: von vorn.
        _state[kStart] = @(now);
        _state[kUntil] = @(_wall() + delay);
        _state[kBoot] = @(_boot());
        start = now;
        [self save];
    }
    NSTimeInterval wallLeft = [self num:kUntil] - _wall();
    if (wallLeft > delay) {                       // Uhr zurückgestellt
        _state[kUntil] = @(_wall() + delay);
        wallLeft = delay;
        [self save];
    }
    NSTimeInterval left = MAX(start + delay - now, wallLeft);
    if (left > 0) return left;

    // Abgelaufen: Fehlversuche bleiben gezählt, ein späterer Neustart sperrt nicht erneut.
    [_state removeObjectsForKeys:@[kStart, kUntil, kDelay, kBoot]];
    [self save];
    return 0;
}

- (void)recordFailure {
    if (![self load]) return;   // ohne bekannten Zustand ist ohnehin gesperrt; nichts überschreiben
    int f = [self failures] + 1;
    _state[kFailures] = @(f);
    if (f > kFreeAttempts) {
        NSTimeInterval delay = MIN(kMaxDelay, kFirstDelay * pow(2, MIN(f - kFreeAttempts - 1, 16)));
        _state[kDelay] = @(delay);
        _state[kUntil] = @(_wall() + delay);
        _state[kStart] = @(_uptime());
        _state[kBoot] = @(_boot());
    }
    [self save];
}

- (void)reset {
    _state = [NSMutableDictionary dictionary];
    [self save];
}

@end
