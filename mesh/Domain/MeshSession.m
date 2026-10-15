#import "MeshSession.h"
#import "MeshSession+Internal.h"
#import "MeshIdentity.h"
#import "MeshIdentityInfo.h"
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshRelayPool.h"
#import "MeshStore.h"
#import "MeshStore+Outbox.h"
#import "MeshVault.h"
#import "MeshVaultRecord.h"
#import "MeshDeviceSecret.h"
#import "MeshPinGuard.h"
#import "MeshPinStore.h"
#import "MeshMessenger.h"
#import "MeshPanic.h"
#import "MeshInboxWatcher.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshProfile.h"
#import "MeshHex.h"
#import "MeshBech32.h"
#import "MeshTor.h"
#import "MeshCertTime.h"
#import "MeshMemory.h"
#import "MeshLog.h"
#import "MeshJSON.h"
#import "MeshText.h"
#import "MeshTime.h"
#import "MeshTeam.h"
#import "MeshChat.h"
#import "MeshStore+Group.h"

// Öffentliche Start-Relays; Mesh betreibt keinen eigenen Server.
// Mehrere Relays für Redundanz (doppelte Events über die event_id erkannt). Nur Relays ohne
// NIP-42-Pflicht: damus verlangt AUTH für jede Abfrage und ist deshalb nicht dabei.
static NSArray *MeshDefaultRelays(void) {
    return @[ @"wss://relay.primal.net",     // speichert zuverlässig, nimmt große Events (Voice)
              @"wss://relay.snort.social",   // speichert zuverlässig, nimmt große Events
              @"wss://nos.lol",              // Live-Fan-out
              @"wss://nostr.mom" ];          // speichert
}

// Obergrenzen für Profildaten anderer (ein Profilbild als data:-URI ist selten > 200 KB).
static const NSUInteger kMaxProfileName = 64, kMaxProfileAbout = 200, kMaxProfilePicture = 300 * 1024;   // about: wie Android

static const long long kSyncOverlap = 3 * 24 * 3600;              // DMs ab so lange vor der neuesten abholen
static const NSUInteger kRequestProfiles = 30;                     // Namen so vieler Anfragen abfragen
static const long long kOutboxLifetime = 7 * 24 * 3600;           // so lange wird unbestätigt erneut gesendet
static NSString *const kUnifiedInbox = @"mesh.unifiedInbox";
static const NSTimeInterval kMediaMovePause = 1.5;   // zwischen zwei Umzugsschritten
static const NSTimeInterval kMediaMoveIdle = 2;      // so lange nach der letzten Berührung kein Schritt

@interface MeshSession () <MeshRelayPoolDelegate, MeshInboxWatcherDelegate, MeshTeamDelegate>
@end

@implementation MeshSession {
    NSTimer *_expiryTimer;         // nächste selbstlöschende Nachricht
    BOOL _profileRepublished;      // eigenes Profil (mit Bild) einmal je App-Start neu veröffentlicht
    NSString *_openChat;
    MeshInboxWatcher *_watcher;    // nur gesperrt im Hintergrund
    NSSet *_profileAuthors;        // wessen Profile das Abo gerade anfragt
    BOOL _changePending;           // MeshMessagesChangedNotification steht schon an
    NSTimeInterval _lastInteraction;   // letzte Berührung (userDidInteract), für den Medien-Umzug
}

+ (instancetype)shared {
    static MeshSession *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MeshSession alloc] init]; });
    return s;
}

- (void)start {
    _guard = [[MeshPinGuard alloc] initWithStorage:[MeshPinStore new]];
    _panic = [[MeshPanic alloc] init];
    _allIdentities = [NSMutableArray array];
    for (NSNumber *slot in [MeshIdentity savedSlots]) [_allIdentities addObject:[[MeshIdentity alloc] initWithSlot:slot.intValue]];
    _active = [self identityForSlot:[MeshIdentity activeSlot]] ?: _allIdentities[0];
    _pool = [[MeshRelayPool alloc] initWithURLs:MeshDefaultRelays()];
    _pool.delegate = self;
    [[MeshTor shared] start];
}

- (MeshIdentity *)identityForSlot:(int)slot {
    for (MeshIdentity *i in _allIdentities) if (i.slot == slot) return i;
    return nil;
}

- (NSArray *)unlockedIdentities {
    NSMutableArray *out = [NSMutableArray array];
    for (MeshIdentity *i in _allIdentities) if (i.keys) [out addObject:i];
    return out;
}

#pragma mark - Sperren

- (void)goOnline {
    [self stopWatching];   // ab jetzt empfängt der Messenger selbst
    _active.messenger.openChat = _openChat;
    for (MeshIdentity *i in [self unlockedIdentities]) [self startTeamOf:i];
    [self expireMessages];
    [_pool start];   // erst jetzt verbinden: der Abo-Filter braucht die eigenen Pubkeys
    [self scheduleMediaMove:5];   // nach dem Entsperren erst die Oberfläche, dann im Leerlauf umziehen
}

// Einmaliger Umzug der Medieninhalte (MeshStore moveMediaStep): kleine Schritte auf dem Main-Thread
// (Store), nur im Standard-Modus der Runloop, also nicht während gescrollt wird.
- (void)scheduleMediaMove:(NSTimeInterval)delay {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(moveMediaStep) object:nil];
    [self performSelector:@selector(moveMediaStep) withObject:nil afterDelay:delay inModes:@[NSDefaultRunLoopMode]];
}

// Nie direkt nach einer Berührung (Tippen, Scrollen, Chat öffnen): dann erst später. Die Oberfläche
// geht vor, der Umzug darf ruhig länger dauern.
- (void)moveMediaStep {
    if (!_unlocked) return;
    NSTimeInterval idle = [NSDate timeIntervalSinceReferenceDate] - _lastInteraction;
    if (idle < kMediaMoveIdle) { [self scheduleMediaMove:kMediaMoveIdle - idle + 0.1]; return; }
    for (MeshIdentity *i in [self unlockedIdentities])
        if ([i.store moveMediaStep]) { [self scheduleMediaMove:kMediaMovePause]; return; }   // eine Identität nach der anderen
}

- (void)userDidInteract { _lastInteraction = [NSDate timeIntervalSinceReferenceDate]; }

- (void)lock {
    [self notify:MeshWillLockNotification];   // Popups, Bildanzeigen, Caches, Aufnahmen schließen
    _unlocked = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(moveMediaStep) object:nil];
    for (MeshIdentity *i in _allIdentities) [i lock];   // Schlüssel überschreiben, Datenbanken versiegeln
    [_expiryTimer invalidate]; _expiryTimer = nil;
    [_pool stop];                  // keine offenen Verbindungen im gesperrten Zustand
}

// Team-Chat einer entsperrten Identität: Begrüßung, E laden, ggf. die getrennte Verbindung.
- (void)startTeamOf:(MeshIdentity *)identity {
    identity.team.delegate = self;
    [identity.team startWithRelays:MeshDefaultRelays()];
}

- (void)messengerReceivedPanic:(MeshMessenger *)messenger {
    // Erst nach dem laufenden Empfang löschen: der Messenger arbeitet noch mit dem Store.
    dispatch_async(dispatch_get_main_queue(), ^{ [self wipe]; });
}

#pragma mark - Gesperrt lauschen

- (void)startWatching {
    if (_unlocked || _watcher) return;
    NSMutableArray *pubkeys = [NSMutableArray array];
    for (MeshIdentity *i in _allIdentities) { NSString *pk = i.vault.pubkey; if (pk.length == 64) [pubkeys addObject:pk]; }
    if (!pubkeys.count) return;
    _watcher = [[MeshInboxWatcher alloc] initWithPubkeys:pubkeys relays:MeshDefaultRelays() panic:_panic];
    _watcher.delegate = self;
    [_watcher start];
}

- (void)stopWatching { [_watcher stop]; _watcher.delegate = nil; _watcher = nil; }
- (void)keepWatching { [_watcher keepAlive]; }

- (void)watcherSawNewMessage:(MeshInboxWatcher *)watcher { [self notify:MeshIncomingMessageNotification]; }

- (void)watcherSawPanic:(MeshInboxWatcher *)watcher {
    [self stopWatching];
    [self wipe];
}

#pragma mark - Identitäten

- (int)activeIdentitySlot { return _active.slot; }

- (NSArray *)identities {
    NSMutableArray *out = [NSMutableArray array];
    for (MeshIdentity *i in _allIdentities) {
        MeshIdentityInfo *info = [[MeshIdentityInfo alloc] init];
        info.slot = i.slot;
        info.pubkey = i.pubkey;
        info.active = i == _active;
        if (i.keys) {
            MeshProfile *p = [i.store loadProfile];
            info.name = p.name;
            info.picture = p.picture;
        }
        [out addObject:info];
    }
    return out;
}

- (void)switchToIdentity:(int)slot {
    MeshIdentity *i = [self identityForSlot:slot];
    if (!i || i == _active || !i.keys) return;
    _active.messenger.openChat = nil;
    _active = i;
    _openChat = nil;
    [MeshIdentity saveSlots:[_allIdentities valueForKey:@"slot"] active:slot];
    [self notify:MeshIdentityChangedNotification];
}

// Neue Identität (nsec nil = frischer Schlüssel), mit derselben PIN verschlüsselt, sofort aktiv.
- (BOOL)addIdentityWithPin:(NSString *)pin nsec:(NSString *)nsec {
    if (!_unlocked || ![MeshSession isValidSecret:pin kind:[self secretKind]] || [self verifyPin:pin] != MeshPinOK) return NO;
    MeshKeys *k = nil;
    if (nsec.length) {
        NSString *hrp = nil;
        NSData *raw = [MeshBech32 decode:[[nsec stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString] hrp:&hrp];
        k = raw.length == 32 && [hrp isEqualToString:@"nsec"] ? [MeshKeys fromSeckey:raw] : nil;
        MeshWipe(raw);
        if (!k) return NO;
        for (MeshIdentity *i in _allIdentities) if ([i.pubkey isEqualToString:[MeshHex encode:k.xonlyPub]]) return NO;   // schon da
    } else {
        k = [MeshKeys generate];
    }
    int slot = 0;
    while ([self identityForSlot:slot]) slot++;
    [[NSFileManager defaultManager] removeItemAtPath:[MeshIdentity databasePathForSlot:slot] error:NULL];   // Reste
    MeshIdentity *identity = [[MeshIdentity alloc] initWithSlot:slot];
    if ([self loadDeviceSecret] != MeshPinOK) return NO;
    identity.vault.deviceSecret = _active.vault.deviceSecret;
    if (![identity.vault storeKeys:k secret:[self normalized:pin kind:[self secretKind]] kdf:_active.vault.kdf]) { [identity destroy]; return NO; }
    [identity unlockWithKeys:k panic:_panic delegate:self];
    [self startTeamOf:identity];
    [_allIdentities addObject:identity];
    [MeshIdentity saveSlots:[_allIdentities valueForKey:@"slot"] active:_active.slot];
    [self switchToIdentity:slot];
    [_pool resubscribe];   // die neue Identität empfängt ab jetzt mit
    return YES;
}

- (BOOL)unifiedInbox { return [[NSUserDefaults standardUserDefaults] boolForKey:kUnifiedInbox]; }

- (void)setUnifiedInbox:(BOOL)unified {
    [[NSUserDefaults standardUserDefaults] setBool:unified forKey:kUnifiedInbox];
    [self notify:MeshMessagesChangedNotification];
}

#pragma mark - Eigenes Profil

- (NSString *)myPubkeyHex { return _active.pubkey; }
- (NSString *)myNpub      { return _active.keys ? [MeshBech32 encodeHrp:@"npub" data:_active.keys.xonlyPub] : nil; }

- (NSString *)myNsec {
    NSData *sk = _active.keys.seckey;   // gesperrt: kein Schlüssel im RAM
    NSString *nsec = sk ? [MeshBech32 encodeHrp:@"nsec" data:sk] : nil;
    MeshWipe(sk);
    return nsec;
}

- (MeshProfile *)profile { return [_active.store loadProfile]; }

- (void)saveProfile:(MeshProfile *)profile {
    NSString *before = [_active.store loadProfile].picture ?: @"";
    [_active.store saveProfile:profile];
    [self publishProfile:profile];
    // Bild geändert oder entfernt: auch privat an die Kontakte (Android liest Bilder nicht aus kind-0)
    if (![before isEqualToString:profile.picture ?: @""]) [_active.messenger sendPictureToAllContacts];
    [self notify:MeshMessagesChangedNotification];
    [self notifyProfileOf:_active.pubkey];
}

// NIP-01 kind-0: Name, Über und Bild ins Netz. Bild wie in der Android-App als Base64-JPEG (Avatar
// 256 px, ein paar Dutzend KB); größer als kMaxProfilePicture geht es nicht mit, Name/Über schon.
- (void)publishProfile:(MeshProfile *)profile {
    if (!_active.keys || !profile) return;
    NSMutableDictionary *meta = [@{ @"name": (profile.name ?: @""), @"display_name": (profile.name ?: @""), @"about": (profile.about ?: @"") } mutableCopy];
    if (profile.picture.length && profile.picture.length <= kMaxProfilePicture) meta[@"picture"] = profile.picture;
    NSData *j = [MeshJSON dataWithObject:meta];
    MeshEvent *e = [MeshEvent kind:0 content:[[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] tags:@[]];
    if ([e signWithKeys:_active.keys]) [_pool publish:e];
}

#pragma mark - Verbindung

- (BOOL)anyRelayConnected { return _pool.anyConnected; }
- (NSUInteger)connectedRelayCount { return _pool.connectedCount; }
- (NSUInteger)relayCount { return _pool.relayCount; }

- (BOOL)usesTor { return [MeshTor shared].enabled; }
- (BOOL)torReady { return [MeshTor shared].state == MeshTorReady; }
- (BOOL)torFailed { return [MeshTor shared].state == MeshTorFailed; }
- (int)torBootstrapPercent { return [MeshTor shared].bootstrapPercent; }
- (BOOL)torFirstStart { return self.usesTor && ![[MeshTor shared] hasDirectoryCache]; }
- (BOOL)clockPlausible { return MeshClockPlausible(time(NULL), MESH_BUILD_TIME); }

#pragma mark - Selbstlöschen

- (void)setOpenChat:(NSString *)peerHex {
    [self userDidInteract];   // Chat öffnen/schließen: Umzugsschritte warten
    _openChat = [peerHex copy];
    _active.messenger.openChat = _openChat;
    if (!peerHex) return;
    [_active.messenger chatOpened:peerHex];
    [self scheduleExpiry];
}

// Abgelaufenes löschen und den Wecker auf die nächste Ablaufzeit stellen (alle Identitäten).
- (void)expireMessages {
    BOOL changed = NO;
    for (MeshIdentity *i in [self unlockedIdentities]) changed |= [i.messenger deleteExpired];
    if (changed) [self notify:MeshMessagesChangedNotification];
    [self scheduleExpiry];
}

- (void)scheduleExpiry {
    [_expiryTimer invalidate]; _expiryTimer = nil;
    NSTimeInterval wait = -1;
    for (MeshIdentity *i in [self unlockedIdentities]) {
        NSTimeInterval w = [i.messenger secondsUntilNextExpiry];
        if (w >= 0 && (wait < 0 || w < wait)) wait = w;
    }
    if (wait < 0) return;
    _expiryTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(1, wait) target:self
                                                  selector:@selector(expireMessages) userInfo:nil repeats:NO];
}

// Gebündelt: Beim Verbinden kommen dutzende DMs kurz nacheinander; die Oberfläche (Chatliste mit
// Entschlüsseln aller Vorschauen, offener Chat) soll nicht nach jeder einzelnen neu aufbauen.
- (void)messagesChanged {
    [self scheduleExpiry];
    if (_changePending) return;
    _changePending = YES;
    [self performSelector:@selector(postMessagesChanged) withObject:nil afterDelay:0.25];
}

- (void)postMessagesChanged {
    _changePending = NO;
    [self notify:MeshMessagesChangedNotification];
}

#pragma mark - MeshMessengerDelegate

- (MeshIdentity *)identityOf:(MeshMessenger *)messenger {
    for (MeshIdentity *i in _allIdentities) if (i.messenger == messenger) return i;
    return nil;
}

- (void)messenger:(MeshMessenger *)messenger send:(MeshEvent *)e {
    // In die Warteschlange, bis ein Relay bestätigt: ohne Verbindung geht sie beim nächsten Verbinden.
    NSData *json = [MeshJSON dataWithObject:[e toJSONObject]];
    [[self identityOf:messenger].store queueEvent:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]
                                          eventId:e.eventId created:MeshNow()];
    [_pool publish:e];
}

- (void)messenger:(MeshMessenger *)messenger acceptedContact:(NSString *)peer { [self requestProfileOf:peer]; }

// Privat geschicktes Profilbild: Avatare neu zeichnen (MeshAvatarView und der Bild-Cache hängen am Bildtext).
- (void)messenger:(MeshMessenger *)messenger changedPictureOf:(NSString *)peer {
    [self notifyProfileOf:peer];
    [self messagesChanged];   // gebündelt wie neue Nachrichten
}

// Hinweis für Nachrichten außerhalb des offenen Chats (die UI zeigt ihn nur im Vordergrund).
- (void)messenger:(MeshMessenger *)messenger received:(MeshMessage *)message from:(NSString *)peer {
    MeshIdentity *identity = [self identityOf:messenger];
    if (identity == _active && [peer isEqualToString:_openChat]) return;
    BOOL group = MeshGroupOfChat(peer) != nil;   // Gruppen: nur Mitglieder kommen hier an
    if (!group && ![identity.store isAccepted:peer]) return;   // Anfragen von Fremden ohne Hinweis
    NSString *name = identity == _active ? [self displayNameFor:peer] : nil;
    NSString *preview = message.kind == MeshPayloadText ? message.content : nil;
    if (group && name && preview && message.sender) preview = [NSString stringWithFormat:@"%@: %@", [self senderName:message.sender inChat:peer], preview];
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshIncomingMessageNotification object:nil
        userInfo:@{ MeshIncomingName: name ?: @"", MeshIncomingPreview: preview ?: @"", MeshIncomingKind: @(message.kind) }];
}

#pragma mark - MeshTeamDelegate

- (MeshIdentity *)identityOfTeam:(MeshTeam *)team {
    for (MeshIdentity *i in _allIdentities) if (i.team == team) return i;
    return nil;
}

- (void)teamChanged:(MeshTeam *)team { [self messagesChanged]; }

// Hinweis wie bei normalen Chats, außer stumm geschaltet, ausgeblendet oder offen.
- (void)team:(MeshTeam *)team received:(MeshMessage *)message {
    MeshIdentity *identity = [self identityOfTeam:team];
    [self messagesChanged];
    if (team.muted || team.hidden || (identity == _active && MeshIsTeamChat(_openChat))) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshIncomingMessageNotification object:nil
        userInfo:@{ MeshIncomingName: identity == _active ? @"Mesh Team" : @"", MeshIncomingPreview: message.content ?: @"", MeshIncomingKind: @(MeshPayloadText) }];
}

#pragma mark - MeshRelayPoolDelegate

// DMs an alle eigenen Identitäten + Profile ihrer Kontakte. Gesperrt gibt es keine.
- (NSDictionary *)subscriptionsForPool:(MeshRelayPool *)pool {
    // Erste Verbindung nach dem Start: eigenes Profil einmal neu senden (ältere Versionen schickten kein Bild mit)
    if (!_profileRepublished && _active.keys) {
        _profileRepublished = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            MeshProfile *p = [self profile];
            if (p.name.length || p.picture.length || p.about.length) [self publishProfile:p];
        });
    }
    NSMutableArray *mine = [NSMutableArray array], *contacts = [NSMutableArray array];
    long long newest = LLONG_MAX;
    for (MeshIdentity *i in [self unlockedIdentities]) {
        [mine addObject:i.pubkey];
        // Auch Anfragen, damit dort der Name steht; ihr Bild zeigt die App erst nach dem Annehmen.
        NSArray *known = [[i.store acceptedContactPubkeys] arrayByAddingObjectsFromArray:[i.store requestPubkeys:kRequestProfiles]];
        for (NSString *pk in known) if (![contacts containsObject:pk]) [contacts addObject:pk];
        newest = MIN(newest, [i.store newestReceivedTime]);
    }
    if (!mine.count) return nil;
    NSMutableDictionary *subs = [NSMutableDictionary dictionary];
    // Nur ab kurz vor der neuesten empfangenen Nachricht: sonst spielt jedes Verbinden den ganzen
    // Verlauf neu ein. Der Puffer fängt Absender mit nachgehender Uhr und spät zugestellte Events.
    // Das Live-Abo hat kein since: Relays wenden since auch auf neue Events an, und created_at setzt
    // der Absender (ein iPod mit leerem Akku steht auf 1970). Doppeltes fängt hasEventId ab.
    NSMutableDictionary *history = [@{ @"kinds": @[@4], @"#p": mine } mutableCopy];
    if (newest > 0 && newest != LLONG_MAX) history[@"since"] = @(MAX(0, newest - kSyncOverlap));
    subs[@"mesh-dm"] = history;
    subs[@"mesh-dm-live"] = @{ @"kinds": @[@4], @"#p": mine, @"limit": @0 };
    if (contacts.count) subs[@"mesh-prof"] = @{ @"kinds": @[@0], @"authors": contacts };
    _profileAuthors = [NSSet setWithArray:contacts];
    return subs;
}

// Was nach Ablauf der Frist noch unbestätigt ist, gilt als nicht zugestellt.
- (NSArray *)pendingEventsForPool:(MeshRelayPool *)pool { return [self pendingEventsForPool:pool excluding:nil]; }

// Je Verbindung höchstens MeshOutboxMaxBytes für alle Identitäten zusammen (nicht 50 Medien-Events auf
// einmal: der A4 hat 256 MB); ohne das, was diese Verbindung schon bekommen hat. Der Rest folgt, sobald
// das Relay seine Warteschlange abgearbeitet hat (MeshRelayPool fragt dann erneut).
- (NSArray *)pendingEventsForPool:(MeshRelayPool *)pool excluding:(NSSet *)eventIds {
    long long now = MeshNow();
    NSMutableArray *events = [NSMutableArray array];
    NSUInteger budget = MeshOutboxMaxBytes;
    for (MeshIdentity *i in [self unlockedIdentities]) {
        if (!budget) break;
        if ([i.store expireQueuedBefore:now - kOutboxLifetime]) [self notify:MeshMessagesChangedNotification];
        for (NSString *json in [i.store queuedEventsExcluding:eventIds maxBytes:budget]) @autoreleasepool {
            budget = json.length >= budget ? 0 : budget - json.length;
            MeshEvent *e = [MeshEvent fromJSONObject:[MeshJSON objectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]]];
            if (e) [events addObject:e];
        }
    }
    return events;
}

- (MeshEvent *)pool:(MeshRelayPool *)pool authEventForRelay:(NSString *)url challenge:(NSString *)challenge {
    if (!_active.keys) return nil;
    MeshEvent *e = [MeshEvent kind:22242 content:@"" tags:@[ @[@"relay", url], @[@"challenge", challenge] ]];
    if (![e signWithKeys:_active.keys]) return nil;
    MeshLog(@"NIP-42: sende AUTH an %@", url);
    return e;
}

- (void)pool:(MeshRelayPool *)pool didReceiveEvent:(MeshEvent *)event subId:(NSString *)subId {
    if (!_unlocked) return;   // nach dem Sperren können noch Events in der Main-Queue stehen
    if ([subId hasPrefix:@"pair-"]) { [self receivePairingEvent:event subId:subId]; return; }
    if (event.kind == 0) { [self receiveProfile:event]; return; }
    // An welche eigene Identität? (p-Tag; eine DM an mehrere eigene geht an jede)
    BOOL changed = NO;
    for (MeshIdentity *i in [self unlockedIdentities])
        if ([event hasTag:@"p" value:i.pubkey]) changed |= [i.messenger receive:event];
    if (changed) [self messagesChanged];
    // Neue Anfrage: Profil-Abo neu senden, damit ihr Name kommt. Nur wenn sie damit unter die
    // abgefragten fällt, und gebündelt: viele neue Absender (Spam) lösen ein Abo aus, nicht viele.
    if (changed && event.pubkey.length && ![_profileAuthors containsObject:event.pubkey]
        && [[_active.store requestPubkeys:kRequestProfiles] containsObject:event.pubkey]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:_pool selector:@selector(resubscribe) object:nil];
        [_pool performSelector:@selector(resubscribe) withObject:nil afterDelay:5];
    }
}

// kind-0: Profil eines Kontakts oder einer Anfrage. Ändert nur vorhandene Kontakte (ein Relay kann
// keine anlegen); Felder auf Typ und Größe geprüft. Von Anfragen nur der Name.
- (void)receiveProfile:(MeshEvent *)event {
    NSDictionary *meta = [MeshJSON objectWithData:[event.content dataUsingEncoding:NSUTF8StringEncoding]];
    if (![meta isKindOfClass:[NSDictionary class]]) return;
    NSString *name = [meta[@"name"] isKindOfClass:[NSString class]] ? MeshCleanName(meta[@"name"]) : nil;
    NSString *pic  = [meta[@"picture"] isKindOfClass:[NSString class]] ? meta[@"picture"] : nil;
    name = MeshTruncate(name, kMaxProfileName);
    if (pic.length > kMaxProfilePicture) pic = nil;
    NSString *about = [meta[@"about"] isKindOfClass:[NSString class]] ? MeshTruncate(MeshStripInvisible(meta[@"about"]), kMaxProfileAbout) : @"";
    BOOL changed = NO;
    for (MeshIdentity *i in [self unlockedIdentities]) {
        // Anfragen: nur der Name, kein Bild (bis zu 30 Fremde à 300 KB); nach dem Annehmen kommt es neu.
        BOOL accepted = [i.store isAccepted:event.pubkey];
        // Bild fehlt noch (z.B. Profil kam an, als der Kontakt noch eine Anfrage war): gleiches Event nochmal übernehmen
        BOOL fill = accepted && pic.length && ![i.store picForContact:event.pubkey].length;
        // Ohne "picture" (Android veröffentlicht keins) das bisherige behalten: es kann privat per DM gekommen sein.
        NSString *keep = accepted && !pic.length ? [i.store picForContact:event.pubkey] : nil;
        BOOL newer = [i.store setContactProfile:event.pubkey pname:name pic:(accepted ? (pic.length ? pic : keep) : nil) createdAt:event.createdAt sameAgain:fill];
        if (newer && accepted) [i.store setAbout:about forContact:event.pubkey];   // von Anfragen nur der Name
        changed |= newer;
    }
    if (!changed) return;
    [self messagesChanged];   // gebündelt: beim Verbinden kommen viele Profile kurz nacheinander
    [self notifyProfileOf:event.pubkey];
}

- (void)pool:(MeshRelayPool *)pool didStoreEvent:(NSString *)eventId {
    BOOL changed = NO;
    for (MeshIdentity *i in [self unlockedIdentities]) {
        changed |= [i.store markDelivered:eventId];          // kann "Ab Gesehen"-Uhren starten
        changed |= [i.store markFanoutDelivered:eventId];    // Gruppe: irgendeine Kopie angekommen = zwei Haken
        [i.messenger eventStored:eventId];                   // B9: gl nach bestätigter Übergabe
    }
    if (changed) [self messagesChanged];
}

#pragma mark - Hilfen

// Profil eines neu angenommenen Kontakts: das Profil-Abo neu senden (gleiche ID ersetzt das alte),
// statt je Kontakt ein weiteres offen zu lassen.
- (void)requestProfileOf:(NSString *)hex { [_pool resubscribe]; }

- (void)notify:(NSString *)name {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
}

// Nur die Avatare dieses Pubkeys neu zeichnen, nicht alle Caches leeren.
- (void)notifyProfileOf:(NSString *)pubkey {
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshProfilesChangedNotification object:nil
                                                      userInfo:pubkey.length ? @{ MeshProfilePubkey: pubkey } : nil];
}

@end
