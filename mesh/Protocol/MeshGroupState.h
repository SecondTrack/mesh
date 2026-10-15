// Zustand einer Gruppe (docs/TEAM_GROUPS_PROTOCOL.md, B1), wie er in Einladung und Zustand reist:
//
//   {"v":1,"g":"<gid>","n":"<Name>","a":"<admin pk>","r":<Revision>,"m":["<pk>",…],
//    "nm":{"<pk>":"<Anzeigename>",…},"t":<Timer s, 0=aus>,"tm":"read"|"sent"[,"o":1][,"p":"<16 Hex>"]}
//
// o (B10, offene Gruppe): nur geschrieben, wenn offen, direkt nach "tm" und vor "p". Gelesen werden nur
// die Zahlen 1 (offen) und 0 (geschlossen); alles andere (auch "o":1 mit m = []) macht den Zustand ungültig.
//
// p (B7, Gruppenbild): die ersten 16 Hex-Zeichen von SHA-256 über die rohen Bildbytes. Fehlt es oder
// ist es leer, hat die Gruppe kein Bild. Erzeugt wird es nur, wenn gesetzt, als letztes Feld
// (der B6-Prüfvektor ohne Bild bleibt byte-gleich); anderes als 16 Hex macht den Zustand ungültig.
//
// Lesen tolerant (unbekannte Felder egal), aber jedes Feld geprüft: gid 16 Hex, pks 64 Hex (klein
// gemacht), Name 1–50 UTF-16-Einheiten nach dem Säubern (B8.6, MeshCleanGroupText), Mitgliedsnamen
// über 40 werden verworfen, Mitglieder ohne Doppelte, mit dem Admin, höchstens 20 (leer nur als "aufgelöst"). Erzeugt wird kompakt in genau dieser Feldfolge (Prüfvektor B6).
// Wer das tragende Event signiert haben muss (a) und ob die Revision passt, prüft der Aufrufer.
#import <Foundation/Foundation.h>

enum { MeshGroupMaxMembers = 20, MeshGroupMaxName = 50, MeshGroupMaxMemberName = 40 };

@interface MeshGroupState : NSObject
// Aus dem gelesenen JSON-Objekt (MeshJSON); nil, wenn etwas nicht passt.
+ (instancetype)stateFromObject:(id)object;
// Neu (Ersteller): Revision 1, nur der Admin als Mitglied.
+ (instancetype)stateWithGroup:(NSString *)gid name:(NSString *)name admin:(NSString *)admin adminName:(NSString *)adminName;
// Platzhalter beim Beitritt per Link (B10): Revision 0, nur der Admin aus dem Link als Mitglied.
+ (instancetype)linkPlaceholder:(NSString *)gid name:(NSString *)name admin:(NSString *)admin;

@property (nonatomic, readonly) NSString *gid;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *admin;
@property (nonatomic, readonly) long long revision;
@property (nonatomic, readonly) NSArray *members;       // pks, Admin zuerst wie gesendet
@property (nonatomic, readonly) NSDictionary *names;    // pk -> Anzeigename (nur Mitglieder)
@property (nonatomic, readonly) int timer;              // Sekunden, 0 = aus
@property (nonatomic, readonly) BOOL timerFromSent;     // "sent" statt "read"
@property (nonatomic, readonly) BOOL dissolved;         // m = []
@property (nonatomic, readonly) NSString *picture;      // p: 16 Hex klein, nil = kein Bild
@property (nonatomic, readonly) BOOL open;              // o: jeder mit Link kann beitreten (B10)

- (BOOL)hasMember:(NSString *)pk;
- (NSString *)nameOf:(NSString *)pk;                    // @"" = keiner

// Nächste Revision mit Änderung (Admin). nil, wenn das Ergebnis ungültig wäre (z.B. 21 Mitglieder).
- (instancetype)withMember:(NSString *)pk name:(NSString *)name;
- (instancetype)withoutMember:(NSString *)pk;
- (instancetype)renamed:(NSString *)name;
- (instancetype)withTimer:(int)seconds fromSent:(BOOL)fromSent;
- (instancetype)dissolvedState;                         // m = [], nm = {}
- (instancetype)bumped;                                 // nur r+1 (B8.1: jede Einladung)
- (instancetype)withPicture:(NSString *)hash;           // p setzen (16 Hex) bzw. nil = entfernen
// B9: Admin übergeben (r+1, neues a muss in m stehen, nicht der bisherige). Schließt die Gruppe (B10: kein o).
- (instancetype)withAdmin:(NSString *)pk;
- (instancetype)withOpen:(BOOL)open;                    // B10: o setzen/entfernen (r+1)
// Ohne neue Revision: ein Mitglied hat verlassen (nur lokal, bis der Admin den Zustand schickt).
- (instancetype)locallyWithout:(NSString *)pk;

- (NSString *)json;   // kompakt, Feldfolge wie oben
+ (BOOL)isPubkey:(NSString *)pk;   // 64 Hex-Zeichen
+ (BOOL)isPictureHash:(NSString *)p;   // 16 Hex-Zeichen
+ (BOOL)isLinkKey:(NSString *)k;       // 32 Hex-Zeichen (B10: k, 16 Zufallsbytes)
+ (NSString *)cleanName:(NSString *)raw max:(NSUInteger)max;   // B8.6 gesäubert, auf max UTF-16 gekürzt
@end
