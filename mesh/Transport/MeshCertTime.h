// Gültigkeitszeitraum eines Zertifikats prüfen.
//
// Unser mbedTLS ist ohne Uhrzeitprüfung gebaut, weil alte iPods bei leerem Akku das Datum
// verlieren (dann 1970) und sonst keine Verbindung mehr zustande käme. Wir prüfen selbst,
// aber nur bei plausibler Uhr: liegt sie vor dem Build-Zeitpunkt, ist sie sicher falsch.
#include <time.h>

// Setzt das Makefile auf den Build-Zeitpunkt; ohne (Mac-Tests) gibt es keine Untergrenze.
#ifndef MESH_BUILD_TIME
#define MESH_BUILD_TIME 0
#endif

typedef struct { int year, mon, day, hour, min, sec; } MeshCertDate;

typedef enum {
    MeshCertTimeOK = 0,
    MeshCertTimeExpired,
    MeshCertTimeNotYetValid,
    MeshCertTimeClockUnknown    // Uhr unplausibel, Zeitraum nicht genau prüfbar
} MeshCertTimeResult;

// Bei unplausibler Uhr gilt: Was schon vor dem Build abgelaufen war, ist sicher abgelaufen.

MeshCertTimeResult MeshCertCheckTime(time_t now, time_t buildTime, MeshCertDate from, MeshCertDate to);
int MeshClockPlausible(time_t now, time_t buildTime);
