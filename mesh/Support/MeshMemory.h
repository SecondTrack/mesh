// Sensible Puffer (Schlüssel, Aufnahmen) überschreiben, bevor der Speicher freigegeben wird.
// Wirkt nur bei NSMutableData; unveränderliche Daten bleiben unberührt.
#import <Foundation/Foundation.h>

void MeshWipe(NSData *data);
void MeshWipeBytes(void *bytes, size_t length);
