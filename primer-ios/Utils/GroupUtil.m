//
//  GroupUtil.m
//  bither-ios
//
//  Copyright 2014 http://Bither.net
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.


#import "GroupUtil.h"


@implementation GroupUtil {

}


+ (NSString *)getMarketName:(MarketType)marketType {
    NSString *name;
    switch (marketType) {
        case COINMARKETCAP:
            name = NSLocalizedString(@"CoinMarketCap", nil);
            break;
        default:
            name = NSLocalizedString(@"CoinMarketCap", nil);
            break;
    }
    return name;

}

+ (NSString *)getMarketDomain:(MarketType)marketType {
    switch (marketType) {
        case COINMARKETCAP:
            return @"coinmarketcap.com";
        default:
            return nil;
    }
}


+ (int)getMarketValue:(MarketType)marketType {

    switch (marketType) {
        case COINMARKETCAP:
            return 1;
    }
    return 1;

}

+ (MarketType)getMarketType:(NSInteger)value {

    switch (value) {
        case 1:
            return COINMARKETCAP;
    }
    return COINMARKETCAP;
}

+ (UIColor *)getMarketColor:(MarketType)marketType {
    switch (marketType) {
        //ffff9329
//        case HUOBI:
//            return RGBA(255, 147, 41, 1);
//            //ff3bbf59
        case COINMARKETCAP:
            return RGBA(59, 191, 89, 1);
//            //ff25bebc
//        case OKCOIN:
//            return RGBA(21, 135, 198, 1);
//            //ff5b469d
//        case CHBTC:
//            return RGBA(91, 70, 157, 1);
//            //fff93c25
//        case BTCCHINA:
//            return RGBA(249, 60, 37, 1);
//            //ffa3bd0b
//        case BITFINEX:
//            return RGBA(163, 189, 11, 1);
//            //ffe31f21
//        case MARKET796:
//            return RGBA(227, 31, 33, 1);
//        case BTCTRADE:
//            return RGBA(168, 88, 0, 1);
//        case COINBASE:
//            return RGBA(21, 103, 177, 1);
        default:
            return nil;
    }
}


@end
