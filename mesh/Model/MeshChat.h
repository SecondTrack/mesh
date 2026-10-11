// Eine Zeile der Chatliste: Kontakt und letzte Nachricht.
#import <Foundation/Foundation.h>

@interface MeshChat : NSObject
@property (nonatomic, copy)   NSString *pubkey;        // hex x-only pubkey des Kontakts
@property (nonatomic, copy)   NSString *name;          // Anzeigename (setzt MeshSession)
@property (nonatomic, assign) BOOL      unknown;       // Kontakt nicht angenommen
@property (nonatomic, copy)   NSString *ownName;       // vom Nutzer vergeben (aus dem Store)
@property (nonatomic, copy)   NSString *profileName;   // aus dem kind-0-Profil (aus dem Store)
@property (nonatomic, assign) NSInteger lastKind;      // MeshPayloadKind der letzten Nachricht
@property (nonatomic, copy)   NSString *lastContent;   // Anfang der letzten Nachricht (bei Medien nur der Marker)
@property (nonatomic, assign) long long ts;            // Unix-Sekunden der letzten Nachricht
@property (nonatomic, assign) BOOL      fromMe;        // letzte Nachricht war von mir
@property (nonatomic, assign) int       identitySlot;  // zu welcher eigenen Identität der Chat gehört
@property (nonatomic, copy)   NSString *identityPubkey;
@end
