#import "MeshIdentity.h"
#import "MeshStore.h"
#import "MeshVault.h"
#import "MeshKeys.h"
#import "MeshMessenger.h"
#import "MeshSignal.h"
#import "MeshStore+Signal.h"
#import "MeshInboxPolicy.h"
#import "MeshDeviceSecret.h"
#import "MeshHex.h"
#import "MeshMemory.h"

static NSString *const kSlots = @"mesh.identities", *const kActive = @"mesh.activeIdentity";

@implementation MeshIdentity

+ (NSArray *)savedSlots {
    NSArray *s = [[NSUserDefaults standardUserDefaults] arrayForKey:kSlots];
    NSMutableArray *out = [NSMutableArray array];
    for (id n in s) if ([n isKindOfClass:[NSNumber class]] && [n intValue] >= 0 && ![out containsObject:n]) [out addObject:n];
    return out.count ? [out sortedArrayUsingSelector:@selector(compare:)] : @[@0];
}

+ (int)activeSlot {
    int a = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kActive];
    return [[self savedSlots] containsObject:@(a)] ? a : [[self savedSlots][0] intValue];
}

+ (void)saveSlots:(NSArray *)slots active:(int)active {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:slots forKey:kSlots];
    [d setInteger:active forKey:kActive];
    [d synchronize];
}

+ (NSString *)databasePathForSlot:(int)slot {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = dirs.count ? dirs[0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    // sqlite legt nur die Datei an, nicht den Ordner: bei Jailbreak-Apps fehlt Documents oft.
    [[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *name = slot == 0 ? @"mesh.sqlite" : [NSString stringWithFormat:@"mesh-%d.sqlite", slot];
    return [docs stringByAppendingPathComponent:name];
}

- (instancetype)initWithSlot:(int)slot {
    if ((self = [super init])) {
        _slot = slot;
        _store = [[MeshStore alloc] init];
        [_store openAtPath:[MeshIdentity databasePathForSlot:slot]];
        _vault = [[MeshVault alloc] initWithStore:_store deviceSecret:nil];   // Geheimnis erst bei Bedarf
        _inbox = [[MeshInboxPolicy alloc] initWithStore:_store];
    }
    return self;
}

- (void)unlockWithKeys:(MeshKeys *)keys panic:(MeshPanic *)panic delegate:(id<MeshMessengerDelegate>)delegate {
    _keys = keys;
    _pubkey = [MeshHex encode:keys.xonlyPub];
    NSData *dataKey = [keys derivedKey:@"mesh-db-v1"];
    // Das Siegel-Merkmal im Schlüsselbund gilt für die ursprüngliche Datenbank; neue sind leer.
    [_store setDataKey:dataKey knownSealed:_slot == 0 && [MeshDeviceSecret databaseSealed]];
    MeshWipe(dataKey);   // der Store hält seine eigene Kopie
    if (_slot == 0 && _store.sealed) [MeshDeviceSecret markDatabaseSealed];
    NSData *seed = keys.seckey;
    _signal = [[MeshSignal alloc] initWithStorage:_store seed:seed];
    MeshWipe(seed);
    _messenger = [[MeshMessenger alloc] initWithStore:_store keys:keys inbox:_inbox panic:panic];
    _messenger.signal = _signal;
    _messenger.delegate = delegate;
}

- (void)lock {
    [_keys wipe]; _keys = nil;
    _messenger = nil;
    _signal = nil;
    _vault.deviceSecret = nil;
    [_store setDataKey:nil];
}

- (BOOL)destroy {
    [self lock];
    return [_store destroyAndReopen];
}

@end
