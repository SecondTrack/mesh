// Diagnosezeilen nach Documents/mesh.log (per SSH lesbar, max. 256 KB) und NSLog.
// Nur in Debug-Builds; geloggt werden Zustände und Fehler, nie Nachrichteninhalte oder Schlüssel.
// make package baut ohne Log; nur FINALPACKAGE=0 schaltet es ein (siehe Makefile).
#import <Foundation/Foundation.h>

#ifdef DEBUG
void MeshLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
#else
#define MeshLog(...) do { } while (0)
#endif

// Löscht das Log samt Resten älterer Versionen (mesh.log.old/.prev). Release-Builds rufen das beim
// Start auf, damit nach einem Debug-Paket keine Metadaten liegen bleiben; Zurücksetzen immer.
void MeshLogRemove(void);
