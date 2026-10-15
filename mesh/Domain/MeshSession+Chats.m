// Kontakte, Chats und Nachrichten der angezeigten Identität (siehe MeshSession.h).
#import "MeshSession+Internal.h"
#import "MeshIdentity.h"
#import "MeshMessenger.h"
#import "MeshSignal.h"
#import "MeshStore.h"
#import "MeshStore+Signal.h"
#import "MeshStore+Chat.h"
#import "MeshMessage.h"
#import "MeshChat.h"
#import "MeshPayload.h"
#import "MeshContactCode.h"
#import "MeshSafetyCode.h"
#import "MeshHex.h"
#import "MeshBech32.h"
#import "MeshTeam.h"
#import "MeshGroupState.h"
#import "MeshStore+Group.h"
#import "MeshTime.h"
#import "MeshL10n.h"

@implementation MeshSession (Chats)

#pragma mark - Senden

- (BOOL)sendContent:(NSString *)content to:(NSString *)peerHex replyTo:(NSString *)replyTo {
    MeshMessenger *messenger = self.active.messenger;
    if (!messenger) return NO;   // z.B. eine Sprachnachricht, deren Kodierung erst nach dem Sperren fertig wird
    NSString *gid = MeshGroupOfChat(peerHex);
    MeshMessage *m = gid ? [messenger sendGroup:gid content:content replyTo:replyTo]
                   : MeshIsTeamChat(peerHex) ? [self.active.team send:content]   // nur Text, anonym, ohne Antwort-Bezug
                   : [messenger send:content to:peerHex replyTo:replyTo];
    if (m) [self messagesChanged];
    return m != nil;
}

- (BOOL)sendTo:(NSString *)peerHex text:(NSString *)text replyTo:(NSString *)replyTo {
    return text.length && [self sendContent:text to:peerHex replyTo:replyTo];
}

- (BOOL)tooLargeForGroup:(NSString *)chat image:(NSData *)jpeg {
    return MeshGroupOfChat(chat) && jpeg.length && ![MeshMessenger fitsGroup:[MeshPayload contentWithImage:jpeg]];
}

- (BOOL)tooLargeForGroup:(NSString *)chat voice:(NSData *)audio seconds:(int)seconds {
    return MeshGroupOfChat(chat) && audio.length && ![MeshMessenger fitsGroup:[MeshPayload contentWithVoice:audio seconds:seconds]];
}

- (BOOL)sendImageTo:(NSString *)peerHex jpeg:(NSData *)jpeg replyTo:(NSString *)replyTo {
    return jpeg.length && [self sendContent:[MeshPayload contentWithImage:jpeg] to:peerHex replyTo:replyTo];
}

- (BOOL)sendVoiceTo:(NSString *)peerHex audio:(NSData *)audio seconds:(int)seconds replyTo:(NSString *)replyTo {
    return audio.length && [self sendContent:[MeshPayload contentWithVoice:audio seconds:seconds] to:peerHex replyTo:replyTo];
}

- (BOOL)sendFileTo:(NSString *)peerHex data:(NSData *)data name:(NSString *)name mime:(NSString *)mime replyTo:(NSString *)replyTo {
    if (!data.length || data.length > MeshMaxFileBytes) return NO;
    if (MeshGroupOfChat(peerHex) || MeshIsTeamChat(peerHex)) return NO;   // Dateien nur im 1:1-Chat
    return [self sendContent:[MeshPayload contentWithFile:data name:name mime:mime] to:peerHex replyTo:replyTo];
}

- (BOOL)sendContact:(NSString *)contactHex to:(NSString *)peerHex {
    NSString *code = [MeshContactCode codeWithNpub:[self npubFor:contactHex] bundle:[self.active.store bundleForContact:contactHex]];
    return [self sendContent:[MeshPayload contentWithContactName:[self displayNameFor:contactHex] code:code] to:peerHex replyTo:nil];
}

- (NSArray *)acceptedContacts { return [self.active.store acceptedContactPubkeys]; }

#pragma mark - Reaktionen, Löschen, Selbstlöschen

- (void)react:(NSString *)emoji to:(MeshMessage *)message in:(NSString *)peerHex {
    if (MeshIsTeamChat(peerHex)) return;
    NSString *gid = MeshGroupOfChat(peerHex);
    BOOL ok = gid ? [self.active.messenger reactInGroup:gid emoji:emoji to:message] : [self.active.messenger react:emoji to:message in:peerHex];
    if (ok) [self messagesChanged];
}

- (BOOL)deleteForEveryone:(MeshMessage *)message in:(NSString *)peerHex {
    if (MeshIsTeamChat(peerHex)) return NO;
    NSString *gid = MeshGroupOfChat(peerHex);
    BOOL ok = gid ? [self.active.messenger deleteInGroup:gid message:message] : [self.active.messenger deleteForEveryone:message in:peerHex];
    if (ok) [self messagesChanged];
    return ok;
}

- (void)clearChat:(NSString *)peerHex forEveryone:(BOOL)everyone {
    if (MeshGroupOfChat(peerHex) || MeshIsTeamChat(peerHex)) [self.active.store clearChat:peerHex at:MeshNow()];   // nur lokal
    else [self.active.messenger clearChat:peerHex forEveryone:everyone];
    [self messagesChanged];
}

- (int)timerFor:(NSString *)peerHex fromSent:(BOOL *)fromSent {
    NSString *gid = MeshGroupOfChat(peerHex);
    if (gid || MeshIsTeamChat(peerHex)) {   // Gruppe: aus dem Zustand des Admins; Team-Chat: nie
        MeshGroupState *s = gid ? [self.active.messenger groupState:gid status:NULL inviter:NULL] : nil;
        if (fromSent) *fromSent = s.timerFromSent;
        return s.timer;
    }
    return [self.active.messenger timerFor:peerHex fromSent:fromSent];
}

- (void)setTimer:(int)seconds fromSent:(BOOL)fromSent for:(NSString *)peerHex {
    NSString *gid = MeshGroupOfChat(peerHex);
    if (MeshIsTeamChat(peerHex)) return;
    if (gid) [self.active.messenger setGroupTimer:seconds fromSent:fromSent group:gid];   // nur der Admin
    else [self.active.messenger setTimer:seconds fromSent:fromSent for:peerHex];
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
    [self.active.messenger sendPictureTo:hex];   // privat: Android-Kontakte sehen unser kind-0-Bild sonst nicht
    [self.active.messenger contactAccepted:hex];   // B8.5: zurückgehaltene Gruppeneinladungen von ihm
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
    if (MeshIsTeamChat(peerHex)) return @"Mesh Team";
    NSString *gid = MeshGroupOfChat(peerHex);
    if (gid) return [self.active.messenger groupState:gid status:NULL inviter:NULL].name ?: L(@"Group");
    MeshStore *store = self.active.store;
    BOOL accepted = [store isAccepted:peerHex];
    return contactDisplayName(peerHex, [store nameForContact:peerHex], [store profileNameForContact:peerHex], accepted);
}

- (NSString *)pictureFor:(NSString *)peerHex {
    NSString *gid = MeshGroupOfChat(peerHex);
    if (gid) return [self.active.messenger groupPicture:gid];   // B7: nur beigetreten, passend zum Zustand
    if (MeshIsTeamChat(peerHex)) return nil;
    MeshStore *store = self.active.store;
    return [store isAccepted:peerHex] ? [store picForContact:peerHex] : nil;
}

- (NSString *)aboutFor:(NSString *)peerHex {
    if (MeshGroupOfChat(peerHex) || MeshIsTeamChat(peerHex)) return nil;
    MeshStore *store = self.active.store;
    return [store isAccepted:peerHex] ? [store aboutForContact:peerHex] : nil;
}

// Gruppe: beigetreten (auch wenn inzwischen nur noch lesbar); Einladung nicht. Team-Chat: immer.
- (BOOL)isAccepted:(NSString *)peerHex {
    if (MeshIsTeamChat(peerHex)) return YES;
    NSString *gid = MeshGroupOfChat(peerHex);
    if (gid) {
        MeshGroupStatus status = MeshGroupInvited;
        return [self.active.messenger groupState:gid status:&status inviter:NULL] && status != MeshGroupInvited;
    }
    return [self.active.store isAccepted:peerHex];
}

- (void)acceptContact:(NSString *)peerHex {
    [self.active.store setAccepted:peerHex];
    [self.active.store forgetProfileTimeOf:peerHex];   // das Profil mit Bild neu laden (als Anfrage nur der Name)
    [self.active.messenger sendPictureTo:peerHex];     // eigenes Bild privat; die Gegenseite antwortet mit ihrem
    [self.active.messenger contactAccepted:peerHex];   // B8.5: zurückgehaltene Gruppeneinladungen von ihm
    [self requestProfileOf:peerHex];
    [self notifyProfileOf:peerHex];
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

- (NSString *)safetyCodeQRWith:(NSString *)peerHex {
    NSArray *groups = [self safetyNumberWith:peerHex];
    return groups ? [MeshSafetyCode payloadFrom:[self myPubkeyHex] to:peerHex groups:groups] : nil;
}

- (MeshSafetyScan)checkSafetyScan:(NSString *)scanned with:(NSString *)peerHex {
    NSArray *groups = [self safetyNumberWith:peerHex];
    if (!groups) return MeshSafetyNotACode;
    MeshSafetyScan r = [MeshSafetyCode check:scanned me:[self myPubkeyHex] peer:peerHex groups:groups];
    if (r == MeshSafetyMatch) [self setVerified:YES for:peerHex];
    return r;
}

- (BOOL)usesSignalWith:(NSString *)peerHex { return [self.active.signal hasSessionWith:peerHex]; }
- (BOOL)isVerified:(NSString *)peerHex { return [self.active.store isVerified:peerHex]; }
- (void)setVerified:(BOOL)verified for:(NSString *)peerHex { [self.active.store setVerified:peerHex verified:verified]; }

- (void)deleteChat:(NSString *)peerHex {
    NSString *gid = MeshGroupOfChat(peerHex);
    if (MeshIsTeamChat(peerHex)) self.active.team.hidden = YES;   // Team-Chat: nur ausblenden
    else if (gid) [self.active.messenger deleteGroup:gid];         // erst verlassen, dann lokal löschen
    else [self.active.store deleteContact:peerHex];
    [self notify:MeshMessagesChangedNotification];
}

- (void)blockContact:(NSString *)peerHex {
    if (MeshGroupOfChat(peerHex) || MeshIsTeamChat(peerHex)) return;
    [self.active.store blockContact:peerHex];
    [self notify:MeshMessagesChangedNotification];
}

#pragma mark - Chats

// Chats der angezeigten Identität, im gemeinsamen Posteingang die aller entsperrten (wie Android).
- (NSArray *)chatList {
    NSMutableArray *chats = [NSMutableArray array];
    MeshChat *team = nil;
    NSArray *identities = self.unifiedInbox ? [self unlockedIdentities] : @[self.active];
    for (MeshIdentity *i in identities) {
        if (!i.keys) continue;
        NSMutableSet *groupsSeen = [NSMutableSet set];
        for (MeshChat *c in [i.store chatList]) {   // bringt Namen und Annahme gleich mit
            c.identitySlot = i.slot;
            c.identityPubkey = i.pubkey;
            if (MeshIsTeamChat(c.pubkey)) {   // angeheftet, nur für die angezeigte Identität
                if (i == self.active && i.team && !i.team.hidden) { c.isTeam = YES; c.name = @"Mesh Team"; team = c; }
                continue;
            }
            NSString *gid = MeshGroupOfChat(c.pubkey);
            if (gid) {
                if (![self fillGroupRow:c gid:gid identity:i]) continue;
                [groupsSeen addObject:gid];
            } else {
                c.name = contactDisplayName(c.pubkey, c.ownName, c.profileName, !c.unknown);
            }
            [chats addObject:c];
        }
        // Gruppen ohne Nachricht (Einladung, gerade angelegt)
        for (NSString *gid in [i.store groupIds]) {
            if ([groupsSeen containsObject:gid]) continue;
            MeshChat *c = [[MeshChat alloc] init];
            c.pubkey = MeshGroupChat(gid);
            c.identitySlot = i.slot;
            c.identityPubkey = i.pubkey;
            c.ts = [i.store groupCreated:gid];
            c.lastContent = @"";
            if ([self fillGroupRow:c gid:gid identity:i]) [chats addObject:c];
        }
    }
    [chats sortUsingComparator:^NSComparisonResult(MeshChat *a, MeshChat *b) {
        return a.ts == b.ts ? NSOrderedSame : a.ts > b.ts ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (team) [chats insertObject:team atIndex:0];
    return chats;
}

// Name, Stand und Absender einer Gruppenzeile; NO, wenn der Zustand nicht lesbar ist.
- (BOOL)fillGroupRow:(MeshChat *)c gid:(NSString *)gid identity:(MeshIdentity *)i {
    MeshGroupStatus status = MeshGroupInvited;
    NSString *inviter = nil;
    MeshGroupState *s = [i.messenger groupState:gid status:&status inviter:&inviter];
    if (!s) return NO;
    c.isGroup = YES;
    c.groupStatus = status;
    c.name = s.name;
    if (status == MeshGroupInvited && inviter)
        c.inviter = contactDisplayName(inviter, [i.store nameForContact:inviter], [i.store profileNameForContact:inviter], YES);
    if (c.sender.length && !c.fromMe) c.senderName = [self memberName:c.sender state:s store:i.store];
    return YES;
}

// Mitglied: eigener Kontaktname (angenommen), sonst der Name aus der Gruppe mit "~abcd" (erste 4 Hex
// des Pubkeys) dahinter, damit sich niemand unbemerkt als Kontakt ausgibt; ohne Namen das Kürzel.
- (NSString *)memberName:(NSString *)pk state:(MeshGroupState *)s store:(MeshStore *)store {
    if ([store isAccepted:pk]) return contactDisplayName(pk, [store nameForContact:pk], [store profileNameForContact:pk], YES);
    NSString *n = [s nameOf:pk];
    if (!n.length) return [pk substringToIndex:MIN((NSUInteger)8, pk.length)];
    return [NSString stringWithFormat:@"%@ ~%@", n, [pk substringToIndex:MIN((NSUInteger)4, pk.length)]];
}

- (NSString *)senderName:(NSString *)pk inChat:(NSString *)chat {
    if ([pk isEqualToString:[self myPubkeyHex]]) return L(@"You");
    NSString *gid = MeshGroupOfChat(chat);
    MeshGroupState *s = gid ? [self.active.messenger groupState:gid status:NULL inviter:NULL] : nil;
    return [self memberName:pk state:s store:self.active.store];
}

- (NSArray *)messagesWith:(NSString *)peerHex { return [self.active.store messagesForChat:peerHex]; }
- (NSArray *)messagesWith:(NSString *)peerHex limit:(NSUInteger)limit { return [self.active.store messagesForChat:peerHex limit:limit]; }

- (NSArray *)messagesWith:(NSString *)peerHex before:(MeshMessage *)oldest limit:(NSUInteger)limit {
    if (!oldest) return [self messagesWith:peerHex limit:limit];
    return [self.active.store messagesForChat:peerHex beforeTs:oldest.ts rowId:oldest.rowId limit:limit];
}

- (NSUInteger)messageCountFrom:(NSString *)key in:(NSString *)peerHex { return [self.active.store countFromKey:key chat:peerHex]; }
- (NSUInteger)messageCountAfter:(long long)ts in:(NSString *)peerHex { return [self.active.store countAfterTs:ts chat:peerHex]; }
- (BOOL)hasMessage:(NSString *)key in:(NSString *)peerHex { return [self.active.store hasMessageWithKey:key chat:peerHex]; }

- (NSData *)mediaOf:(MeshMessage *)m {
    if (m.kind != MeshPayloadImage && m.kind != MeshPayloadVoice && m.kind != MeshPayloadFile) return nil;
    return [[self payloadOf:m] data];
}

- (MeshPayload *)payloadOf:(MeshMessage *)m {
    NSString *content = [self.active.store contentOfMessage:m.rowId];
    return content ? [MeshPayload parse:content] : nil;
}

- (NSArray *)mediaWith:(NSString *)peerHex { return [self.active.store mediaForChat:peerHex]; }

// Ungeprüfte Dateien einmal einordnen (danach gemerkt), dann nur noch zählen.
- (NSUInteger)mediaCountWith:(NSString *)peerHex onlyMine:(BOOL)mine {
    MeshStore *store = self.active.store;
    for (MeshMessage *m in [store unclassifiedFilesForChat:peerHex onlyMine:mine]) [self isVideo:m];
    return [store mediaCountForChat:peerHex onlyMine:mine];
}

// Ob eine Datei ein Video ist, steht nur im verschlüsselten Inhalt. Einmal nachsehen und in width
// vermerken (-1 Video, -2 andere Datei): Zeilenhöhen und Galerie brauchen dann nichts zu entschlüsseln.
- (BOOL)isVideo:(MeshMessage *)m {
    if (m.kind != MeshPayloadFile) return NO;
    if (m.width) return m.width == -1;
    MeshPayload *p = [self payloadOf:m];
    if (!p) {   // entsperrt und trotzdem nicht lesbar: nicht bei jedem Zählen neu entschlüsseln
        if (self.unlocked && self.active.store) [self rememberImageWidth:-2 height:0 of:m];
        return NO;
    }
    BOOL video = [p.fileMime isEqualToString:@"video/mp4"];
    [self rememberImageWidth:video ? -1 : -2 height:0 of:m];
    return video;
}

- (long long)readAtIn:(NSString *)peerHex { return [self.active.store readAtForChat:peerHex]; }
- (void)markReadIn:(NSString *)peerHex { [self.active.store setReadAt:(long long)[[NSDate date] timeIntervalSince1970] chat:peerHex]; }

- (void)rememberImageWidth:(int)width height:(int)height of:(MeshMessage *)message {
    [self.active.store setImageWidth:width height:height ofMessage:message.rowId];
    message.width = width;
    message.height = height;
}

@end
