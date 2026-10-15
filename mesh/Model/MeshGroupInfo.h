// Was die Oberfläche über eine Gruppe wissen darf (MeshSession groupInfo:): Name, Admin,
// Mitglieder mit Anzeigenamen, offene Einladungen (nur beim Admin), eigener Stand.
#import <Foundation/Foundation.h>
#import "MeshChat.h"

@interface MeshGroupInfo : NSObject
@property (nonatomic, copy)   NSString *chat;          // "g:<gid>"
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *admin;         // Pubkey
@property (nonatomic, copy)   NSArray *members;        // Pubkeys, Admin zuerst
@property (nonatomic, copy)   NSDictionary *names;     // Pubkey -> Anzeigename (Kontaktname, sonst aus der Gruppe)
@property (nonatomic, copy)   NSArray *invited;        // Pubkeys mit offener Einladung (nur Admin)
@property (nonatomic, assign) MeshGroupStatus status;
@property (nonatomic, assign) BOOL amAdmin;
@property (nonatomic, assign) int timer;
@property (nonatomic, assign) BOOL timerFromSent;
@property (nonatomic, assign) BOOL hasPicture;         // Zustand trägt ein Gruppenbild (p, B7)
@property (nonatomic, assign) BOOL open;               // B10: jeder mit Link kann beitreten
@property (nonatomic, copy)   NSString *link;          // B10: Beitritts-Link (Admin oder Mitglied mit k), nil = keiner
@property (nonatomic, copy)   NSArray *proposals;      // B9, nur Admin: je @{id, from, candidate, text} (text = "<M> schlägt <C> vor")
@property (nonatomic, copy)   NSString *voucher;       // B9, Einladung: Name des Bürgen, wenn der Admin kein Kontakt ist
@property (nonatomic, copy)   NSString *adminLabel;    // Admin: Kontaktname bzw. "Name ~abcd"
- (BOOL)canWrite;                                      // Mitglied: Nachrichten gehen hinaus
@end
