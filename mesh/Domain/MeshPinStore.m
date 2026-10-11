#import "MeshPinStore.h"
#import "MeshKeychain.h"

static NSString *const kAccount = @"pin-guard";

@implementation MeshPinStore

- (NSDictionary *)loadPinState:(MeshPinLoad *)result {
    OSStatus st = errSecSuccess;
    NSData *data = [MeshKeychain read:kAccount status:&st];
    if (st == errSecItemNotFound) return [self migrateFromDefaults:result];
    *result = MeshPinLoadFailed;
    if (st != errSecSuccess) return nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if (![plist isKindOfClass:[NSDictionary class]]) { *result = MeshPinLoadCorrupt; return nil; }
    *result = MeshPinLoadOK;
    return plist;
}

- (BOOL)savePinState:(NSDictionary *)state {
    if (!state) return [MeshKeychain remove:kAccount] == errSecSuccess;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state
                                                              format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    return data && [MeshKeychain write:data account:kAccount] == errSecSuccess;
}

// Ältere Versionen zählten in NSUserDefaults. Übernommen wird die Zahl der Fehlversuche;
// die Wartezeit rechnet MeshPinGuard beim nächsten Fehlversuch neu. Die alten Einträge
// verschwinden erst, wenn der Schlüsselbund den Zähler hat.
- (NSDictionary *)migrateFromDefaults:(MeshPinLoad *)result {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger failures = [d integerForKey:@"mesh.pin.failures"];
    *result = MeshPinLoadEmpty;
    NSDictionary *state = failures > 0 ? @{ @"failures": @(failures) } : nil;
    if (state && ![self savePinState:state]) { *result = MeshPinLoadFailed; return nil; }
    for (NSString *k in @[@"mesh.pin.failures", @"mesh.pin.lockedUntil", @"mesh.pin.monoStart", @"mesh.pin.delay"])
        [d removeObjectForKey:k];
    if (state) *result = MeshPinLoadOK;
    return state;
}

@end
