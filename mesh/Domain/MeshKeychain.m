#import "MeshKeychain.h"
#import "MeshLog.h"

static NSString *const kService = @"de.mesh.ios.vault";

static NSMutableDictionary *query(NSString *account) {
    return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService: kService,
               (__bridge id)kSecAttrAccount: account } mutableCopy];
}

static void logFailure(NSString *what, NSString *account, OSStatus st) {
    if (st != errSecSuccess && st != errSecItemNotFound) MeshLog(@"Schlüsselbund %@ %@: %d", what, account, (int)st);
}

@implementation MeshKeychain

+ (NSData *)read:(NSString *)account status:(OSStatus *)status {
    NSMutableDictionary *q = query(account);
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    logFailure(@"lesen", account, st);
    if (status) *status = st;
    return st == errSecSuccess ? (__bridge_transfer NSData *)out : nil;
}

+ (OSStatus)add:(NSData *)data account:(NSString *)account accessible:(CFTypeRef)accessible {
    NSMutableDictionary *q = query(account);
    q[(__bridge id)kSecValueData] = data;
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)accessible;
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    logFailure(@"anlegen", account, st);
    return st;
}

+ (OSStatus)add:(NSData *)data account:(NSString *)account {
    return [self add:data account:account accessible:kSecAttrAccessibleWhenUnlockedThisDeviceOnly];
}

// Ändern statt löschen und neu anlegen: Scheitert das Schreiben, bleibt der alte Wert stehen.
+ (OSStatus)write:(NSData *)data account:(NSString *)account accessible:(CFTypeRef)accessible {
    NSDictionary *change = @{ (__bridge id)kSecValueData: data, (__bridge id)kSecAttrAccessible: (__bridge id)accessible };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)query(account), (__bridge CFDictionaryRef)change);
    if (st == errSecItemNotFound) return [self add:data account:account accessible:accessible];
    logFailure(@"schreiben", account, st);
    return st;
}

+ (OSStatus)write:(NSData *)data account:(NSString *)account {
    return [self write:data account:account accessible:kSecAttrAccessibleWhenUnlockedThisDeviceOnly];
}

+ (OSStatus)writeReadableWhileLocked:(NSData *)data account:(NSString *)account {
    return [self write:data account:account accessible:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
}

+ (OSStatus)remove:(NSString *)account {
    OSStatus st = SecItemDelete((__bridge CFDictionaryRef)query(account));
    logFailure(@"löschen", account, st);
    return st == errSecItemNotFound ? errSecSuccess : st;
}

@end
