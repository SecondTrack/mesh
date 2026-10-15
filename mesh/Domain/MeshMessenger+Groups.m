// Gruppen (docs/TEAM_GROUPS_PROTOCOL.md, Teil B, mit den Klarstellungen B8): Einladen, Beitreten,
// Zustand, Verlassen und Gruppennachrichten. Regeln beim Empfang:
//  - Einladung nur vom Admin der Gruppe und nur von einem angenommenen Kontakt. Ist der Absender (noch)
//    kein angenommener Kontakt, wird sie versiegelt zurückgehalten (B8.5, 30 Tage, höchstens 20) und
//    erscheint, sobald er angenommen wird.
//  - Zustand nur vom gespeicherten Admin, höhere Revision; neue Gruppen entstehen nie aus einem Zustand.
//    B9: ein neues a nur, wenn es in m steht (Übergabe); danach gilt nur noch das neue a. Ein Zustand von
//    einem Mitglied, das (noch) nicht Admin ist, wartet bis 15 min im RAM (Übergabe unterwegs).
//    gl vom Admin heißt aufgelöst (B8.7), wirkt aber erst nach 15 min ohne Übergabe (sonst normaler Austritt).
//  - B9/B10 (Vorschläge, Bürgschaften, offene Gruppen, Link-Beitritt): MeshMessenger+GroupsOpen.m.
//  - Gruppenbild (B7) nur vom Admin, nur beigetreten, nur wenn der Hash zum p des Zustands passt; kommt
//    es vor dem Zustand, wartet höchstens eins je Gruppe im RAM.
//  - Nachrichten nur, wenn ich beigetreten bin und der Absender in meinem m steht. Kommen sie vor dem
//    passenden Zustand, warten sie im RAM (B8.4) und werden nach jedem angewandten Zustand erneut geprüft.
//    Keine Fremden-Regel (die Mitglieder sind bekannt), aber Größengrenzen (B8.3) und keine Dateien
//    (B8.2); kein Bundle, kein Kontakt, keine Panik.
// Steueranweisungen werden einmal angewendet und dann als erledigt gemerkt; was nur noch nicht passt
// (gepuffert, zurückgehalten), bekommt keinen Vermerk, damit Relays es später erneut liefern dürfen.
#import "MeshMessenger+Internal.h"
#import "MeshStore.h"
#import "MeshStore+Chat.h"
#import "MeshStore+Group.h"
#import "MeshGroupState.h"
#import "MeshEnvelope.h"
#import "MeshEvent.h"
#import "MeshKeys.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshChat.h"
#import "MeshHex.h"
#import "MeshJSON.h"
#import "MeshTime.h"
#import "MeshText.h"
#import "MeshCrypto.h"
#import "MeshLog.h"
#import "MeshBase64.h"
#import "MeshStore+Outbox.h"
#import "MeshMessenger+GroupsInternal.h"

static const long long kInviteLifetime = 30 * 24 * 3600;   // offene Einladungen vergisst der Admin danach
static const long long kMaxClockSkew = 15 * 60;
static const NSUInteger kMaxEmoji = 32;
static const int kMaxInvitesPerInviter = 5, kMaxInvites = 50;   // offene Einladungen (wie Android)
static const NSUInteger kMaxStateJSON = 16 * 1024, kMaxJSONDepth = 4;
static const NSUInteger kMaxGroupPicture = 64 * 1024;      // B7: rohe Bytes, wie das Profilbild
static const NSUInteger kMaxPendingPictures = 16;          // wartende Gruppenbilder insgesamt (je Gruppe eins)
static const NSUInteger kMaxBufferedPerGroup = 50;         // B8.4: früh angekommene Events je Gruppe
static const long long kBufferLifetime = 15 * 60;          // B8.4: so lange warten sie
static const NSUInteger kMaxBufferedBytes = 2 * 1024 * 1024;   // alle Gruppen zusammen (256 MB RAM)
static const int kMaxHeldInvites = 20, kMaxHeldPerSender = 5;  // B8.5: zurückgehaltene Einladungen
static const long long kRemovedMemory = 24 * 3600;         // B10: so lange kein Link-Beitritt nach dem Entfernen

// Gruppenbild: JPEG oder PNG (Magic Bytes), 1 Byte bis 64 KB. Dekodiert wird erst beim Anzeigen
// über MeshImageCodec (Kopfprüfung + eigener Decoder).
static BOOL isGroupPicture(NSData *d) {
    if (!d.length || d.length > kMaxGroupPicture) return NO;
    const uint8_t *b = d.bytes;
    static const uint8_t png[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    return (d.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) || (d.length >= 8 && !memcmp(b, png, 8));
}

static NSString *pictureHash(NSData *d) {
    return d ? [[MeshHex encode:[MeshCrypto sha256:d]] substringToIndex:16] : nil;
}

// Länge des Inhalts (Base64) je Art: Text 64 KB, Bild 256 KB, Sprache 512 KB (B8.3, jede Kopie geht an
// bis zu 19 Mitglieder). Dateien und Videos gibt es in Gruppen nicht (B8.2: mesh:file und mesh:fc).
static NSUInteger maxGroupContent(MeshPayloadKind kind) {
    switch (kind) {
        case MeshPayloadText:
        case MeshPayloadContact: return 64 * 1024;
        case MeshPayloadImage:   return 256 * 1024;
        case MeshPayloadVoice:   return 512 * 1024;
        default:                 return 0;
    }
}

@implementation MeshPendingGroupEvent
@end

// cmid einer Gruppennachricht: 1–64 Hex-Zeichen (Android: 16), klein. nil sonst.
static NSString *validCmid(NSString *cmid) {
    if (!cmid.length || cmid.length > 64) return nil;
    for (NSUInteger i = 0; i < cmid.length; i++) {
        unichar c = [cmid characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return nil;
    }
    return cmid.lowercaseString;
}

static MeshGroupState *parseState(NSString *json) {
    NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
    id obj = d.length && d.length <= kMaxStateJSON && MeshJSONShallow(d, kMaxJSONDepth) ? [MeshJSON objectWithData:d] : nil;
    return [MeshGroupState stateFromObject:obj];
}

// Name eines Mitglieds für Systemzeilen: aus dem Zustand, bei Nicht-Kontakten mit "~abcd" (erste
// 4 Hex des Pubkeys) gegen Nachahmung; ohne Namen das Kürzel.
static NSString *labelFor(MeshGroupState *s, NSString *pk, BOOL contact) {
    NSString *n = [s nameOf:pk];
    if (!n.length) return [pk substringToIndex:MIN((NSUInteger)8, pk.length)];
    return contact ? n : [NSString stringWithFormat:@"%@ ~%@", n, [pk substringToIndex:MIN((NSUInteger)4, pk.length)]];
}
#define memberLabel(s, pk) labelFor((s), (pk), [self.store isAccepted:(pk)])

@implementation MeshMessenger (Groups)

#pragma mark - Zustand

- (MeshGroupState *)groupState:(NSString *)gid status:(MeshGroupStatus *)status inviter:(NSString **)inviter {
    if (![MeshEnvelope isGroupId:gid]) return nil;
    MeshGroupState *s = parseState([self.store groupState:gid.lowercaseString status:status inviter:inviter]);
    return [s.gid isEqualToString:gid.lowercaseString] ? s : nil;   // versiegelt an die gid gebunden, doppelt hält besser
}

- (NSArray *)pendingInvitesForGroup:(NSString *)gid {
    return [self.store invitesForGroup:gid since:MeshNow() - kInviteLifetime];
}

+ (NSString *)groupPictureHash:(NSData *)bytes { return pictureHash(bytes); }

+ (BOOL)fitsGroup:(NSString *)content {
    NSUInteger max = maxGroupContent([MeshPayload kindOf:content]);
    return content.length && max && content.length <= max;
}

// Nur beigetreten (Einladungen zeigen noch kein Bild) und nur, wenn es zum p des Zustands passt.
- (NSString *)groupPicture:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || status == MeshGroupInvited) return nil;
    NSData *d = [self storedPictureOf:s];
    return d ? [MeshBase64 encode:d] : nil;
}

- (BOOL)maintainGroups {
    [self.store pruneInvitesBefore:MeshNow() - kInviteLifetime];
    BOOL changed = [self maintainOpenGroups];   // B9/B10: Vorschläge, Bürgschaften, Link-Beitritte, Aufgeschobenes
    return [self contactAccepted:nil] || changed;
}

#pragma mark - Admin

- (NSString *)createGroup:(NSString *)name members:(NSArray *)pubkeys myName:(NSString *)myName {
    NSString *gid = [MeshHex encode:[MeshCrypto randomBytes:8]];
    MeshGroupState *s = [MeshGroupState stateWithGroup:gid name:name admin:self.myPubkey adminName:myName ?: @""];
    if (!s || ![self save:s status:MeshGroupMember inviter:nil]) return nil;
    [self notice:MeshGroupNoticeCreated name:s.name gid:gid byMe:YES];
    [self invite:pubkeys toGroup:gid];
    return gid;
}

// Nur angenommene Kontakte; m und offene Einladungen zusammen höchstens 20. B8.1: jede Einladung (auch
// eine erneute) erzeugt einen Zustand mit r+1, der an die Mitglieder geht und in gi reist. So nehmen auch
// früher Entfernte oder Ausgetretene sie an (deren Stand hat eine ältere Revision).
- (BOOL)invite:(NSArray *)pubkeys toGroup:(NSString *)gid { return [self invite:pubkeys toGroup:gid allowing:nil]; }

// allowing: Nicht-Kontakte, die trotzdem eingeladen werden dürfen (B9: angenommener Vorschlag).
- (BOOL)invite:(NSArray *)pubkeys toGroup:(NSString *)gid allowing:(NSString *)allowed {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status]) return NO;
    NSMutableSet *pending = [NSMutableSet setWithArray:[self pendingInvitesForGroup:s.gid]];
    NSMutableArray *targets = [NSMutableArray array];
    for (NSString *raw in pubkeys) {
        NSString *pk = [raw isKindOfClass:[NSString class]] ? raw.lowercaseString : nil;
        if (![MeshGroupState isPubkey:pk] || [s hasMember:pk] || [targets containsObject:pk] || [self.store isBlocked:pk] || [pk isEqualToString:self.myPubkey]) continue;
        if (![self.store isAccepted:pk] && ![pk isEqualToString:allowed]) continue;
        if (![pending containsObject:pk] && s.members.count + pending.count >= MeshGroupMaxMembers) break;
        [pending addObject:pk];
        [targets addObject:pk];
    }
    if (!targets.count) return NO;
    MeshGroupState *next = [s bumped];
    if (!next || ![self publish:next extra:nil]) return NO;
    NSString *invite = [MeshEnvelope groupInvite:[next json]];
    BOOL any = NO;
    for (NSString *pk in targets) {
        MeshEvent *e = [self eventWith:invite to:pk];
        if (!e) continue;
        [self.store addInvite:pk group:s.gid at:MeshNow()];
        [self forgetProposalsOf:pk gid:s.gid];
        [self.delegate messenger:self send:e];
        any = YES;
    }
    return any;
}

- (BOOL)removeMember:(NSString *)pk fromGroup:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status]) return NO;
    if (![s hasMember:pk]) {   // noch nicht beigetreten: nur die Einladung vergessen
        [self.store removeInvite:pk group:s.gid];
        return YES;
    }
    MeshGroupState *next = [s withoutMember:pk];
    if (!next || ![self publish:next extra:pk]) return NO;
    [self.store addGroupRecord:MeshGroupRecordRemoved gid:s.gid data:pk at:MeshNow()];   // B10: 24 h kein Link-Beitritt
    [self notice:MeshGroupNoticeRemoved name:memberLabel(s, pk) gid:s.gid byMe:YES];
    return YES;
}

- (BOOL)renameGroup:(NSString *)gid to:(NSString *)name {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status]) return NO;
    MeshGroupState *next = [s renamed:name];
    if (!next || [next.name isEqualToString:s.name] || ![self publish:next extra:nil]) return NO;
    [self notice:MeshGroupNoticeRenamed name:next.name gid:s.gid byMe:YES];
    return YES;
}

- (BOOL)setGroupTimer:(int)seconds fromSent:(BOOL)fromSent group:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status]) return NO;
    MeshGroupState *next = [s withTimer:seconds fromSent:fromSent];
    if (!next || ![self publish:next extra:nil]) return NO;
    if (next.timer != s.timer) [self addNotice:[MeshPayload noticeTimer:next.timer byMe:YES] chat:MeshGroupChat(s.gid) byMe:YES];
    return YES;
}

// B7: neues Bild = r+1, Zustand an alle, dazu das Bild an jedes Mitglied. nil = entfernen (ohne gp).
- (BOOL)setGroupPicture:(NSData *)bytes group:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status] || (bytes && !isGroupPicture(bytes))) return NO;
    MeshGroupState *next = [s withPicture:pictureHash(bytes)];
    if (!next) return NO;
    NSData *old = [self storedPictureOf:s];
    if (![self storePicture:bytes gid:s.gid]) return NO;
    if (![self publish:next extra:nil]) { [self storePicture:old gid:s.gid]; return NO; }
    if (bytes) [self sendControl:[MeshEnvelope groupPicture:bytes gid:s.gid] toAll:[self recipientsOf:next]];
    [self pictureChanged:s.gid];
    return YES;
}

#pragma mark - Mitglied

- (BOOL)acceptInvite:(NSString *)gid myName:(NSString *)myName {
    MeshGroupStatus status = MeshGroupMember;
    NSString *inviter = nil;
    MeshGroupState *s = [self groupState:gid status:&status inviter:&inviter];
    if (!s || status != MeshGroupInvited || s.dissolved) return NO;
    // B9: Admin kein angenommener Kontakt -> nur mit gültiger Bürgschaft (der Bürge muss weiter Kontakt sein)
    if (([self.store isBlocked:s.admin] || ![self.store isAccepted:s.admin]) && ![self voucherFor:s.gid admin:s.admin]) return NO;
    NSString *join = [MeshEnvelope groupJoin:s.gid name:[MeshGroupState cleanName:myName max:MeshGroupMaxMemberName]];
    if (![self sendControl:join toAll:@[s.admin]]) return NO;
    BOOL member = [s hasMember:self.myPubkey];
    if (![self.store setGroupStatus:(member ? MeshGroupMember : MeshGroupJoining) gid:s.gid]) return NO;
    [self forgetVouchersFor:s.gid];
    if (member) [self replayGroup:s.gid];
    return YES;
}

- (void)declineInvite:(NSString *)gid {
    MeshGroupStatus status = MeshGroupMember;
    if ([self groupState:gid status:&status inviter:NULL] && status == MeshGroupInvited) {
        [self forgetVouchersFor:gid.lowercaseString];
        [self.store deleteGroup:gid.lowercaseString];
    }
}

- (BOOL)deletingDissolves:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    return [self amAdminOf:s status:status];
}

// Mitglied: "verlassen" an Admin und alle. Admin: Zustand mit m = [] (r+1) UND gl (B8.7), auch an offen
// Eingeladene (deren Einladung verschwindet dann). Noch nicht hinausgegangene Kopien eigener Nachrichten
// bleiben liegen: wer gegangen ist, schreibt nicht mehr in die Gruppe.
- (BOOL)leaveGroup:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || (status != MeshGroupMember && status != MeshGroupJoining && status != MeshGroupLinkJoining)) return NO;
    NSArray *to = [self recipientsOf:s];
    if (![to containsObject:s.admin] && ![s.admin isEqualToString:self.myPubkey]) to = [to arrayByAddingObject:s.admin];
    [self dropQueuedCopiesOf:s.gid];
    if ([self amAdminOf:s status:status]) {
        for (NSString *pk in [self pendingInvitesForGroup:s.gid]) if (![to containsObject:pk]) to = [to arrayByAddingObject:pk];
        MeshGroupState *gone = [s dissolvedState];
        if (!gone || ![self save:gone status:MeshGroupDissolved inviter:nil]) return NO;
        [self sendControl:[MeshEnvelope groupState:[gone json]] toAll:to];
        [self sendControl:[MeshEnvelope groupLeave:s.gid] toAll:to];
        [self notice:MeshGroupNoticeDissolved name:@"" gid:s.gid byMe:YES];
        return YES;
    }
    [self sendControl:[MeshEnvelope groupLeave:s.gid] toAll:to];
    [self.store setGroupStatus:MeshGroupLeft gid:s.gid];
    [self notice:MeshGroupNoticeYouLeft name:@"" gid:s.gid byMe:YES];
    return YES;
}

- (BOOL)deleteGroup:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s) return NO;
    if (status == MeshGroupMember || status == MeshGroupJoining || status == MeshGroupLinkJoining) [self leaveGroup:gid];
    [self.pendingGroupEvents removeObjectForKey:s.gid];
    [self.heldGroupControl removeObjectForKey:s.gid];
    [self forgetVouchersFor:s.gid];
    return [self.store deleteGroup:s.gid];   // Trigger: Fan-out-Kopien der Nachrichten verlassen die Warteschlange
}

#pragma mark - Nachrichten senden

- (NSString *)groupPlain:(NSString *)content gid:(NSString *)gid cmid:(NSString *)cmid replyTo:(NSString *)replyTo
                   timer:(int)timer mode:(MeshTimerMode)mode to:(NSString *)pk {
    // Bundle nur an angenommene Kontakte: Nicht-Kontakte bekommen keins (kein Signal-Aufbau mit Fremden)
    NSString *bundle = [self.store isAccepted:pk] ? [self ownBundleFor:pk] : nil;
    return [MeshEnvelope inGroup:gid plain:[MeshEnvelope message:content cmid:cmid replyTo:replyTo timer:timer mode:mode bundle:bundle]];
}

// Die erste Kopie entsteht sofort (ihre Event-ID und Zeit trägt die Nachricht), die übrigen schrittweise
// (fanoutStep, je Runloop-Durchgang eine). Jede Event-ID steht dauerhaft in fanout: Haken, Löschen und
// Ablauf erfassen alle Kopien, auch nach Sperren und Entsperren.
- (MeshMessage *)sendGroup:(NSString *)gid content:(NSString *)content replyTo:(NSString *)replyTo {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || status != MeshGroupMember || s.dissolved || ![MeshMessenger fitsGroup:content]) return nil;

    MeshMessage *m = [[MeshMessage alloc] init];
    m.fromMe = YES;
    m.cmid = [MeshEnvelope newMessageId];
    m.replyTo = replyTo;
    m.timer = s.timer;
    m.ts = MeshNow();
    MeshTimerMode mode = s.timerFromSent ? MeshTimerFromSent : MeshTimerFromRead;
    NSMutableArray *rest = [[self recipientsOf:s] mutableCopy];
    BOOL anyone = rest.count > 0;
    MeshEvent *first = nil;
    while (!first && rest.count) @autoreleasepool {
        NSString *pk = rest[0];
        [rest removeObjectAtIndex:0];
        // verifizierter Kontakt mit fremder Identität: fällt hier heraus
        first = [self eventWith:[self groupPlain:content gid:s.gid cmid:m.cmid replyTo:replyTo timer:s.timer mode:mode to:pk] to:pk];
    }
    if (anyone && !first) return nil;
    if (first) { m.ts = first.createdAt; m.eventId = first.eventId; }
    else m.status = MeshMessageDelivered;   // allein in der Gruppe: nichts zu senden
    if (s.timer > 0 && s.timerFromSent) m.expiresAt = m.ts + s.timer;
    if (![self.store insertMessage:m chat:MeshGroupChat(s.gid) content:content]) return nil;
    if (first) {
        [self.store addFanout:first.eventId message:m.rowId];
        [self.delegate messenger:self send:first];
    }
    if (rest.count) {
        [self.fanoutJobs addObject:[@{ @"gid": s.gid, @"row": @(m.rowId), @"content": content, @"cmid": m.cmid,
                                        @"reply": replyTo ?: @"", @"timer": @(s.timer), @"mode": @(mode), @"to": rest } mutableCopy]];
        [self scheduleFanout];
    }
    return m;
}

// Noch nicht gebaute und noch nicht bestätigte Kopien eigener Nachrichten dieser Gruppe verwerfen
// (Verlassen, Entfernt, Aufgelöst). Was schon ein Relay hat, ist unterwegs.
- (void)dropQueuedCopiesOf:(NSString *)gid {
    NSIndexSet *mine = [self.fanoutJobs indexesOfObjectsPassingTest:^BOOL(NSDictionary *job, NSUInteger i, BOOL *stop) { return [job[@"gid"] isEqualToString:gid]; }];
    [self.fanoutJobs removeObjectsAtIndexes:mine];
    [self.store dropQueuedCopiesInChat:MeshGroupChat(gid)];
}

- (BOOL)reactInGroup:(NSString *)gid emoji:(NSString *)emoji to:(MeshMessage *)message {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    NSString *key = message.key;
    if (!s || status != MeshGroupMember || !key.length) return NO;
    NSString *next = [message.reactMine isEqualToString:emoji] ? @"" : (emoji ?: @"");
    NSString *chat = MeshGroupChat(s.gid);
    if (![self.store setReaction:next mine:YES key:key chat:chat]) return NO;
    message.reactMine = next.length ? next : nil;
    [self sendControl:[MeshEnvelope inGroup:s.gid plain:[MeshEnvelope reactionTo:key emoji:next]] toAll:[self recipientsOf:s]];
    return YES;
}

- (BOOL)deleteInGroup:(NSString *)gid message:(MeshMessage *)message {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || !message.fromMe || !message.key.length) return NO;
    [self.store deleteMessage:message.rowId];   // Trigger: noch wartende Kopien gehen nicht mehr hinaus
    if (status == MeshGroupMember)
        [self sendControl:[MeshEnvelope inGroup:s.gid plain:[MeshEnvelope deletionOf:message.key]] toAll:[self recipientsOf:s]];
    return YES;
}

#pragma mark - Zurückgehaltene Einladungen (B8.5)

// Von einem angenommenen Kontakt (peer, nil = alle prüfen): zeigen, was er als Admin geschickt hat.
// Von Blockierten verwerfen, älter als 30 Tage verwerfen, alles andere bleibt liegen.
- (BOOL)contactAccepted:(NSString *)peer {
    [self.store pruneHeldInvitesBefore:MeshNow() - kInviteLifetime];
    BOOL changed = NO;
    for (NSArray *row in [self.store heldInvites]) {
        long long rowId = [row[0] longLongValue];
        NSDictionary *o = [row[1] length] ? [MeshJSON objectWithData:[row[1] dataUsingEncoding:NSUTF8StringEncoding]] : nil;
        NSString *from = [o isKindOfClass:[NSDictionary class]] && [o[@"f"] isKindOfClass:[NSString class]] ? o[@"f"] : nil;
        NSString *json = [o isKindOfClass:[NSDictionary class]] && [o[@"s"] isKindOfClass:[NSString class]] ? o[@"s"] : nil;
        if (![MeshGroupState isPubkey:from] || !json || [self.store isBlocked:from]) { [self.store removeHeldInvite:rowId]; continue; }
        MeshGroupState *s = parseState(json);
        // B9: auch ohne Kontakt, wenn eine gültige Bürgschaft für genau diese gid und diesen Admin vorliegt
        BOOL vouched = s && [self voucherFor:s.gid admin:from] != nil;
        if (!vouched && ((peer && ![from isEqualToString:peer]) || ![self.store isAccepted:from])) continue;
        [self.store removeHeldInvite:rowId];
        if (s && [s.admin isEqualToString:from] && !s.dissolved) changed |= [self applyInvite:s from:from];
    }
    return changed;
}

- (void)holdInvite:(MeshGroupState *)s from:(NSString *)from eventId:(NSString *)eventId {
    [self.store pruneHeldInvitesBefore:MeshNow() - kInviteLifetime];
    NSArray *held = [self.store heldInvites];
    if ((int)held.count >= kMaxHeldInvites) return;   // voll: nicht merken (Relays dürfen später erneut liefern)
    int fromSender = 0;
    for (NSArray *row in held) {
        NSDictionary *o = [row[1] length] ? [MeshJSON objectWithData:[row[1] dataUsingEncoding:NSUTF8StringEncoding]] : nil;
        if (![o isKindOfClass:[NSDictionary class]]) continue;
        if ([o[@"e"] isEqual:eventId]) return;   // schon zurückgehalten
        if ([o[@"f"] isEqual:from] && [o[@"g"] isEqual:s.gid]) [self.store removeHeldInvite:[row[0] longLongValue]];   // neuere ersetzt ältere
        else if ([o[@"f"] isEqual:from]) fromSender++;
    }
    if (fromSender >= kMaxHeldPerSender) return;
    NSData *j = [MeshJSON dataWithObject:@{ @"f": from, @"g": s.gid, @"e": eventId ?: @"", @"s": [s json] }];
    if (j) [self.store holdInvite:[[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] at:MeshNow()];
}

@end

@implementation MeshMessenger (GroupHelpers)

- (BOOL)save:(MeshGroupState *)s status:(MeshGroupStatus)status inviter:(NSString *)inviter {
    return s && [self.store saveGroup:s.gid state:[s json] status:status inviter:inviter];
}

- (NSArray *)recipientsOf:(MeshGroupState *)s {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *pk in s.members) if (![pk isEqualToString:self.myPubkey]) [out addObject:pk];
    return out;
}

// Steueranweisung einzeln an jeden; Anzahl der gesendeten.
- (NSUInteger)sendControl:(NSString *)plain toAll:(NSArray *)peers {
    NSUInteger n = 0;
    for (NSString *pk in peers) @autoreleasepool {
        MeshEvent *e = [self eventWith:plain to:pk];
        if (!e) continue;
        [self.delegate messenger:self send:e];
        n++;
    }
    return n;
}

- (void)notice:(MeshGroupNotice)event name:(NSString *)name gid:(NSString *)gid byMe:(BOOL)byMe {
    [self addNotice:[MeshPayload noticeGroup:event name:name] chat:MeshGroupChat(gid) byMe:byMe];
}

- (BOOL)amAdminOf:(MeshGroupState *)s status:(MeshGroupStatus)status {
    return s && status == MeshGroupMember && [s.admin isEqualToString:self.myPubkey] && !s.dissolved;
}

// Neuer Zustand an alle Mitglieder (und an extra, z.B. ein gerade Entferntes).
- (BOOL)publish:(MeshGroupState *)s extra:(NSString *)extra {
    if (![self save:s status:MeshGroupMember inviter:nil]) return NO;
    NSMutableArray *to = [[self recipientsOf:s] mutableCopy];
    if (extra && ![to containsObject:extra]) [to addObject:extra];
    [self sendControl:[MeshEnvelope groupState:[s json]] toAll:to];
    return YES;
}

#pragma mark - Empfangen

// keep: nicht als erledigt merken (zurückgehalten, B8.5).
- (BOOL)receiveInvite:(MeshEnvelope *)env event:(MeshEvent *)event keep:(BOOL *)keep {
    NSString *from = event.pubkey;
    if ([self.store isBlocked:from]) return NO;
    MeshGroupState *s = parseState(env.groupState);
    if (!s || ![s.admin isEqualToString:from] || s.dissolved) return NO;          // nur der Admin lädt ein
    if (![self.store isAccepted:from] && ![self voucherFor:s.gid admin:from]) {   // kein Kontakt, keine Bürgschaft: zurückhalten
        [self holdInvite:s from:from eventId:event.eventId];
        *keep = YES;
        return NO;
    }
    return [self applyInvite:s from:from];
}

// Admin-Bedingungen wie beim direkten Empfang (auch für zurückgehaltene).
- (BOOL)applyInvite:(MeshGroupState *)s from:(NSString *)from {
    BOOL trusted = [self.store isAccepted:from] || [self voucherFor:s.gid admin:from];   // B8.5 bzw. Bürgschaft (B9)
    if (!trusted || [self.store isBlocked:from] || ![s.admin isEqualToString:from] || s.dissolved) return NO;
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *known = [self groupState:s.gid status:&status inviter:NULL];
    if (known) {
        // B1 gilt auch für Einladungen: gleicher Admin, höhere Revision (wie Android). Wer früher ging, hat noch
        // den alten Admin gespeichert und lehnt die Einladung eines neuen ab; eine abgelaufene Einladung (B9)
        // trägt schon den Übergabe-Zustand und nimmt die des neuen Admins an.
        if (![known.admin isEqualToString:s.admin] || s.revision <= known.revision) return NO;
        if (status == MeshGroupMember || status == MeshGroupJoining) return [self receiveState:s from:from];
    } else if ([self.store groupIds].count >= kMaxGroups) {
        return NO;
    }
    // Spam-Deckel: offene Einladungen höchstens 5 je Einladendem, 50 insgesamt
    if (status != MeshGroupInvited || !known) {
        if ([self.store invitationCountFrom:from] >= kMaxInvitesPerInviter || [self.store invitationCountFrom:nil] >= kMaxInvites) return NO;
    }
    return [self save:s status:MeshGroupInvited inviter:from];
}

- (BOOL)receiveState:(MeshGroupState *)s from:(NSString *)from { BOOL keep = NO; return [self receiveState:s from:from keep:&keep]; }

// keep: nicht als erledigt merken (wartet im RAM auf die Übergabe, B9).
- (BOOL)receiveState:(MeshGroupState *)s from:(NSString *)from keep:(BOOL *)keep {
    if (!s) return NO;
    MeshGroupStatus status = MeshGroupInvited;
    NSString *inviter = nil;
    MeshGroupState *known = [self groupState:s.gid status:&status inviter:&inviter];
    if (!known || s.revision <= known.revision) return NO;
    NSString *me = self.myPubkey;
    BOOL active = status == MeshGroupMember || status == MeshGroupJoining;
    if (![from isEqualToString:known.admin]) {
        // B9: ein Mitglied, das sich selbst als Admin führt, kann der neue Admin sein, dessen Übergabe noch
        // unterwegs ist: bis 15 min im RAM halten (eins je Gruppe), nach jedem angewandten Zustand neu prüfen.
        if (active && [s.admin isEqualToString:from] && [known hasMember:from] && ![from isEqualToString:me]) {
            [self holdState:s from:from];
            *keep = YES;
        }
        return NO;
    }
    // Vom gespeicherten Admin signiert. Gleiches a: B1. Neues a: nur ein Mitglied aus m (B9-Übergabe).
    BOOL transfer = ![s.admin isEqualToString:known.admin];
    if (transfer && (s.dissolved || ![s hasMember:s.admin])) return NO;

    if (status == MeshGroupInvited) {   // Einladung aktualisieren; aufgelöst: Einladung still verwerfen
        if (transfer) {                 // B9: offene Einladung des alten Admins verfällt
            [self forgetVouchersFor:s.gid];
            if (![self save:s status:MeshGroupInviteExpired inviter:inviter]) return NO;
            [self notice:MeshGroupNoticeInviteExpired name:@"" gid:s.gid byMe:NO];
            return YES;
        }
        if (s.dissolved) return [self.store deleteGroup:s.gid];
        return [self save:s status:MeshGroupInvited inviter:inviter];
    }
    if (status == MeshGroupLinkJoining) return [self receiveFirstState:s known:known inviter:inviter];
    if (!active) return NO;   // verlassen/entfernt/aufgelöst/abgelaufen: nur lesbar

    MeshGroupStatus next = status;
    if (s.dissolved) next = MeshGroupDissolved;
    else if ([s hasMember:me]) next = MeshGroupMember;
    else if (status == MeshGroupMember) next = MeshGroupRemoved;   // Beitretende stehen erst nach dem Admin-Zustand drin
    if (![self save:s status:next inviter:inviter]) return NO;
    [self reconcilePictureOf:s joined:next == MeshGroupMember];
    if (transfer || !s.open) [self.store setGroupLinkKey:nil gid:s.gid];   // B10: k nur in offenen Gruppen desselben Admins

    if (next == MeshGroupDissolved || next == MeshGroupRemoved) {
        [self dropQueuedCopiesOf:s.gid];
        [self.pendingGroupEvents removeObjectForKey:s.gid];
        [self.heldGroupControl removeObjectForKey:s.gid];
        [self notice:next == MeshGroupDissolved ? MeshGroupNoticeDissolved : MeshGroupNoticeYouRemoved name:@"" gid:s.gid byMe:NO];
        return YES;
    }
    for (NSString *pk in s.members)
        if (![known hasMember:pk] && ![pk isEqualToString:me]) [self notice:MeshGroupNoticeJoined name:memberLabel(s, pk) gid:s.gid byMe:NO];
    for (NSString *pk in known.members)
        if (![s hasMember:pk]) [self notice:MeshGroupNoticeRemoved name:memberLabel(known, pk) gid:s.gid byMe:NO];
    if (transfer) {
        if ([s.admin isEqualToString:me]) [self notice:MeshGroupNoticeYouAdmin name:@"" gid:s.gid byMe:NO];
        else [self notice:MeshGroupNoticeNewAdmin name:memberLabel(s, s.admin) gid:s.gid byMe:NO];
    }
    if (s.open != known.open) [self notice:s.open ? MeshGroupNoticeOpened : MeshGroupNoticeClosed name:@"" gid:s.gid byMe:NO];
    if (![s.name isEqualToString:known.name]) [self notice:MeshGroupNoticeRenamed name:s.name gid:s.gid byMe:NO];
    if (s.timer != known.timer) [self addNotice:[MeshPayload noticeTimer:s.timer byMe:NO] chat:MeshGroupChat(s.gid) byMe:NO];
    [self stateApplied:s];                                   // B9/B10: Wartendes (Zustand, gl, gk) neu prüfen
    if (next == MeshGroupMember) [self replayGroup:s.gid];   // B8.4: früh Angekommenes jetzt prüfen
    return YES;
}

// B10: erster Zustand nach dem Beitritt per Link. Nur vom Admin aus dem Link (= gespeicherter Admin, kein
// Wechsel), mit mir in m, nicht aufgelöst, innerhalb von 7 Tagen. Alles andere wird nicht übernommen.
- (BOOL)receiveFirstState:(MeshGroupState *)s known:(MeshGroupState *)known inviter:(NSString *)inviter {
    if (![s.admin isEqualToString:known.admin] || s.dissolved || ![s hasMember:self.myPubkey] || [self linkJoinExpired:s.gid]) return NO;
    if (![self save:s status:MeshGroupMember inviter:inviter]) return NO;
    [self.store setGroupLinkAt:0 gid:s.gid];
    if (!s.open) [self.store setGroupLinkKey:nil gid:s.gid];
    [self reconcilePictureOf:s joined:YES];
    [self stateApplied:s];
    [self replayGroup:s.gid];
    return YES;
}

// Admin. Mit offener Einladung (≤ 30 Tage): normaler Beitritt, auch wenn ein k mitkommt. Sonst per Link (B10):
// Gruppe offen, k stimmt (konstante Zeit), nicht gesperrt, nicht in den letzten 24 h entfernt, höchstens 10
// Link-Beitritte je Stunde. "< 20" zählt nur Mitglieder.
- (BOOL)receiveJoin:(MeshEnvelope *)env from:(NSString *)from {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:env.group status:&status inviter:NULL];
    if (![self amAdminOf:s status:status] || [s hasMember:from] || s.members.count >= MeshGroupMaxMembers || [self.store isBlocked:from]) return NO;
    BOOL invited = [self.store hasInvite:from group:s.gid since:MeshNow() - kInviteLifetime];
    if (!invited && ![self linkJoinAllowed:s from:from key:env.joinKey]) return NO;
    MeshGroupState *next = [s withMember:from name:env.joinName];
    if (!next || ![self publish:next extra:nil]) return NO;
    if (!invited) [self.store addGroupRecord:MeshGroupRecordLinkJoin gid:s.gid data:@"" at:MeshNow()];
    NSData *picture = [self storedPictureOf:next];   // B7: das neue Mitglied bekommt Zustand (oben) und Bild
    if (picture) [self sendControl:[MeshEnvelope groupPicture:picture gid:s.gid] toAll:@[from]];
    NSString *k = next.open ? [self.store groupLinkKey:s.gid] : nil;   // B10: k nur an den Neuen
    if (k) [self sendControl:[MeshEnvelope groupKey:s.gid key:k] toAll:@[from]];
    [self.store removeInvite:from group:s.gid];
    [self forgetProposalsOf:from gid:s.gid];
    [self notice:MeshGroupNoticeJoined name:memberLabel(next, from) gid:s.gid byMe:NO];
    [self replayGroup:s.gid];   // B8.4: Nachrichten des Neuen, die vor dem Beitritt kamen
    return YES;
}

- (BOOL)linkJoinAllowed:(MeshGroupState *)s from:(NSString *)from key:(NSString *)key {
    NSString *k = s.open ? [self.store groupLinkKey:s.gid] : nil;
    NSData *a = key ? [MeshHex decode:key] : nil, *b = k ? [MeshHex decode:k] : nil;
    if (a.length != 16 || b.length != 16 || ![MeshCrypto constantTimeEqual:a to:b]) return NO;
    long long now = MeshNow();
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordRemoved gid:s.gid])
        if ([row[1] longLongValue] >= now - kRemovedMemory && [row[2] isEqualToString:from]) return NO;
    return [self.store groupRecordCount:MeshGroupRecordLinkJoin gid:s.gid since:now - 3600] < 10;
}

- (BOOL)receiveLeave:(NSString *)gid from:(NSString *)from { BOOL keep = NO; return [self receiveLeave:gid from:from keep:&keep]; }

// Ab sofort diesem Mitglied nichts mehr senden; der Admin entfernt es und verteilt den Zustand.
// Verlässt der Admin eine aktive Gruppe, kann eine Übergabe unterwegs sein (B9): gl bis 15 min im RAM halten;
// kommt die Übergabe, ist es ein normaler Austritt, sonst die Auflösung (B8.7, applyAdminLeave).
// Offene Einladung: gl des Admins verwirft sie sofort.
- (BOOL)receiveLeave:(NSString *)gid from:(NSString *)from keep:(BOOL *)keep {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || ![s hasMember:from] || [from isEqualToString:self.myPubkey]) return NO;
    if (status == MeshGroupInvited) return [from isEqualToString:s.admin] && [self.store deleteGroup:s.gid];
    if (status != MeshGroupMember && status != MeshGroupJoining) return NO;
    if ([from isEqualToString:s.admin]) {
        [self holdLeave:s.gid from:from];
        *keep = YES;
        return YES;   // nichts Sichtbares, aber so stellt MeshSession den Wecker (secondsUntilNextExpiry)
    }
    if ([self amAdminOf:s status:status]) {
        MeshGroupState *next = [s withoutMember:from];
        if (!next || ![self publish:next extra:nil]) return NO;
    } else if (![self save:[s locallyWithout:from] status:status inviter:nil]) {
        return NO;
    }
    [self notice:MeshGroupNoticeLeft name:memberLabel(s, from) gid:s.gid byMe:NO];
    return YES;
}

// B8.7 nach Ablauf der Wartezeit: der Admin ist gegangen, ohne zu übergeben -> aufgelöst.
- (BOOL)applyAdminLeave:(NSString *)gid from:(NSString *)from {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || ![s.admin isEqualToString:from] || (status != MeshGroupMember && status != MeshGroupJoining)) return NO;
    if (![self.store setGroupStatus:MeshGroupDissolved gid:s.gid]) return NO;
    [self dropQueuedCopiesOf:s.gid];
    [self.pendingGroupEvents removeObjectForKey:s.gid];
    [self.heldGroupControl removeObjectForKey:s.gid];
    [self notice:MeshGroupNoticeDissolved name:@"" gid:s.gid byMe:NO];
    return YES;
}

#pragma mark - Gruppenbild (B7)

// Gespeichertes Bild, nur wenn es zum p dieses Zustands passt (sonst nil).
- (NSData *)storedPictureOf:(MeshGroupState *)s {
    if (!s.picture) return nil;
    NSString *b64 = [self.store groupPicture:s.gid];
    NSData *d = b64 ? [MeshBase64 decode:b64] : nil;
    return isGroupPicture(d) && [pictureHash(d) isEqualToString:s.picture] ? d : nil;
}

- (BOOL)storePicture:(NSData *)bytes gid:(NSString *)gid {
    return [self.store setGroupPicture:(bytes ? [MeshBase64 encode:bytes] : nil) gid:gid];
}

- (void)pictureChanged:(NSString *)gid {
    if ([self.delegate respondsToSelector:@selector(messenger:changedPictureOf:)])
        [self.delegate messenger:self changedPictureOf:MeshGroupChat(gid)];
}

// Nach einem neuen Zustand: ein wartendes Bild mit passendem Hash übernehmen (nur beigetreten);
// ein gespeichertes, das nicht mehr passt (entfernt oder neues unterwegs), löschen.
- (void)reconcilePictureOf:(MeshGroupState *)s joined:(BOOL)joined {
    NSData *pending = self.pendingGroupPictures[s.gid];
    if (joined && pending && s.picture && [pictureHash(pending) isEqualToString:s.picture]) {
        [self.pendingGroupPictures removeObjectForKey:s.gid];
        if ([self storePicture:pending gid:s.gid]) [self pictureChanged:s.gid];
        return;
    }
    if ([self.store groupPicture:s.gid] && ![self storedPictureOf:s] && [self storePicture:nil gid:s.gid]) [self pictureChanged:s.gid];
}

// gp: nur vom Admin, nur wenn ich beigetreten bin (bzw. gerade beitrete: dann wartend), JPEG/PNG bis 64 KB,
// und der Hash muss zum p des gespeicherten Zustands passen; sonst höchstens eins je Gruppe merken.
- (BOOL)receiveGroupPicture:(MeshEnvelope *)env from:(NSString *)from {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:env.group status:&status inviter:NULL];
    NSData *d = env.groupPicture;
    if (!s || ![s.admin isEqualToString:from] || [from isEqualToString:self.myPubkey] || !isGroupPicture(d)) return NO;
    if (status != MeshGroupMember && status != MeshGroupJoining && status != MeshGroupLinkJoining) return NO;
    NSString *hash = pictureHash(d);
    if (status == MeshGroupMember && [hash isEqualToString:s.picture]) {
        [self.pendingGroupPictures removeObjectForKey:s.gid];
        NSData *old = [self storedPictureOf:s];
        if ([old isEqualToData:d] || ![self storePicture:d gid:s.gid]) return NO;
        [self pictureChanged:s.gid];
        return YES;
    }
    if (!self.pendingGroupPictures[s.gid] && self.pendingGroupPictures.count >= kMaxPendingPictures) return NO;
    self.pendingGroupPictures[s.gid] = d;   // das neueste ersetzt ein älteres wartendes
    return NO;
}

#pragma mark - Gruppennachrichten empfangen

// Endgültig verworfen (mit Vermerk) nur: unbekannte gid, verlassen/entfernt/aufgelöst, ungültiges Format,
// Doppeltes, vor dem Leeren. Passt nur die Mitgliedschaft noch nicht (Einladung offen, Beitritt läuft,
// Absender noch nicht in m), wartet das Event ohne Vermerk im RAM (B8.4).
- (BOOL)receiveGroupEvent:(MeshPendingGroupEvent *)p {
    MeshEnvelope *env = p.env;
    NSString *from = p.from;
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:env.group status:&status inviter:NULL];
    BOOL open = status == MeshGroupInvited || status == MeshGroupJoining || status == MeshGroupMember || status == MeshGroupLinkJoining;
    if (!s || !open || [from isEqualToString:self.myPubkey]) { [self discardId:p.eventId]; return NO; }

    NSString *content = env.content, *cmid = nil;
    if (env.type == MeshEnvelopeReaction) {
        if (env.emoji.length > kMaxEmoji || !env.target.length) { [self discardId:p.eventId]; return NO; }
    } else if (env.type == MeshEnvelopeDelete) {
        if (!env.target.length) { [self discardId:p.eventId]; return NO; }
    } else {
        cmid = validCmid(env.cmid);
        if (!cmid || ![MeshMessenger fitsGroup:content]) { [self discardId:p.eventId]; return NO; }   // B8.2/B8.3
    }
    if (status != MeshGroupMember || ![s hasMember:from]) { [self buffer:p gid:s.gid]; return NO; }

    NSString *chat = MeshGroupChat(s.gid);
    if (p.createdAt < [self.store clearedAt:chat]) { [self discardId:p.eventId]; return NO; }   // vor dem Leeren geschrieben
    if (env.type == MeshEnvelopeReaction) {
        [self discardId:p.eventId];
        return [self.store setReaction:env.emoji key:env.target chat:chat sender:from];
    }
    if (env.type == MeshEnvelopeDelete) {
        [self discardId:p.eventId];
        return [self.store deleteMessageWithKey:env.target chat:chat sender:from];   // nur eigene des Absenders
    }
    if ([self.store hasMessage:cmid chat:chat sender:from]) { [self discardId:p.eventId]; return NO; }
    // Kein Codewort-Test: die Notlöschung per Text gilt nur im 1:1-Chat.

    long long t = MeshNow();
    MeshMessage *m = [[MeshMessage alloc] init];
    m.ts = MIN(p.createdAt, t + kMaxClockSkew);
    m.eventId = p.eventId;
    m.cmid = cmid;
    m.replyTo = env.replyTo;
    m.timer = env.timer;
    m.sender = from;
    m.status = MeshMessageDelivered;
    if (env.timer > 0) {
        if (env.timerMode == MeshTimerFromSent) m.expiresAt = p.createdAt + env.timer;
        else if ([self.openChat isEqualToString:chat]) m.expiresAt = t + env.timer;
    }
    if (![self.store insertMessage:m chat:chat content:content]) return NO;
    m.content = content;
    [self.delegate messenger:self received:m from:chat];
    return YES;
}

// Puffer (B8.4): je Gruppe höchstens 50, jedes höchstens 15 Minuten, alle zusammen höchstens 2 MB. Voll =
// nicht puffern, aber auch nicht als erledigt merken.
- (void)buffer:(MeshPendingGroupEvent *)p gid:(NSString *)gid {
    long long now = MeshNow();
    NSUInteger total = 0;
    for (NSString *g in [self.pendingGroupEvents allKeys]) {
        NSMutableArray *list = self.pendingGroupEvents[g];
        [list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MeshPendingGroupEvent *x, NSDictionary *b) { return now - x.arrived <= kBufferLifetime; }]];
        if (!list.count) { [self.pendingGroupEvents removeObjectForKey:g]; continue; }
        for (MeshPendingGroupEvent *x in list) total += x.bytes;
    }
    NSMutableArray *list = self.pendingGroupEvents[gid];
    for (MeshPendingGroupEvent *x in list) if ([x.eventId isEqualToString:p.eventId]) return;
    if (list.count >= kMaxBufferedPerGroup || total + p.bytes > kMaxBufferedBytes) return;
    if (!list) self.pendingGroupEvents[gid] = list = [NSMutableArray array];
    [list addObject:p];
}

// Nach einem angewandten Zustand: Gepuffertes dieser Gruppe erneut prüfen, Nachrichten vor Reaktionen
// und Löschen. Was weiter nicht passt, landet wieder im Puffer.
- (BOOL)replayGroup:(NSString *)gid {
    NSArray *list = self.pendingGroupEvents[gid];
    if (!list.count) return NO;
    [self.pendingGroupEvents removeObjectForKey:gid];
    long long now = MeshNow();
    BOOL changed = NO;
    for (int pass = 0; pass < 2; pass++)
        for (MeshPendingGroupEvent *p in list) {
            if ((p.env.type == MeshEnvelopeMessage) != (pass == 0) || now - p.arrived > kBufferLifetime) continue;
            changed |= [self receiveGroupEvent:p];
        }
    return changed;
}

@end

@implementation MeshMessenger (GroupReceive)

// Eine Kopie der ältesten ausstehenden Nachricht. Vorher geprüft: gibt es die Nachricht noch (gelöscht,
// abgelaufen), bin ich noch Mitglied, ist der Empfänger noch in m? Sonst entfällt die Kopie.
- (void)fanoutStep {
    NSMutableDictionary *job = self.fanoutJobs.firstObject;
    if (!job) return;
    NSMutableArray *to = job[@"to"];
    NSString *gid = job[@"gid"];
    long long row = [job[@"row"] longLongValue];
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!to.count || !s || status != MeshGroupMember || s.dissolved || ![self.store hasMessageRow:row]) {
        [self.fanoutJobs removeObjectAtIndex:0];
        return;
    }
    NSString *pk = to[0];
    [to removeObjectAtIndex:0];
    if (!to.count) [self.fanoutJobs removeObjectAtIndex:0];
    if (![s hasMember:pk]) return;
    NSString *reply = [job[@"reply"] length] ? job[@"reply"] : nil;
    MeshEvent *e = [self eventWith:[self groupPlain:job[@"content"] gid:gid cmid:job[@"cmid"] replyTo:reply
                                              timer:[job[@"timer"] intValue] mode:(MeshTimerMode)[job[@"mode"] intValue] to:pk] to:pk];
    if (!e || ![self.store addFanout:e.eventId message:row]) return;
    [self.delegate messenger:self send:e];
}


- (BOOL)receiveGroup:(MeshEnvelope *)env event:(MeshEvent *)event {
    BOOL changed = NO, keep = NO;
    switch (env.type) {
        case MeshEnvelopeGroupInvite: changed = [self receiveInvite:env event:event keep:&keep]; break;
        case MeshEnvelopeGroupState:  changed = [self receiveState:parseState(env.groupState) from:event.pubkey keep:&keep]; break;
        case MeshEnvelopeGroupJoin:   changed = [self receiveJoin:env from:event.pubkey]; break;
        case MeshEnvelopeGroupLeave:  changed = [self receiveLeave:env.group from:event.pubkey keep:&keep]; break;
        case MeshEnvelopeGroupPicture: changed = [self receiveGroupPicture:env from:event.pubkey]; break;
        case MeshEnvelopeGroupPropose: changed = [self receiveProposal:env from:event.pubkey]; break;
        case MeshEnvelopeGroupVouch:   changed = [self receiveVouch:env from:event.pubkey]; break;
        case MeshEnvelopeGroupKey:     changed = [self receiveGroupKey:env from:event.pubkey keep:&keep]; break;
        case MeshEnvelopeMessage:
        case MeshEnvelopeReaction:
        case MeshEnvelopeDelete: {
            MeshPendingGroupEvent *p = [[MeshPendingGroupEvent alloc] init];
            p.env = env;
            p.from = event.pubkey;
            p.eventId = event.eventId;
            p.createdAt = event.createdAt;
            p.arrived = MeshNow();
            p.bytes = env.content.length * 2 + 256;
            return [self receiveGroupEvent:p];
        }
        default: break;   // Dateiteile (mesh:fc) und Unbekanntes in Gruppen: verwerfen (B8.2)
    }
    if (!keep) [self discard:event];   // Steueranweisungen nur einmal
    return changed;
}

@end
