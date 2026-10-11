// Ablaufprüfung für Zertifikate bei richtiger und falscher Geräteuhr.
#import "MeshTest.h"
#import "MeshCertTime.h"

static time_t at(int y, int m, int d) {
    struct tm t = {0}; t.tm_year = y - 1900; t.tm_mon = m - 1; t.tm_mday = d; t.tm_hour = 12;
    return timegm(&t);
}

int main(void) { @autoreleasepool {
    time_t build = at(2026, 10, 8);
    MeshCertDate from = {2026, 9, 1, 0, 0, 0}, to = {2026, 11, 30, 23, 59, 59};

    check(MeshCertCheckTime(at(2026, 10, 20), build, from, to) == MeshCertTimeOK, "valid");
    check(MeshCertCheckTime(at(2026, 12, 1), build, from, to) == MeshCertTimeExpired, "expired");
    MeshCertDate later = {2027, 1, 1, 0, 0, 0}, laterEnd = {2027, 6, 1, 0, 0, 0};
    check(MeshCertCheckTime(at(2026, 10, 20), build, later, laterEnd) == MeshCertTimeNotYetValid, "not yet valid");
    // iPod nach leerem Akku: Uhr steht auf 1970 → nicht prüfbar, keine Ablehnung
    check(MeshCertCheckTime(0, build, from, to) == MeshCertTimeClockUnknown, "clock 1970");
    check(MeshCertCheckTime(at(2025, 1, 1), build, from, to) == MeshCertTimeClockUnknown, "clock before build");
    // Auch bei falscher Uhr: vor dem Build abgelaufen = sicher abgelaufen
    MeshCertDate oldFrom = {2024, 1, 1, 0, 0, 0}, oldTo = {2025, 1, 1, 0, 0, 0};
    check(MeshCertCheckTime(0, build, oldFrom, oldTo) == MeshCertTimeExpired, "expired before build, clock 1970");
    check(MeshClockPlausible(0, build) == 0 && MeshClockPlausible(at(2026, 12, 1), build) == 1, "clock plausibility");
    // Grenzen sekundengenau
    struct tm e = {0}; e.tm_year = 126; e.tm_mon = 10; e.tm_mday = 30; e.tm_hour = 23; e.tm_min = 59; e.tm_sec = 59;
    check(MeshCertCheckTime(timegm(&e), build, from, to) == MeshCertTimeOK, "last second valid");
    check(MeshCertCheckTime(timegm(&e) + 1, build, from, to) == MeshCertTimeExpired, "one second after");

    return testsDone();
}}
