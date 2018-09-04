//
//  NTicker.h
//  bither-ios
//
//  Created by 李庆 on 2018/7/31.
//  Copyright © 2018年 Bither. All rights reserved.
//

#import "JSONModel.h"
@class NTickerData;
@class NTickerMetaData;
@class NTickerQuotes;
@class NTickerConvert;

@interface NTicker : JSONModel
@property(nonatomic, strong) NTickerData *data;
@property(nonatomic, strong) NTickerMetaData *metadata;
+(NTicker *)sharedManager;
-(void)setCacheData;
@end
@interface NTickerData : JSONModel
@property(nonatomic, strong) NSString *t_id;
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) NSString *symbol;
@property(nonatomic, strong) NSString *website_slug;
@property(nonatomic, strong) NSString *rank;
@property(nonatomic, strong) NSString *circulating_supply;
@property(nonatomic, strong) NSString *total_supply;
@property(nonatomic, strong) NSString *max_supply;
@property(nonatomic, strong) NTickerQuotes *quotes;
@property(nonatomic, strong) NSString *last_updated;
@end
@interface NTickerMetaData : JSONModel
@property(nonatomic, strong) NSString *timestamp;
@property(nonatomic, strong) NSString *error;
@end
@interface NTickerQuotes : JSONModel
@property(nonatomic, strong) NTickerConvert *USD;
@property(nonatomic, strong) NTickerConvert *CNY;
@end

@interface NTickerConvert : JSONModel
@property(nonatomic, strong) NSString *price;
@property(nonatomic, strong) NSString *volume_24h;
@property(nonatomic, strong) NSString *market_cap;
@property(nonatomic, strong) NSString *percent_change_1h;
@property(nonatomic, strong) NSString *percent_change_24h;
@property(nonatomic, strong) NSString *percent_change_7d;
@end
