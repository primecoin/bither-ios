//
//  BTBlockProvider.h
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

#import <Foundation/Foundation.h>
#import "BTBlock.h"


@interface BTBlockProvider : NSObject

+ (instancetype)instance;

- (int)getBlockCount;

- (NSMutableArray *)getAllBlocks;

- (NSArray *)getBlocksWithLimit:(NSInteger)limit;

- (NSMutableArray *)getBlocksFrom:(uint)blockNo;

- (BTBlock *)getLastBlock;

- (BTBlock *)getLastOrphanBlock;

- (BTBlock *)getBlock:(NSData *)blockHash;


- (BOOL)isExist:(NSData *)blockHash;


- (void)addBlock:(BTBlock *)block;

- (void)addBlocks:(NSArray *)blocks;

- (void)updateBlock:(NSData *)blockHash withIsMain:(BOOL)isMain;

- (BTBlock *)getOrphanBlockByPrevHash:(NSData *)prevHash;

- (BTBlock *)getMainChainBlock:(NSData *)blockHash;

- (void)removeBlock:(NSData *)blockHash;

- (void)cleanOldBlock;

@end
