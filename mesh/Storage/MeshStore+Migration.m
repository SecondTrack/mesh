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
        "CREATE TABLE IF NOT EXISTS signal(key TEXT PRIMARY KEY, value TEXT NOT NULL);"
        // Inhalte von Bild, Sprache, Datei (versiegelt wie in messages.content, gleicher Kontext); rowid = messages.rowid.
        // Der Trigger löscht sie mit der Nachricht, in derselben Anweisung (alle Löschwege, auch Leeren und Ablauf).
        "CREATE TABLE IF NOT EXISTS message_blobs(rowid INTEGER PRIMARY KEY, content TEXT NOT NULL);"
        "CREATE TRIGGER IF NOT EXISTS messages_blob_delete AFTER DELETE ON messages "
        "  BEGIN DELETE FROM message_blobs WHERE rowid=old.rowid; END;"
        // Stand einmaliger Umstellungen (moveMediaStep).
        "CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL);"
        // Gruppen (ab 0.1.27): Zustand-JSON versiegelt, eigener Stand (MeshGroupStatus), wer eingeladen hat.
        "CREATE TABLE IF NOT EXISTS groups(gid TEXT PRIMARY KEY, status INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL,"
        "  inviter TEXT, created INTEGER NOT NULL DEFAULT 0);"
        // Offene Einladungen des Admins (nach 30 Tagen vergessen).
        "CREATE TABLE IF NOT EXISTS group_invites(gid TEXT NOT NULL, pubkey TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY(gid, pubkey));"
        // Team-Chat: Einweg-Schlüssel E (versiegelt), Rundbriefe bis (since), erster Start, Schalter.
        "CREATE TABLE IF NOT EXISTS team(id INTEGER PRIMARY KEY CHECK(id=1), ekey TEXT, used INTEGER NOT NULL DEFAULT 0,"
        "  since INTEGER NOT NULL DEFAULT 0, started INTEGER NOT NULL DEFAULT 0, hidden INTEGER NOT NULL DEFAULT 0,"
        "  muted INTEGER NOT NULL DEFAULT 0);"
        // Warteschlange der anonymen Verbindung: nie über die der echten Identität (outbox) senden.
        "CREATE TABLE IF NOT EXISTS team_outbox(event_id TEXT PRIMARY KEY, event TEXT NOT NULL, created INTEGER NOT NULL);"
        // Gruppen-Fan-out (ab 0.1.30): jede Kopie einer Gruppennachricht (Event-ID je Mitglied) -> Nachricht.
        "CREATE TABLE IF NOT EXISTS fanout(event_id TEXT PRIMARY KEY, message_rowid INTEGER NOT NULL);"
        "CREATE INDEX IF NOT EXISTS idx_fanout_msg ON fanout(message_rowid);"
        // Einladungen von noch nicht angenommenen Absendern (B8.5): versiegelt, höchstens 30 Tage / 20 Stück.
        "CREATE TABLE IF NOT EXISTS held_invites(id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, data TEXT NOT NULL);"
        // B9/B10 (ab 0.1.33): Vorschläge (Admin), Bürgschaften, Link-Beitritte und Entfernte je Stunde/Tag (Admin),
        // aufgeschobene Sendungen (gl erst nach Zustellung der Übergabe). data versiegelt an Art und gid.
        "CREATE TABLE IF NOT EXISTS group_records(id INTEGER PRIMARY KEY AUTOINCREMENT, kind INTEGER NOT NULL, gid TEXT,"
        "  at INTEGER NOT NULL, data TEXT NOT NULL);"
        "CREATE INDEX IF NOT EXISTS idx_group_records ON group_records(kind, gid, at);"
        // Gelöschte Nachricht (jeder Weg: einzeln, Leeren, Ablauf, Gruppe/Kontakt löschen): ihr Event und alle
        // Fan-out-Kopien verlassen die Warteschlangen, auch die anonyme des Team-Chats. Nichts geht mehr hinaus.
        "CREATE TRIGGER IF NOT EXISTS messages_outbox_delete AFTER DELETE ON messages BEGIN "
        "  DELETE FROM outbox WHERE event_id=old.event_id;"
        "  DELETE FROM team_outbox WHERE event_id=old.event_id;"
        "  DELETE FROM outbox WHERE event_id IN (SELECT event_id FROM fanout WHERE message_rowid=old.rowid);"
        "  DELETE FROM fanout WHERE message_rowid=old.rowid; END;";
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
        // Absender in Gruppen bzw. Rundbrief/Begrüßung im Team-Chat (MeshMessage.sender); alte Zeilen NULL.
        { "messages", "sender", "TEXT", NULL },
        // Gruppenbild (B7): Base64 der Bildbytes, versiegelt an die gid; NULL = keins.
        { "groups", "pic", "TEXT", NULL },
        // B10: Link-Geheimnis k (versiegelt an die gid; Admin, bei Mitgliedern aus gk) und Beginn eines Link-Beitritts.
        { "groups", "lkey", "TEXT", NULL },
        { "groups", "link_at", "INTEGER NOT NULL DEFAULT 0", NULL },
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
    // Neue oder leere Datenbank: nichts umzuziehen, die Indizes gleich anlegen
    sqlite3_stmt *any = [self prepare:"SELECT 1 FROM messages LIMIT 1"];
    BOOL empty = any && sqlite3_step(any) != SQLITE_ROW;
    sqlite3_finalize(any);
    if (empty && ![self metaValue:"media_moved"]) [self finishMediaMove];
    sqlite3_stmt *v = [self prepare:"PRAGMA user_version"];
    self.migrated = v && sqlite3_step(v) == SQLITE_ROW && sqlite3_column_int(v, 0) >= MeshSchemaSealed;
    sqlite3_finalize(v);
    self.metaSealed = [self metaValue:"meta_sealed"] != 0;
    return YES;
}

#pragma mark - Medien in message_blobs

- (long long)metaValue:(const char *)key {
    sqlite3_stmt *st = [self prepare:"SELECT value FROM meta WHERE key=?"];
    if (!st) return 0;
    sqlite3_bind_text(st, 1, key, -1, SQLITE_STATIC);
    long long v = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return v;
}

- (BOOL)setMeta:(const char *)key value:(long long)value {
    sqlite3_stmt *st = [self prepare:"INSERT OR REPLACE INTO meta(key, value) VALUES(?,?)"];
    if (!st) return NO;
    sqlite3_bind_text(st, 1, key, -1, SQLITE_STATIC);
    sqlite3_bind_int64(st, 2, value);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

// Abschluss: Indizes über Spalten hinter content bzw. pic. Erst jetzt und nicht beim Öffnen, weil
// das Anlegen jede Medienzeile ganz lesen müsste (am A4 beim Start zu lang). Eine Transaktion.
- (BOOL)finishMediaMove {
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK
        && sqlite3_exec(self.db, "CREATE INDEX IF NOT EXISTS idx_msg_timers ON messages(chat, from_me, expires, timer);"   // startTimersInChat
                                 "CREATE INDEX IF NOT EXISTS idx_msg_media ON messages(chat, kind, width, from_me);"        // Galerie zählen
                                 // isAccepted und Chatliste lesen accepted aus dem Index statt hinter dem Profilbild
                                 "CREATE INDEX IF NOT EXISTS idx_contacts_accepted ON contacts(pubkey, accepted);",
                        NULL, NULL, NULL) == SQLITE_OK
        && [self setMeta:"media_moved" value:1];
    if (ok && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return YES;
    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
    return NO;
}

#pragma mark - Versiegeln

// Ältere Werte (Klartext, enc1, enc2 aus Schema 2) ins aktuelle Format überführen. Als erledigt
// gilt die Migration nach erfolgreichem COMMIT; danach räumt VACUUM frei gewordene Seiten auf.
- (void)migrateSeals {
    if (self.migrated) return;
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK;

    // Medien können schon in message_blobs liegen (neu eingefügt oder umgezogen): dort neu versiegeln.
    sqlite3_stmt *sel = [self prepare:"SELECT m.rowid, m.chat, COALESCE(b.content, m.content), m.kind, m.secs, m.from_me, m.event_id, "
                                      "b.rowid IS NOT NULL FROM messages m LEFT JOIN message_blobs b ON b.rowid=m.rowid"];
    sqlite3_stmt *upd = [self prepare:"UPDATE messages SET content=?, kind=?, secs=? WHERE rowid=?"];
    sqlite3_stmt *updMeta = [self prepare:"UPDATE messages SET kind=?2, secs=?3 WHERE rowid=?4"];
    sqlite3_stmt *updBlob = [self prepare:"UPDATE message_blobs SET content=?1 WHERE rowid=?4"];
    ok = ok && sel && upd && updMeta && updBlob;
    while (ok && sqlite3_step(sel) == SQLITE_ROW) {
        NSString *chat = columnText(sel, 1), *stored = columnText(sel, 2), *eventId = columnText(sel, 6);
        NSString *plain = [MeshSeal isSealed:stored]
            ? [self open:stored context:messageContextV2(chat, sqlite3_column_int(sel, 3), sqlite3_column_int(sel, 4))]
            : [self legacyPlain:stored];
        if (!plain) continue;   // manipuliert oder bereits aktuell (enc2 aus Schema 3 öffnet mit V2 nicht)
        MeshPayload *p = [MeshPayload parse:plain];
        NSString *sealed = [self seal:plain context:messageContext(chat, (int)p.kind, p.seconds, sqlite3_column_int(sel, 5) != 0, eventId, nil)];
        long long rowId = sqlite3_column_int64(sel, 0);
        if (sqlite3_column_int(sel, 7)) {   // Inhalt in message_blobs, Art und Länge in messages
            bindText(updBlob, 1, sealed);
            sqlite3_bind_int64(updBlob, 4, rowId);
            sqlite3_bind_int(updMeta, 2, (int)p.kind);
            sqlite3_bind_int(updMeta, 3, p.seconds);
            sqlite3_bind_int64(updMeta, 4, rowId);
            ok = sealed && sqlite3_step(updBlob) == SQLITE_DONE && sqlite3_step(updMeta) == SQLITE_DONE;
            sqlite3_reset(updBlob); sqlite3_reset(updMeta);
            continue;
        }
        bindText(upd, 1, sealed);
        sqlite3_bind_int(upd, 2, (int)p.kind);
        sqlite3_bind_int(upd, 3, p.seconds);
        sqlite3_bind_int64(upd, 4, rowId);
        ok = sealed && sqlite3_step(upd) == SQLITE_DONE;
        sqlite3_reset(upd);
    }
    sqlite3_finalize(sel); sqlite3_finalize(upd); sqlite3_finalize(updMeta); sqlite3_finalize(updBlob);

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

#pragma mark - Metadaten versiegeln (0.1.30)

// Wer wen eingeladen hat und wer in einer Gruppe was geschrieben hat, lag bis 0.1.29 im Klartext:
// groups.inviter, group_invites.pubkey und messages.sender (Pubkeys). Einmalig beim Entsperren
// versiegeln, in einer Transaktion; schlägt etwas fehl, bleibt alles wie es war (Lesen versteht dann
// weiter Klartext) und es geht beim nächsten Entsperren erneut. team.used wird nicht mehr gebraucht: 0.
- (void)migrateMetadata {
    if ([self metaValue:"meta_sealed"]) { self.metaSealed = YES; return; }
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK;
    // messages.sender: nur Pubkeys (Team-Chat: 'all'/'app' sind keine Metadaten über Personen)
    sqlite3_stmt *sel = ok ? [self prepare:"SELECT rowid, chat, event_id, sender FROM messages WHERE sender IS NOT NULL "
                                           "AND sender NOT IN ('all','app') AND substr(sender,1,5) != 'enc2:'"] : NULL;
    sqlite3_stmt *upd = ok ? [self prepare:"UPDATE messages SET sender=? WHERE rowid=?"] : NULL;
    ok = ok && sel && upd;
    while (ok && sqlite3_step(sel) == SQLITE_ROW) {
        NSString *sealed = [self seal:columnText(sel, 3) context:senderContext(columnText(sel, 1), columnText(sel, 2))];
        bindText(upd, 1, sealed);
        sqlite3_bind_int64(upd, 2, sqlite3_column_int64(sel, 0));
        ok = sealed && sqlite3_step(upd) == SQLITE_DONE;
        sqlite3_reset(upd);
    }
    sqlite3_finalize(sel); sqlite3_finalize(upd);
    // groups.inviter
    sel = ok ? [self prepare:"SELECT gid, inviter FROM groups WHERE inviter IS NOT NULL AND inviter != '' AND substr(inviter,1,5) != 'enc2:'"] : NULL;
    upd = ok ? [self prepare:"UPDATE groups SET inviter=? WHERE gid=?"] : NULL;
    ok = ok && sel && upd;
    while (ok && sqlite3_step(sel) == SQLITE_ROW) {
        NSString *gid = columnText(sel, 0), *sealed = [self seal:columnText(sel, 1) context:inviterContext(gid)];
        bindText(upd, 1, sealed); bindText(upd, 2, gid);
        ok = sealed && sqlite3_step(upd) == SQLITE_DONE;
        sqlite3_reset(upd);
    }
    sqlite3_finalize(sel); sqlite3_finalize(upd);
    // group_invites.pubkey
    sel = ok ? [self prepare:"SELECT rowid, gid, pubkey FROM group_invites WHERE substr(pubkey,1,5) != 'enc2:'"] : NULL;
    upd = ok ? [self prepare:"UPDATE group_invites SET pubkey=? WHERE rowid=?"] : NULL;
    ok = ok && sel && upd;
    while (ok && sqlite3_step(sel) == SQLITE_ROW) {
        NSString *sealed = [self seal:columnText(sel, 2) context:inviteeContext(columnText(sel, 1))];
        bindText(upd, 1, sealed);
        sqlite3_bind_int64(upd, 2, sqlite3_column_int64(sel, 0));
        ok = sealed && sqlite3_step(upd) == SQLITE_DONE;
        sqlite3_reset(upd);
    }
    sqlite3_finalize(sel); sqlite3_finalize(upd);
    ok = ok && sqlite3_exec(self.db, "UPDATE team SET used=0", NULL, NULL, NULL) == SQLITE_OK && [self setMeta:"meta_sealed" value:1];
    if (ok && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) { self.metaSealed = YES; return; }
    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
}

@end

@implementation MeshStore (MediaMove)

// Ein Schritt: die nächsten Zeilen nach rowid (bis ~64 KB Medien oder 20 Zeilen, mindestens eine) lesen, die
// Medieninhalte unverändert (versiegelt, gleicher Kontext) nach message_blobs kopieren und erst
// danach messages.content leeren, alles in einer Transaktion samt Fortschritt. Wird die App
// mittendrin beendet, rollt sqlite den Schritt zurück: die Zeilen stehen dann noch vollständig in
// messages und werden beim nächsten Mal wieder übernommen (INSERT OR REPLACE, idempotent).
- (BOOL)moveMediaStep {
    if ([self metaValue:"media_moved"]) return NO;
    long long from = [self metaValue:"media_scan"], last = from;
    NSMutableArray *rows = [NSMutableArray array], *contents = [NSMutableArray array];
    sqlite3_stmt *sel = [self prepare:"SELECT rowid, kind, content FROM messages WHERE rowid > ? ORDER BY rowid"];
    if (!sel) return NO;
    sqlite3_bind_int64(sel, 1, from);
    NSUInteger bytes = 0, seen = 0;
    // Klein: läuft auf dem Main-Thread, größere Schritte ließen den A4 nach dem Update minutenlang ruckeln.
    while (bytes < 64 * 1024 && seen < 20 && sqlite3_step(sel) == SQLITE_ROW) {
        seen++;
        last = sqlite3_column_int64(sel, 0);
        int kind = sqlite3_column_int(sel, 1);
        if (kind != 1 && kind != 2 && kind != 3) continue;   // MeshPayloadImage, Voice, File
        NSData *raw = columnBlob(sel, 2);   // Bytes wie gespeichert, ohne Umweg über NSString
        if (!raw.length) continue;          // schon umgezogen oder neu eingefügt
        [rows addObject:@(last)];
        [contents addObject:raw];
        bytes += raw.length;
    }
    sqlite3_finalize(sel);
    if (!seen) return ![self finishMediaMove];   // alles durch

    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK;
    sqlite3_stmt *copy = ok ? [self prepare:"INSERT OR REPLACE INTO message_blobs(rowid, content) VALUES(?,?)"] : NULL;
    // Nur leeren, was genau so kopiert wurde
    sqlite3_stmt *clear = ok ? [self prepare:"UPDATE messages SET content='' WHERE rowid=?1 AND content=?2"] : NULL;
    sqlite3_stmt *undo = ok ? [self prepare:"DELETE FROM message_blobs WHERE rowid=?"] : NULL;
    ok = ok && copy && clear && undo;
    for (NSUInteger i = 0; ok && i < rows.count; i++) {
        long long rowId = [rows[i] longLongValue];
        NSData *raw = contents[i];
        sqlite3_bind_int64(copy, 1, rowId);
        sqlite3_bind_text(copy, 2, raw.bytes, (int)raw.length, SQLITE_STATIC);
        ok = sqlite3_step(copy) == SQLITE_DONE;
        sqlite3_reset(copy);
        sqlite3_bind_int64(clear, 1, rowId);
        sqlite3_bind_text(clear, 2, raw.bytes, (int)raw.length, SQLITE_STATIC);
        ok = ok && sqlite3_step(clear) == SQLITE_DONE;
        BOOL cleared = sqlite3_changes(self.db) > 0;
        sqlite3_reset(clear);
        if (ok && !cleared) {   // inzwischen anders (kann nicht vorkommen): die Kopie nicht gelten lassen
            sqlite3_bind_int64(undo, 1, rowId);
            ok = sqlite3_step(undo) == SQLITE_DONE;
            sqlite3_reset(undo);
        }
    }
    sqlite3_finalize(copy); sqlite3_finalize(clear); sqlite3_finalize(undo);
    ok = ok && [self setMeta:"media_scan" value:last];
    if (ok && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return YES;
    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
    return NO;   // später erneut (nächstes Entsperren), nicht in einer Schleife
}

@end
