// Ereignisse, mit denen Domäne und Transport die UI informieren.
// Liegt in Support/, damit jede Schicht sie nutzen kann, ohne die Session zu importieren.
#import <Foundation/Foundation.h>

extern NSString *const MeshMessagesChangedNotification;     // Chatliste/Chat neu laden
extern NSString *const MeshConnectionChangedNotification;   // ein Relay hat (ent)verbunden
extern NSString *const MeshTransportChangedNotification;    // Tor-Zustand geändert (nur für den Transport)
extern NSString *const MeshProfilesChangedNotification;     // Profil/Avatar eines Kontakts oder des Nutzers geändert
extern NSString *const MeshWillLockNotification;
extern NSString *const MeshWipedNotification;
extern NSString *const MeshIdentityChangedNotification;    // andere eigene Identität angezeigt
// Neue Nachricht außerhalb des offenen Chats. userInfo: MeshIncomingName, MeshIncomingPreview;
// gesperrt (Hintergrund) ohne userInfo: Absender und Inhalt sind dann nicht lesbar.
extern NSString *const MeshIncomingMessageNotification;
extern NSString *const MeshIncomingName, *const MeshIncomingPreview, *const MeshIncomingKind;              // Notlöschung: alles weg, zurück zur Einrichtung           // vor dem Sperren: alles mit entschlüsselten Daten schließen

