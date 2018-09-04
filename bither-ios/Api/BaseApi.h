//  BaseApi.h
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

#import <Foundation/Foundation.h>
#import "BitherEngine.h"
#import "AFNetworking.h"

#define kMKNetworkKitRequestTimeOutInSeconds 10

#define BITHER_GET_COOKIE_URL @"api/v1/cookie"//获取服务端cookie
#define BLOCKCHAIN_INFO_GET_LASTST_BLOCK @"http://api.primecoin.org/rest/pcoin/syncblock"//获取最新区块
#define BITHER_IN_SIGNATURES_API  @"api/v1/address/%@/insignature/%d"//根据地址获取签名
#define SPLIT_BROADCAST @"https://bitpie.getcai.com/api/v1/%@/broadcast"//发送广播（获取比特派bcc地址）

#define BCD_PREBLOCKHASH @"https://bitpie.getcai.com/api/v1/bcd/current/block/hash"//获取块的哈希值

#define SPLIT_HAS_ADDRESS @"https://bitpie.getcai.com/api/v1/%@/has/address/%@"//获取比特派bcc地址

#define BITHER_Q_MYTRANSACTIONS @"api/v1/address/%@/transaction"//未使用
#define BITHER_ERROR_API  @"api/v1/error"//上传错误日志
#define BITHER_EXCHANGE_TICKER @"v2/ticker/42/?convert=CNY"//更新图表交易数据
#define BITHER_KLINE_URL @"api/v1/exchange/%d/kline/%d"//未使用
#define BITHER_DEPTH_URL @"api/v1/exchange/%d/depth"//未使用
#define BITHER_TREND_URL @"currencies/primecoin"//获取图表数据
#define BITHER_UPLOAD_AVATAR @"api/v1/avatar"//未使用
#define BITHER_DOWNLOAD_AVATAR @"api/v1/avatar"//未使用

#define BC_ADDRESS_TX_URL @"api/v2/address/%@/transaction/p/%d"//获取交易数据——bither
#define BC_ADDRESS_STAT_URL @"api/v2/address/%@/transaction/stat"//获取我的交易数据——bither
//limit=50 one Page can show 50 tx informations
#define BLOCK_INFO_ADDRESS_TX_URL @"http://api.primecoin.org/rest/pcoin/txs/%@?offset=%d&length=100"//账户钱包列表数据
//#define BLOCK_INFO_TX_INDEX_URL @"http://192.168.1.10/rest/pcoin/txs/%@"//获取交易数据

@interface BaseApi : NSObject

#pragma mark-get

- (void)get:(NSString *)url withParams:(NSDictionary *)params networkType:(BitherNetworkType)networkType completed:(CompletedOperation)completedOperationParam andErrorCallback:(ErrorHandler)errorCallback;

- (void)get:(NSString *)url withParams:(NSDictionary *)params networkType:(BitherNetworkType)networkType completed:(CompletedOperation)completedOperationParam andErrorCallback:(ErrorHandler)errorCallback ssl:(BOOL)ssl;

- (void)execGetBlockChain:(NSString *)url withParams:(NSDictionary *)params networkType:(BitherNetworkType)networkType completed:(CompletedOperation)completedOperationParam andErrorCallback:(ErrorHandler)errorCallback ssl:(BOOL)ssl;

- (void)getBlockChainBh:(NSString *)url withParams:(NSDictionary *)params networkType:(BitherNetworkType)networkType completed:(CompletedOperation)completedOperationParam andErrorCallback:(ErrorHandler)errorCallback ssl:(BOOL)ssl;

- (void)getBlockChainTx:(NSString *)url withParams:(NSDictionary *)params networkType:(BitherNetworkType)networkType completed:(CompletedOperation)completedOperationParam andErrorCallback:(ErrorHandler)errorCallback ssl:(BOOL)ssl;

#pragma mark-post

- (void)post:(NSString *)url withParams:(NSDictionary *)params networkType:(BitherNetworkType)networkType completed:(CompletedOperation)completedOperationParam andErrorCallBack:(ErrorHandler)errorCallback;

- (void)post:(NSString *)url withParams:(NSDictionary *)params networkType:(BitherNetworkType)networkType completed:(CompletedOperation)completedOperationParam andErrorCallBack:(ErrorHandler)errorCallback ssl:(BOOL)ssl;
#pragma AF-GET
- (void)AFGet:(NSString *)url withParams:(NSDictionary *)params completed:(IdResponseBlock)completedOperationParam andErrorCallback:(ErrorBlock)errorCallback;
@end
