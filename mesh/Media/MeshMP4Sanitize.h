// Fremde MP4-Videos neu verpacken, bevor der System-Player sie sieht.
//
// Der MP4-Parser von iOS 6 hatte Lücken, und echte Videos tragen viel mehr als Bild und Ton
// (Metadaten-Spuren, Datum, Farbangaben …). Deshalb liest Mesh nur eine H.264-Bildspur und eine
// AAC-Tonspur, prüft jede Tabelle, jede Größe und die NAL-Rahmen jedes Bildes und schreibt daraus eine
// neue, minimale Datei (ftyp, moov, mdat). Alles andere fällt weg. Passt etwas nicht: nil.
// Die H.264-Daten selbst dekodiert weiter das System (Hardware-Decoder).
#import <Foundation/Foundation.h>

NSData *MeshMP4Sanitize(NSData *mp4, NSString **reason);
