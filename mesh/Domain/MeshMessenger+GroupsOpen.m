// Gruppen, Nachträge B9 und B10 (docs/TEAM_GROUPS_PROTOCOL.md):
//  - Admin übergeben: Zustand mit r+1 und neuem a (aus m) an Mitglieder und offen Eingeladene. Der alte Admin
//    vergisst offene Einladungen, Vorschläge, k, Link-Zähler und Entfernte. "Übergeben und austreten": gl an
//    einen Empfänger erst, wenn ein Relay dessen Übergabe-Zustand bestätigt hat (aufgeschoben, versiegelt).
//    Empfänger halten einen Zustand eines Mitglieds, das sich als Admin führt, und ein gl des gespeicherten
//    Admins bis 15 min im RAM (eins je Gruppe), bis die Übergabe da ist.
//  - Vorschläge (gpr, nur beim Admin) und Bürgschaften (gvo, beim Vorgeschlagenen), versiegelt, 30 Tage.
//    Eine Bürgschaft lässt genau die Einladung dieser gid von genau diesem Admin zu, solange der Bürge ein
//    angenommener Kontakt ist.
//  - Offene Gruppen: k (16 Zufallsbytes) versiegelt beim Admin; Mitglieder bekommen es per gk. Beitritt per Link
//    legt einen Platzhalter an (r = 0, m = [Admin]) und nimmt nur den ersten Zustand vom Link-Admin mit mir in m.
#import "MeshMessenger+GroupsInternal.h"
#import "MeshStore.h"
#import "MeshStore+Outbox.h"
#import "MeshGroupState.h"
#import "MeshGroupLink.h"
#import "MeshEnvelope.h"
#import "MeshEvent.h"
#import "MeshPayload.h"
#import "MeshHex.h"
#import "MeshJSON.h"
#import "MeshTime.h"
#import "MeshText.h"
#import "MeshCrypto.h"

static const long long kHoldLifetime = 15 * 60;            // wartender Zustand, gl, gk (RAM)
static const long long kRecordLifetime = 30 * 24 * 3600;   // Vorschläge und Bürgschaften
static const long long kLinkJoinLifetime = 7 * 24 * 3600;  // Link-Beitritt ohne Zustand: fehlgeschlagen
static const long long kRemovedMemory = 24 * 3600, kLinkJoinWindow = 3600;
static const int kMaxProposals = 20, kMaxProposalsPerMember = 5;
static const int kMaxVouchers = 20, kMaxVouchersPerVoucher = 5;

static NSDictionary *recordObject(NSString *json) {
    NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
    id o = d.length ? [MeshJSON objectWithData:d] : nil;
    return [o isKindOfClass:[NSDictionary class]] ? o : nil;
}

static NSString *recordJSON(NSDictionary *o) {
    NSData *j = [MeshJSON dataWithObject:o];
    return j ? [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] : nil;
}

static NSString *stringIn(NSDictionary *o, NSString *key) { return [o[key] isKindOfClass:[NSString class]] ? o[key] : nil; }

@implementation MeshMessenger (GroupsOpen)

#pragma mark - Admin übergeben (B9)

- (BOOL)transferAdmin:(NSString *)pubkey group:(NSString *)gid leave:(BOOL)leave {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status]) return NO;
    MeshGroupState *next = [s withAdmin:pubkey];
    if (!next) return NO;
    NSArray *members = [self recipientsOf:next];
    NSMutableArray *to = [members mutableCopy];
    for (NSString *pk in [self pendingInvitesForGroup:s.gid]) if (![to containsObject:pk]) [to addObject:pk];   // ihre Einladung verfällt
    if (![self save:next status:MeshGroupMember inviter:nil]) return NO;
    // Was nur der Admin hatte, gilt nicht weiter (k reist nie mit)
    [self.store removeInvitesForGroup:s.gid];
    [self.store setGroupLinkKey:nil gid:s.gid];
    for (NSNumber *k in @[@(MeshGroupRecordProposal), @(MeshGroupRecordLinkJoin), @(MeshGroupRecordRemoved)])
        [self.store removeGroupRecords:(MeshGroupRecord)k.intValue gid:s.gid];
    NSString *state = [MeshEnvelope groupState:[next json]], *gl = [MeshEnvelope groupLeave:s.gid];
    for (NSString *pk in to) @autoreleasepool {
        MeshEvent *e = [self eventWith:state to:pk];
        if (!e) continue;
        [self.delegate messenger:self send:e];
        if (leave && [members containsObject:pk])   // gl erst nach Zustellung dieses Zustands (eventStored:)
            [self.store addGroupRecord:MeshGroupRecordDeferred gid:nil data:recordJSON(@{ @"a": e.eventId, @"t": pk, @"p": gl }) at:MeshNow()];
    }
    [self notice:MeshGroupNoticeNewAdmin name:[next nameOf:pubkey].length ? [next nameOf:pubkey] : [pubkey substringToIndex:8] gid:s.gid byMe:YES];
    if (s.open) [self notice:MeshGroupNoticeClosed name:@"" gid:s.gid byMe:YES];
    if (leave) {
        [self dropQueuedCopiesOf:s.gid];
        [self.pendingGroupEvents removeObjectForKey:s.gid];
        [self.heldGroupControl removeObjectForKey:s.gid];
        [self.store setGroupStatus:MeshGroupLeft gid:s.gid];
        [self notice:MeshGroupNoticeYouLeft name:@"" gid:s.gid byMe:YES];
    }
    return YES;
}

// Ein Relay hat ein eigenes Event bestätigt: aufgeschobene Sendungen dahinter (gl nach der Übergabe) jetzt.
- (BOOL)eventStored:(NSString *)eventId {
    if (!eventId.length) return NO;
    BOOL any = NO;
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordDeferred gid:nil]) {
        NSDictionary *o = recordObject(row[2]);
        if (o && ![stringIn(o, @"a") isEqualToString:eventId]) continue;
        [self.store removeGroupRecord:[row[0] longLongValue]];
        if (o) any |= [self sendDeferred:o];
    }
    return any;
}

- (BOOL)sendDeferred:(NSDictionary *)o {
    NSString *to = stringIn(o, @"t"), *plain = stringIn(o, @"p");
    if (![MeshGroupState isPubkey:to] || ![plain hasPrefix:@"\1mesh:gl:"]) return NO;   // nur gl wird aufgeschoben
    return [self sendControl:plain toAll:@[to]] > 0;
}

#pragma mark - Wartendes im RAM (B9)

- (NSMutableDictionary *)heldFor:(NSString *)gid create:(BOOL)create {
    NSMutableDictionary *h = self.heldGroupControl[gid];
    if (!h && create) self.heldGroupControl[gid] = h = [NSMutableDictionary dictionary];
    return h;
}

- (void)dropEmptyHold:(NSString *)gid { if (![self.heldGroupControl[gid] count]) [self.heldGroupControl removeObjectForKey:gid]; }

- (void)holdState:(MeshGroupState *)s from:(NSString *)from {
    NSMutableDictionary *h = [self heldFor:s.gid create:YES];
    MeshGroupState *old = h[@"state"];
    if (old && old.revision >= s.revision && MeshNow() - [h[@"stateAt"] longLongValue] <= kHoldLifetime) return;
    h[@"state"] = s; h[@"stateFrom"] = from; h[@"stateAt"] = @(MeshNow());
}

- (void)holdLeave:(NSString *)gid from:(NSString *)from {
    NSMutableDictionary *h = [self heldFor:gid create:YES];
    if ([h[@"leave"] isEqualToString:from]) return;   // die Wartezeit läuft ab dem ersten
    h[@"leave"] = from; h[@"leaveAt"] = @(MeshNow());
}

// Nach jedem angewandten Zustand: gl eines inzwischen abgelösten Admins = normaler Austritt; passendes gk
// übernehmen; ein wartender Zustand des neuen Admins jetzt prüfen.
- (void)stateApplied:(MeshGroupState *)s {
    NSMutableDictionary *h = [self heldFor:s.gid create:NO];
    if (!h) return;
    long long now = MeshNow();
    NSString *leaver = h[@"leave"];
    if (leaver && ![leaver isEqualToString:s.admin]) {
        [h removeObjectsForKeys:@[@"leave", @"leaveAt"]];
        [self receiveLeave:s.gid from:leaver];
    }
    if (h[@"key"]) {
        NSString *k = h[@"key"], *from = h[@"keyFrom"];
        BOOL fresh = now - [h[@"keyAt"] longLongValue] <= kHoldLifetime;
        if (!fresh || ([from isEqualToString:s.admin] && s.open)) {
            [h removeObjectsForKeys:@[@"key", @"keyFrom", @"keyAt"]];
            MeshGroupStatus status = MeshGroupInvited;
            if (fresh && [self groupState:s.gid status:&status inviter:NULL] && status == MeshGroupMember) [self.store setGroupLinkKey:k gid:s.gid];
        }
    }
    MeshGroupState *waiting = h[@"state"];
    if (waiting) {
        NSString *from = h[@"stateFrom"];
        BOOL fresh = now - [h[@"stateAt"] longLongValue] <= kHoldLifetime;
        [h removeObjectsForKeys:@[@"state", @"stateFrom", @"stateAt"]];
        BOOL keep = NO;
        if (fresh && waiting.revision > s.revision) [self receiveState:waiting from:from keep:&keep];
    }
    [self dropEmptyHold:s.gid];
}

// gl des Admins ohne Übergabe nach 15 min: aufgelöst (B8.7). Altes Wartendes verwerfen.
- (BOOL)processGroupDeadlines {
    long long now = MeshNow();
    BOOL changed = NO;
    for (NSString *gid in [self.heldGroupControl allKeys]) {
        NSMutableDictionary *h = self.heldGroupControl[gid];
        if (h[@"leave"] && now - [h[@"leaveAt"] longLongValue] >= kHoldLifetime) {
            NSString *from = h[@"leave"];
            [h removeObjectsForKeys:@[@"leave", @"leaveAt"]];
            changed |= [self applyAdminLeave:gid from:from];
        }
        if (h[@"state"] && now - [h[@"stateAt"] longLongValue] > kHoldLifetime) [h removeObjectsForKeys:@[@"state", @"stateFrom", @"stateAt"]];
        if (h[@"key"] && now - [h[@"keyAt"] longLongValue] > kHoldLifetime) [h removeObjectsForKeys:@[@"key", @"keyFrom", @"keyAt"]];
        [self dropEmptyHold:gid];
    }
    return changed;
}

- (NSTimeInterval)secondsUntilGroupDeadline {
    long long now = MeshNow(), next = -1;
    for (NSDictionary *h in [self.heldGroupControl allValues]) {
        if (!h[@"leave"]) continue;
        long long w = MAX(0, [h[@"leaveAt"] longLongValue] + kHoldLifetime - now);
        if (next < 0 || w < next) next = w;
    }
    return next;
}

#pragma mark - Vorschläge (B9, beim Admin)

// gpr: nur von beigetretenen Mitgliedern; C nicht ich, nicht gesperrt, nicht Mitglied, nicht eingeladen;
// Name nach B8.6 höchstens 40 (sonst ganz verwerfen, leer erlaubt); je (gid, C) einer, höchstens 20 je Gruppe
// und 5 je Vorschlagendem.
- (BOOL)receiveProposal:(MeshEnvelope *)env from:(NSString *)from {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:env.group status:&status inviter:NULL];
    NSString *c = env.subject;
    if (![self amAdminOf:s status:status] || ![s hasMember:from] || [from isEqualToString:self.myPubkey]) return NO;
    if ([c isEqualToString:self.myPubkey] || [self.store isBlocked:c] || [s hasMember:c] || [[self pendingInvitesForGroup:s.gid] containsObject:c]) return NO;
    NSString *name = MeshCleanGroupText(env.subjectName ?: @"");
    if (name.length > MeshGroupMaxMemberName) return NO;
    [self.store pruneGroupRecords:MeshGroupRecordProposal before:MeshNow() - kRecordLifetime];
    NSArray *rows = [self.store groupRecords:MeshGroupRecordProposal gid:s.gid];
    if ((int)rows.count >= kMaxProposals) return NO;
    int byFrom = 0;
    for (NSArray *row in rows) {
        NSDictionary *o = recordObject(row[2]);
        if ([stringIn(o, @"c") isEqualToString:c]) return NO;   // schon vorgeschlagen: weitere ignorieren
        if ([stringIn(o, @"m") isEqualToString:from]) byFrom++;
    }
    if (byFrom >= kMaxProposalsPerMember) return NO;
    NSString *json = recordJSON(@{ @"m": from, @"c": c, @"n": name });
    return json && [self.store addGroupRecord:MeshGroupRecordProposal gid:s.gid data:json at:MeshNow()];
}

- (NSArray *)proposalsForGroup:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status]) return @[];
    [self.store pruneGroupRecords:MeshGroupRecordProposal before:MeshNow() - kRecordLifetime];
    NSArray *invited = [self pendingInvitesForGroup:s.gid];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordProposal gid:s.gid]) {
        NSDictionary *o = recordObject(row[2]);
        NSString *m = stringIn(o, @"m"), *c = stringIn(o, @"c");
        if (![MeshGroupState isPubkey:m] || ![MeshGroupState isPubkey:c] || [s hasMember:c] || [invited containsObject:c] || [self.store isBlocked:c]) {
            [self.store removeGroupRecord:[row[0] longLongValue]];   // erledigt oder nicht mehr gültig
            continue;
        }
        [out addObject:@{ @"id": row[0], @"from": m, @"candidate": c, @"name": stringIn(o, @"n") ?: @"" }];
    }
    return out;
}

- (NSDictionary *)proposal:(long long)rowId group:(NSString *)gid {
    for (NSDictionary *p in [self proposalsForGroup:gid]) if ([p[@"id"] longLongValue] == rowId) return p;
    return nil;
}

// Einladen = normale Einladung (B8.1), auch wenn C kein Kontakt des Admins ist.
- (BOOL)acceptProposal:(long long)rowId group:(NSString *)gid {
    NSDictionary *p = [self proposal:rowId group:gid];
    if (!p || ![self invite:@[p[@"candidate"]] toGroup:gid allowing:p[@"candidate"]]) return NO;
    [self.store removeGroupRecord:rowId];
    return YES;
}

- (BOOL)rejectProposal:(long long)rowId group:(NSString *)gid {
    if (![self proposal:rowId group:gid]) return NO;
    [self.store removeGroupRecord:rowId];
    return YES;
}

- (void)forgetProposalsOf:(NSString *)pk gid:(NSString *)gid {
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordProposal gid:gid])
        if ([stringIn(recordObject(row[2]), @"c") isEqualToString:pk]) [self.store removeGroupRecord:[row[0] longLongValue]];
}

#pragma mark - Vorschlagen (B9, Mitglied)

// Eigener angenommener Kontakt, noch nicht in m: Bürgschaft an C, Vorschlag an den Admin.
- (BOOL)proposeContact:(NSString *)pubkey name:(NSString *)name group:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    NSString *c = [MeshGroupState isPubkey:pubkey] ? pubkey.lowercaseString : nil;
    if (!s || status != MeshGroupMember || s.dissolved || [s.admin isEqualToString:self.myPubkey]) return NO;
    if (!c || [c isEqualToString:self.myPubkey] || [c isEqualToString:s.admin] || [s hasMember:c] || ![self.store isAccepted:c] || [self.store isBlocked:c]) return NO;
    NSString *clean = [MeshGroupState cleanName:name ?: @"" max:MeshGroupMaxMemberName];
    if (![self sendControl:[MeshEnvelope groupVouch:s.gid admin:s.admin groupName:s.name] toAll:@[c]]) return NO;
    if (![self sendControl:[MeshEnvelope groupPropose:s.gid candidate:c name:clean] toAll:@[s.admin]]) return NO;
    [self notice:MeshGroupNoticeProposed name:clean.length ? clean : [c substringToIndex:8] gid:s.gid byMe:YES];
    return YES;
}

#pragma mark - Bürgschaften (B9, beim Vorgeschlagenen)

// gvo: nur von einem angenommenen Kontakt; Admin nicht ich und nicht der Bürge; Gruppenname nach B8.6
// höchstens 50. Je (gid, Admin) eine (neue ersetzt alte), höchstens 5 je Bürge, 20 insgesamt (die älteste fällt
// heraus), 30 Tage. Danach zurückgehaltene Einladungen erneut prüfen (gvo nach gi).
- (BOOL)receiveVouch:(MeshEnvelope *)env from:(NSString *)from {
    NSString *admin = env.subject, *gid = env.group;
    if (![self.store isAccepted:from] || [self.store isBlocked:from]) return NO;
    if ([admin isEqualToString:self.myPubkey] || [admin isEqualToString:from] || [self.store isBlocked:admin]) return NO;
    NSString *name = MeshCleanGroupText(env.subjectName ?: @"");
    if (name.length > MeshGroupMaxName) return NO;
    [self.store pruneGroupRecords:MeshGroupRecordVoucher before:MeshNow() - kRecordLifetime];
    NSMutableArray *rows = [NSMutableArray array];
    int byFrom = 0;
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordVoucher gid:nil]) {
        NSDictionary *o = recordObject(row[2]);
        if (!o || ([stringIn(o, @"g") isEqualToString:gid] && [stringIn(o, @"a") isEqualToString:admin])) {
            [self.store removeGroupRecord:[row[0] longLongValue]];   // neue ersetzt alte
            continue;
        }
        if ([stringIn(o, @"m") isEqualToString:from]) byFrom++;
        [rows addObject:row];
    }
    if (byFrom >= kMaxVouchersPerVoucher) return NO;
    while ((int)rows.count >= kMaxVouchers) { [self.store removeGroupRecord:[rows[0][0] longLongValue]]; [rows removeObjectAtIndex:0]; }
    NSString *json = recordJSON(@{ @"g": gid, @"a": admin, @"n": name, @"m": from });
    if (!json || ![self.store addGroupRecord:MeshGroupRecordVoucher gid:nil data:json at:MeshNow()]) return NO;
    return [self contactAccepted:nil];   // eine schon zurückgehaltene Einladung jetzt zeigen
}

// Bürge einer gültigen Bürgschaft für (gid, Admin): nur solange er angenommener Kontakt und nicht gesperrt ist.
- (NSString *)voucherFor:(NSString *)gid admin:(NSString *)admin {
    if (!gid || !admin) return nil;
    long long since = MeshNow() - kRecordLifetime;
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordVoucher gid:nil]) {
        NSDictionary *o = recordObject(row[2]);
        NSString *m = stringIn(o, @"m");
        if ([row[1] longLongValue] < since || ![stringIn(o, @"g") isEqualToString:gid] || ![stringIn(o, @"a") isEqualToString:admin]) continue;
        if ([MeshGroupState isPubkey:m] && [self.store isAccepted:m] && ![self.store isBlocked:m]) return m;
    }
    return nil;
}

- (NSString *)voucherForInvite:(NSString *)gid {
    MeshGroupStatus status = MeshGroupMember;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || status != MeshGroupInvited || [self.store isAccepted:s.admin]) return nil;
    return [self voucherFor:s.gid admin:s.admin];
}

- (void)forgetVouchersFor:(NSString *)gid {
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordVoucher gid:nil])
        if ([stringIn(recordObject(row[2]), @"g") isEqualToString:gid]) [self.store removeGroupRecord:[row[0] longLongValue]];
}

#pragma mark - Offene Gruppen (B10, Admin)

- (BOOL)setGroupOpen:(BOOL)open group:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status] || s.open == open) return NO;
    MeshGroupState *next = [s withOpen:open];
    NSString *k = open ? [MeshHex encode:[MeshCrypto randomBytes:16]] : nil;
    if (!next || (open && k.length != 32) || ![self.store setGroupLinkKey:k gid:s.gid]) return NO;
    if (![self publish:next extra:nil]) { [self.store setGroupLinkKey:nil gid:s.gid]; return NO; }
    [self sendControl:[MeshEnvelope groupKey:s.gid key:k] toAll:[self recipientsOf:next]];   // Schließen: leer
    [self notice:open ? MeshGroupNoticeOpened : MeshGroupNoticeClosed name:@"" gid:s.gid byMe:YES];
    return YES;
}

// Neues k, r+1 (mit "o"): alte Links gehen nicht mehr.
- (BOOL)resetGroupLink:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (![self amAdminOf:s status:status] || !s.open) return NO;
    MeshGroupState *next = [s bumped];
    NSString *k = [MeshHex encode:[MeshCrypto randomBytes:16]], *old = [self.store groupLinkKey:s.gid];
    if (!next || k.length != 32 || ![self.store setGroupLinkKey:k gid:s.gid]) return NO;
    if (![self publish:next extra:nil]) { [self.store setGroupLinkKey:old gid:s.gid]; return NO; }
    [self sendControl:[MeshEnvelope groupKey:s.gid key:k] toAll:[self recipientsOf:next]];
    return YES;
}

// Admin und Mitglieder mit k: Link nur in offenen Gruppen, nur beigetreten.
- (NSString *)groupLink:(NSString *)gid {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:gid status:&status inviter:NULL];
    if (!s || status != MeshGroupMember || !s.open || s.dissolved) return nil;
    return [MeshGroupLink linkWithGroup:s.gid admin:s.admin key:[self.store groupLinkKey:s.gid]];
}

// gk: nur vom aktuellen Admin, nur Mitglied, nur bei "o":1 (leer = geschlossen, k löschen). Zu früh (Zustand
// mit "o" oder die Übergabe noch unterwegs): einmal je Gruppe im RAM halten.
- (BOOL)receiveGroupKey:(MeshEnvelope *)env from:(NSString *)from keep:(BOOL *)keep {
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = [self groupState:env.group status:&status inviter:NULL];
    NSString *k = env.joinKey;
    if (!s || [from isEqualToString:self.myPubkey] || (status != MeshGroupMember && status != MeshGroupJoining && status != MeshGroupLinkJoining)) return NO;
    if (status == MeshGroupMember && [from isEqualToString:s.admin] && (s.open || !k.length)) {
        [self.store setGroupLinkKey:(k.length ? k : nil) gid:s.gid];
        return YES;
    }
    if (!k.length || (![from isEqualToString:s.admin] && ![s hasMember:from])) return NO;
    NSMutableDictionary *h = [self heldFor:s.gid create:YES];
    h[@"key"] = k; h[@"keyFrom"] = from; h[@"keyAt"] = @(MeshNow());
    *keep = YES;
    return NO;
}

#pragma mark - Beitritt per Link (B10, Beitretender)

- (BOOL)linkJoinExpired:(NSString *)gid {
    long long t = [self.store groupLinkAt:gid];
    return t > 0 && t < MeshNow() - kLinkJoinLifetime;
}

// Vorhandener inaktiver Eintrag mit gleichem Admin wird wiederverwendet; anderer Admin oder aufgelöst: ablehnen.
- (NSString *)joinGroupByLink:(NSString *)text name:(NSString *)groupName myName:(NSString *)myName {
    MeshGroupLink *l = [MeshGroupLink parse:text];
    if (!l || [l.admin isEqualToString:self.myPubkey] || [self.store isBlocked:l.admin]) return nil;
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *known = [self groupState:l.gid status:&status inviter:NULL];
    if (known) {
        if (![known.admin isEqualToString:l.admin] || known.dissolved || status == MeshGroupDissolved) return nil;
        if (status == MeshGroupMember || status == MeshGroupJoining) return l.gid;
        if (status == MeshGroupLinkJoining && [self linkJoinExpired:l.gid]) {   // vor erneutem gj prüfen
            [self.store setGroupStatus:MeshGroupJoinFailed gid:l.gid];
            status = MeshGroupJoinFailed;
        }
    } else if ([self.store groupIds].count >= kMaxGroups) {
        return nil;
    }
    MeshGroupState *placeholder = known ? nil
        : [MeshGroupState linkPlaceholder:l.gid name:[MeshGroupState cleanName:groupName ?: @"" max:MeshGroupMaxName].length ? groupName : @"Group" admin:l.admin];
    if (!known && !placeholder) return nil;
    MeshEvent *e = [self eventWith:[MeshEnvelope groupJoin:l.gid name:[MeshGroupState cleanName:myName ?: @"" max:MeshGroupMaxMemberName] key:l.key] to:l.admin];
    if (!e) return nil;
    if (placeholder && ![self save:placeholder status:MeshGroupLinkJoining inviter:l.admin]) return nil;
    if (known && status != MeshGroupLinkJoining && ![self.store setGroupStatus:MeshGroupLinkJoining gid:l.gid]) return nil;
    if (placeholder || status != MeshGroupLinkJoining) [self.store setGroupLinkAt:MeshNow() gid:l.gid];
    [self.delegate messenger:self send:e];
    return l.gid;
}

- (BOOL)isValidGroupLinkCard:(NSString *)content {
    MeshPayload *p = [MeshPayload parse:content];
    return p.kind == MeshPayloadGroupLink && p.text && MeshCleanGroupText(p.text).length <= MeshGroupMaxName && [MeshGroupLink parse:p.code] != nil;
}

#pragma mark - Wartung (beim Entsperren)

- (BOOL)maintainOpenGroups {
    long long now = MeshNow();
    [self.store pruneGroupRecords:MeshGroupRecordProposal before:now - kRecordLifetime];
    [self.store pruneGroupRecords:MeshGroupRecordVoucher before:now - kRecordLifetime];
    [self.store pruneGroupRecords:MeshGroupRecordRemoved before:now - kRemovedMemory];
    [self.store pruneGroupRecords:MeshGroupRecordLinkJoin before:now - kLinkJoinWindow];
    BOOL changed = NO;
    for (NSString *gid in [self.store groupIdsWithStatus:MeshGroupLinkJoining])
        if ([self linkJoinExpired:gid]) changed |= [self.store setGroupStatus:MeshGroupJoinFailed gid:gid];
    // Aufgeschobenes, dessen Vorgänger nicht mehr wartet (bestätigt oder abgelaufen): jetzt senden
    for (NSArray *row in [self.store groupRecords:MeshGroupRecordDeferred gid:nil]) {
        NSDictionary *o = recordObject(row[2]);
        if (o && [self.store isQueuedEvent:stringIn(o, @"a")]) continue;
        [self.store removeGroupRecord:[row[0] longLongValue]];
        if (o) [self sendDeferred:o];
    }
    return changed;
}

@end
