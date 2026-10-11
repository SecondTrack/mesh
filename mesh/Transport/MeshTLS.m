#import "MeshTLS.h"
#import "MeshTor.h"
#import "MeshCertTime.h"
#import "MeshLog.h"

#include <sys/socket.h>
#include "mbedtls/net_sockets.h"
#include "mbedtls/ssl.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/error.h"
#include "mbedtls/x509_crt.h"

static const NSTimeInterval kHandshakeTimeout = 20;

// Vertrauenswürdige Wurzeln: Mozilla-CA-Bundle aus dem App-Bundle (der Speicher von iOS 6 ist
// veraltet). Einmal geparst und danach nur gelesen: von allen Verbindungen gemeinsam genutzt.
static mbedtls_x509_crt *MeshTrustedRoots(void) {
    static mbedtls_x509_crt roots;
    static BOOL ok;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mbedtls_x509_crt_init(&roots);
        NSString *path = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
        NSData *pem = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (!pem.length) return;
        NSMutableData *z = [pem mutableCopy];
        [z appendBytes:"" length:1];                      // PEM-Parser verlangt abschließende 0
        int bad = mbedtls_x509_crt_parse(&roots, z.bytes, z.length);
        ok = (bad >= 0 && roots.version != 0);
        MeshLog(@"TLS: CA-Bundle geladen (%d nicht lesbar)", bad);
    });
    return ok ? &roots : NULL;
}

// Zusatzprüfung je Zertifikat der Kette: Gültigkeitszeitraum, wenn die Uhr plausibel ist.
static int MeshVerifyTime(void *ctx, mbedtls_x509_crt *crt, int depth, uint32_t *flags) {
    MeshCertDate from = { crt->valid_from.year, crt->valid_from.mon, crt->valid_from.day,
                          crt->valid_from.hour, crt->valid_from.min, crt->valid_from.sec };
    MeshCertDate to   = { crt->valid_to.year, crt->valid_to.mon, crt->valid_to.day,
                          crt->valid_to.hour, crt->valid_to.min, crt->valid_to.sec };
    switch (MeshCertCheckTime(time(NULL), MESH_BUILD_TIME, from, to)) {
        case MeshCertTimeExpired:      *flags |= MBEDTLS_X509_BADCERT_EXPIRED; break;
        case MeshCertTimeNotYetValid:  *flags |= MBEDTLS_X509_BADCERT_FUTURE;  break;
        case MeshCertTimeOK:
        case MeshCertTimeClockUnknown: break;
    }
    return 0;
}

@implementation MeshTLS {
    mbedtls_net_context      _fd;
    mbedtls_entropy_context  _entropy;
    mbedtls_ctr_drbg_context _drbg;
    mbedtls_ssl_context      _ssl;
    mbedtls_ssl_config       _conf;
    BOOL _open;         // Handshake fertig, Daten können fließen
    BOOL _connecting;   // Aufbau läuft; den Socket gibt dann nur der verbindende Thread frei
    BOOL _closed;       // close wurde gerufen
    NSLock *_ioLock;   // mbedTLS ist nicht threadsicher: lesen, schreiben und schließen nacheinander
    CFReadStreamRef _voipRead;    // nur Markierung: iOS hält VoIP-Sockets im Hintergrund wach
    CFWriteStreamRef _voipWrite;
}

- (instancetype)init {
    if ((self = [super init])) {
        mbedtls_net_init(&_fd);
        mbedtls_ssl_init(&_ssl);
        mbedtls_ssl_config_init(&_conf);
        mbedtls_ctr_drbg_init(&_drbg);
        mbedtls_entropy_init(&_entropy);
        _ioLock = [[NSLock alloc] init];
    }
    return self;
}

// Der Aufbau läuft ohne Lock (er blockiert lange). close darf in dieser Zeit den Socket nicht
// freigeben, sonst könnte die Nummer neu vergeben werden und Handshake-Bytes landeten in einer
// anderen Verbindung. Deshalb räumt immer der Thread auf, der verbindet.
- (BOOL)connectHost:(NSString *)host port:(int)port error:(NSString **)errorOut {
    [_ioLock lock];
    if (_closed) { [_ioLock unlock]; return NO; }
    _connecting = YES;
    [_ioLock unlock];

    BOOL ok = [self establishHost:host port:port error:errorOut];

    [_ioLock lock];
    _connecting = NO;
    if (ok && !_closed) { _open = YES; [self markForBackground]; }
    else { ok = NO; mbedtls_net_free(&_fd); }
    [_ioLock unlock];
    return ok;
}

// Als VoIP-Socket markieren (wie GCDAsyncSocket enableBackgroundingOnSocket): mit dem
// Hintergrundmodus "voip" weckt iOS die App, wenn im Hintergrund Daten ankommen. Gelesen wird
// weiter über mbedTLS; die Streams schließen den Socket nicht.
- (void)markForBackground {
#if TARGET_OS_IPHONE
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, _fd.fd, &_voipRead, &_voipWrite);
    if (!_voipRead || !_voipWrite) { [self unmarkForBackground]; return; }
    CFReadStreamSetProperty(_voipRead, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanFalse);
    CFWriteStreamSetProperty(_voipWrite, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanFalse);
    CFReadStreamSetProperty(_voipRead, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP);
    CFWriteStreamSetProperty(_voipWrite, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP);
    CFReadStreamOpen(_voipRead);
    CFWriteStreamOpen(_voipWrite);
#endif
}

- (void)unmarkForBackground {
    if (_voipRead) { CFReadStreamClose(_voipRead); CFRelease(_voipRead); _voipRead = NULL; }
    if (_voipWrite) { CFWriteStreamClose(_voipWrite); CFRelease(_voipWrite); _voipWrite = NULL; }
}

- (BOOL)establishHost:(NSString *)host port:(int)port error:(NSString **)errorOut {
    int ret;
    const char *pers = "mesh-ios-tls";

    ret = mbedtls_ctr_drbg_seed(&_drbg, mbedtls_entropy_func, &_entropy,
                                (const unsigned char *)pers, strlen(pers));
    if (ret != 0) return [self fail:ret out:errorOut];

    // Direkt oder über Tors SOCKS5-Proxy (dann sieht das Relay nur einen Tor-Exit).
    int socks = [[MeshTor shared] socksPort];
    if ([MeshTor shared].enabled && socks <= 0) {   // zweite Sicherung: nie direkt, wenn Tor gewollt ist
        if (errorOut) *errorOut = @"Tor nicht bereit";
        return NO;
    }
    if (socks > 0) {
        char sp[8]; snprintf(sp, sizeof(sp), "%d", socks);
        ret = mbedtls_net_connect(&_fd, "127.0.0.1", sp, MBEDTLS_NET_PROTO_TCP);
        if (ret != 0) return [self fail:ret out:errorOut];
        if (![self socks5ConnectTo:host port:port error:errorOut]) return NO;
    } else {
        char portStr[8]; snprintf(portStr, sizeof(portStr), "%d", port);
        ret = mbedtls_net_connect(&_fd, host.UTF8String, portStr, MBEDTLS_NET_PROTO_TCP);
        if (ret != 0) return [self fail:ret out:errorOut];
    }
    // Ein Relay, das nichts mehr annimmt, darf write: nicht ewig festhalten: der Schreiber hält den
    // I/O-Lock, und close wartet in derselben Queue. Lesen bleibt ohne Frist (ruhende Verbindung).
    struct timeval sendTimeout = { 20, 0 };
    setsockopt(_fd.fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, sizeof(sendTimeout));

    ret = mbedtls_ssl_config_defaults(&_conf, MBEDTLS_SSL_IS_CLIENT,
                                      MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) return [self fail:ret out:errorOut];

    // Zertifikat muss zu einer bekannten Wurzel führen und auf den Hostnamen passen.
    mbedtls_x509_crt *roots = MeshTrustedRoots();
    if (!roots) { if (errorOut) *errorOut = @"TLS: CA-Bundle fehlt"; return NO; }
    mbedtls_ssl_conf_authmode(&_conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&_conf, roots, NULL);
    mbedtls_ssl_conf_verify(&_conf, MeshVerifyTime, NULL);
    mbedtls_ssl_conf_rng(&_conf, mbedtls_ctr_drbg_random, &_drbg);
    // Read-Timeout: der Reader gibt so alle 300ms den I/O-Lock frei, damit Writes durchkommen.
    mbedtls_ssl_conf_read_timeout(&_conf, 300);

    ret = mbedtls_ssl_setup(&_ssl, &_conf);
    if (ret != 0) return [self fail:ret out:errorOut];

    // SNI: viele Relays hängen hinter Hosts, die ohne SNI abweisen.
    ret = mbedtls_ssl_set_hostname(&_ssl, host.UTF8String);
    if (ret != 0) return [self fail:ret out:errorOut];

    // recv_timeout als 5. Arg → mbedtls_ssl_read liefert MBEDTLS_ERR_SSL_TIMEOUT statt ewig zu blocken.
    mbedtls_ssl_set_bio(&_ssl, &_fd, mbedtls_net_send, mbedtls_net_recv, mbedtls_net_recv_timeout);

    // Das Lese-Timeout (300 ms, für den Lock-Wechsel beim Lesen) gilt auch im Handshake. Über Tor
    // dauert eine Antwort oft länger: Timeout heißt hier "weiter warten", bis zur Gesamtfrist.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kHandshakeTimeout];
    while ((ret = mbedtls_ssl_handshake(&_ssl)) != 0) {
        BOOL again = ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE || ret == MBEDTLS_ERR_SSL_TIMEOUT;
        if (!again || [deadline timeIntervalSinceNow] < 0) return [self fail:ret out:errorOut];
    }
    return YES;
}

// Genau n Bytes senden bzw. empfangen (TCP liefert in Stücken).
static BOOL sendAll(mbedtls_net_context *fd, const unsigned char *p, size_t n) {
    while (n > 0) { int r = mbedtls_net_send(fd, p, n); if (r <= 0) return NO; p += r; n -= (size_t)r; }
    return YES;
}
static BOOL recvAll(mbedtls_net_context *fd, unsigned char *p, size_t n) {
    while (n > 0) { int r = mbedtls_net_recv(fd, p, n); if (r <= 0) return NO; p += r; n -= (size_t)r; }
    return YES;
}

// SOCKS5-CONNECT auf dem rohen Socket (vor dem TLS-Handshake). Domain-Typ, damit Tor selbst
// auflöst (kein DNS-Leak).
- (BOOL)socks5ConnectTo:(NSString *)host port:(int)port error:(NSString **)errorOut {
    const char *h = host.UTF8String; size_t hlen = h ? strlen(h) : 0;
    if (hlen == 0 || hlen > 255) { if (errorOut) *errorOut = @"SOCKS: host length"; return NO; }

    // Begrüßung: VER=5, 1 Methode, 0x00 = ohne Anmeldung
    unsigned char greet[3] = { 0x05, 0x01, 0x00 }, resp[2];
    if (!sendAll(&_fd, greet, 3) || !recvAll(&_fd, resp, 2) || resp[0] != 0x05 || resp[1] != 0x00) {
        if (errorOut) *errorOut = @"SOCKS: greeting refused"; return NO;
    }

    // CONNECT: VER, CMD=1, RSV, ATYP=3 (Domain), Länge, Host, Port
    unsigned char req[262]; size_t n = 0;
    req[n++] = 0x05; req[n++] = 0x01; req[n++] = 0x00; req[n++] = 0x03;
    req[n++] = (unsigned char)hlen;
    memcpy(req + n, h, hlen); n += hlen;
    req[n++] = (port >> 8) & 0xFF; req[n++] = port & 0xFF;
    if (!sendAll(&_fd, req, n)) { if (errorOut) *errorOut = @"SOCKS: send connect"; return NO; }

    // Antwort: VER, REP (0 = ok), RSV, ATYP, gebundene Adresse, Port: Adresse wird verworfen.
    unsigned char rep[4];
    if (!recvAll(&_fd, rep, 4)) { if (errorOut) *errorOut = @"SOCKS: no reply"; return NO; }
    if (rep[0] != 0x05 || rep[1] != 0x00) { if (errorOut) *errorOut = [NSString stringWithFormat:@"SOCKS: reply=%d", rep[1]]; return NO; }
    size_t skip;
    if (rep[3] == 0x01) skip = 4;
    else if (rep[3] == 0x04) skip = 16;
    else if (rep[3] == 0x03) { unsigned char l; if (!recvAll(&_fd, &l, 1)) return NO; skip = l; }
    else { if (errorOut) *errorOut = @"SOCKS: address type"; return NO; }
    unsigned char waste[255 + 2];
    return recvAll(&_fd, waste, skip + 2);
}

- (int)write:(NSData *)data {
    [_ioLock lock];
    if (!_open) { [_ioLock unlock]; return -1; }
    const unsigned char *p = data.bytes;
    size_t left = data.length;
    int result = (int)data.length;
    while (left > 0) {
        int ret = mbedtls_ssl_write(&_ssl, p, left);
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (ret <= 0) { result = ret; break; }
        p += ret; left -= ret;
    }
    [_ioLock unlock];
    return result;
}

- (NSData *)readUpTo:(int)maxLen {
    unsigned char *buf = malloc(maxLen);
    int ret;
    while (1) {
        [_ioLock lock];
        if (!_open) { [_ioLock unlock]; free(buf); return nil; }
        ret = mbedtls_ssl_read(&_ssl, buf, maxLen);
        [_ioLock unlock];
        // WANT_READ/WANT_WRITE/TIMEOUT: keine App-Daten vorhanden. Lock ist freigegeben →
        // ein wartender Writer kommt jetzt dran. Danach erneut versuchen.
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE ||
            ret == MBEDTLS_ERR_SSL_TIMEOUT) continue;
        break;
    }
    if (ret <= 0) { free(buf); return nil; }
    NSData *d = [NSData dataWithBytes:buf length:ret];
    free(buf);
    return d;
}

- (void)close {
    [_ioLock lock];
    _closed = YES;
    if (_connecting) {
        // Aufbau unterbrechen; den Socket gibt connectHost: frei.
        if (_fd.fd >= 0) shutdown(_fd.fd, SHUT_RDWR);
    } else {
        if (_open) { mbedtls_ssl_close_notify(&_ssl); _open = NO; }
        [self unmarkForBackground];
        mbedtls_net_free(&_fd);   // idempotent (setzt fd = -1)
    }
    [_ioLock unlock];
}

- (BOOL)fail:(int)ret out:(NSString **)errorOut {
    if (errorOut) {
        char b[128]; mbedtls_strerror(ret, b, sizeof(b));
        *errorOut = [NSString stringWithFormat:@"mbedTLS -0x%04x: %s", -ret, b];
    }
    return NO;
}

- (void)dealloc {
    [self unmarkForBackground];
    mbedtls_net_free(&_fd);   // falls close nie lief; idempotent
    mbedtls_ssl_free(&_ssl);
    mbedtls_ssl_config_free(&_conf);
    mbedtls_ctr_drbg_free(&_drbg);
    mbedtls_entropy_free(&_entropy);
}

@end
