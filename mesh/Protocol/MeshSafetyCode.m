#import "MeshSafetyCode.h"

static NSString *const kPrefix = @"meshsn:1:";

static BOOL allDigits(NSString *s) {
    return [s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound;
}

@implementation MeshSafetyCode

+ (NSString *)payloadFrom:(NSString *)me to:(NSString *)peer groups:(NSArray *)groups {
    return [NSString stringWithFormat:@"%@%@:%@:%@", kPrefix, me.lowercaseString, peer.lowercaseString, [groups componentsJoinedByString:@""]];
}

+ (MeshSafetyScan)check:(NSString *)scanned me:(NSString *)me peer:(NSString *)peer groups:(NSArray *)groups {
    NSString *t = [scanned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![t hasPrefix:kPrefix]) return MeshSafetyNotACode;
    NSArray *parts = [[t substringFromIndex:kPrefix.length] componentsSeparatedByString:@":"];
    if (parts.count != 3 || [parts[2] length] != 60 || !allDigits(parts[2])) return MeshSafetyNotACode;
    if ([parts[0] caseInsensitiveCompare:peer] != NSOrderedSame || [parts[1] caseInsensitiveCompare:me] != NSOrderedSame)
        return MeshSafetyOtherContact;
    NSString *mine = [groups componentsJoinedByString:@""];
    return mine.length == 60 && [parts[2] isEqualToString:mine] ? MeshSafetyMatch : MeshSafetyMismatch;
}

@end
