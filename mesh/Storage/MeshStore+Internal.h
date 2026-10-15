// sqlite-Zugang für die Teile von MeshStore, die in eigenen Dateien liegen (MeshStore+Vault,
// MeshStore+Outbox, MeshStore+Migration). Nur dort importieren (tests/layers_check.sh prüft das).
#import "MeshStore.h"
#import <sqlite3.h>

@interface MeshStore ()
@property (nonatomic) BOOL migrated;   // user_version ≥ MeshSchemaSealed: nur noch enc2 gilt
@end

@interface MeshStore (Internal)
- (sqlite3 *)db;
- (sqlite3_stmt *)prepare:(const char *)sql;
- (BOOL)exists:(const char *)sql text:(NSString *)arg;   // mindestens eine Zeile?
- (BOOL)run:(const char *)sql text:(NSString *)arg;      // ohne Ergebniszeilen
- (NSString *)seal:(NSString *)plain context:(NSString *)context;     // nil ohne Datenschlüssel
- (NSString *)open:(NSString *)stored context:(NSString *)context;    // nach der Migration nur enc2
- (NSString *)legacyPlain:(NSString *)value;                         // enc1 oder Klartext älterer Versionen
@end

@interface MeshStore (Migration)
- (BOOL)createSchema;    // Tabellen anlegen, ältere Schemata ergänzen, migrated aus user_version
- (void)migrateSeals;    // einmalig beim ersten Entsperren: alles auf enc2 mit Kontext
- (long long)metaValue:(const char *)key;                 // Tabelle meta, 0 = nicht gesetzt
- (BOOL)setMeta:(const char *)key value:(long long)value;
- (BOOL)finishMediaMove;                                  // Indizes anlegen, Umzug als erledigt merken
@end

static inline void bindText(sqlite3_stmt *st, int i, NSString *s) {
    if (s) sqlite3_bind_text(st, i, s.UTF8String, -1, SQLITE_TRANSIENT);
    else   sqlite3_bind_null(st, i);
}

static inline NSString *columnText(sqlite3_stmt *st, int i) {
    const unsigned char *t = sqlite3_column_text(st, i);
    return t ? [NSString stringWithUTF8String:(const char *)t] : nil;
}

static inline NSData *columnBlob(sqlite3_stmt *st, int i) {
    return [NSData dataWithBytes:sqlite3_column_blob(st, i) length:sqlite3_column_bytes(st, i)];
}

// Kontext für MeshSeal: an welche Stelle ein verschlüsselter Wert gehört.
static inline NSString *contactContext(const char *column, NSString *pubkey) {
    return [NSString stringWithFormat:@"contacts.%s|%@", column, pubkey];
}

static inline NSString *profileContext(const char *column) {
    return [NSString stringWithFormat:@"profile.%s", column];
}

// Nachrichten: Chat, Art, Länge, Richtung und Event-ID, sonst ließen sich Inhalte innerhalb eines
// Chats vertauschen oder gesendet/empfangen umdrehen.
static inline NSString *messageContext(NSString *chat, int kind, int secs, BOOL fromMe, NSString *eventId) {
    return [NSString stringWithFormat:@"messages.content|%@|%d|%d|%d|%@", chat, kind, secs, fromMe ? 1 : 0, eventId ?: @""];
}

// Reaktionen hängen an der Zeile: eine Reaktion lässt sich nicht auf eine andere Nachricht umhängen.
static inline NSString *reactionContext(NSString *chat, long long rowId, BOOL mine) {
    return [NSString stringWithFormat:@"messages.react_%@|%@|%lld", mine ? @"mine" : @"peer", chat, rowId];
}
