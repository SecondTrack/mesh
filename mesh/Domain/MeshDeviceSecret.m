#import "MeshDeviceSecret.h"
#import "MeshKeychain.h"
#import "MeshCrypto.h"
#import "MeshMemory.h"

static NSString *const kAccount = @"device-secret";
static NSString *const kSealedAccount = @"database-sealed";

@implementation MeshDeviceSecret

+ (NSData *)existing { return [self existingNotFound:NULL]; }

+ (NSData *)existingNotFound:(BOOL *)notFound {
    OSStatus st = errSecSuccess;
    NSData *d = [MeshKeychain read:kAccount status:&st];
    if (notFound) *notFound = (st == errSecItemNotFound);
    return d.length == 32 ? [d mutableCopy] : nil;   // mit MeshWipe löschbar
}

+ (void)remove {
    [MeshKeychain remove:kAccount];
    [MeshKeychain remove:kSealedAccount];
}

// Im Zweifel versiegelt: Nur ein sicher fehlender Merker lässt alte Formate noch zu.
+ (BOOL)databaseSealed {
    OSStatus st = errSecSuccess;
    [MeshKeychain read:kSealedAccount status:&st];
    return st != errSecItemNotFound;
}

// Scheitert das Anlegen, versucht es das nächste Entsperren erneut.
+ (void)markDatabaseSealed {
    if (![self databaseSealed]) [MeshKeychain add:[NSData dataWithBytes:"1" length:1] account:kSealedAccount];
}

+ (NSData *)existingOrCreate {
    BOOL notFound = NO;
    NSData *d = [self existingNotFound:&notFound];
    if (d || !notFound) return d;   // bei einem Lesefehler nichts anlegen
    NSData *fresh = [MeshCrypto randomBytes:32];
    // Erst verwenden, wenn es sich auch wieder lesen lässt.
    d = [MeshKeychain add:fresh account:kAccount] == errSecSuccess ? [self existing] : nil;
    if (![d isEqualToData:fresh]) { MeshWipe(d); d = nil; }
    MeshWipe(fresh);
    return d;
}

@end
