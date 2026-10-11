// Lauscht im gesperrten Zustand auf neue DMs an die eigenen Pubkeys (stehen öffentlich im Vault).
// Entschlüsselt nichts: meldet nur, dass etwas da ist ("Neue Nachricht", ohne Absender und Inhalt,
// wie Androids Sperrbildschirm-Version), und erkennt das Token der Notlöschung (["mw", …]), das
// ohne Schlüssel prüfbar ist. Läuft im VoIP-Hintergrundmodus weiter.
#import <Foundation/Foundation.h>
@class MeshPanic, MeshInboxWatcher;

@protocol MeshInboxWatcherDelegate <NSObject>
- (void)watcherSawNewMessage:(MeshInboxWatcher *)watcher;
- (void)watcherSawPanic:(MeshInboxWatcher *)watcher;
@end

@interface MeshInboxWatcher : NSObject
- (instancetype)initWithPubkeys:(NSArray *)pubkeys relays:(NSArray *)urls panic:(MeshPanic *)panic;
@property (nonatomic, mesh_weak) id<MeshInboxWatcherDelegate> delegate;
- (void)start;
- (void)stop;
- (void)keepAlive;   // im VoIP-Weckruf: Getrenntes neu verbinden
@end
