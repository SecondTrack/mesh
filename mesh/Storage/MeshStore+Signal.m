#import "MeshStore+Signal.h"
#import "MeshStore+Internal.h"
#import "MeshBase64.h"

static NSString *signalContext(NSString *key) { return [@"signal|" stringByAppendingString:key]; }

@implementation MeshStore (Signal)

- (NSData *)signalValueForKey:(NSString *)key {
    sqlite3_stmt *st = [self prepare:"SELECT value FROM signal WHERE key=?"];
    if (!st) return nil;
    bindText(st, 1, key);
    NSString *stored = sqlite3_step(st) == SQLITE_ROW ? columnText(st, 0) : nil;
    sqlite3_finalize(st);
    NSString *b64 = stored ? [self open:stored context:signalContext(key)] : nil;
    return b64 ? [MeshBase64 decode:b64] : nil;
}

- (BOOL)setSignalValue:(NSData *)value forKey:(NSString *)key {
    if (!value) return [self run:"DELETE FROM signal WHERE key=?" text:key];
    NSString *sealed = [self seal:[MeshBase64 encode:value] context:signalContext(key)];
    sqlite3_stmt *st = sealed ? [self prepare:"INSERT OR REPLACE INTO signal(key, value) VALUES(?,?)"] : NULL;
    if (!st) return NO;
    bindText(st, 1, key);
    bindText(st, 2, sealed);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (NSString *)bundleForContact:(NSString *)pubkeyHex {
    sqlite3_stmt *st = [self prepare:"SELECT bundle FROM contacts WHERE pubkey=?"];
    if (!st) return nil;
    bindText(st, 1, pubkeyHex);
    NSString *stored = sqlite3_step(st) == SQLITE_ROW ? columnText(st, 0) : nil;
    sqlite3_finalize(st);
    NSString *bundle = [self open:stored context:contactContext("bundle", pubkeyHex)];
    return bundle.length ? bundle : nil;
}

- (void)setBundle:(NSString *)bundle forContact:(NSString *)pubkeyHex {
    NSString *sealed = [self seal:bundle context:contactContext("bundle", pubkeyHex)];
    sqlite3_stmt *st = sealed ? [self prepare:"UPDATE contacts SET bundle=? WHERE pubkey=?"] : NULL;
    if (!st) return;
    bindText(st, 1, sealed);
    bindText(st, 2, pubkeyHex);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

@end
