// Gemeinsames Gerüst der Mac-Tests: check zählt, testsDone druckt die Übersicht und liefert den
// Exit-Code für tests/run.sh.
#import <Foundation/Foundation.h>

static int ok = 0, bad = 0;

static void check(BOOL condition, const char *name) {
    if (condition) ok++;
    else { bad++; printf("  FAIL %s\n", name); }
}

static int testsDone(void) {
    printf("== %d ok, %d fehlgeschlagen ==\n", ok, bad);
    return bad ? 1 : 0;
}
