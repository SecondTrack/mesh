// Lokalisierung über NSLocalizedString und <Sprache>.lproj/Localizable.strings.
//
// Schlüssel ist der englische Text; fehlt eine Übersetzung, zeigt iOS den Schlüssel, also Englisch.
// Eine neue Sprache braucht nur eine weitere Localizable.strings mit denselben Schlüsseln.
// Info.plist: CFBundleDevelopmentRegion = en, CFBundleLocalizations = (en, de).
#import <Foundation/Foundation.h>

#ifndef MESH_L10N_H
#define MESH_L10N_H

#define L(k)        NSLocalizedString((k), nil)
#define LF(k, ...)  [NSString stringWithFormat:NSLocalizedString((k), nil), __VA_ARGS__]

#endif
