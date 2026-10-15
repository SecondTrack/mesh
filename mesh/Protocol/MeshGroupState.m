#import "MeshGroupState.h"
#import "MeshText.h"

static const int kMaxTimer = 365 * 24 * 3600;
static const long long kMaxRevision = 9007199254740991LL;   // 2^53-1: bleibt in jedem JSON-Leser exakt

static BOOL isHex(NSString *s, NSUInteger length) {
    if (![s isKindOfClass:[NSString class]] || s.length != length) return NO;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NO;
    }
    return YES;
}

// Ganze Zahl aus JSON (kein true/false, keine Nachkommastellen); NO sonst.
static BOOL integerValue(id v, long long *out) {
    if (![v isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) return NO;
    double d = [v doubleValue];
    if (d != d || d < -(double)kMaxRevision || d > (double)kMaxRevision || d != floor(d)) return NO;
    *out = (long long)d;
    return YES;
}

@implementation MeshGroupState

+ (BOOL)isPubkey:(NSString *)pk { return isHex(pk, 64); }
+ (BOOL)isPictureHash:(NSString *)p { return isHex(p, 16); }
+ (BOOL)isLinkKey:(NSString *)k { return isHex(k, 32); }

// B8.6: säubern, dann auf max UTF-16-Einheiten kürzen (eigene Eingaben, Beitrittsname).
+ (NSString *)cleanName:(NSString *)raw max:(NSUInteger)max {
    return MeshTruncateUTF16(MeshCleanGroupText(raw), max);
}

+ (instancetype)stateFromObject:(id)o {
    if (![o isKindOfClass:[NSDictionary class]]) return nil;
    long long v = 0, r = 0, t = 0;
    if (!integerValue(o[@"v"], &v) || v != 1) return nil;
    if (!isHex(o[@"g"], 16) || ![self isPubkey:o[@"a"]]) return nil;
    if (!integerValue(o[@"r"], &r) || r < 0) return nil;
    id tv = o[@"t"];
    if (tv && !integerValue(tv, &t)) return nil;
    if (t < 0 || t > kMaxTimer) return nil;
    id tm = o[@"tm"];
    if (tm && ![tm isKindOfClass:[NSString class]]) return nil;
    // p (B7): fehlt oder leer = kein Bild; sonst genau 16 Hex
    id p = o[@"p"];
    if (p && ![p isKindOfClass:[NSString class]]) return nil;
    if ([p length] && !isHex(p, 16)) return nil;
    // o (B10): fehlt = geschlossen; sonst genau 0 oder 1
    long long open = 0;
    if (o[@"o"] && (!integerValue(o[@"o"], &open) || (open != 0 && open != 1))) return nil;

    // Name: nach dem Säubern (B8.6) 1–50 UTF-16-Einheiten, sonst ungültig (nicht kürzen)
    if (![o[@"n"] isKindOfClass:[NSString class]]) return nil;
    NSString *name = MeshCleanGroupText(o[@"n"]);
    if (!name.length || name.length > MeshGroupMaxName) return nil;

    NSString *admin = [o[@"a"] lowercaseString];
    NSArray *m = o[@"m"];
    if (![m isKindOfClass:[NSArray class]] || m.count > MeshGroupMaxMembers) return nil;
    NSMutableArray *members = [NSMutableArray array];
    for (id pk in m) {
        if (![self isPubkey:pk]) return nil;
        NSString *k = [pk lowercaseString];
        if ([members containsObject:k]) return nil;   // keine Doppelten
        [members addObject:k];
    }
    if (members.count && ![members containsObject:admin]) return nil;   // leer nur als "aufgelöst"
    if (open == 1 && !members.count) return nil;                        // B10: "o" mit m = [] ist ungültig

    id nm = o[@"nm"];
    if (nm && ![nm isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (id key in (NSDictionary *)nm) {
        if (![self isPubkey:key]) continue;   // tolerant: Fremdes überspringen
        NSString *k = [key lowercaseString];
        if (![members containsObject:k]) continue;
        id value = nm[key];
        if (![value isKindOfClass:[NSString class]]) continue;
        NSString *clean = MeshCleanGroupText(value);   // B8.6: länger als 40 = verworfen (wie fehlend), nicht gekürzt
        if (clean.length <= MeshGroupMaxMemberName) names[k] = clean;
    }

    MeshGroupState *s = [[self alloc] init];
    s->_gid = [o[@"g"] lowercaseString];
    s->_name = name;
    s->_admin = admin;
    s->_revision = r;
    s->_members = members;
    s->_names = names;
    s->_timer = (int)t;
    s->_timerFromSent = [tm isEqualToString:@"sent"];
    s->_picture = [p length] ? [p lowercaseString] : nil;
    s->_open = open == 1;
    return s;
}

+ (instancetype)stateWithGroup:(NSString *)gid name:(NSString *)name admin:(NSString *)admin adminName:(NSString *)adminName {
    NSString *n = [self cleanName:name max:MeshGroupMaxName];
    if (!isHex(gid, 16) || ![self isPubkey:admin] || !n.length) return nil;
    MeshGroupState *s = [[self alloc] init];
    s->_gid = gid.lowercaseString;
    s->_name = n;
    s->_admin = admin.lowercaseString;
    s->_revision = 1;
    s->_members = @[s->_admin];
    s->_names = @{ s->_admin: [self cleanName:adminName max:MeshGroupMaxMemberName] };
    return s;
}

+ (instancetype)linkPlaceholder:(NSString *)gid name:(NSString *)name admin:(NSString *)admin {
    MeshGroupState *s = [self stateWithGroup:gid name:name admin:admin adminName:@""];
    if (s) { s->_revision = 0; s->_names = @{}; }
    return s;
}

- (BOOL)dissolved { return _members.count == 0; }
- (BOOL)hasMember:(NSString *)pk { return pk && [_members containsObject:pk]; }
- (NSString *)nameOf:(NSString *)pk { return (pk ? _names[pk] : nil) ?: @""; }

// Kopie mit neuer Revision (bump) oder gleicher.
- (instancetype)copyWithMembers:(NSArray *)members names:(NSDictionary *)names bump:(BOOL)bump {
    if (members.count > MeshGroupMaxMembers || _revision >= kMaxRevision) return nil;
    MeshGroupState *s = [[MeshGroupState alloc] init];
    s->_gid = _gid; s->_name = _name; s->_admin = _admin;
    s->_revision = _revision + (bump ? 1 : 0);
    s->_members = [members copy];
    NSMutableDictionary *n = [NSMutableDictionary dictionary];
    for (NSString *pk in members) if (names[pk]) n[pk] = names[pk];
    s->_names = n;
    s->_timer = _timer; s->_timerFromSent = _timerFromSent;
    s->_picture = _picture;
    s->_open = _open && members.count > 0;
    return s;
}

- (instancetype)withMember:(NSString *)pk name:(NSString *)name {
    if (![MeshGroupState isPubkey:pk] || self.dissolved) return nil;
    NSString *k = pk.lowercaseString;
    if ([_members containsObject:k]) return nil;
    NSMutableDictionary *names = [_names mutableCopy];
    names[k] = [MeshGroupState cleanName:name max:MeshGroupMaxMemberName];
    return [self copyWithMembers:[_members arrayByAddingObject:k] names:names bump:YES];
}

- (instancetype)withoutMember:(NSString *)pk {
    if (![_members containsObject:pk] || [pk isEqualToString:_admin]) return nil;
    NSMutableArray *m = [_members mutableCopy];
    [m removeObject:pk];
    return [self copyWithMembers:m names:_names bump:YES];
}

- (instancetype)locallyWithout:(NSString *)pk {
    if (![_members containsObject:pk] || [pk isEqualToString:_admin]) return nil;
    NSMutableArray *m = [_members mutableCopy];
    [m removeObject:pk];
    return [self copyWithMembers:m names:_names bump:NO];
}

- (instancetype)renamed:(NSString *)name {
    NSString *n = [MeshGroupState cleanName:name max:MeshGroupMaxName];
    if (!n.length || self.dissolved) return nil;
    MeshGroupState *s = [self copyWithMembers:_members names:_names bump:YES];
    if (s) s->_name = n;
    return s;
}

- (instancetype)withTimer:(int)seconds fromSent:(BOOL)fromSent {
    if (seconds < 0 || seconds > kMaxTimer || self.dissolved) return nil;
    MeshGroupState *s = [self copyWithMembers:_members names:_names bump:YES];
    if (s) { s->_timer = seconds; s->_timerFromSent = seconds > 0 && fromSent; }
    return s;
}

- (instancetype)dissolvedState { return [self copyWithMembers:@[] names:@{} bump:YES]; }

- (instancetype)bumped { return self.dissolved ? nil : [self copyWithMembers:_members names:_names bump:YES]; }

- (instancetype)withPicture:(NSString *)hash {
    if ((hash && !isHex(hash, 16)) || self.dissolved) return nil;
    MeshGroupState *s = [self copyWithMembers:_members names:_names bump:YES];
    if (s) s->_picture = hash.lowercaseString;
    return s;
}

- (instancetype)withAdmin:(NSString *)pk {
    NSString *k = [MeshGroupState isPubkey:pk] ? pk.lowercaseString : nil;
    if (!k || self.dissolved || ![_members containsObject:k] || [k isEqualToString:_admin]) return nil;
    MeshGroupState *s = [self copyWithMembers:_members names:_names bump:YES];
    if (s) { s->_admin = k; s->_open = NO; }   // B10: Übergabe schließt die Gruppe, k reist nie mit
    return s;
}

- (instancetype)withOpen:(BOOL)open {
    if (self.dissolved) return nil;
    MeshGroupState *s = [self copyWithMembers:_members names:_names bump:YES];
    if (s) s->_open = open;
    return s;
}

#pragma mark - JSON

// JSON-String: Anführungszeichen, Backslash und Steuerzeichen maskiert, alles andere roh (UTF-8).
static void appendString(NSMutableString *out, NSString *s) {
    [out appendString:@"\""];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
            case '"':  [out appendString:@"\\\""]; break;
            case '\\': [out appendString:@"\\\\"]; break;
            case '\n': [out appendString:@"\\n"]; break;
            case '\r': [out appendString:@"\\r"]; break;
            case '\t': [out appendString:@"\\t"]; break;
            default:
                if (c < 0x20 || c == 0x2028 || c == 0x2029) [out appendFormat:@"\\u%04x", c];
                else [out appendFormat:@"%C", c];
        }
    }
    [out appendString:@"\""];
}

- (NSString *)json {
    NSMutableString *j = [NSMutableString stringWithString:@"{\"v\":1,\"g\":"];
    appendString(j, _gid);
    [j appendString:@",\"n\":"]; appendString(j, _name);
    [j appendString:@",\"a\":"]; appendString(j, _admin);
    [j appendFormat:@",\"r\":%lld,\"m\":[", _revision];
    for (NSUInteger i = 0; i < _members.count; i++) {
        if (i) [j appendString:@","];
        appendString(j, _members[i]);
    }
    [j appendString:@"],\"nm\":{"];
    BOOL first = YES;
    for (NSString *pk in _members) {   // Reihenfolge wie m
        if (!_names[pk]) continue;
        if (!first) [j appendString:@","];
        first = NO;
        appendString(j, pk);
        [j appendString:@":"];
        appendString(j, _names[pk]);
    }
    [j appendFormat:@"},\"t\":%d,\"tm\":\"%@\"", _timer, _timerFromSent ? @"sent" : @"read"];
    if (_open) [j appendString:@",\"o\":1"];                                                // B10: nach "tm", vor "p"
    if (_picture.length) { [j appendString:@",\"p\":"]; appendString(j, _picture); }   // B7: nur mit Bild, als letztes
    [j appendString:@"}"];
    return j;
}

@end
