// Stimmeffekte, 1:1 wie in der Android-App (gleiche Rechnung, gleiche Namen): none, anonym, high, chipmunk,
// chipmunk_anon, deep, robot, alien. PCM16 mono 16 kHz rein, gleich lang raus; nil bei Speicherfehler.
#import <Foundation/Foundation.h>

NSData *MeshVoiceFXApply(NSData *pcm, NSString *effect);
