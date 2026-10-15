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

// Gruppennamen, Mitgliedsnamen, Beitrittsname (Protokoll B8.6, gleich wie Android): alle Zeichen der
// Kategorien Cc und Cf entfernen außer U+200D (ZWJ), dann Leerzeichen am Anfang und Ende; Folgen von
// Leerzeichen innen bleiben. Kein Zusammenfassen wie MeshCleanName.
NSString *MeshCleanGroupText(NSString *raw);

// Auf höchstens max UTF-16-Einheiten kürzen, ohne ein Surrogatpaar zu zerschneiden (B8.6).
NSString *MeshTruncateUTF16(NSString *s, NSUInteger max);
