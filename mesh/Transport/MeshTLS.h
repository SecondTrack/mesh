// Blockierender TLS-1.2/1.3-Client über mbedTLS (vendor/mbedtls).
// Der TLS-Stack von iOS 4–6 kann moderne Server nicht mehr erreichen; deshalb ein eigener im Binary.
// Prüft Zertifikatskette (Resources/cacert.pem) und Hostnamen.
//
// Alle Aufrufe blockieren, nur auf einem Hintergrund-Thread benutzen.
#import <Foundation/Foundation.h>

@interface MeshTLS : NSObject

// TCP + TLS-Handshake zu host:port. NO bei Fehler (errorOut = mbedTLS-Code als String).
- (BOOL)connectHost:(NSString *)host port:(int)port error:(NSString **)errorOut;

// Verschlüsselt senden. Anzahl geschriebener Bytes, <0 bei Fehler.
- (int)write:(NSData *)data;

// Bis zu maxLen entschlüsselte Bytes lesen (blockiert bis Daten/Close). nil bei Close/Fehler.
- (NSData *)readUpTo:(int)maxLen;

- (void)close;

@end
