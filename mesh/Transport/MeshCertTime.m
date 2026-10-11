#import "MeshCertTime.h"

static int cmp(MeshCertDate a, MeshCertDate b) {
    int x[6] = { a.year, a.mon, a.day, a.hour, a.min, a.sec };
    int y[6] = { b.year, b.mon, b.day, b.hour, b.min, b.sec };
    for (int i = 0; i < 6; i++) if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
    return 0;
}

static MeshCertDate dateOf(time_t when) {
    struct tm t;
    gmtime_r(&when, &t);
    MeshCertDate d = { t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec };
    return d;
}

int MeshClockPlausible(time_t now, time_t buildTime) { return now >= buildTime; }

MeshCertTimeResult MeshCertCheckTime(time_t now, time_t buildTime, MeshCertDate from, MeshCertDate to) {
    if (!MeshClockPlausible(now, buildTime))
        return cmp(dateOf(buildTime), to) > 0 ? MeshCertTimeExpired : MeshCertTimeClockUnknown;
    MeshCertDate n = dateOf(now);
    if (cmp(n, from) < 0) return MeshCertTimeNotYetValid;
    if (cmp(n, to) > 0)   return MeshCertTimeExpired;
    return MeshCertTimeOK;
}
