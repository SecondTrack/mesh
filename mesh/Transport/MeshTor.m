#import "MeshTor.h"
#import "MeshNotifications.h"
#import "MeshLog.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <spawn.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/sysctl.h>
#include <signal.h>

extern char **environ;

#ifndef MESH_USE_TOR
#define MESH_USE_TOR 0
#endif

static const int kSocksPort = 19050;
static NSString *const kDataDir = @"/var/mobile/Library/Mesh-Tor";
// Steuerkanal als Unix-Socket im Datenordner (0700, nur mobile): Ein TCP-Port ließe sich von jedem
// Programm belegen, solange Tor neu startet, und dann "fertig" melden. Der SOCKS-Port bleibt TCP,
// weil iOS nur TCP-Sockets als VoIP weckt; dass ihn wirklich Tor hält, prüft GETINFO net/listeners.
static NSString *const kControlSocket = @"/var/mobile/Library/Mesh-Tor/control";
static NSString *const kCookiePath = @"/var/mobile/Library/Mesh-Tor/control_auth_cookie";
static const NSTimeInterval kSpawnEvery = 30;   // so oft höchstens selbst starten
static NSString *const kLockPath = @"/var/mobile/Library/Mesh-Tor/lock";
static const NSTimeInterval kStaleAfter = 120;  // so lange läuft Tor ohne erreichbaren Steuer-Socket, dann Neustart
static const NSTimeInterval kGiveUp = 180;   // so lange ohne Dienst: "Tor nicht verfügbar" anzeigen

@implementation MeshTor {
    NSDate *_since;
    NSDate *_spawned;
    pid_t _child;            // selbst gestartetes Tor (0 = keins), wird nach dem Ende abgeholt
    NSDate *_unreachable;    // seit wann ein laufendes Tor nicht antwortet (nil = antwortet oder läuft nicht)
}
- (BOOL)hasDirectoryCache {
    return [[NSFileManager defaultManager] fileExistsAtPath:[kDataDir stringByAppendingPathComponent:@"cached-microdesc-consensus"]];
}

+ (instancetype)shared {
    static MeshTor *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MeshTor alloc] init]; });
    return s;
}

- (BOOL)enabled { return MESH_USE_TOR ? YES : NO; }

- (int)socksPort { return (_state == MeshTorReady) ? kSocksPort : 0; }

- (void)start {
#if MESH_USE_TOR
    if (_since) return;
    _since = [NSDate date];
    _state = MeshTorStarting;
    [NSThread detachNewThreadSelector:@selector(watch) toTarget:self withObject:nil];
#else
    _state = MeshTorOff;   // direkter Transport
#endif
}

// Zustand nur auf dem Main-Thread ändern; Benachrichtigung nur bei Änderung.
- (void)setState:(MeshTorState)state percent:(int)percent {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (state == self->_state && percent == self->_bootstrapPercent) return;
        self->_state = state;
        self->_bootstrapPercent = percent;
        [[NSNotificationCenter defaultCenter] postNotificationName:MeshTransportChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:MeshConnectionChangedNotification object:nil];
    });
}

#pragma mark - Control-Port (eigener Thread)

static int connectControl(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    // Großzügig: direkt nach dem Start liest Tor am iPod sein Verzeichnis (~30 MB) und antwortet
    // dabei bis zu einigen zehn Sekunden nicht. Ein kürzeres Warten fing endlos von vorn an.
    struct timeval tv = { 60, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    struct sockaddr_un a = { 0 };
    a.sun_family = AF_UNIX;
    strlcpy(a.sun_path, kControlSocket.fileSystemRepresentation, sizeof(a.sun_path));
    a.sun_len = (unsigned char)SUN_LEN(&a);
    if (connect(fd, (struct sockaddr *)&a, (socklen_t)SUN_LEN(&a)) != 0) { close(fd); return -1; }
    return fd;
}

// Eine Antwort bis zur Endzeile "250 OK" oder einem Fehlercode; nil bei Abbruch.
static NSString *command(int fd, NSString *line) {
    NSData *out = [[line stringByAppendingString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (send(fd, out.bytes, out.length, 0) != (ssize_t)out.length) return nil;
    NSMutableData *in = [NSMutableData data];
    char buf[512];
    while (in.length < 16384) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) return nil;
        [in appendBytes:buf length:(NSUInteger)n];
        NSString *s = [[NSString alloc] initWithData:in encoding:NSUTF8StringEncoding];
        for (NSString *l in [s componentsSeparatedByString:@"\r\n"])
            if (l.length >= 4 && [l characterAtIndex:3] == ' ') return s;   // "250 OK", "515 …"
    }
    return nil;
}

static NSString *hex(NSData *d) {
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 2];
    const uint8_t *b = d.bytes;
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

// Hält Tor selbst den SOCKS-Port? (Sonst könnte ihn ein anderes Programm belegt haben.)
static BOOL ownsSocksPort(int fd) {
    NSString *r = command(fd, @"GETINFO net/listeners/socks");
    return [r rangeOfString:[NSString stringWithFormat:@"\"127.0.0.1:%d\"", kSocksPort]].location != NSNotFound;
}

static int bootstrapPercent(NSString *reply) {
    if (!reply) return -1;   // Verbindung abgerissen (sonst läse sich nil als 0 %)
    NSRange r = [reply rangeOfString:@"PROGRESS="];
    return r.location == NSNotFound ? -1 : [[reply substringFromIndex:NSMaxRange(r)] intValue];
}

// Antwortet kein Dienst (launchd hat ihn nicht geladen, etwa nach der Installation über SSH, oder
// er wurde beendet), startet die App Tor selbst: als eigenen Prozess, den iOS mit der App nicht
// einfriert. Gleiche Einstellungen wie layout/Library/LaunchDaemons/de.mesh.tor.plist; ein zweiter
// Start scheitert an den belegten Ports und beendet sich.
- (void)spawnIfDue {
    if (_spawned && -[_spawned timeIntervalSinceNow] < kSpawnEvery) return;
    _spawned = [NSDate date];
    NSString *bin = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"mesh-tor"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:bin]) return;
    // Der Ordner muss uns gehören und darf kein Symlink sein (sonst läge der Steuer-Socket woanders).
    struct stat st;
    if (lstat(kDataDir.fileSystemRepresentation, &st) == 0) {
        if (!S_ISDIR(st.st_mode) || st.st_uid != getuid()) { MeshLog(@"Tor: Datenordner gehört nicht uns"); return; }
        if ((st.st_mode & 077) != 0) chmod(kDataDir.fileSystemRepresentation, 0700);
    } else if (mkdir(kDataDir.fileSystemRepresentation, 0700) != 0) return;
    char socks[24], control[160];
    snprintf(socks, sizeof(socks), "127.0.0.1:%d", kSocksPort);
    snprintf(control, sizeof(control), "unix:%s", kControlSocket.fileSystemRepresentation);
    const char *argv[] = { "mesh-tor", "--ignore-missing-torrc", "-f", "/dev/null",
        "--DataDirectory", kDataDir.fileSystemRepresentation, "--SocksPort", socks,
        "--ControlPort", control, "--CookieAuthentication", "1", "--ClientOnly", "1",
        "--AvoidDiskWrites", "1", "--Log", "warn stderr", NULL };
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    // Eigene Prozessgruppe: launchd beendet sonst mit der App (ihrer Gruppe) auch Tor, und jeder Start
    // müsste das Verzeichnis neu einlesen.
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);
    pid_t pid = 0;
    int err = posix_spawn(&pid, bin.fileSystemRepresentation, &fa, &attr, (char *const *)argv, environ);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&fa);
    if (!err) _child = pid;
    if (err) MeshLog(@"Tor: Start fehlgeschlagen (%d)", err);
}

// Notlöschung: Tor anhalten und den Datenordner leeren. Der Zustand verrät Guard-Relays und wann Tor
// zuletzt lief; das Verzeichnis lädt Tor beim nächsten Start neu (dauert dann wieder gut eine Minute).
- (void)forgetState {
#if MESH_USE_TOR
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int fd = connectControl();
        NSData *cookie = fd >= 0 ? [NSData dataWithContentsOfFile:kCookiePath] : nil;
        if (cookie.length == 32 && [command(fd, [@"AUTHENTICATE " stringByAppendingString:hex(cookie)]) hasPrefix:@"250"])
            command(fd, @"SIGNAL HALT");
        if (fd >= 0) close(fd);
        sleep(1);
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *f in [fm contentsOfDirectoryAtPath:kDataDir error:NULL])
            [fm removeItemAtPath:[kDataDir stringByAppendingPathComponent:f] error:NULL];
    });
#endif
}

- (void)wakeUp {
#if MESH_USE_TOR
    if (!_since) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int fd = connectControl();
        if (fd < 0) return;
        NSData *cookie = [NSData dataWithContentsOfFile:kCookiePath];
        if (cookie.length == 32 && [command(fd, [@"AUTHENTICATE " stringByAppendingString:hex(cookie)]) hasPrefix:@"250"])
            command(fd, @"SIGNAL ACTIVE");   // ab Tor 0.4.0; holt Verzeichnis und Kreise sofort neu
        close(fd);
    });
#endif
}

// Läuft schon ein Tor mit diesem Datenordner? Tor hält seine Datei "lock" per flock fest. Nur dann
// ein eigenes starten: ein zweites Tor löscht beim Start den Steuer-Socket des ersten (unlink vor
// bind) und beendet sich am Lock; übrig bliebe ein laufendes, aber unerreichbares Tor.
static BOOL torRunning(void) {
    int fd = open(kLockPath.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return NO;
    BOOL held = flock(fd, LOCK_SH | LOCK_NB) != 0 && errno == EWOULDBLOCK;
    if (!held) flock(fd, LOCK_UN);
    close(fd);
    return held;
}

// Ein Tor, das läuft, aber seit kStaleAfter nicht erreichbar ist (Socket gelöscht, hängt), beenden:
// launchd bzw. die nächste Runde startet es frisch. Nur eigene Prozesse namens mesh-tor.
static void stopUnreachableTor(void) {
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t len = 0;
    if (sysctl(mib, 3, NULL, &len, NULL, 0) != 0 || !len) return;
    struct kinfo_proc *procs = malloc(len);
    if (procs && sysctl(mib, 3, procs, &len, NULL, 0) == 0) {
        for (size_t i = 0; i < len / sizeof(struct kinfo_proc); i++) {
            struct kinfo_proc *p = &procs[i];
            if (p->kp_eproc.e_ucred.cr_uid == getuid() && !strncmp(p->kp_proc.p_comm, "mesh-tor", MAXCOMLEN))
                kill(p->kp_proc.p_pid, SIGTERM);
        }
    }
    free(procs);
}

// Ein beendetes eigenes Tor abholen (sonst bliebe es als Zombie stehen); ein laufendes bleibt.
- (void)reapChild {
    if (_child > 0 && waitpid(_child, NULL, WNOHANG) == _child) _child = 0;
}

- (void)watch {
    @autoreleasepool {
        BOOL ready = NO;
        for (;;) {
            @autoreleasepool {
                int fd = connectControl();
                NSData *cookie = fd >= 0 ? [NSData dataWithContentsOfFile:kCookiePath] : nil;
                NSString *auth = cookie.length == 32 ? command(fd, [@"AUTHENTICATE " stringByAppendingString:hex(cookie)]) : nil;
                [self reapChild];
                if (![auth hasPrefix:@"250"]) {
                    BOOL answered = fd >= 0;   // Tor läuft, nur die Anmeldung scheitert: nicht noch eins starten
                    if (fd >= 0) close(fd);
                    BOOL late = -[_since timeIntervalSinceNow] > kGiveUp;
                    if (ready) MeshLog(@"Tor: Verbindung verloren (Cookie %lu Byte, Antwort %@)", (unsigned long)cookie.length, auth);
                    ready = NO;
                    BOOL running = !answered && torRunning();
                    if (!answered && !running && -[_since timeIntervalSinceNow] > 3) [self spawnIfDue];   // erst dem Dienst eine Chance geben
                    if (!running) _unreachable = nil;
                    else if (!_unreachable) _unreachable = [NSDate date];
                    else if (-[_unreachable timeIntervalSinceNow] > kStaleAfter) {
                        MeshLog(@"Tor: läuft, aber ohne Steuer-Socket, starte neu");
                        stopUnreachableTor();
                        _unreachable = nil;
                        _since = [NSDate date];   // frische Frist: kein kurzes "Tor läuft nicht" beim Neustart
                    }
                    [self setState:late && !running ? MeshTorFailed : MeshTorStarting percent:0];   // läuft es, wird es noch
                    sleep(2);
                    continue;
                }
                _unreachable = nil;
                // Fortschritt abfragen, bis die Verbindung abreißt (Dienst neu gestartet).
                for (;;) {
                    int p = bootstrapPercent(command(fd, @"GETINFO status/bootstrap-phase"));
                    if (p >= 100 && !ownsSocksPort(fd)) p = 99;   // fertig, aber der Port gehört nicht Tor
                    if (!ready && p >= 100) MeshLog(@"Tor: bereit");
                    if (p < 0) break;
                    ready = p >= 100;
                    [self setState:ready ? MeshTorReady : MeshTorStarting percent:p];
                    sleep(ready ? 10 : 1);
                }
                close(fd);
                ready = NO;
                [self setState:MeshTorStarting percent:0];
            }
        }
    }
}

@end
