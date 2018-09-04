//
//  ObtainBccMonitoredDetailViewController.h
//  bither-ios
//
//  Created by 韩珍 on 2017/7/28.
//  Copyright © 2017年 Bither. All rights reserved.
//  获得bcc监控详情

#import <UIKit/UIKit.h>
#import "SendViewController.h"
#import "SplitCoinUtil.h"

@interface ObtainBccMonitoredDetailViewController : UIViewController

@property BTAddress *btAddress;
@property uint64_t amount;
@property(weak) NSObject <SendDelegate> *sendDelegate;
@property(nonatomic) SplitCoin splitCoin;

@end
