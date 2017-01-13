//
//  MJProperty.m
//  MJExtensionExample
//
//  Created by MJ Lee on 15/4/17.
//  Copyright (c) 2015年 小码哥. All rights reserved.
//

#import "MJProperty.h"
#import "MJFoundation.h"
#import "MJExtensionConst.h"
#import <objc/message.h>

@interface MJProperty()
@property (strong, nonatomic) NSMutableDictionary *propertyKeysDict;
@property (strong, nonatomic) NSMutableDictionary *objectClassInArrayDict;
@end

@implementation MJProperty

#pragma mark - 初始化
- (instancetype)init
{
    if (self = [super init]) {
        _propertyKeysDict = [NSMutableDictionary dictionary];
        _objectClassInArrayDict = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 缓存
+ (instancetype)cachedPropertyWithProperty:(objc_property_t)property
{
    MJProperty *propertyObj = objc_getAssociatedObject(self, property);
    if (propertyObj == nil) {
        propertyObj = [[self alloc] init];
        propertyObj.property = property;
        objc_setAssociatedObject(self, property, propertyObj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return propertyObj;
}

#pragma mark - 公共方法
- (void)setProperty:(objc_property_t)property
{
    _property = property;
    
    MJExtensionAssertParamNotNil(property);
    
    // 1.属性名
    _name = @(property_getName(property));
    
    // 2.成员类型
    NSString *attrs = @(property_getAttributes(property));
    NSUInteger dotLoc = [attrs rangeOfString:@","].location;
    NSString *code = nil;
    NSUInteger loc = 1;
    if (dotLoc == NSNotFound) { // 没有,
        code = [attrs substringFromIndex:loc];
    } else {
        code = [attrs substringWithRange:NSMakeRange(loc, dotLoc - loc)];
    }
    _type = [MJPropertyType cachedTypeWithCode:code];
}

/**
 *  获得成员变量的值
 */
- (id)valueForObject:(id)object
{
    if (self.type.KVCDisabled) return [NSNull null];
    return [object valueForKey:self.name];
}

/**
 *  设置成员变量的值
 */
- (void)setValue:(id)value forObject:(id)object
{
    if (self.type.KVCDisabled || value == nil) return;
    [object setValue:value forKey:self.name];
}

/**
 *  通过字符串key创建对应的keys
 */
// 黄玉辉：把一级或多级key拆分，封装成MJPropertyKey放在数组中。
- (NSArray *)propertyKeysWithStringKey:(NSString *)stringKey
{
    if (stringKey.length == 0) return nil;
    
    NSMutableArray *propertyKeys = [NSMutableArray array];
    // 如果有多级映射
    // 黄玉辉：如 @"oldName" : @"name.oldName"
    NSArray *oldKeys = [stringKey componentsSeparatedByString:@"."];
    
    for (NSString *oldKey in oldKeys) {
        // 黄玉辉：带索引的情况，如 @"nameChangedTime" : @"name.info[1].nameChangedTime"。
        NSUInteger start = [oldKey rangeOfString:@"["].location;
        if (start != NSNotFound) { // 有索引的key
            NSString *prefixKey = [oldKey substringToIndex:start];
            NSString *indexKey = prefixKey;
            if (prefixKey.length) {
                MJPropertyKey *propertyKey = [[MJPropertyKey alloc] init];
                propertyKey.name = prefixKey;
                [propertyKeys addObject:propertyKey];
                
                indexKey = [oldKey stringByReplacingOccurrencesOfString:prefixKey withString:@""];
            }
            
            /** 解析索引 **/
            // 元素
            NSArray *cmps = [[indexKey stringByReplacingOccurrencesOfString:@"[" withString:@""] componentsSeparatedByString:@"]"];
            // 黄玉辉：可能有多级索引，如info[1][2]。
            for (NSInteger i = 0; i<cmps.count - 1; i++) {
                MJPropertyKey *subPropertyKey = [[MJPropertyKey alloc] init];
                subPropertyKey.type = MJPropertyKeyTypeArray;
                subPropertyKey.name = cmps[i];
                [propertyKeys addObject:subPropertyKey];
            }
        } else { // 没有索引的key
            MJPropertyKey *propertyKey = [[MJPropertyKey alloc] init];
            propertyKey.name = oldKey;
            [propertyKeys addObject:propertyKey];
        }
    }
    
    return propertyKeys;
}

/** 对应着字典中的key */
/**
 黄玉辉：重要代码
 把当前MJProperty对象实例所属的类与在该类下所对应的字典key保存为一条记录。
 */
- (void)setOriginKey:(id)originKey forClass:(Class)c
{
    if ([originKey isKindOfClass:[NSString class]]) { // 字符串类型的key
        NSArray *propertyKeys = [self propertyKeysWithStringKey:originKey];
        if (propertyKeys.count) {
            // 黄玉辉：注意，数组里的元素也是数组，内层数组的元素是MJPropertyKey，是由一级或多级key拆分封装而成。
            [self setPorpertyKeys:@[propertyKeys] forClass:c];
        }
    } else if ([originKey isKindOfClass:[NSArray class]]) {
        NSMutableArray *keyses = [NSMutableArray array];
        for (NSString *stringKey in originKey) {
            NSArray *propertyKeys = [self propertyKeysWithStringKey:stringKey];
            if (propertyKeys.count) {
                [keyses addObject:propertyKeys];
            }
        }
        if (keyses.count) {
            [self setPorpertyKeys:keyses forClass:c];
        }
    }
}

/** 对应着字典中的多级key */
/**
 黄玉辉：
 如 @"oldName" : @"name.oldName"
 名字为oldName的MJProperty对象实例保存了一条记录，该记录的key是它所属的类，value是一个数组，
 数组里面的元素也是数组，内层数组的元素则是MJPropertyKey，它们的名字分别是name和oldName。
 以下这种情况比较好理解：
 @"otherName" : @[@"otherName", @"name.newName", @"name.oldName"]
 */
- (void)setPorpertyKeys:(NSArray *)propertyKeys forClass:(Class)c
{
    if (propertyKeys.count == 0) return;
    self.propertyKeysDict[NSStringFromClass(c)] = propertyKeys;
}
- (NSArray *)propertyKeysForClass:(Class)c
{
    return self.propertyKeysDict[NSStringFromClass(c)];
}

/** 模型数组中的模型类型 */
- (void)setObjectClassInArray:(Class)objectClass forClass:(Class)c
{
    if (!objectClass) return;
    self.objectClassInArrayDict[NSStringFromClass(c)] = objectClass;
}
- (Class)objectClassInArrayForClass:(Class)c
{
    return self.objectClassInArrayDict[NSStringFromClass(c)];
}
@end
