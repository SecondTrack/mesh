#import "MeshStore+Vault.h"
#import "MeshStore+Internal.h"
#import "MeshVaultRecord.h"

@implementation MeshStore (Vault)

// Im Zweifel vorhanden: Ein Lesefehler darf nicht zur Einrichtung führen, die den Vault ersetzt.
- (BOOL)hasVault {
    sqlite3_stmt *st = [self prepare:"SELECT 1 FROM vault WHERE id=1"];
    if (!st) return YES;
    BOOL none = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return !none;
}

- (BOOL)saveVault:(MeshVaultRecord *)r {
    sqlite3_stmt *st = [self prepare:"INSERT OR REPLACE INTO vault(id, salt, iv, ct, pubkey, iters, peppered, kdf) VALUES(1,?,?,?,?,?,?,?)"];
    if (!st) return NO;
    BOOL ok = sqlite3_bind_blob(st, 1, r.salt.bytes, (int)r.salt.length, SQLITE_TRANSIENT) == SQLITE_OK
           && sqlite3_bind_blob(st, 2, r.iv.bytes, (int)r.iv.length, SQLITE_TRANSIENT) == SQLITE_OK
           && sqlite3_bind_blob(st, 3, r.ciphertext.bytes, (int)r.ciphertext.length, SQLITE_TRANSIENT) == SQLITE_OK
           && sqlite3_bind_text(st, 4, r.pubkey.UTF8String, -1, SQLITE_TRANSIENT) == SQLITE_OK
           && sqlite3_bind_int (st, 5, r.iterations) == SQLITE_OK
           && sqlite3_bind_int (st, 6, r.boundToDevice ? 1 : 0) == SQLITE_OK
           && sqlite3_bind_int (st, 7, r.kdf) == SQLITE_OK
           && sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (MeshVaultRecord *)loadVault {
    sqlite3_stmt *st = [self prepare:"SELECT salt, iv, ct, pubkey, iters, peppered, kdf FROM vault WHERE id=1"];
    MeshVaultRecord *r = nil;
    if (st && sqlite3_step(st) == SQLITE_ROW) {
        r = [MeshVaultRecord new];
        r.salt = columnBlob(st, 0);
        r.iv = columnBlob(st, 1);
        r.ciphertext = columnBlob(st, 2);
        r.pubkey = columnText(st, 3) ?: @"";
        r.iterations = sqlite3_column_int(st, 4);
        r.boundToDevice = sqlite3_column_int(st, 5) != 0;
        r.kdf = sqlite3_column_int(st, 6);
    }
    sqlite3_finalize(st);
    return r;
}

- (NSString *)loadIdentitySeckeyHex {
    sqlite3_stmt *st = [self prepare:"SELECT seckey FROM identity WHERE id=1"];
    NSString *out = (st && sqlite3_step(st) == SQLITE_ROW) ? columnText(st, 0) : nil;
    sqlite3_finalize(st);
    return out;
}

- (BOOL)clearPlaintextIdentity {
    BOOL ok = sqlite3_exec(self.db, "DELETE FROM identity", NULL, NULL, NULL) == SQLITE_OK;
    if (ok) sqlite3_exec(self.db, "VACUUM", NULL, NULL, NULL);   // Klartext-Schlüssel auch aus freien Seiten
    return ok;
}

@end
