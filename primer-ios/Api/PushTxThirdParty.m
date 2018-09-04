//
//  PushTxThirdParty.m
//  bither-ios
//
//  Created by 宋辰文 on 16/5/10.
//  Copyright © 2016年 Bither. All rights reserved.
//

#import "PushTxThirdParty.h"
#import "NSString+Base58.h"//1+1=1
#import "AFHTTPRequestOperationManager.h"

static PushTxThirdParty* instance;

@implementation PushTxThirdParty{
    AFHTTPRequestOperationManager* manager;
}

+(instancetype)instance{
    if(!instance){
        instance = [[PushTxThirdParty alloc]init];
    }
    return instance;
}

-(instancetype)init{
    if (!(self = [super init])) return nil;
    manager = [AFHTTPRequestOperationManager manager];
    return self;
}

-(void)pushTx:(BTTx*) tx {//上传交易到第三方平台
    NSString* raw = [NSString hexWithData:tx.toData];
    [self pushToBlockChainInfo:raw];
    [self pushToBtcCom:raw];
    [self pushToChainQuery:raw];
    [self pushToBlockr:raw];
    [self pushToBlockExplorer:raw];
}

-(void)pushToUrl:(NSString*)url key:(NSString*)key rawTx:(NSString*)rawTx tag:(NSString*)tag {
    NSLog(@"begin push tx to %@", tag);
    [manager POST:url parameters:@{key: rawTx} success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSLog(@"push tx to %@ success", tag);
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        NSLog(@"push tx to %@ failed", tag);
    }];
}

-(void)pushToBlockChainInfo:(NSString*) raw {
    [self pushToUrl:@"https://blockchain.info/pushtx" key:@"tx" rawTx:raw tag:@"blockchain.info"];
}

-(void)pushToBtcCom:(NSString*) raw {
    [self pushToUrl:@"https://btc.com/api/v1/tx/publish" key:@"hex" rawTx:raw tag:@"BTC.com"];
}

-(void)pushToChainQuery:(NSString*) raw {
    [self pushToUrl:@"https://chainquery.com/bitcoin-api/sendrawtransaction" key:@"transaction" rawTx:raw tag:@"ChainQuery.com"];
}

-(void)pushToBlockr:(NSString*)raw {
    [self pushToUrl:@"https://blockr.io/api/v1/tx/push" key:@"hex" rawTx:raw tag:@"blockr.io"];
}

-(void)pushToBlockExplorer:(NSString*)raw {
    [self pushToUrl:@"https://blockexplorer.com/api/tx/send" key:@"rawtx" rawTx:raw tag:@"BlockExplorer"];
}

@end
