//
//  MODScopeFunction.m
//  MongoObjCDriver
//
//  Created by Jérôme Lebel on 12/06/2014.
//
//

#import "MongoObjCDriver-private.h"

@interface MODScopeFunction ()

@property (nonatomic, copy, readwrite) NSString *function;
@property (nonatomic, copy, readwrite) MODSortedDictionary *scope;

@end

@implementation MODScopeFunction

- (instancetype)initWithFunction:(NSString *)function scope:(MODSortedDictionary *)scope
{
    if (self = [self init]) {
        self.function = function;
        self.scope = scope;
    }
    return self;
}

- (void)dealloc
{
    self.function = nil;
    self.scope = nil;
    MOD_SUPER_DEALLOC();
}

- (NSString *)jsonValueWithPretty:(BOOL)pretty strictJSON:(BOOL)strictJSON jsonKeySortOrder:(MODJsonKeySortOrder)jsonKeySortOrder
{
    NSString *scopeString;
    
    scopeString = [MODClient convertObjectToJson:self.scope pretty:pretty strictJson:strictJSON jsonKeySortOrder:jsonKeySortOrder];
    if (!strictJSON && pretty) {
        return [NSString stringWithFormat:@"ScopeFunction(\"%@\", %@)", [MODClient escapeQuotesForString:self.function], scopeString];
    } else if (!strictJSON && !pretty) {
        return [NSString stringWithFormat:@"ScopeFunction(\"%@\",%@)", [MODClient escapeQuotesForString:self.function], scopeString];
    } else if (pretty) {
        return [NSString stringWithFormat:@"{ \"$scope\" : %@, \"$function\" : \"%@\" }", scopeString, [MODClient escapeQuotesForString:self.function]];
    } else {
        return [NSString stringWithFormat:@"{\"$scope\":%@,\"$function\":\"%@\"}", scopeString, [MODClient escapeQuotesForString:self.function]];
    }
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[self class]]) {
        return [self.scope isEqual:[object scope]] && [self.function isEqualToString:[object function]];
    }
    return NO;
}

@end
