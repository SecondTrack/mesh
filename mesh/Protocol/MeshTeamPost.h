// Rundbrief des Mesh-Teams "an alle" (docs/TEAM_GROUPS_PROTOCOL.md, A2): content eines kind-1-Events
// {"v":1,"de":"<Text>","en":"<Text>"}. Nur Text: je höchstens 4000 Zeichen, kein \1mesh: darin,
// unsichtbare und Steuerzeichen außer \n entfernt, mindestens eine Sprache nicht leer.
// Absender, Tag und Zeit prüft MeshTeam.
#import <Foundation/Foundation.h>

enum { MeshTeamMaxText = 4000 };

@interface MeshTeamPost : NSObject
+ (instancetype)postFromObject:(id)object;   // aus MeshJSON; nil, wenn ungültig
@property (nonatomic, readonly) NSString *de, *en;   // gesäubert, @"" = fehlt
- (NSString *)textPreferringGerman:(BOOL)german;     // Gerätesprache, sonst die andere

// Säubern wie oben; nil, wenn der Text zu lang ist oder einen Marker enthält.
+ (NSString *)cleanText:(NSString *)raw;
@end
