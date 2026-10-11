// Textfunktionen für Eingaben von außen.
#import <Foundation/Foundation.h>

// Steuer- und Schreibrichtungszeichen entfernen (damit lässt sich Text optisch umdrehen oder
// verstecken), Leerraum zu einzelnen Leerzeichen zusammenfassen.
NSString *MeshCleanName(NSString *raw);

// Nur Steuer- und Schreibrichtungszeichen entfernen, Zeilen bleiben (Nachrichtentext).
NSString *MeshStripInvisible(NSString *raw);

// Auf höchstens max Zeichen kürzen, ohne ein Emoji oder Kombinationszeichen zu zerschneiden
// (ein halbes Surrogatpaar lässt sich nicht mehr als UTF-8 kodieren).
NSString *MeshTruncate(NSString *s, NSUInteger max);
