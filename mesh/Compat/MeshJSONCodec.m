#import "MeshJSONCodec.h"

#include <errno.h>
#include <math.h>

#pragma mark - Parser

typedef struct {
    const uint8_t *p;
    const uint8_t *end;
    int depth;
} MJParser;

static id mj_value(MJParser *ps);

static void mj_skipWS(MJParser *ps) {
    while (ps->p < ps->end && (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r')) ps->p++;
}

static BOOL mj_literal(MJParser *ps, const char *lit) {
    size_t n = strlen(lit);
    if ((size_t)(ps->end - ps->p) < n || memcmp(ps->p, lit, n) != 0) return NO;
    ps->p += n;
    return YES;
}

static int mj_hex4(MJParser *ps) {
    if (ps->end - ps->p < 4) return -1;
    int v = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t c = ps->p[i];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= c - '0';
        else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
        else return -1;
    }
    ps->p += 4;
    return v;
}

static NSString *mj_string(MJParser *ps) {
    if (ps->p >= ps->end || *ps->p != '"') return nil;
    ps->p++;
    NSMutableData *buf = [NSMutableData data];
    while (ps->p < ps->end) {
        uint8_t c = *ps->p++;
        if (c == '"') return [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
        if (c < 0x20) return nil;                       // Steuerzeichen müssen escaped sein
        if (c != '\\') { [buf appendBytes:&c length:1]; continue; }
        if (ps->p >= ps->end) return nil;
        uint8_t e = *ps->p++;
        uint8_t out;
        switch (e) {
            case '"': out = '"'; break;   case '\\': out = '\\'; break;  case '/': out = '/'; break;
            case 'b': out = '\b'; break;  case 'f': out = '\f'; break;   case 'n': out = '\n'; break;
            case 'r': out = '\r'; break;  case 't': out = '\t'; break;
            case 'u': {
                int cp = mj_hex4(ps);
                if (cp < 0) return nil;
                if (cp >= 0xD800 && cp <= 0xDBFF) {             // High-Surrogate → Low muss folgen
                    if (ps->end - ps->p < 2 || ps->p[0] != '\\' || ps->p[1] != 'u') return nil;
                    ps->p += 2;
                    int lo = mj_hex4(ps);
                    if (lo < 0xDC00 || lo > 0xDFFF) return nil;
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                    return nil;                                 // einzelnes Low-Surrogate
                }
                uint8_t u[4]; int n;
                if (cp < 0x80)        { u[0] = (uint8_t)cp; n = 1; }
                else if (cp < 0x800)  { u[0] = 0xC0 | (cp >> 6); u[1] = 0x80 | (cp & 0x3F); n = 2; }
                else if (cp < 0x10000) { u[0] = 0xE0 | (cp >> 12); u[1] = 0x80 | ((cp >> 6) & 0x3F); u[2] = 0x80 | (cp & 0x3F); n = 3; }
                else                  { u[0] = 0xF0 | (cp >> 18); u[1] = 0x80 | ((cp >> 12) & 0x3F); u[2] = 0x80 | ((cp >> 6) & 0x3F); u[3] = 0x80 | (cp & 0x3F); n = 4; }
                [buf appendBytes:u length:n];
                continue;
            }
            default: return nil;
        }
        [buf appendBytes:&out length:1];
    }
    return nil;                                                 // nicht abgeschlossen
}

static NSNumber *mj_number(MJParser *ps) {
    const uint8_t *start = ps->p;
    BOOL isFloat = NO;
    if (ps->p < ps->end && *ps->p == '-') ps->p++;
    if (ps->p >= ps->end) return nil;
    if (*ps->p == '0') ps->p++;
    else if (*ps->p >= '1' && *ps->p <= '9') { while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9') ps->p++; }
    else return nil;
    if (ps->p < ps->end && *ps->p == '.') {
        isFloat = YES; ps->p++;
        if (ps->p >= ps->end || *ps->p < '0' || *ps->p > '9') return nil;
        while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    }
    if (ps->p < ps->end && (*ps->p == 'e' || *ps->p == 'E')) {
        isFloat = YES; ps->p++;
        if (ps->p < ps->end && (*ps->p == '+' || *ps->p == '-')) ps->p++;
        if (ps->p >= ps->end || *ps->p < '0' || *ps->p > '9') return nil;
        while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    }
    size_t len = (size_t)(ps->p - start);
    if (len > 64) return nil;
    char tmp[65];
    memcpy(tmp, start, len); tmp[len] = 0;
    if (!isFloat) {
        errno = 0;
        long long v = strtoll(tmp, NULL, 10);
        if (errno != ERANGE) return [NSNumber numberWithLongLong:v];
    }
    return [NSNumber numberWithDouble:strtod(tmp, NULL)];
}

static id mj_array(MJParser *ps) {
    ps->p++;                                                    // '['
    NSMutableArray *a = [NSMutableArray array];
    mj_skipWS(ps);
    if (ps->p < ps->end && *ps->p == ']') { ps->p++; return a; }
    while (1) {
        id v = mj_value(ps);
        if (!v) return nil;
        [a addObject:v];
        mj_skipWS(ps);
        if (ps->p >= ps->end) return nil;
        if (*ps->p == ',') { ps->p++; continue; }
        if (*ps->p == ']') { ps->p++; return a; }
        return nil;
    }
}

static id mj_object(MJParser *ps) {
    ps->p++;                                                    // '{'
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    mj_skipWS(ps);
    if (ps->p < ps->end && *ps->p == '}') { ps->p++; return d; }
    while (1) {
        mj_skipWS(ps);
        NSString *k = mj_string(ps);
        if (!k) return nil;
        mj_skipWS(ps);
        if (ps->p >= ps->end || *ps->p != ':') return nil;
        ps->p++;
        id v = mj_value(ps);
        if (!v) return nil;
        [d setObject:v forKey:k];
        mj_skipWS(ps);
        if (ps->p >= ps->end) return nil;
        if (*ps->p == ',') { ps->p++; continue; }
        if (*ps->p == '}') { ps->p++; return d; }
        return nil;
    }
}

static id mj_value(MJParser *ps) {
    mj_skipWS(ps);
    if (ps->p >= ps->end) return nil;
    switch (*ps->p) {
        case '{': case '[': {
            if (++ps->depth > MeshJSONMaxDepth) return nil;
            id v = (*ps->p == '{') ? mj_object(ps) : mj_array(ps);
            ps->depth--;
            return v;
        }
        case '"': return mj_string(ps);
        case 't': return mj_literal(ps, "true")  ? [NSNumber numberWithBool:YES] : nil;
        case 'f': return mj_literal(ps, "false") ? [NSNumber numberWithBool:NO]  : nil;
        case 'n': return mj_literal(ps, "null")  ? [NSNull null] : nil;
        default:  return mj_number(ps);
    }
}

#pragma mark - Serialisierer

static BOOL mj_write(id obj, NSMutableData *out, int depth);

static void mj_writeString(NSString *s, NSMutableData *out) {
    static const char hex[] = "0123456789abcdef";
    const char *u = s.UTF8String;
    if (!u) u = "";
    [out appendBytes:"\"" length:1];
    for (const uint8_t *p = (const uint8_t *)u; *p; p++) {
        uint8_t c = *p;
        const char *esc = NULL;
        switch (c) {
            case '"': esc = "\\\""; break;  case '\\': esc = "\\\\"; break;
            case '\n': esc = "\\n"; break;  case '\r': esc = "\\r"; break;
            case '\t': esc = "\\t"; break;  case '\b': esc = "\\b"; break;
            case '\f': esc = "\\f"; break;
        }
        if (esc) { [out appendBytes:esc length:2]; continue; }
        if (c < 0x20) {
            char e[6] = { '\\', 'u', '0', '0', hex[c >> 4], hex[c & 0xF] };
            [out appendBytes:e length:6];
            continue;
        }
        [out appendBytes:&c length:1];
    }
    [out appendBytes:"\"" length:1];
}

static BOOL mj_write(id obj, NSMutableData *out, int depth) {
    if (depth > MeshJSONMaxDepth) return NO;
    if ([obj isKindOfClass:[NSString class]]) { mj_writeString(obj, out); return YES; }
    if ([obj isKindOfClass:[NSNull class]]) { [out appendBytes:"null" length:4]; return YES; }
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)obj) == CFBooleanGetTypeID()) {
            BOOL b = [obj boolValue];
            [out appendBytes:(b ? "true" : "false") length:(b ? 4 : 5)];
            return YES;
        }
        const char *t = [obj objCType];
        NSString *s;
        if (*t == 'f' || *t == 'd') {
            double v = [obj doubleValue];
            if (isnan(v) || isinf(v)) return NO;
            s = [NSString stringWithFormat:@"%.17g", v];
        } else {
            s = [obj stringValue];
        }
        NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
        [out appendData:d];
        return YES;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        [out appendBytes:"[" length:1];
        BOOL first = YES;
        for (id v in obj) {
            if (!first) [out appendBytes:"," length:1];
            first = NO;
            if (!mj_write(v, out, depth + 1)) return NO;
        }
        [out appendBytes:"]" length:1];
        return YES;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        [out appendBytes:"{" length:1];
        BOOL first = YES;
        for (id k in obj) {
            if (![k isKindOfClass:[NSString class]]) return NO;
            if (!first) [out appendBytes:"," length:1];
            first = NO;
            mj_writeString(k, out);
            [out appendBytes:":" length:1];
            if (!mj_write([obj objectForKey:k], out, depth + 1)) return NO;
        }
        [out appendBytes:"}" length:1];
        return YES;
    }
    return NO;
}

#pragma mark -

@implementation MeshJSONCodec

+ (id)objectWithData:(NSData *)data {
    if (!data.length || data.length > MeshJSONMaxBytes) return nil;
    MJParser ps = { data.bytes, (const uint8_t *)data.bytes + data.length, 0 };
    id v = mj_value(&ps);
    if (!v) return nil;
    mj_skipWS(&ps);
    return (ps.p == ps.end) ? v : nil;                          // nichts hinter dem Dokument
}

+ (NSData *)dataWithObject:(id)object {
    if (![object isKindOfClass:[NSArray class]] && ![object isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableData *out = [NSMutableData data];
    return mj_write(object, out, 0) ? out : nil;
}

@end
