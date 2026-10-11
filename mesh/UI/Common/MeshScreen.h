// Gemeinsamer Anfang jedes Bildschirms: volle Höhe (Statusleiste ist ausgeblendet), eigene
// Wurzel-View im Mesh-Hintergrund. Dazu für jede Seite:
//  - Antippen außerhalb eines Eingabefelds schließt die Tastatur (Knöpfe, Listen bleiben bedienbar).
//  - Läge das aktive Feld unter der Tastatur, scrollt sein Scrollbereich es sichtbar; ohne
//    Scrollbereich rückt die Seite so weit hoch wie nötig.
#import <UIKit/UIKit.h>

@interface UIViewController (MeshScreen)
- (void)mesh_loadScreen;                         // in loadView als Erstes aufrufen
- (void)mesh_setAvoidsKeyboard:(BOOL)avoids;     // NO: die Seite rückt Felder selbst (Chat-Eingabeleiste)
@end
