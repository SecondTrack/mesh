// Eine Chat-Zeile: Text-, Bild- oder Sprachnachricht als Sprechblase mit Status-Haken,
// optional mit Zitat darüber (Antwort) und Reaktionen am unteren Rand.
#import <UIKit/UIKit.h>
#import "MeshMessage.h"

@interface MeshBubbleCell : UITableViewCell
// Vor setText:/setImage:/setVoice: setzen; nil entfernt.
- (void)setQuoteAuthor:(NSString *)author text:(NSString *)text;
- (void)setReactions:(NSString *)reactions;   // z.B. "👍❤️"
+ (CGFloat)extraHeightWithQuote:(BOOL)quote reactions:(BOOL)reactions;

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
- (void)setVoiceProgress:(CGFloat)progress;              // 0…1 abgespielt

+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width;
+ (CGFloat)heightForImageOfSize:(CGSize)size width:(CGFloat)width;
+ (CGFloat)heightForVoice;
+ (CGFloat)heightForFile;
+ (CGFloat)heightForVideo;
+ (CGFloat)heightForContactCardWithAction:(BOOL)action;
@end
