// MeshVault mit einem Speicher im RAM: Rundweg, falscher Code, Schreibfehler, Gerätebindung.
#import "MeshTest.h"
#import "MeshVault.h"
#import "MeshStore+Vault.h"
#import "MeshVaultRecord.h"
#import "MeshKeys.h"
#import "MeshCrypto.h"
#import "MeshHex.h"

// Ersetzt die sqlite-Datei; failWrites/corrupt simulieren volle Platte bzw. kaputte Seiten.
@interface FakeStore : MeshStore
@property (nonatomic) MeshVaultRecord *row;
@property (nonatomic) BOOL failWrites, corrupt;
@property (nonatomic, copy) NSString *identityHex;   // Klartext-Schlüssel alter Installationen
@end
@implementation FakeStore
- (NSString *)loadIdentitySeckeyHex { return self.identityHex; }
- (BOOL)clearPlaintextIdentity { self.identityHex = nil; return YES; }
- (BOOL)hasVault { return self.row != nil; }
- (BOOL)saveVault:(MeshVaultRecord *)r {
    if (self.failWrites) return NO;
    MeshVaultRecord *c = [MeshVaultRecord new];
    NSMutableData *ct = [r.ciphertext mutableCopy];
    if (self.corrupt) ((unsigned char *)ct.mutableBytes)[0] ^= 1;
    c.salt = r.salt; c.iv = r.iv; c.ciphertext = ct; c.pubkey = r.pubkey;
    c.iterations = r.iterations; c.boundToDevice = r.boundToDevice; c.kdf = r.kdf;
    self.row = c;
    return YES;
}
- (MeshVaultRecord *)loadVault { return self.row; }
@end

@interface MeshVault (Test)
- (MeshKeys *)openWithPin_:(NSString *)pin;
@end
@implementation MeshVault (Test)
- (MeshKeys *)openWithPin_:(NSString *)pin { MeshVaultOpen r; return [self openWithPin:pin result:&r]; }
@end

// Vault, wie ihn Versionen vor der Gerätebindung angelegt haben: nur der Code im PBKDF2.
static void writeLegacyVault(FakeStore *s, MeshKeys *k, NSString *pin) {
    NSData *salt = [MeshCrypto randomBytes:16], *iv = [MeshCrypto randomBytes:16];
    NSData *dk = [MeshCrypto pbkdf2:pin salt:salt iters:MeshVaultIterations];
    MeshVaultRecord *r = [MeshVaultRecord new];
    r.salt = salt; r.iv = iv; r.ciphertext = [MeshCrypto aes256cbcEncrypt:k.seckey key:dk iv:iv];
    r.pubkey = [MeshHex encode:k.xonlyPub]; r.iterations = MeshVaultIterations; r.boundToDevice = NO;
    [s saveVault:r];
}

static NSData *randomSecret(void) {
    NSMutableData *d = [NSMutableData dataWithLength:32]; arc4random_buf(d.mutableBytes, 32);
    return d;
}

int main(void) { @autoreleasepool {
    FakeStore *s = [FakeStore new];
    MeshKeys *k = [MeshKeys generate];

    // Ohne Gerätegeheimnis wird nichts angelegt: eine kopierte Datenbank wäre sonst offline durchprobierbar.
    MeshVault *unbound = [[MeshVault alloc] initWithStore:s deviceSecret:nil];
    check(![unbound storeKeys:k pin:@"1234"] && ![unbound exists], "refuses without device secret");

    MeshVault *v = [[MeshVault alloc] initWithStore:s deviceSecret:randomSecret()];

    check(![v exists], "empty");
    check([v openWithPin_:@"1234"] == nil, "open without vault");
    check([v storeKeys:k pin:@"1234"], "store");
    check([v exists], "exists after store");
    check([[v openWithPin_:@"1234"].seckey isEqual:k.seckey], "roundtrip");
    int wrongOk = 0;
    for (int i = 0; i < 200; i++)
        if ([v openWithPin_:[NSString stringWithFormat:@"%04d", 5000 + i]]) wrongOk++;
    check(wrongOk == 0, "wrong pins rejected");
    check([v openWithPin_:@""] == nil, "empty pin");

    MeshVaultRecord *before = s.row;
    s.failWrites = YES;
    check(![v storeKeys:k pin:@"9999"], "write failure reported");
    check(s.row == before && [[v openWithPin_:@"1234"].seckey isEqual:k.seckey], "old vault intact");
    s.failWrites = NO; s.corrupt = YES;
    check(![v storeKeys:k pin:@"9999"], "readback mismatch reported");
    s.corrupt = NO;

    check([v storeKeys:k pin:@"4711"] && [v openWithPin_:@"1234"] == nil
          && [[v openWithPin_:@"4711"].seckey isEqual:k.seckey], "pin change");
    check(![s.row.salt isEqual:before.salt], "fresh salt");

    // Gerätegeheimnis: alter Vault wird beim Öffnen gebunden, danach nur noch mit Geheimnis offen
    writeLegacyVault(s, k, @"4711");
    check([[unbound openWithPin_:@"4711"].seckey isEqual:k.seckey] && !unbound.boundToDevice, "legacy vault opens");
    NSData *secret = randomSecret();
    MeshVault *bound = [[MeshVault alloc] initWithStore:s deviceSecret:secret];
    check(!bound.boundToDevice, "old vault not bound");
    MeshVaultOpen r;
    check([[bound openWithPin:@"4711" result:&r].seckey isEqual:k.seckey] && r == MeshVaultOpened, "open old vault with secret");
    check(bound.boundToDevice && s.row.boundToDevice, "migrated to device-bound");
    check([[bound openWithPin:@"4711" result:&r].seckey isEqual:k.seckey], "bound vault opens");

    // Datenbank-Kopie ohne das Geheimnis (Backup, anderes Gerät): nicht einmal prüfbar
    MeshVault *thief = [[MeshVault alloc] initWithStore:s deviceSecret:nil];
    check([thief openWithPin:@"4711" result:&r] == nil && r == MeshVaultSecretMissing, "copy without secret");
    MeshVault *wrongDev = [[MeshVault alloc] initWithStore:s deviceSecret:randomSecret()];
    check([wrongDev openWithPin:@"4711" result:&r] == nil && r == MeshVaultWrongPin, "wrong secret fails");
    check([bound storeKeys:k pin:@"123456"] && [bound openWithPin:@"4711" result:&r] == nil
          && [[bound openWithPin:@"123456" result:&r].seckey isEqual:k.seckey], "pin change keeps binding");

    // Sperren: Gerätegeheimnis vergessen, danach wie ohne Schlüsselbund
    bound.deviceSecret = nil;
    check(![bound readyToOpen], "not ready without secret");
    check([bound openWithPin:@"123456" result:&r] == nil && r == MeshVaultSecretMissing, "forgotten secret");
    check(![bound storeKeys:k pin:@"654321"], "no store after forgetting");
    bound.deviceSecret = secret;
    check([[bound openWithPin:@"123456" result:&r].seckey isEqual:k.seckey], "reloaded secret opens");
    check([bound readyToOpen], "ready with secret");
    check(![[[MeshVault alloc] initWithStore:[FakeStore new] deviceSecret:randomSecret()] readyToOpen], "not ready without vault");

    // Überschriebener Schlüssel (nach dem Sperren) darf nie als leerer Vault landen
    MeshKeys *wiped = [MeshKeys generate];
    [wiped wipe];
    MeshVaultRecord *kept = s.row;
    check(![bound storeKeys:wiped pin:@"111111"] && s.row == kept, "wiped keys are not stored");

    // Erstes Festlegen: Klartext-Identität übernehmen, erst danach löschen
    FakeStore *fresh = [FakeStore new];
    fresh.identityHex = [MeshHex encode:k.seckey];
    MeshVault *setup = [[MeshVault alloc] initWithStore:fresh deviceSecret:randomSecret()];
    fresh.failWrites = YES;
    check(![setup createWithSecret:@"222222" kdf:MeshVaultPBKDF2] && fresh.identityHex, "plaintext kept when vault fails");
    fresh.failWrites = NO;
    MeshKeys *adopted = [setup createWithSecret:@"222222" kdf:MeshVaultPBKDF2];
    check([adopted.seckey isEqual:k.seckey] && !fresh.identityHex, "plaintext identity adopted and removed");
    check(![setup createWithSecret:@"333333" kdf:MeshVaultPBKDF2], "no second create");
    FakeStore *empty = [FakeStore new];
    MeshVault *newbie = [[MeshVault alloc] initWithStore:empty deviceSecret:randomSecret()];
    MeshKeys *generated = [newbie createWithSecret:@"444444" kdf:MeshVaultPBKDF2];
    check(generated && [[newbie openWithPin_:@"444444"].seckey isEqual:generated.seckey], "new identity created");

    // PIN-Wechsel über mehrere Vaults: gesichert, neu geschrieben, bei Fehler zurückgeschrieben
    MeshVaultRecord *backup = [newbie record];
    check([newbie storeKeys:generated pin:@"555555"] && [newbie openWithPin_:@"555555"], "rekeyed");
    check([newbie restoreRecord:backup] && [newbie openWithPin_:@"444444"] && ![newbie openWithPin_:@"555555"], "restored old pin");
    check(![newbie restoreRecord:nil], "nothing to restore");

    // Passphrase: scrypt, Art steht lesbar im Eintrag (Sperrbildschirm zeigt das passende Feld)
    NSString *phrase = @"aalen abarbeiten abartig abbaden abbaggern";
    check([newbie storeKeys:generated secret:phrase kdf:MeshVaultScrypt] && newbie.kdf == MeshVaultScrypt && empty.row.iterations == MeshVaultScryptN, "passphrase stored with scrypt");
    check([[newbie openWithPin_:phrase].seckey isEqual:generated.seckey] && ![newbie openWithPin_:@"aalen abarbeiten abartig abbaden"], "passphrase opens, shorter does not");
    empty.row.iterations = 1 << 24;
    check(![newbie openWithPin_:phrase], "absurd scrypt cost refused");
    empty.row.iterations = 1 << 15;
    check(![newbie openWithPin_:phrase], "other scrypt cost refused");
    check([newbie storeKeys:generated pin:@"666666"] && [newbie openWithPin_:@"666666"], "pbkdf2 again");
    empty.row.iterations = 1000;
    check(![newbie openWithPin_:@"666666"], "too few pbkdf2 rounds refused");
    empty.row.iterations = MeshVaultIterations; empty.row.kdf = (MeshVaultKDF)7;
    check(![newbie openWithPin_:@"666666"], "unknown kdf refused");

    return testsDone();
}}
