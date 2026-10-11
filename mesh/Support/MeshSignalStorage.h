// Speicher für den Signal-Zustand (Sitzungen, PreKeys, Identitäten) als Schlüssel-Wert-Paare.
// Liegt in Support, weil Domain (MeshSignal) es nutzt und Storage (MeshStore+Signal) es erfüllt.
#import <Foundation/Foundation.h>

@protocol MeshSignalStorage <NSObject>
- (NSData *)signalValueForKey:(NSString *)key;
- (BOOL)setSignalValue:(NSData *)value forKey:(NSString *)key;   // nil = löschen; NO, wenn nicht gespeichert
@end
