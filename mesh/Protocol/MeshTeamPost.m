#import "MeshTeamPost.h"
#import "MeshText.h"

@implementation MeshTeamPost

+ (NSString *)cleanText:(NSString *)raw {
    if (![raw isKindOfClass:[NSString class]] || raw.length > MeshTeamMaxText) return nil;
    if ([raw rangeOfString:@"\1mesh:"].location != NSNotFound) return nil;   // nie Marker auswerten
    NSString *s = MeshStripInvisible(raw);
    NSCharacterSet *drop = [NSCharacterSet characterSetWithCharactersInString:@"\t\r\v\f"];
    s = [[s componentsSeparatedByCharactersInSet:drop] componentsJoinedByString:@""];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (instancetype)postFromObject:(id)o {
    if (![o isKindOfClass:[NSDictionary class]]) return nil;
    id v = o[@"v"];
    if (![v isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID() || [v doubleValue] != 1) return nil;
    NSString *de = @"", *en = @"";
    if (o[@"de"] && !(de = [self cleanText:o[@"de"]])) return nil;
    if (o[@"en"] && !(en = [self cleanText:o[@"en"]])) return nil;
    if (!de.length && !en.length) return nil;
    MeshTeamPost *p = [[self alloc] init];
    p->_de = de;
    p->_en = en;
    return p;
}

- (NSString *)textPreferringGerman:(BOOL)german {
    NSString *first = german ? _de : _en, *other = german ? _en : _de;
    return first.length ? first : other;
}

@end
