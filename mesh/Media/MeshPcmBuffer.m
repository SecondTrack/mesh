#import "MeshPcmBuffer.h"
#import "MeshMemory.h"

@implementation MeshPcmBuffer {
    NSMutableData *_data;
    NSUInteger _filled;
    NSObject *_lock;
}

- (instancetype)initWithCapacity:(NSUInteger)bytes {
    if ((self = [super init])) {
        _data = [NSMutableData dataWithLength:bytes];
        _lock = [NSObject new];
    }
    return self;
}

- (void)append:(const void *)bytes length:(NSUInteger)length {
    @synchronized (_lock) {
        NSUInteger n = MIN(_data.length - _filled, length);
        memcpy((char *)_data.mutableBytes + _filled, bytes, n);
        _filled += n;
    }
}

- (NSMutableData *)take {
    @synchronized (_lock) {
        NSMutableData *out = [NSMutableData dataWithBytes:_data.bytes length:_filled];
        MeshWipe(_data);
        _filled = 0;
        return out;
    }
}

- (void)dealloc { MeshWipe(_data); }

@end
