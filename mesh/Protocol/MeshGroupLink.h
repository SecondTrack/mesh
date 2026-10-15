// Beitritts-Link einer offenen Gruppe (docs/TEAM_GROUPS_PROTOCOL.md, B10):
//
//   meshg:1:<gid 16 Hex>:<Admin-pk 64 Hex>:<k 32 Hex>
//
// Beim Lesen: Leerraum außen weg, Präfix ohne Groß/klein, Hex geprüft und klein gemacht. Alles andere = nil.
#import <Foundation/Foundation.h>

@interface MeshGroupLink : NSObject
+ (instancetype)parse:(NSString *)text;
+ (NSString *)linkWithGroup:(NSString *)gid admin:(NSString *)admin key:(NSString *)key;   // nil, wenn ein Teil ungültig ist
@property (nonatomic, readonly) NSString *gid, *admin, *key;
@property (nonatomic, readonly) NSString *text;   // in der erzeugten Form (klein)
@end
