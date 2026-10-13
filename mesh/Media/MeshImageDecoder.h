// Fremde Bilder ohne die Decoder von iOS 6 öffnen: JPEG und PNG entpackt stb_image (vendor/stb) in
// eigenem Code; iOS bekommt nur fertige Pixel. ImageIO (libjpeg, libpng) sieht keine fremden Dateien mehr.
#import <UIKit/UIKit.h>

// nil bei kaputter Datei, anderem Format oder über maxSide Pixeln Kantenlänge
UIImage *MeshDecodeImage(NSData *data, int maxSide);
