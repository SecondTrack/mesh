// Dialoge im Mesh-Design (dunkel, Mint-Akzent) als Ersatz für die grauen
// iOS-UIAlertView/UIActionSheet. Block-basiert, hält sich selbst am Leben bis zum Schließen.
#import <UIKit/UIKit.h>

@interface MeshPopup : NSObject

// Einfacher Hinweis mit OK.
+ (void)info:(NSString *)message;
+ (void)dismissAll;   // läuft auch automatisch bei MeshWillLockNotification

// Bestätigung (Abbrechen + eine Aktion). destructive = rote Aktion.
+ (void)confirm:(NSString *)title message:(NSString *)message
         action:(NSString *)actionTitle destructive:(BOOL)destructive
        handler:(void(^)(BOOL confirmed))handler;

// Auswahl-Sheet (Liste). handler bekommt den Index (-1 = Abbrechen).
+ (void)sheet:(NSString *)title options:(NSArray *)options
 destructiveIndex:(NSInteger)destructiveIndex
      handler:(void(^)(NSInteger index))handler;

// Auswahl-Sheet mit einer Reihe Emojis darüber (Reaktionen). Einträge ab destructiveFrom sind rot.
// handler: Index des Eintrags (-1 = Abbrechen) oder das gewählte Emoji (Index -1).
+ (void)sheet:(NSString *)title emojis:(NSArray *)emojis options:(NSArray *)options
 destructiveFrom:(NSInteger)destructiveFrom
      handler:(void(^)(NSInteger index, NSString *emoji))handler;

// Texteingabe (z.B. PIN). handler: text + ob OK gedrückt wurde.
+ (void)input:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder
       secure:(BOOL)secure numeric:(BOOL)numeric
      handler:(void(^)(NSString *text, BOOL ok))handler;

@end
