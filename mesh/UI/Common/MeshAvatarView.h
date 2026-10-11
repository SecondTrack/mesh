// Runder Avatar: Profilbild, wenn es inline vorliegt, sonst eine neutrale Silhouette
// (MeshAvatarIdenticon: das Muster aus dem Pubkey, zum Unterscheiden eigener Identitäten).
// Zeichnet bei Profiländerungen automatisch neu.
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MeshAvatarSource) {
    MeshAvatarContact,     // Bild des Kontakts mit diesem Pubkey
    MeshAvatarSelf,        // eigenes Profilbild
    MeshAvatarIdenticon,   // immer nur das Identicon
    MeshAvatarPreview      // nur das gesetzte picture (Profil bearbeiten), sonst die Silhouette
};

@interface MeshAvatarView : UIView
- (instancetype)initWithFrame:(CGRect)frame source:(MeshAvatarSource)source;
@property (nonatomic, readonly) MeshAvatarSource source;
@property (nonatomic, copy) NSString *pubkey;
@property (nonatomic, copy) NSString *picture;   // gesetzt: dieses Bild statt des gespeicherten (Vorschau beim Bearbeiten)

// Runde Plakette unten rechts am Avatar (Kamera, Schlüssel): Akzentfläche mit Rand in
// Hintergrundfarbe. Nicht antippbar, bis ein Ziel gesetzt wird.
+ (UIButton *)badgeWithGlyph:(NSString *)glyph diameter:(CGFloat)diameter forAvatarFrame:(CGRect)avatar;

// Für die Vollbild-Ansicht: das Bild der Quelle in 512 × 512.
+ (UIImage *)largeImageForSource:(MeshAvatarSource)source pubkey:(NSString *)pubkey;   // ohne Bild die Silhouette
@end
