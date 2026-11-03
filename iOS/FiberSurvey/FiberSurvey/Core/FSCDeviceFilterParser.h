#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FSCDeviceFilterParser : NSObject
+ (nullable NSArray<NSString *> *)parse:(NSString *)text error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)duration:(NSString *)text seconds:(NSTimeInterval *)seconds;
+ (NSString *)boundedText:(NSString *)text;
@end
NS_ASSUME_NONNULL_END
