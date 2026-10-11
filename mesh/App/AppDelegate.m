// Fenster + Sperr-Gate: erst Code (festlegen/eingeben), dann die Chatliste.
// Beim Wechsel in den Hintergrund wird gesperrt (Schlüssel aus dem RAM, App-Switcher zeigt den Lock).
#import "AppDelegate.h"
#import "ChatsListViewController.h"
#import "LockViewController.h"
#import "PassphraseLockViewController.h"
#import "SetupProtectionViewController.h"
#import "WordsSetupViewController.h"
#import "ConnectViewController.h"
#import "MeshTheme.h"
#import "MeshSession.h"
#import "MeshLog.h"
#import "MeshBanner.h"
#import "MeshFormat.h"
#import "MeshL10n.h"
#import "MeshEmoji.h"
#import "MeshGlyphs.h"
#include <notify.h>

static const NSTimeInterval kAlertGrace = 60;   // so lange darf ein Systemdialog offen sein, ohne dass gesperrt wird

@implementation AppDelegate {
    UIView *_cover;          // deckt den Inhalt ab, solange ein Systemdialog (Akku, Fotozugriff) davor liegt
    NSDate *_coveredSince;   // Wanduhr: der Timer unten steht still, während das Gerät schläft
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // Statusleiste ausblenden -> jede View ist volle 480 pt hoch, nichts wird unten abgeschnitten.
    [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];

    [self removeLeftovers];
    [self observeDeviceLock];
    [MeshEmoji install];   // aktuelle Emojis (Noto) statt der Schrift von iOS 6
    [[MeshSession shared] start];

    // Notlöschung (Codewort von einem Kontakt) bei offener App: zurück zur Einrichtung.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wiped)
                                                 name:MeshWipedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incoming:)
                                                 name:MeshIncomingMessageNotification object:nil];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [MeshTheme bg];
    [self showLock];
    [self.window makeKeyAndVisible];
    return YES;
}

// Sperrbildschirm: ohne Vault die Einrichtung, sonst die Eingabe passend zur gewählten Schutzart.
- (void)showLock {
    UIViewController *old = self.window.rootViewController;
    if ([old isKindOfClass:[ConnectViewController class]]) [(ConnectViewController *)old cancel];
    MeshSession *s = [MeshSession shared];
    if ([s needsSetup]) { [self showSetup]; return; }
    MESH_WEAK AppDelegate *weakSelf = self;
    if ([s secretKind] == MeshSecretWords) {
        PassphraseLockViewController *lock = [[PassphraseLockViewController alloc] init];
        lock.onUnlocked = ^{ [weakSelf showConnect]; };
        lock.onStartOver = ^{ [weakSelf showSetup]; };
        self.window.rootViewController = lock;
        return;
    }
    LockViewController *lock = [[LockViewController alloc] init];
    lock.onUnlocked = ^{ [weakSelf showConnect]; };
    lock.onStartOver = ^{ [weakSelf showSetup]; };
    self.window.rootViewController = lock;
}

// Erster Start (oder nach dem Löschen): Schutzart wählen, dann PIN oder Wörter festlegen.
- (void)showSetup {
    SetupProtectionViewController *choose = [[SetupProtectionViewController alloc] init];
    MESH_WEAK AppDelegate *weakSelf = self;
    choose.onChoose = ^(MeshSecretKind kind, NSUInteger words) {
        if (kind == MeshSecretPin) [weakSelf showPinSetup]; else [weakSelf showWordsSetup:words];
    };
    self.window.rootViewController = choose;
}

- (void)showPinSetup {
    LockViewController *lock = [[LockViewController alloc] init];
    lock.setupMode = YES;
    MESH_WEAK AppDelegate *weakSelf = self;
    lock.onUnlocked = ^{ [weakSelf showConnect]; };
    lock.onBack = ^{ [weakSelf showSetup]; };
    self.window.rootViewController = lock;
}

- (void)showWordsSetup:(NSUInteger)words {
    WordsSetupViewController *setup = [[WordsSetupViewController alloc] initWithWords:words];
    MESH_WEAK AppDelegate *weakSelf = self;
    setup.onBack = ^{ [weakSelf showSetup]; };
    setup.onConfirmed = ^MeshPinResult(NSString *phrase) {
        MeshPinResult r = [[MeshSession shared] setupWithSecret:phrase kind:MeshSecretWords];
        if (r == MeshPinOK) [weakSelf showConnect];
        return r;
    };
    self.window.rootViewController = setup;
}

// Startbildschirm, während die Relays verbinden.
- (void)showConnect {
    ConnectViewController *connect = [[ConnectViewController alloc] init];
    MESH_WEAK AppDelegate *weakSelf = self;
    connect.onDone = ^{ [weakSelf showMain]; };
    self.window.rootViewController = connect;
}

// Hauptoberfläche nach dem Entsperren.
- (void)showMain {
    if (![MeshSession shared].unlocked) { [self showLock]; return; }
    ChatsListViewController *chats = [[ChatsListViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:chats];
    [nav mesh_useFullScreenLayout];
    [nav setNavigationBarHidden:YES animated:NO];
    self.window.rootViewController = nav;
}

// iOS 4 bis 6 melden beim Standby-Knopf nur willResignActive, genau wie bei einem Systemdialog
// (Akku fast leer, Fotozugriff). Darum: Inhalt sofort abdecken, gesperrt wird beim Hintergrund, beim
// Sperren des Geräts (Darwin-Meldung lockcomplete) oder wenn der Dialog länger als kAlertGrace offen
// bleibt. Kommt die App vorher zurück (Dialog weggetippt), geht es ohne neue PIN weiter.
- (void)applicationWillResignActive:(UIApplication *)application {
    if (![MeshSession shared].unlocked) { [self watchInBackground]; return; }
    [self showCover];
    _coveredSince = [NSDate date];
    [self performSelector:@selector(lockNow) withObject:nil afterDelay:kAlertGrace];
}
- (void)applicationDidEnterBackground:(UIApplication *)application { [self lockNow]; }

- (void)observeDeviceLock {
    // Zwei Meldungen, falls eine auf einer iOS-Version fehlt: Gerät gesperrt bzw. Display aus.
    MESH_WEAK AppDelegate *weakSelf = self;
    for (NSString *name in @[@"com.apple.springboard.lockcomplete", @"com.apple.springboard.hasBlankedScreen"]) {
        int token;
        notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int t) {
            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) [weakSelf lockNow];
        });
    }
}

- (void)showCover {
    if (_cover) return;
    _cover = [[UIView alloc] initWithFrame:self.window.bounds];
    _cover.backgroundColor = [MeshTheme bg];
    UIImageView *logo = [[UIImageView alloc] initWithImage:[MeshGlyphs logo:84]];
    logo.center = CGPointMake(_cover.bounds.size.width / 2, _cover.bounds.size.height / 2);
    [_cover addSubview:logo];
    [self.window addSubview:_cover];
}

- (void)hideCover {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(lockNow) object:nil];
    [_cover removeFromSuperview];
    _cover = nil;
}

- (void)lockNow {
    [self hideCover];
    if ([MeshSession shared].unlocked) {
        [[MeshSession shared] lock];
        [self.window.rootViewController mesh_dismissPresentedAnimated:NO];   // Bildanzeige, Bildwähler, Scanner
        [self showLock];
    }
    [self watchInBackground];
}

// Gesperrt nur auf neue DMs lauschen. Der VoIP-Modus weckt die App, wenn Daten ankommen; alle
// zehn Minuten (kürzer erlaubt iOS nicht) baut keepWatching getrennte Verbindungen neu auf.
- (void)watchInBackground {
    UIApplication *app = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier task = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:task]; task = UIBackgroundTaskInvalid;
    }];
    [[MeshSession shared] startWatching];
    [app setKeepAliveTimeout:600 handler:^{ [[MeshSession shared] keepWatching]; }];
    // Zeit für TLS-Handshakes, dann darf iOS die App schlafen legen (die Sockets wecken sie).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (task != UIBackgroundTaskInvalid) { [app endBackgroundTask:task]; task = UIBackgroundTaskInvalid; }
    });
}

// Auch am Sperrbildschirm im Vordergrund lauschen (Notlöschung), erst das Entsperren beendet es.
- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Systemdialog weg, nicht gesperrt: einfach weiter. War die App länger abgedeckt (auch im
    // Schlaf, wenn keine Sperr-Meldung kam), doch sperren.
    if (_cover && _coveredSince && -[_coveredSince timeIntervalSinceNow] > kAlertGrace) [self lockNow];
    else [self hideCover];
    if (![MeshSession shared].unlocked) [[MeshSession shared] startWatching];
    [application clearKeepAliveTimeout];
    application.applicationIconBadgeNumber = 0;
    [application cancelAllLocalNotifications];
}

// Im Vordergrund ein Banner mit Name und Vorschau; gesperrt nur "Neue Nachricht" (ohne Absender,
// ohne Inhalt: beides ist dann nicht lesbar und gehört nicht auf den Sperrbildschirm).
- (void)incoming:(NSNotification *)n {
    UIApplication *app = [UIApplication sharedApplication];
    if (app.applicationState == UIApplicationStateActive) {
        NSString *name = n.userInfo[MeshIncomingName];
        if (!name.length || ![MeshSession shared].unlocked) return;
        NSString *preview = [MeshFormat preview:n.userInfo[MeshIncomingPreview] kind:[n.userInfo[MeshIncomingKind] integerValue]];
        [MeshBanner showTitle:name text:preview.length ? preview : L(@"New message")];
        return;
    }
    UILocalNotification *note = [[UILocalNotification alloc] init];
    note.alertBody = L(@"New message");
    note.soundName = UILocalNotificationDefaultSoundName;
    note.applicationIconBadgeNumber = app.applicationIconBadgeNumber + 1;
    [app presentLocalNotificationNow:note];
}

- (void)wiped {
    UIViewController *root = self.window.rootViewController;
    if ([root isKindOfClass:[SetupProtectionViewController class]] || [root isKindOfClass:[WordsSetupViewController class]]
        || ([root isKindOfClass:[LockViewController class]] && [(LockViewController *)root setupMode])) return;   // zeigt die Einrichtung schon
    [self.window.rootViewController mesh_dismissPresentedAnimated:NO];
    [self showLock];
}

// Was ältere Versionen ungeschützt hinterlassen konnten: Sprachaufnahmen als tmp/mesh-*.wav,
// einen kopierten nsec in der Zwischenablage, das Log eines Debug-Pakets.
- (void)removeLeftovers {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmp = NSTemporaryDirectory();
    for (NSString *f in [fm contentsOfDirectoryAtPath:tmp error:NULL])
        if ([f hasPrefix:@"mesh-"]) [fm removeItemAtPath:[tmp stringByAppendingPathComponent:f] error:NULL];

    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if ([pb.string hasPrefix:@"nsec1"]) pb.items = @[];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"mesh.clipboard.until"];
#ifndef DEBUG
    MeshLogRemove();
#endif
}

@end
