#import "MeshQRDecoder.h"
#include "quirc.h"
#import "MeshLog.h"

@implementation MeshQRDecoder {
    struct quirc *_q;
    int _w, _h;
}

- (void)dealloc { if (_q) quirc_destroy(_q); }

// Graustufenbild in quircs Puffer schreiben (Mittelwert aus B, G, R).
- (BOOL)loadGray:(const uint8_t *)base width:(int)w height:(int)h bytesPerRow:(size_t)bpr {
    if (!_q) _q = quirc_new();
    if (!_q) return NO;
    if (_w != w || _h != h) {
        if (quirc_resize(_q, w, h) < 0) { _w = _h = 0; return NO; }
        _w = w; _h = h;
    }
    int gw = 0, gh = 0;
    uint8_t *gray = quirc_begin(_q, &gw, &gh);
    if (!gray || gw != w || gh != h) return NO;
    for (int y = 0; y < h; y++) {
        const uint8_t *row = base + y * bpr;
        uint8_t *g = gray + y * w;
        for (int x = 0; x < w; x++) {
            const uint8_t *p = row + x * 4;
            g[x] = (uint8_t)((p[0] + p[1] + p[2]) / 3);
        }
    }
    quirc_end(_q);
    return YES;
}

// Ausgewertet wird das mittlere Quadrat (bei 1280×720: 720×720): Der Code liegt im Zielrahmen, und
// quirc rechnet so auf gut der Hälfte der Pixel.
- (NSString *)decodePixelBuffer:(CVPixelBufferRef)ib {
    if (!ib || CVPixelBufferGetPixelFormatType(ib) != kCVPixelFormatType_32BGRA) return nil;
    CVPixelBufferLockBaseAddress(ib, kCVPixelBufferLock_ReadOnly);
    int w = (int)CVPixelBufferGetWidth(ib), h = (int)CVPixelBufferGetHeight(ib);
    size_t bpr = CVPixelBufferGetBytesPerRow(ib);
    const uint8_t *base = CVPixelBufferGetBaseAddress(ib);
    int side = MIN(w, h);
    const uint8_t *crop = base ? base + (size_t)((h - side) / 2) * bpr + (size_t)((w - side) / 2) * 4 : NULL;
    BOOL ok = base && side > 0 && bpr >= (size_t)w * 4 && [self loadGray:crop width:side height:side bytesPerRow:bpr];
    CVPixelBufferUnlockBaseAddress(ib, kCVPixelBufferLock_ReadOnly);
    if (!ok) return nil;

#ifdef DEBUG
    {   // Diagnose: alle 3 s ein Graubild (PGM) und was quirc findet
        static CFAbsoluteTime last;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - last > 3) {
            last = now;
            int gw = 0, gh = 0;
            uint8_t *g = quirc_begin(_q, &gw, &gh);   // Puffer ist noch das letzte Bild
            NSMutableData *pgm = [[[NSString stringWithFormat:@"P5\n%d %d\n255\n", gw, gh] dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
            [pgm appendBytes:g length:(NSUInteger)(gw * gh)];
            NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
            [pgm writeToFile:[docs stringByAppendingPathComponent:@"qr-frame.pgm"] atomically:YES];
            quirc_end(_q);
            for (int i = 0; i < quirc_count(_q); i++) {
                struct quirc_code c; struct quirc_data d;
                quirc_extract(_q, i, &c);
                int err = quirc_decode(&c, &d);
                MeshLog(@"QR-Diag: %d Codes, #%d size=%d err=%d (%s)", quirc_count(_q), i, c.size, err, quirc_strerror(err));
            }
            if (!quirc_count(_q)) MeshLog(@"QR-Diag: kein Code gefunden (%dx%d)", gw, gh);
        }
    }
#endif
    for (int i = 0; i < quirc_count(_q); i++) {
        struct quirc_code code; struct quirc_data data;
        quirc_extract(_q, i, &code);
        if (quirc_decode(&code, &data) != 0) {   // gespiegelt (Frontkamera, Spiegel) noch einmal
            quirc_flip(&code);
            if (quirc_decode(&code, &data) != 0) continue;
        }
        NSString *text = [[NSString alloc] initWithBytes:data.payload length:data.payload_len encoding:NSUTF8StringEncoding];
        if (text.length) return text;
    }
    return nil;
}

@end
