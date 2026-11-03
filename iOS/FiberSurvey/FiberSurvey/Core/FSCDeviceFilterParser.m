#import "FSCDeviceFilterParser.h"
#import <math.h>
@implementation FSCDeviceFilterParser
+ (NSArray<NSString *> *)parse:(NSString *)text error:(NSError **)error {
    if (text.length > 8192) {
        if (error) *error = [NSError errorWithDomain:@"FiberSurvey.Input" code:1 userInfo:@{NSLocalizedDescriptionKey:@"白名单输入最多8192个字符"}];
        return nil;
    }
    NSMutableCharacterSet *separators = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
    [separators addCharactersInString:@",，;；"];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *keys = [NSMutableSet set];
    for (NSString *part in [text componentsSeparatedByCharactersInSet:separators]) {
        if (!part.length) continue;
        if (part.length > 64) {
            if (error) *error = [NSError errorWithDomain:@"FiberSurvey.Input" code:2 userInfo:@{NSLocalizedDescriptionKey:@"白名单最多100个编号，每个不超过64个字符"}];
            return nil;
        }
        NSString *key = part.lowercaseString;
        if (![keys containsObject:key]) {
            if (result.count >= 100) {
                if (error) *error = [NSError errorWithDomain:@"FiberSurvey.Input" code:2 userInfo:@{NSLocalizedDescriptionKey:@"白名单最多100个不同编号"}];
                return nil;
            }
            [keys addObject:key]; [result addObject:part];
        }
    }
    return result.copy;
}
+ (BOOL)duration:(NSString *)text seconds:(NSTimeInterval *)seconds {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:value];
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double parsed = 0;
    if (!value.length || ![scanner scanDouble:&parsed] || !scanner.isAtEnd || !isfinite(parsed) || parsed < 1 || parsed > 60) return NO;
    if (seconds) *seconds = parsed;
    return YES;
}
+ (NSString *)boundedText:(NSString *)text {
    if (text.length <= 4096) return text;
    NSRange range = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 4096)];
    return [[text substringWithRange:range] stringByAppendingString:@" …[显示截断；非完整报文]"];
}
@end
