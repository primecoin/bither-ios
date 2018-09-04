//
//  NTicker.m
//  bither-ios
//
//  Created by 李庆 on 2018/7/31.
//  Copyright © 2018年 Bither. All rights reserved.
//

#import "NTicker.h"

@implementation NTicker
+(BOOL)propertyIsOptional:(NSString*)propertyName
{
    return YES;
}
+ (instancetype)sharedManager{
    
    static NTicker *_shareNTickerManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"NTicker"]) {
            
            NSData *rr = [[NSUserDefaults standardUserDefaults] objectForKey:@"NTicker"];
            _shareNTickerManager = [NSKeyedUnarchiver unarchiveObjectWithData:rr];
        }else{
            _shareNTickerManager = [[NTicker alloc] init];
        }
    });
    
    return _shareNTickerManager;
}
-(void)setCacheData{
    [NTicker sharedManager].data = self.data;
    [NTicker sharedManager].metadata = self.metadata;
    NSData *dT = [NSKeyedArchiver archivedDataWithRootObject:self];
    [[NSUserDefaults standardUserDefaults] setObject:dT forKey:@"NTicker"];
}
@end

@implementation NTickerData
+(BOOL)propertyIsOptional:(NSString*)propertyName
{
    return YES;
}

+(JSONKeyMapper *)keyMapper{
    return [[JSONKeyMapper alloc]initWithModelToJSONDictionary:@{@"t_id":@"id"}];
}
@end

@implementation NTickerMetaData
+(BOOL)propertyIsOptional:(NSString*)propertyName
{
    return YES;
}
@end

@implementation NTickerQuotes
+(BOOL)propertyIsOptional:(NSString*)propertyName
{
    return YES;
}
@end

@implementation NTickerConvert

@end
