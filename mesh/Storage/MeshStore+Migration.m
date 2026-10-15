#import "MeshStore+Internal.h"
#import "MeshPayload.h"
#import "MeshSeal.h"

// Spalte messages.kind enthält den MeshPayloadKind (0 Text, 1 Bild, 2 Sprache, 3 Datei, 4 Hinweis, 5 Kontakt).
// PRAGMA user_version: 2 = alle Felder enc2; 3 = zusätzlich Nachrichten an Richtung und Event-ID
// gebunden. Ab MeshSchemaSealed gilt nur noch enc2.
static const int MeshSchemaSealed = 3;

static NSString *messageContextV2(NSString *chat, int kind, int secs) {   // Schema 2, nur Migration
    return [NSString stringWithFormat:@"messages.content|%@|%d|%d", chat, kind, secs];
}

@implementation MeshStore (Migration)

- (BOOL)table:(const char *)table hasColumn:(const char *)column {
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%s)", table];
    sqlite3_stmt *st = [self prepare:sql.UTF8String];
    BOOL found = NO;
    while (!found && st && sqlite3_step(st) == SQLITE_ROW)
        found = strcmp((const char *)sqlite3_column_text(st, 1) ?: "", column) == 0;
    sqlite3_finalize(st);
    return found;
}

- (BOOL)createSchema {
    const char *schema =
        "CREATE TABLE IF NOT EXISTS identity(id INTEGER PRIMARY KEY CHECK(id=1), seckey TEXT);"
        "CREATE TABLE IF NOT EXISTS vault(id INTEGER PRIMARY KEY CHECK(id=1), salt BLOB, iv BLOB, ct BLOB, pubkey TEXT, iters INTEGER);"
        "CREATE TABLE IF NOT EXISTS contacts(pubkey TEXT PRIMARY KEY, name TEXT, verified INTEGER NOT NULL DEFAULT 0, pname TEXT, pic TEXT);"
        "CREATE TABLE IF NOT EXISTS profile(id INTEGER PRIMARY KEY CHECK(id=1), name TEXT, about TEXT, pic TEXT);"
        "CREATE TABLE IF NOT EXISTS messages("
        "  rowid INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  chat TEXT NOT NULL, from_me INTEGER NOT NULL,"
        "  content TEXT NOT NULL, ts INTEGER NOT NULL,"
        "  event_id TEXT UNIQUE, status INTEGER NOT NULL DEFAULT 0);"
        "CREATE INDEX IF NOT EXISTS idx_msg_chat ON messages(chat, ts);"
        "CREATE TABLE IF NOT EXISTS deleted(event_id TEXT PRIMARY KEY);"
        "CREATE TABLE IF NOT EXISTS blocked(pubkey TEXT PRIMARY KEY);"
        "CREATE TABLE IF NOT EXISTS outbox(event_id TEXT PRIMARY KEY, event TEXT NOT NULL, created INTEGER NOT NULL);"
        // Je Chat: Selbstlösch-Timer (Sekunden, Modus MeshTimerMode) und Zeitpunkt des letzten Leerens.
        "CREATE TABLE IF NOT EXISTS chats(chat TEXT PRIMARY KEY, timer INTEGER NOT NULL DEFAULT 0,"
        "  timer_mode INTEGER NOT NULL DEFAULT 0, cleared INTEGER NOT NULL DEFAULT 0);"
        // Signal: Sitzungen, PreKeys, bekannte Identitäten (Werte versiegelt, siehe MeshStore+Signal).
        "CREATE TABLE IF NOT EXISTS signal(key TEXT PRIMARY KEY, value TEXT NOT NULL);";
    if (sqlite3_exec(self.db, schema, NULL, NULL, NULL) != SQLITE_OK) return NO;
    // Spalten, die ältere Datenbanken noch nicht haben; fill läuft einmal direkt nach dem Anlegen.
    static const struct { const char *table, *column, *definition, *fill; } added[] = {
        { "contacts", "verified", "INTEGER NOT NULL DEFAULT 0" },
        { "contacts", "pname", "TEXT" },
        { "contacts", "pic", "TEXT" },
        { "messages", "status", "INTEGER NOT NULL DEFAULT 0" },
        { "vault", "peppered", "INTEGER NOT NULL DEFAULT 0" },   // = MeshVaultRecord.boundToDevice
        { "vault", "kdf", "INTEGER NOT NULL DEFAULT 0" },        // MeshVaultKDF
        // Bestehende Kontakte hat der Nutzer selbst angelegt oder angeschrieben → angenommen.
        { "contacts", "accepted", "INTEGER NOT NULL DEFAULT 1" },
        // Art und Länge der Nachricht unverschlüsselt, damit Listen ohne Medien-Daten auskommen.
        { "messages", "kind", "INTEGER NOT NULL DEFAULT 0" },
        { "messages", "secs", "INTEGER NOT NULL DEFAULT 0" },
        // Zeitstempel des übernommenen Profils, damit kein älteres wieder eingespielt wird.
        { "contacts", "pts", "INTEGER NOT NULL DEFAULT 0" },
        // Größe des Klartexts in Byte, damit die Grenzen für Fremde nicht jeden Inhalt lesen müssen.
        // Für alte Zeilen aus der versiegelten Länge geschätzt.
        { "messages", "bytes", "INTEGER NOT NULL DEFAULT 0", "UPDATE messages SET bytes = length(content) * 3 / 4" },
        // Bildmaße wie Art und Länge unverschlüsselt: Zeilenhöhen ohne das Bild zu entschlüsseln.
        { "messages", "width", "INTEGER NOT NULL DEFAULT 0", NULL },
        { "messages", "height", "INTEGER NOT NULL DEFAULT 0", NULL },
        // Format der Android-App: Nachrichten-ID des Absenders und zitierte Nachricht (zufällige IDs,
        // unverschlüsselt für die Suche), Reaktionen (verschlüsselt), Selbstlöschen.
        { "messages", "cmid", "TEXT", NULL },
        { "messages", "reply_to", "TEXT", NULL },
        { "messages", "react_mine", "TEXT", NULL },
        { "messages", "react_peer", "TEXT", NULL },
        { "messages", "timer", "INTEGER NOT NULL DEFAULT 0", NULL },
        { "messages", "expires", "INTEGER NOT NULL DEFAULT 0", NULL },
        // Signal-Bundle des Kontakts (aus QR-Code oder Nachricht), versiegelt.
        { "contacts", "bundle", "TEXT", NULL },
        // "Über mich" aus dem kind-0-Profil des Kontakts, versiegelt.
        { "contacts", "about", "TEXT", NULL },
        // Bis wann der Chat gelesen ist (Unix-Sekunden): Trennlinie "Neue Nachrichten".
        { "chats", "read", "INTEGER NOT NULL DEFAULT 0", NULL },
    };
    for (size_t i = 0; i < sizeof(added) / sizeof(added[0]); i++) {
        if ([self table:added[i].table hasColumn:added[i].column]) continue;
        NSString *sql = [NSString stringWithFormat:@"ALTER TABLE %s ADD COLUMN %s %s",
                         added[i].table, added[i].column, added[i].definition];
        if (sqlite3_exec(self.db, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK && added[i].fill)
            sqlite3_exec(self.db, added[i].fill, NULL, NULL, NULL);
    }
    sqlite3_exec(self.db, "CREATE INDEX IF NOT EXISTS idx_msg_cmid ON messages(chat, cmid);"
                          "CREATE INDEX IF NOT EXISTS idx_msg_expires ON messages(expires);", NULL, NULL, NULL);
    sqlite3_stmt *v = [self prepare:"PRAGMA user_version"];
    self.migrated = v && sqlite3_step(v) == SQLITE_ROW && sqlite3_column_int(v, 0) >= MeshSchemaSealed;
    sqlite3_finalize(v);
    return YES;
}

// Ältere Werte (Klartext, enc1, enc2 aus Schema 2) ins aktuelle Format überführen. Als erledigt
// gilt die Migration nach erfolgreichem COMMIT; danach räumt VACUUM frei gewordene Seiten auf.
- (void)migrateSeals {
    if (self.migrated) return;
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK;

    sqlite3_stmt *sel = [self prepare:"SELECT rowid, chat, content, kind, secs, from_me, event_id FROM messages"];
    sqlite3_stmt *upd = [self prepare:"UPDATE messages SET content=?, kind=?, secs=? WHERE rowid=?"];
    ok = ok && sel && upd;
    while (ok && sqlite3_step(sel) == SQLITE_ROW) {
        NSString *chat = columnText(sel, 1), *stored = columnText(sel, 2), *eventId = columnText(sel, 6);
        NSString *plain = [MeshSeal isSealed:stored]
            ? [self open:stored context:messageContextV2(chat, sqlite3_column_int(sel, 3), sqlite3_column_int(sel, 4))]
            : [self legacyPlain:stored];
        if (!plain) continue;   // manipuliert oder bereits aktuell (enc2 aus Schema 3 öffnet mit V2 nicht)
        MeshPayload *p = [MeshPayload parse:plain];
        NSString *sealed = [self seal:plain context:messageContext(chat, (int)p.kind, p.seconds, sqlite3_column_int(sel, 5) != 0, eventId)];
        bindText(upd, 1, sealed);
        sqlite3_bind_int(upd, 2, (int)p.kind);
        sqlite3_bind_int(upd, 3, p.seconds);
        sqlite3_bind_int64(upd, 4, sqlite3_column_int64(sel, 0));
        ok = sealed && sqlite3_step(upd) == SQLITE_DONE;
        sqlite3_reset(upd);
    }
    sqlite3_finalize(sel); sqlite3_finalize(upd);

    const char *contactColumns[] = { "name", "pname", "pic" }, *profileColumns[] = { "name", "about", "pic" };
    for (int table = 0; table < 2 && ok; table++) {
        for (int c = 0; c < 3 && ok; c++) {
            const char *col = table == 0 ? contactColumns[c] : profileColumns[c];
            NSString *q = table == 0
                ? [NSString stringWithFormat:@"SELECT rowid, pubkey, %s FROM contacts WHERE %s != '' AND substr(%s,1,5) != 'enc2:'", col, col, col]
                : [NSString stringWithFormat:@"SELECT rowid, '', %s FROM profile WHERE %s != '' AND substr(%s,1,5) != 'enc2:'", col, col, col];
            NSString *u = [NSString stringWithFormat:@"UPDATE %@ SET %s=? WHERE rowid=?", table == 0 ? @"contacts" : @"profile", col];
            sel = [self prepare:q.UTF8String]; upd = [self prepare:u.UTF8String];
            ok = sel && upd;
            while (ok && sqlite3_step(sel) == SQLITE_ROW) {
                NSString *context = table == 0 ? contactContext(col, columnText(sel, 1)) : profileContext(col);
                NSString *sealed = [self seal:[self legacyPlain:columnText(sel, 2)] context:context];
                bindText(upd, 1, sealed);
                sqlite3_bind_int64(upd, 2, sqlite3_column_int64(sel, 0));
                ok = sealed && sqlite3_step(upd) == SQLITE_DONE;
                sqlite3_reset(upd);
            }
            sqlite3_finalize(sel); sqlite3_finalize(upd);
        }
    }

    if (!ok) { sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL); return; }
    char sql[48]; snprintf(sql, sizeof(sql), "PRAGMA user_version = %d", MeshSchemaSealed);
    ok = sqlite3_exec(self.db, sql, NULL, NULL, NULL) == SQLITE_OK;   // in derselben Transaktion
    if (!ok || sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK) { sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL); return; }
    self.migrated = YES;
    sqlite3_exec(self.db, "VACUUM", NULL, NULL, NULL);   // Altes aus freien Seiten entfernen (bestmöglich)
}

@end
