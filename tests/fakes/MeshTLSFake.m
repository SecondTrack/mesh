#import "MeshTLSFake.h"

@implementation MeshTLS {
    NSMutableData *_in, *_out;
    NSData *(^_responder)(NSData *);
    BOOL _open;
}
- (instancetype)init { if ((self = [super init])) { _in = [NSMutableData data]; _out = [NSMutableData data]; } return self; }
- (BOOL)connectHost:(NSString *)h port:(int)p error:(NSString **)e { _open = YES; return YES; }
- (int)write:(NSData *)d {
    if (!_open) return -1;
    [_out appendData:d];
    if (_responder) { NSData *r = _responder(d); _responder = nil; [_in appendData:r]; }
    return (int)d.length;
}
- (NSData *)readUpTo:(int)maxLen {
    if (!_open || !_in.length) return nil;                  // keine Daten mehr = Verbindung zu
    NSUInteger n = MIN((NSUInteger)maxLen, _in.length);
    NSData *d = [_in subdataWithRange:NSMakeRange(0, n)];
    [_in replaceBytesInRange:NSMakeRange(0, n) withBytes:NULL length:0];
    return d;
}
- (void)close { _open = NO; }
- (void)feed:(NSData *)b { [_in appendData:b]; }
- (void)setResponder:(NSData *(^)(NSData *))r { _responder = [r copy]; }
- (NSData *)written { return _out; }
- (BOOL)isOpen { return _open; }
@end
