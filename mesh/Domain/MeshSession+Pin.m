// PIN-Sperre und Notlöschung (siehe MeshSession.h).
#import "MeshSession+Internal.h"
#import "MeshIdentity.h"
#import "MeshKeys.h"
#import "MeshVault.h"
#import "MeshVaultRecord.h"
#import "MeshDeviceSecret.h"
#import "MeshPinGuard.h"
#import "MeshPanic.h"
#import "MeshMessenger.h"
#import "MeshRelayPool.h"
#import "MeshMemory.h"
#import "MeshLog.h"
#import "MeshPassphrase.h"
#import "MeshTor.h"

static const int kWipeAfterFailures = 30;   // wie Android: so viele falsche PINs löschen alles

@implementation MeshSession (Pin)

#pragma mark - PIN-Sperre

- (BOOL)needsSetup { return ![self.active.vault exists]; }

+ (BOOL)isValidPin:(NSString *)pin {
    if (pin.length != MeshPinLength) return NO;
    for (NSUInteger i = 0; i < MeshPinLength; i++) { unichar c = [pin characterAtIndex:i]; if (c < '0' || c > '9') return NO; }
    return YES;
}

// Passphrasen: mindestens 5 Wörter, alle aus der Liste (also von der App gewürfelt).
+ (BOOL)isValidSecret:(NSString *)secret kind:(MeshSecretKind)kind {
    if (kind == MeshSecretPin) return [self isValidPin:secret];
    NSString *n = [MeshPassphrase normalize:secret];
    NSUInteger words = [n componentsSeparatedByString:@" "].count;
    return n.length && words >= MeshPassphraseWords && [MeshPassphrase knownWordsIn:n] == words;
}

- (MeshSecretKind)secretKind { return self.active.vault.kdf == MeshVaultScrypt ? MeshSecretWords : MeshSecretPin; }

static MeshVaultKDF kdfFor(MeshSecretKind kind) { return kind == MeshSecretWords ? MeshVaultScrypt : MeshVaultPBKDF2; }

// Groß/klein, Satzzeichen und Leerzeichen zählen bei Passphrasen nicht.
- (NSString *)normalized:(NSString *)secret kind:(MeshSecretKind)kind {
    return kind == MeshSecretWords ? [MeshPassphrase normalize:secret] : secret;
}

// Der Panik-Code im Wörter-Modus ist frei gewählt: Ziffern und Zeichen zählen (sonst wären "1234"
// leer und "hallo1" gleich "hallo2"), nur Groß/klein und Leerzeichen am Rand nicht.
- (NSString *)panicForm:(NSString *)secret kind:(MeshSecretKind)kind {
    if (kind != MeshSecretWords) return secret;
    NSArray *parts = [[secret ?: @"" lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

// Gerätegeheimnis aus dem Schlüsselbund in die Vaults, nur solange es gebraucht wird (gesperrt
// liegt es nicht im RAM). Ist der Vault schon gebunden, nie ein neues anlegen, sonst wäre er
// verloren. "Anderes Gerät" führt zum Angebot, alles zu löschen: nur melden, wenn es sicher fehlt.
- (MeshPinResult)loadDeviceSecret {
    if (self.active.vault.deviceSecret) return MeshPinOK;
    BOOL bound = self.active.vault.boundToDevice, notFound = NO;
    NSData *secret = bound ? [MeshDeviceSecret existingNotFound:&notFound] : [MeshDeviceSecret existingOrCreate];
    for (MeshIdentity *i in self.allIdentities) i.vault.deviceSecret = secret;   // jeder Vault hält seine eigene Kopie
    MeshWipe(secret);
    if (secret) return MeshPinOK;
    return bound && notFound ? MeshPinDeviceChanged : MeshPinKeychainBusy;
}

- (void)forgetDeviceSecretIfLocked {
    if (self.unlocked) return;
    for (MeshIdentity *i in self.allIdentities) i.vault.deviceSecret = nil;
}

- (MeshPinResult)setupWithPin:(NSString *)pin { return [self setupWithSecret:pin kind:MeshSecretPin]; }

- (MeshPinResult)setupWithSecret:(NSString *)secret kind:(MeshSecretKind)kind {
    if (![MeshSession isValidSecret:secret kind:kind] || [self.active.vault exists]) return MeshPinFailed;
    if ([self loadDeviceSecret] != MeshPinOK) return MeshPinKeychainBusy;   // ohne Geheimnis kein Vault
    NSString *pin = [self normalized:secret kind:kind];
    MeshKeys *k = [self.active.vault createWithSecret:pin kdf:kdfFor(kind)];
    if (!k) { [self forgetDeviceSecretIfLocked]; return MeshPinFailed; }
    [self.guard reset];
    [self didUnlock:k pin:pin];
    return MeshPinOK;
}

// Gemeinsamer Weg für Entsperren und Prüfen: Sperrzeit beachten, Fehlversuche zählen.
- (MeshKeys *)checkPin:(NSString *)pin result:(MeshPinResult *)result {
    MeshKeys *k = [self openVaultWithPin:pin result:result];
    if (!k) [self forgetDeviceSecretIfLocked];
    return k;
}

// pin wie eingegeben: für den Vault vereinheitlicht, für den Panik-Code in dessen eigener Form.
- (MeshKeys *)openVaultWithPin:(NSString *)input result:(MeshPinResult *)result {
    MeshVault *vault = self.active.vault;
    MeshSecretKind kind = [self secretKind];
    NSString *pin = [self normalized:input kind:kind], *panicPin = [self panicForm:input kind:kind];
    if ([self.guard waitRemaining] > 0) { *result = MeshPinLockedOut; return nil; }
    MeshPinResult secret = [self loadDeviceSecret];
    if (![vault recordReadable]) { *result = MeshPinStorageUnreadable; return nil; }
    if (![vault readyToOpen]) { *result = secret == MeshPinOK ? MeshPinKeychainBusy : secret; return nil; }
    // Panik-PIN vor der echten: löscht, statt zu entsperren.
    if ([self.panic matchesPin:panicPin deviceSecret:vault.deviceSecret]) { [self wipe]; *result = MeshPinWiped; return nil; }
    // Erst zählen, dann rechnen: Wer die App während der Ableitung beendet, spart keinen Versuch.
    // Ein alter, ungebundener Vault öffnet auch ohne Geheimnis.
    [self.guard recordFailure];
    MeshVaultOpen open;
    MeshKeys *k = [vault openWithPin:pin result:&open];
    if (open == MeshVaultSecretMissing) { *result = MeshPinKeychainBusy; return nil; }
    if (!k && [self.guard failures] >= kWipeAfterFailures) { [self wipe]; *result = MeshPinWiped; return nil; }
    if (!k) { *result = MeshPinWrong; return nil; }
    [self.guard reset];
    *result = MeshPinOK;
    return k;
}

- (MeshPinResult)unlockWithPin:(NSString *)pin {
    MeshPinResult r;
    MeshKeys *k = [self checkPin:pin result:&r];
    if (!k) return r;
    [self didUnlock:k pin:[self normalized:pin kind:[self secretKind]]];
    return MeshPinOK;
}

// Angezeigte Identität mit ihrem Schlüssel, die übrigen mit derselben PIN; dann online gehen.
- (void)didUnlock:(MeshKeys *)k pin:(NSString *)pin {
    self.unlocked = YES;
    [self.active unlockWithKeys:k panic:self.panic delegate:self];
    for (MeshIdentity *i in self.allIdentities) {
        if (i == self.active || ![i.vault exists]) continue;
        MeshVaultOpen open;
        MeshKeys *ik = [i.vault openWithPin:pin result:&open];
        if (ik) [i unlockWithKeys:ik panic:self.panic delegate:self];
        else MeshLog(@"Identität %d ließ sich nicht entsperren", i.slot);
    }
    [self goOnline];
}

- (void)resetEverything {
    [self stopWatching];
    [self lock];
    [self.panic clearAll];
    for (MeshIdentity *i in self.allIdentities) {
        [i destroy];
        if (i.slot != 0) [[NSFileManager defaultManager] removeItemAtPath:[MeshIdentity databasePathForSlot:i.slot] error:NULL];
    }
    [MeshIdentity saveSlots:@[@0] active:0];
    self.allIdentities = [NSMutableArray arrayWithObject:[[MeshIdentity alloc] initWithSlot:0]];
    self.active = self.allIdentities[0];
    [MeshDeviceSecret remove];   // meldet Fehler selbst im Log (MeshKeychain)
    [[MeshTor shared] forgetState];
    MeshLogRemove();
    [self.guard reset];
}

// PIN gegen den Vault prüfen, ohne etwas zu entsperren oder zu sperren.
- (MeshPinResult)verifyPin:(NSString *)pin {
    MeshPinResult r;
    [[self checkPin:pin result:&r] wipe];
    return r;
}

// Neuer Code = alle Schlüssel neu verschlüsseln (neues Salt/IV). Alle oder keiner: Ließe sich eine
// Identität nicht öffnen, bliebe sie auf dem alten Code und wäre danach unerreichbar; scheitert
// ein Schreiben, gehen die schon geänderten Vaults auf den alten Stand zurück.
- (MeshPinResult)setNewPin:(NSString *)newPin { return [self setNewSecret:newPin kind:MeshSecretPin]; }

// Auch der Wechsel zwischen PIN und Passphrase. Eine Panik-PIN passt dann nicht mehr zur Eingabe
// am Sperrbildschirm und wird entfernt (die Oberfläche sagt das).
- (MeshPinResult)setNewSecret:(NSString *)secret kind:(MeshSecretKind)kind {
    if (![MeshSession isValidSecret:secret kind:kind] || !self.active.keys) return MeshPinFailed;
    if ([self loadDeviceSecret] != MeshPinOK) return MeshPinKeychainBusy;
    NSString *newPin = [self normalized:secret kind:kind];
    BOOL kindChanges = kind != [self secretKind];
    // Die Panik-PIN wird vor der echten geprüft: als neue echte PIN würde sie beim Entsperren löschen.
    if (!kindChanges && [self.panic matchesPin:[self panicForm:secret kind:kind] deviceSecret:self.active.vault.deviceSecret]) return MeshPinSameAsPanic;
    for (MeshIdentity *i in self.allIdentities) if ([i.vault exists] && !i.keys) return MeshPinFailed;
    NSMutableArray *done = [NSMutableArray array], *backups = [NSMutableArray array];
    for (MeshIdentity *i in [self unlockedIdentities]) {
        MeshVaultRecord *backup = [i.vault record];
        if (backup && [i.vault storeKeys:i.keys secret:newPin kdf:kdfFor(kind)]) { [done addObject:i]; [backups addObject:backup]; continue; }
        for (NSUInteger n = 0; n < done.count; n++) [[done[n] vault] restoreRecord:backups[n]];
        return MeshPinFailed;
    }
    if (kindChanges) [self.panic clearPin];
    return MeshPinOK;
}

- (NSTimeInterval)pinWaitRemaining { return [self.guard waitRemaining]; }
- (BOOL)keyBoundToDevice { return self.active.vault.boundToDevice; }

#pragma mark - Notlöschung

- (void)wipe {
    MeshLog(@"Notlöschung");
    [self resetEverything];
    [self notify:MeshWipedNotification];
}

// Gilt erst, wenn es für jede Identität ein Token gibt (nach einer neuen Identität neu setzen).
- (BOOL)hasPanicCodeword { return [self.panic hasCodeword] && [self.panic codewordIdentities] >= self.allIdentities.count; }

- (BOOL)panicCodewordNeedsRenewal { return [self.panic hasCodeword] && ![self hasPanicCodeword]; }

- (BOOL)setPanicCodeword:(NSString *)codeword {
    NSMutableArray *pubkeys = [NSMutableArray array];
    for (MeshIdentity *i in self.allIdentities) if (i.vault.pubkey.length == 64) [pubkeys addObject:i.vault.pubkey];
    return pubkeys.count && [self.panic setCodeword:codeword pubkeys:pubkeys];
}

- (BOOL)hasPanicPin { return [self.panic hasPin]; }

// Im Passphrase-Modus ist der Panik-Code ein frei gewähltes Wort oder mehrere (er muss nur nicht
// erraten werden, sondern sich unter Druck eintippen lassen).
- (MeshPinResult)setPanicPin:(NSString *)secret {
    MeshSecretKind kind = [self secretKind];
    NSString *pin = [self panicForm:secret kind:kind];
    BOOL valid = kind == MeshSecretPin ? [MeshSession isValidPin:pin] : pin.length >= 4;
    if (!valid || !self.active.keys) return MeshPinFailed;
    if ([self loadDeviceSecret] != MeshPinOK) return MeshPinKeychainBusy;
    MeshVaultOpen open;
    MeshKeys *real = [self.active.vault openWithPin:[self normalized:secret kind:kind] result:&open];
    if (real) { [real wipe]; return MeshPinSameAsReal; }   // sonst würde normales Entsperren löschen
    return [self.panic setPin:pin deviceSecret:self.active.vault.deviceSecret] ? MeshPinOK : MeshPinFailed;
}

- (void)clearPanicPin { [self.panic clearPin]; }

- (BOOL)sendPanicTrigger:(NSString *)codeword to:(NSString *)peerHex { return [self.active.messenger sendPanicTrigger:codeword to:peerHex]; }

@end
