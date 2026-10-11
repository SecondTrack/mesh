// Untere Leiste der Hauptseiten: zwei Pillen "Chats" und "Ich".
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MeshTab) { MeshTabChats, MeshTabMe };

@interface MeshTabBar : UIView
+ (CGFloat)height;
- (instancetype)initWithFrame:(CGRect)frame selected:(MeshTab)selected;
@property (nonatomic, copy) void (^onSelect)(MeshTab tab);   // nur für die nicht gewählte Pille
@end
