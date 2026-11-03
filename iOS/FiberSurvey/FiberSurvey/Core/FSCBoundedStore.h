#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FSCBoundedStore : NSObject
@property (nonatomic, copy, readonly) NSArray<NSString *> *items;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)prepend:(NSString *)value;
- (void)clear;
@end
NS_ASSUME_NONNULL_END
