//  BitherEngine.m
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

#import "PrimerEngine.h"

static BitherEngine *bitherEngine;
static MKNetworkEngine *userNetworkEngine;
static MKNetworkEngine *statsNetworkEngine;
static MKNetworkEngine *bitcoinNetworkEngine;
static MKNetworkEngine *bcNetworkEngine;
static MKNetworkEngine *hdmNetworkEngine;
static MKNetworkEngine *blockChainEngine;
static MKNetworkEngine *chainBtcComEngine;
static MKNetworkEngine *primeMarketEngine;
@implementation BitherEngine
+ (BitherEngine *)instance {//域名选择
    @synchronized (self) {
        if (bitherEngine == nil) {
            bitherEngine = [[self alloc] init];
            NSMutableDictionary *headerFields = [NSMutableDictionary dictionary];
            [headerFields setValue:@"application/json" forKey:@"Accept"];
            userNetworkEngine = [[MKNetworkEngine alloc] initWithHostName:@"bu.getcai.com" customHeaderFields:headerFields];
            statsNetworkEngine = [[MKNetworkEngine alloc] initWithHostName:@"graphs2.coinmarketcap.com" customHeaderFields:headerFields];//图表相关
            bitcoinNetworkEngine = [[MKNetworkEngine alloc] initWithHostName:@"b.getcai.com" customHeaderFields:headerFields];
            bcNetworkEngine = [[MKNetworkEngine alloc]initWithHostName:@"bc.bither.net" customHeaderFields:headerFields];
            hdmNetworkEngine = [[MKNetworkEngine alloc] initWithHostName:@"hdm.bither.net" customHeaderFields:headerFields];
            //区块相关
            blockChainEngine = [[MKNetworkEngine alloc]initWithHostName:@"192.168.1.10" customHeaderFields:headerFields];
            chainBtcComEngine = [[MKNetworkEngine alloc]initWithHostName:@"chain.btc.com" customHeaderFields:headerFields];
            primeMarketEngine = [[MKNetworkEngine alloc]initWithHostName:@"api.coinmarketcap.com" customHeaderFields:headerFields];
        }
    }
    return bitherEngine;
}

- (MKNetworkEngine *)getUserNetworkEngine {
    return userNetworkEngine;
}

- (MKNetworkEngine *)getStatsNetworkEngine {
    return statsNetworkEngine;
}

- (MKNetworkEngine *)getBitcoinNetworkEngine {
    return bitcoinNetworkEngine;
}

- (MKNetworkEngine *)getBCNetworkEngine {
    return bcNetworkEngine;
}

- (MKNetworkEngine *)getHDMNetworkEngine {
    return hdmNetworkEngine;
}
- (MKNetworkEngine *)getBlockChainEngine{
    return blockChainEngine;
}
- (MKNetworkEngine *)getChainBtcComEngine{
    return chainBtcComEngine;
}
- (MKNetworkEngine *)getPrimeMarketEngine{
    return primeMarketEngine;
}
- (NSArray *)getCookies {
    NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@", userNetworkEngine.readonlyHostName]]];
    return cookies;
}

- (void)setEngineCookie {
    [self setCookieOfDomain:statsNetworkEngine.readonlyHostName];//根据当前网络域名设置cookie
    [self setCookieOfDomain:bitcoinNetworkEngine.readonlyHostName];//根据节点的域名设置cookie
    
}

- (void)setCookieOfDomain:(NSString *)domain {
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@", userNetworkEngine.readonlyHostName]]];
    for (NSHTTPCookie *cookie in cookies) {
        NSMutableDictionary *cookieProperties = [NSMutableDictionary dictionary];
        [cookieProperties setObject:cookie.name forKey:NSHTTPCookieName];
        [cookieProperties setObject:cookie.value forKey:NSHTTPCookieValue];
        [cookieProperties setObject:domain forKey:NSHTTPCookieDomain];
        [cookieProperties setObject:domain forKey:NSHTTPCookieOriginURL];
        [cookieProperties setObject:cookie.path forKey:NSHTTPCookiePath];
        [cookieProperties setObject:[NSNumber numberWithInt:(int)cookie.version] forKey:NSHTTPCookieVersion];
        [cookieProperties setObject:cookie.expiresDate forKey:NSHTTPCookieExpires];
        NSHTTPCookie *newCookie = [NSHTTPCookie cookieWithProperties:cookieProperties];
        [cookieStorage setCookie:newCookie];
    }
    NSArray *cookies1 = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@", domain]]];
    NSLog(@"cook %@", cookies1);
}

@end