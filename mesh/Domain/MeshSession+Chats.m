// Kontakte, Chats und Nachrichten der angezeigten Identität (siehe MeshSession.h).
#import "MeshSession+Internal.h"
#import "MeshIdentity.h"
#import "MeshMessenger.h"
#import "MeshSignal.h"
#import "MeshStore.h"
#import "MeshStore+Signal.h"
#import "MeshMessage.h"
#import "MeshChat.h"
#import "MeshPayload.h"
#import "MeshContactCode.h"
#import "MeshHex.h"
#import "MeshBech32.h"

@implementation MeshSession (Chats)

#pragma mark - Senden

- (BOOL)sendContent:(NSString *)content to:(NSString *)peerHex replyTo:(NSString *)replyTo {
    MeshMessenger *messenger = self.active.messenger;
    if (!messenger) return NO;   // z.B. eine Sprachnachricht, deren Kodierung erst nach dem Sperren fertig wird
    MeshMessage *m = [messenger send:content to:peerHex replyTo:replyTo];
    if (m) [self messagesChanged];
    return m != nil;
}

- (BOOL)sendTo:(NSString *)peerHex text:(NSString *)text replyTo:(NSString *)replyTo {
    return text.length && [self sendContent:text to:peerHex replyTo:replyTo];
}

- (BOOL)sendImageTo:(NSString *)peerHex jpeg:(NSData *)jpeg replyTo:(NSString *)replyTo {
    return jpeg.length && [self sendContent:[MeshPayload contentWithImage:jpeg] to:peerHex replyTo:replyTo];
}

- (BOOL)sendVoiceTo:(NSString *)peerHex audio:(NSData *)audio seconds:(int)seconds replyTo:(NSString *)replyTo {
    return audio.length && [self sendContent:[MeshPayload contentWithVoice:audio seconds:seconds] to:peerHex replyTo:replyTo];
}

- (BOOL)sendFileTo:(NSString *)peerHex data:(NSData *)data name:(NSString *)name mime:(NSString *)mime replyTo:(NSString *)replyTo {
    if (!data.length || data.length > MeshMaxFileBytes) return NO;
    return [self sendContent:[MeshPayload contentWithFile:data name:name mime:mime] to:peerHex replyTo:replyTo];
}

- (BOOL)sendContact:(NSString *)contactHex to:(NSString *)peerHex {
    NSString *code = [MeshContactCode codeWithNpub:[self npubFor:contactHex] bundle:[self.active.store bundleForContact:contactHex]];
    return [self sendContent:[MeshPayload contentWithContactName:[self displayNameFor:contactHex] code:code] to:peerHex replyTo:nil];
}

- (NSArray *)acceptedContacts { return [self.active.store acceptedContactPubkeys]; }

#pragma mark - Reaktionen, Löschen, Selbstlöschen

- (void)react:(NSString *)emoji to:(MeshMessage *)message in:(NSString *)peerHex {
    if ([self.active.messenger react:emoji to:message in:peerHex]) [self messagesChanged];
}

- (BOOL)deleteForEveryone:(MeshMessage *)message in:(NSString *)peerHex {
    BOOL ok = [self.active.messenger deleteForEveryone:message in:peerHex];
    if (ok) [self messagesChanged];
    return ok;
}

- (void)clearChat:(NSString *)peerHex forEveryone:(BOOL)everyone {
    [self.active.messenger clearChat:peerHex forEveryone:everyone];
    [self messagesChanged];
}

- (int)timerFor:(NSString *)peerHex fromSent:(BOOL *)fromSent { return [self.active.messenger timerFor:peerHex fromSent:fromSent]; }

- (void)setTimer:(int)seconds fromSent:(BOOL)fromSent for:(NSString *)peerHex {
    [self.active.messenger setTimer:seconds fromSent:fromSent for:peerHex];
    [self messagesChanged];
}

- (MeshMessage *)message:(NSString *)key in:(NSString *)peerHex { return [self.active.store messageWithKey:key chat:peerHex]; }

- (void)deleteMessage:(MeshMessage *)message {
    [self.active.store deleteMessage:message.rowId];
    [self notify:MeshMessagesChangedNotification];
}

#pragma mark - Kontakte

- (NSString *)pubkeyOfContactCode:(NSString *)code { return [MeshContactCode parse:code].pubkey; }

- (NSString *)addContact:(NSString *)npubOrHex name:(NSString *)name {
    MeshStore *store = self.active.store;
    MeshContactCode *code = [MeshContactCode parse:npubOrHex];
    NSString *hex = code.pubkey;
    if (!hex || [hex isEqualToString:[self myPubkeyHex]]) return nil;   // sich selbst anlegen ergibt keinen Chat
    // Wer einen blockierten Kontakt bewusst wieder hinzufügt, will seine Antworten auch sehen.
    [store unblockContact:hex];
    // Leerer Name -> Anzeigename kommt aus dem geladenen Profil (kind-0), sonst Kürzel.
    [store upsertContact:hex name:(name.length ? name : @"") accepted:YES];
    // Mesh-Code mit Signal-Bundle: gleich mit Forward Secrecy schreiben. Der Handshake schickt das
    // eigene Bundle, damit auch die Gegenseite sofort Signal nutzt (wie Android beim Hinzufügen).
    if (code.bundle && ![store isVerified:hex]) [store setBundle:code.bundle forContact:hex];
    [self.active.messenger sayHelloTo:hex];
    [self requestProfileOf:hex];
    [self notify:MeshMessagesChangedNotification];
    return hex;
}

// Anzeigename: selbst vergebener Name, sonst Profilname, sonst Kürzel. Bei nicht angenommenen
// Kontakten nur das Kürzel, sonst könnte sich ein Fremder per Profilname als "Alice" ausgeben.
static NSString *contactDisplayName(NSString *peerHex, NSString *own, NSString *profile, BOOL accepted) {
    NSString *shortHex = peerHex.length > 8 ? [peerHex substringToIndex:8] : peerHex;
    if (own.length && ![own isEqualToString:shortHex]) return own;   // alter Default war das Kürzel
    // Auch bei Anfragen der Profilname: die Oberfläche hängt dort "· Anfrage" an (MeshFormat contactName),
    // damit sich kein Fremder unmarkiert "Mama" nennen kann.
    return profile.length ? profile : shortHex;
}

- (NSString *)displayNameFor:(NSString *)peerHex {
    MeshStore *store = self.active.store;
    BOOL accepted = [store isAccepted:peerHex];
    return contactDisplayName(peerHex, [store nameForContact:peerHex], [store profileNameForContact:peerHex], accepted);
}

- (NSString *)pictureFor:(NSString *)peerHex {
    MeshStore *store = self.active.store;
    return [store isAccepted:peerHex] ? [store picForContact:peerHex] : nil;
}

- (BOOL)isAccepted:(NSString *)peerHex { return [self.active.store isAccepted:peerHex]; }

- (void)acceptContact:(NSString *)peerHex {
    [self.active.store setAccepted:peerHex];
    [self.active.store forgetProfileTimeOf:peerHex];   // das Profil mit Bild neu laden (als Anfrage nur der Name)
    [self requestProfileOf:peerHex];
    [self notify:MeshProfilesChangedNotification];
    [self notify:MeshMessagesChangedNotification];
}

- (NSString *)npubFor:(NSString *)peerHex { return [MeshBech32 encodeHrp:@"npub" data:[MeshHex decode:peerHex]]; }

// Wie Android aus den Signal-Identitäten; nil, solange das Bundle des Kontakts fehlt.
- (NSArray *)safetyNumberWith:(NSString *)peerHex {
    NSString *bundle = [self.active.store bundleForContact:peerHex];
    return bundle ? [self.active.signal safetyNumberWith:peerHex myPubkey:[self myPubkeyHex] peerBundle:bundle] : nil;
}

- (NSString *)myContactCode {
    NSString *npub = [self myNpub];
    return npub ? [MeshContactCode codeWithNpub:npub bundle:[self.active.signal bundleWithFreshOneTimeKey]] : nil;
}

- (NSString *)myStaticContactCode {
    NSString *npub = [self myNpub];
    return npub ? [MeshContactCode codeWithNpub:npub bundle:[self.active.signal bundle]] : nil;
}

- (BOOL)usesSignalWith:(NSString *)peerHex { return [self.active.signal hasSessionWith:peerHex]; }
- (BOOL)isVerified:(NSString *)peerHex { return [self.active.store isVerified:peerHex]; }
- (void)setVerified:(BOOL)verified for:(NSString *)peerHex { [self.active.store setVerified:peerHex verified:verified]; }

- (void)deleteChat:(NSString *)peerHex {
    [self.active.store deleteContact:peerHex];
    [self notify:MeshMessagesChangedNotification];
}

- (void)blockContact:(NSString *)peerHex {
    [self.active.store blockContact:peerHex];
    [self notify:MeshMessagesChangedNotification];
}

#pragma mark - Chats

// Chats der angezeigten Identität, im gemeinsamen Posteingang die aller entsperrten (wie Android).
- (NSArray *)chatList {
    NSMutableArray *chats = [NSMutableArray array];
    NSArray *identities = self.unifiedInbox ? [self unlockedIdentities] : @[self.active];
    for (MeshIdentity *i in identities) {
        if (!i.keys) continue;
        for (MeshChat *c in [i.store chatList]) {   // bringt Namen und Annahme gleich mit
            c.name = contactDisplayName(c.pubkey, c.ownName, c.profileName, !c.unknown);
            c.identitySlot = i.slot;
            c.identityPubkey = i.pubkey;
            [chats addObject:c];
        }
    }
    [chats sortUsingComparator:^NSComparisonResult(MeshChat *a, MeshChat *b) {
        return a.ts == b.ts ? NSOrderedSame : a.ts > b.ts ? NSOrderedAscending : NSOrderedDescending;
    }];
    return chats;
}

- (NSArray *)messagesWith:(NSString *)peerHex { return [self.active.store messagesForChat:peerHex]; }
- (NSArray *)messagesWith:(NSString *)peerHex limit:(NSUInteger)limit { return [self.active.store messagesForChat:peerHex limit:limit]; }

- (NSData *)mediaOf:(MeshMessage *)m {
    if (m.kind != MeshPayloadImage && m.kind != MeshPayloadVoice && m.kind != MeshPayloadFile) return nil;
    return [[self payloadOf:m] data];
}

- (MeshPayload *)payloadOf:(MeshMessage *)m {
    NSString *content = [self.active.store contentOfMessage:m.rowId];
    return content ? [MeshPayload parse:content] : nil;
}

- (void)rememberImageWidth:(int)width height:(int)height of:(MeshMessage *)message {
    [self.active.store setImageWidth:width height:height ofMessage:message.rowId];
    message.width = width;
    message.height = height;
}

@end
