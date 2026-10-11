// makeicon.m — rendert das Mesh-Node-Icon zentriert + runde Ecken. Aufruf: makeicon out.png size
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>

static void dot(CGContextRef c, double x, double y, double r, double R,double G,double B){
    CGContextSetRGBFillColor(c,R,G,B,1); CGContextFillEllipseInRect(c, CGRectMake(x-r,y-r,2*r,2*r));
}
int main(int argc,char**argv){ @autoreleasepool{
    NSString *out=@(argv[1]); double S=atof(argv[2]); double k=S/108.0, rr=S*0.175;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(NULL,(size_t)S,(size_t)S,8,0,cs,kCGImageAlphaPremultipliedLast);
    // runde Ecken: clip
    CGMutablePathRef p=CGPathCreateMutable();
    CGPathMoveToPoint(p,NULL,rr,0); CGPathAddArcToPoint(p,NULL,S,0,S,rr,rr);
    CGPathAddArcToPoint(p,NULL,S,S,S-rr,S,rr); CGPathAddArcToPoint(p,NULL,0,S,0,S-rr,rr);
    CGPathAddArcToPoint(p,NULL,0,0,rr,0,rr); CGPathCloseSubpath(p);
    CGContextAddPath(c,p); CGContextClip(c);
    // Hintergrund #0A0F0E
    CGContextSetRGBFillColor(c,10/255.0,15/255.0,14/255.0,1); CGContextFillRect(c,CGRectMake(0,0,S,S));
    // Knoten (108-Raum, y gespiegelt: CG-Ursprung unten-links -> yc = 108-y)
    double nx[6]={79,66.5,41.5,29,41.5,66.5}, ny[6]={54,32.4,32.4,54,75.6,75.6};
    double cx=54, cy=54;
    #define TX(x) ((x)*k)
    #define TY(y) ((108-(y))*k)
    // Speichen
    CGContextSetRGBStrokeColor(c,47/255.0,230/255.0,168/255.0,0.55); CGContextSetLineWidth(c,2.4*k); CGContextSetLineCap(c,kCGLineCapRound);
    for(int i=0;i<6;i++){ CGContextMoveToPoint(c,TX(cx),TY(cy)); CGContextAddLineToPoint(c,TX(nx[i]),TY(ny[i])); }
    CGContextStrokePath(c);
    // Sechseck
    CGContextSetRGBStrokeColor(c,47/255.0,230/255.0,168/255.0,0.32); CGContextSetLineWidth(c,2*k);
    CGContextMoveToPoint(c,TX(nx[0]),TY(ny[0])); for(int i=1;i<6;i++)CGContextAddLineToPoint(c,TX(nx[i]),TY(ny[i])); CGContextClosePath(c); CGContextStrokePath(c);
    // äußere Punkte
    for(int i=0;i<6;i++) dot(c,TX(nx[i]),TY(ny[i]),5*k,47/255.0,230/255.0,168/255.0);
    // Zentrum
    dot(c,TX(cx),TY(cy),8*k,92/255.0,255/255.0,198/255.0);
    dot(c,TX(cx),TY(cy),3*k,10/255.0,15/255.0,14/255.0);
    CGImageRef img=CGBitmapContextCreateImage(c);
    CFURLRef u=CFURLCreateWithFileSystemPath(NULL,(CFStringRef)out,kCFURLPOSIXPathStyle,false);
    CGImageDestinationRef d=CGImageDestinationCreateWithURL(u,kUTTypePNG,1,NULL);
    CGImageDestinationAddImage(d,img,NULL); CGImageDestinationFinalize(d);
    printf("icon %s @ %.0f (zentriert, rund)\n",argv[1],S);
    return 0;
}}
