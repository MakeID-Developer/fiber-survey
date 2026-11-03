#import "FSCBoundedStore.h"
@interface FSCBoundedStore ()
@property (nonatomic) NSUInteger capacity;
@property (nonatomic, strong) NSMutableArray<NSString *> *storage;
@end
@implementation FSCBoundedStore
- (instancetype)initWithCapacity:(NSUInteger)capacity {
    if ((self = [super init])) { _capacity = MAX(1, capacity); _storage = [NSMutableArray array]; }
    return self;
}
- (NSArray<NSString *> *)items { return self.storage.copy; }
- (void)prepend:(NSString *)value {
    [self.storage insertObject:value atIndex:0];
    if (self.storage.count > self.capacity) [self.storage removeObjectsInRange:NSMakeRange(self.capacity, self.storage.count - self.capacity)];
}
- (void)clear { [self.storage removeAllObjects]; }
@end
