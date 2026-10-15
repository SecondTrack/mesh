// Eine Chat-Zeile: Text-, Bild- oder Sprachnachricht als Sprechblase mit Status-Haken,
// optional mit Zitat darüber (Antwort) und Reaktionen am unteren Rand.
#import <UIKit/UIKit.h>
#import "MeshMessage.h"

@interface MeshBubbleCell : UITableViewCell
// Vor setText:/setImage:/setVoice: setzen; nil entfernt.
- (void)setQuoteAuthor:(NSString *)author text:(NSString *)text;
@property (nonatomic, copy) void (^quoteTapped)(void);   // Zitat antippen: zur zitierten Nachricht springen
- (void)setReactions:(NSString *)reactions;   // z.B. "👍❤️"
+ (CGFloat)extraHeightWithQuote:(BOOL)quote reactions:(BOOL)reactions;
// Kleine Zeile über der Blase: Absender im Gruppenchat (in seiner Farbe), "an alle" im Team-Chat.
// Vor setText:/… setzen; nil entfernt. Ihre Höhe kommt über extraHeightWithQuote:reactions:header: dazu.
- (void)setHeader:(NSString *)text color:(UIColor *)color;
+ (CGFloat)extraHeightWithQuote:(BOOL)quote reactions:(BOOL)reactions header:(BOOL)header;
// Gruppenchat, eingehend: rundes Absenderbild (MeshAvatarMember) links neben der Blase; nil = keins.
// indent: Blase um die Bildspalte eingerückt (alle Blasen einer Folge bündig). Vor setText:/… setzen.
- (void)setSenderAvatar:(NSString *)pubkey indent:(BOOL)indent;

- (void)setText:(NSString *)text fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
- (void)setImage:(UIImage *)image fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
// image nil: leerer Rahmen in der Größe size, solange das Bild noch dekodiert wird
- (void)setImage:(UIImage *)image size:(CGSize)size fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
- (void)setVoice:(int)seconds seed:(NSString *)seed playing:(BOOL)playing fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
- (void)setFile:(NSString *)name detail:(NSString *)detail fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
// Video wie bei Android: Vorschaubild (nil = dunkle Fläche, solange es entsteht) mit rundem Play-Knopf.
- (void)setVideo:(UIImage *)thumb fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
// Geteilter Kontakt wie bei Android; action nil = keine Aktionszeile (eigene Karten).
- (void)setContactCard:(NSString *)name pubkey:(NSString *)pubkey action:(NSString *)action glyph:(NSString *)glyph
                fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
// Dasselbe mit eigener Unterzeile (z.B. Gruppen-Link, B10) statt "Geteilter Kontakt".
- (void)setCard:(NSString *)name subtitle:(NSString *)subtitle pubkey:(NSString *)pubkey action:(NSString *)action glyph:(NSString *)glyph
         fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width;
- (void)setVoiceProgress:(CGFloat)progress;              // 0…1 abgespielt

+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width;
+ (CGFloat)heightForImageOfSize:(CGSize)size width:(CGFloat)width;
+ (CGFloat)heightForVoice;
+ (CGFloat)heightForFile;
+ (CGFloat)heightForVideo;
+ (CGFloat)heightForContactCardWithAction:(BOOL)action;

// Für setImage:/setVideo: vorbereitet (im Hintergrund aufrufbar): auf Anzeigegröße gerechnet, Ecken
// gerundet auf die Blasenfarbe gemalt. Die Zelle zeigt Bilder nur in dieser Form richtig.
+ (UIImage *)photoForBubble:(UIImage *)image tableWidth:(CGFloat)width fromMe:(BOOL)fromMe scale:(CGFloat)scale;
+ (UIImage *)videoThumbForBubble:(UIImage *)thumb fromMe:(BOOL)fromMe scale:(CGFloat)scale;
@end
