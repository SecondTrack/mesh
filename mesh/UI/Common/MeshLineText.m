#import "MeshLineText.h"
#import "MeshKeyboardLayout.h"
#import "MeshText.h"

static const NSUInteger kMaxLength = 10000;   // weit über der Nachrichtengrenze, schützt das Zeichnen (A4)

@implementation MeshLineText

- (instancetype)init {
    if ((self = [super init])) _text = @"";
    return self;
}

+ (NSUInteger)maxLength { return kMaxLength; }

- (void)setText:(NSString *)text {
    _text = [[[self class] singleLine:text ?: @""] copy];
    _allSelected = NO;
}

- (void)setAllSelected:(BOOL)all { _allSelected = all && _text.length; }

- (NSRange)selectedRange { return _allSelected ? NSMakeRange(0, _text.length) : NSMakeRange(_text.length, 0); }

- (BOOL)insert:(NSString *)s {
    s = [[self class] singleLine:s];
    if (!s.length) return NO;
    NSString *base = _allSelected ? @"" : _text;
    s = MeshTruncate(s, kMaxLength > base.length ? kMaxLength - base.length : 0);
    if (!s.length || ![self allow:self.selectedRange with:s]) return NO;
    _text = [base stringByAppendingString:s];
    _allSelected = NO;
    return YES;
}

- (BOOL)allow:(NSRange)range with:(NSString *)s {
    if (!_shouldChange) return YES;
    NSString *before = _text;
    BOOL ok = _shouldChange(range, s);
    return ok && _text == before;   // hat der Block selbst Text gesetzt, gilt dessen Stand
}

- (BOOL)deleteBackward {
    if (_allSelected) {
        if (!_text.length || ![self allow:self.selectedRange with:@""]) return NO;
        _text = @""; _allSelected = NO;
        return YES;
    }
    NSRange r = [MeshKeyboardLayout deleteRangeIn:_text cursor:_text.length];
    if (!r.length || ![self allow:r with:@""]) return NO;
    _text = [_text substringToIndex:r.location];
    return YES;
}

- (BOOL)paste:(NSString *)raw {
    NSString *base = _allSelected ? @"" : _text;
    NSString *s = [[self class] pasteText:raw max:kMaxLength > base.length ? kMaxLength - base.length : 0];
    return [self insert:s];
}

// Zeilen- und Absatztrenner, Tabs (NEL U+0085, LS U+2028, PS U+2029)
static NSCharacterSet *breaks(void) {
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *s = [NSMutableCharacterSet characterSetWithCharactersInString:@"\r\n\t\v\f"];
        [s addCharactersInRange:NSMakeRange(0x85, 1)];
        [s addCharactersInRange:NSMakeRange(0x2028, 2)];
        set = s;
    });
    return set;
}

+ (NSString *)singleLine:(NSString *)raw {
    if (!raw.length) return @"";
    if ([raw rangeOfCharacterFromSet:breaks()].location == NSNotFound) return raw;
    NSString *s = [raw stringByReplacingOccurrencesOfString:@"\r\n" withString:@" "];
    return [[s componentsSeparatedByCharactersInSet:breaks()] componentsJoinedByString:@" "];
}

// Wie MeshStripInvisible, aber ZWJ/ZWNJ bleiben (sonst zerfallen Familien-, Berufs- und Flaggen-Emojis).
static NSCharacterSet *pasteDrop(void) {
    static NSCharacterSet *drop;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *s = [[NSCharacterSet controlCharacterSet] mutableCopy];
        [s formIntersectionWithCharacterSet:[breaks() invertedSet]];   // werden zu Leerzeichen
        [s removeCharactersInRange:NSMakeRange(0x200C, 2)];  // ZWNJ, ZWJ
        [s removeCharactersInRange:NSMakeRange(0xE0020, 0x60)];   // Tag-Folgen (Flaggen England, Schottland …)
        [s addCharactersInRange:NSMakeRange(0x200B, 1)];
        [s addCharactersInRange:NSMakeRange(0x200E, 2)];     // LRM, RLM
        [s addCharactersInRange:NSMakeRange(0x202A, 5)];     // LRE … RLO
        [s addCharactersInRange:NSMakeRange(0x2066, 4)];     // LRI … PDI
        [s addCharactersInRange:NSMakeRange(0xFEFF, 1)];
        drop = s;
    });
    return drop;
}

+ (NSString *)pasteText:(NSString *)raw max:(NSUInteger)max {
    if (![raw isKindOfClass:[NSString class]] || !raw.length) return @"";
    NSString *s = [[raw componentsSeparatedByCharactersInSet:pasteDrop()] componentsJoinedByString:@""];
    return MeshTruncate([self singleLine:s], max);
}

@end
