// Eingabeleiste im Chat: Kamera, Textfeld und ein Aktionsknopf, der je nach
// Zustand Senden (Text im Feld), Mikrofon (Feld leer) oder Stopp (Aufnahme läuft) ist.
// Während einer Aufnahme ersetzt eine Leiste mit Zeit und "abbrechen" das Feld.
#import <UIKit/UIKit.h>

@class MeshChatInputBar;

@protocol MeshChatInputBarDelegate <NSObject>
- (void)inputBarTappedCamera:(MeshChatInputBar *)bar;
- (void)inputBarHeldCamera:(MeshChatInputBar *)bar;       // langes Drücken: Mediathek
- (void)inputBarTappedAction:(MeshChatInputBar *)bar;     // Senden, Aufnahme starten oder beenden
- (void)inputBarHeldAction:(MeshChatInputBar *)bar;       // langes Drücken: Stimmeffekt wählen
- (void)inputBarCancelledRecording:(MeshChatInputBar *)bar;
@end

@interface MeshChatInputBar : UIView <UITextFieldDelegate>
+ (CGFloat)height;
@property (nonatomic, mesh_weak) id<MeshChatInputBarDelegate> delegate;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, readonly) BOOL hasText;             // ohne Leerraum
@property (nonatomic) BOOL recording;                     // Aufnahme-Leiste und Stopp-Knopf
@property (nonatomic) BOOL microphoneAvailable;           // sonst bei leerem Feld Senden statt Mikrofon
- (void)setRecordingText:(NSString *)text;
- (void)endEditing;
@end
