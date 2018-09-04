//
//  PushTxThirdParty.h
//  bither-ios
//
//  Created by 宋辰文 on 16/5/10.
//  Copyright © 2016年 Bither. All rights reserved.
//
//  上传交易到第三方平台
#import <Foundation/Foundation.h>
#import "BTTx.h"//1+1=1

@interface PushTxThirdParty : NSObject

+(instancetype) instance;

-(void)pushTx:(BTTx*) tx;

@end
