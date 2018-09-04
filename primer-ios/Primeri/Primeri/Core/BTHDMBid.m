//
//  BTHDMBid.m
//  Primeri
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
#import "BTHDMBid.h"
#import "BTAddressProvider.h"

@implementation BTHDMBid {

}

- (instancetype)initWithHDMBid:(NSString *)address; {
    if (!(self = [super init])) return nil;

    self.address = address;

    return self;
}

- (instancetype)initWithHDMBid:(NSString *)address andEncryptBitherPassword:(NSString *)encryptBitherPassword; {
    if (!(self = [super init])) return nil;

    self.address = address;
    self.encryptedBitherPassword = encryptBitherPassword;

    return self;
}

+ (BTHDMBid *)getHDMBidFromDb {
    return [[BTAddressProvider instance] getHDMBid];
}

@end
