// Das eigene Profil: Name, Beschreibung, Bild.
// picture ist die gespeicherte Form des Bildes (Base64 oder data:-URI); anzeigen und erzeugen
// über MeshImageCodec.
#import <Foundation/Foundation.h>

@interface MeshProfile : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *about;
@property (nonatomic, copy) NSString *picture;
@end
