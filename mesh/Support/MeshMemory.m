#import "MeshMemory.h"

// memset_s gibt es erst ab iOS 7; volatile hält den Compiler davon ab, das Löschen wegzuoptimieren.
void MeshWipeBytes(void *bytes, size_t length) {
    volatile unsigned char *p = bytes;
    while (length--) *p++ = 0;
}

void MeshWipe(NSData *data) {
    if ([data isKindOfClass:[NSMutableData class]]) MeshWipeBytes(((NSMutableData *)data).mutableBytes, data.length);
}
