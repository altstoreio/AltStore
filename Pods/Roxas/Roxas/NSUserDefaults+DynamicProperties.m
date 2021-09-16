//
//  NSUserDefaults+DynamicProperties.m
//  Roxas
//
//  Created by Riley Testut on 6/27/15.
//  Copyright (c) 2015 Riley Testut. All rights reserved.
//

#import "NSUserDefaults+DynamicProperties.h"

@import ObjectiveC.runtime;

static NSDictionary *_propertyAccessorMethodsMappingDictionary = nil;

typedef NS_ENUM(char, RSTObjCEncoding)
{
    // Normally I'd prefix these with the enum type, but in this case it's far more readable in practice
    
    Bool       = 'B',
    Char       = 'c',
    Float      = 'f',
    Double     = 'd',
    Int        = 'i',
    Long       = 'l',
    LongLong   = 'q',
    Object     = '@',
};


@interface RSTDummyObject : NSObject

// Primitives
@property (assign, nonatomic) BOOL boolProperty;
@property (assign, nonatomic) float floatProperty;
@property (assign, nonatomic) double doubleProperty;
@property (assign, nonatomic) NSInteger integerProperty;

// Objects
@property (copy, nonatomic) NSURL *URLProperty;
@property (strong, nonatomic) id objectProperty;

@end

@implementation RSTDummyObject
@end


@implementation NSUserDefaults (DynamicProperties)

+ (void)initialize
{
    if (self != [NSUserDefaults class])
    {
        return;
    }
    
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    
    for (unsigned int i = 0; i < count; i++)
    {
        objc_property_t property = properties[i];
        
        const char *name = property_getName(property);
        if (name == NULL)
        {
            continue;
        }
        
        char *isDynamic = property_copyAttributeValue(property, "D");
        if (isDynamic != NULL)
        {
            // Property is a dynamic property
            free(isDynamic);
        }
        else
        {
            // Not a dynamic property, so we'll ignore
            continue;
        }
        
        NSString *propertyName = [NSString stringWithCString:name encoding:[NSString defaultCStringEncoding]];
        
        char *getter = property_copyAttributeValue(property, "G");
        if (getter != NULL)
        {
            // Use custom getter method as dictionary key
            NSString *getterName = [NSString stringWithCString:getter encoding:[NSString defaultCStringEncoding]];
            dictionary[getterName] = propertyName;
            
            free(getter);
        }
        else
        {
            // Use property name as getter method for dictionary key (as per Cocoa conventions)
            dictionary[propertyName] = propertyName;
        }
        
        char *setter = property_copyAttributeValue(property, "S");
        if (setter != NULL)
        {
            // Use custom setter method as dictionary key
            NSString *setterName = [NSString stringWithCString:setter encoding:[NSString defaultCStringEncoding]];
            dictionary[setterName] = propertyName;
            
            free(setter);
        }
        else
        {
            // Transform property name into setProperty: format for dictionary key (as per Cocoa conventions)
            NSString *firstCharacter = [[propertyName substringWithRange:NSMakeRange(0, 1)] uppercaseString];
            
            NSMutableString *setterName = [propertyName mutableCopy];
            [setterName replaceCharactersInRange:NSMakeRange(0, 1) withString:firstCharacter];
            [setterName insertString:@"set" atIndex:0];
            [setterName appendString:@":"];
            
            dictionary[setterName] = propertyName;
        }
    }
    
    _propertyAccessorMethodsMappingDictionary = [dictionary copy];
        
    free(properties);
}

+ (BOOL)resolveInstanceMethod:(SEL)selector
{
    if ([super resolveInstanceMethod:selector])
    {
        return YES;
    }
    
    NSString *methodName = NSStringFromSelector(selector);
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[methodName];
    
    if (propertyName == nil)
    {
        return NO;
    }
    
    objc_property_t property = class_getProperty(self, [propertyName cStringUsingEncoding:[NSString defaultCStringEncoding]]);
    if (propertyName == NULL)
    {
        return NO;
    }
    
    char *propertyEncoding = property_copyAttributeValue(property, "T");
    if (propertyEncoding == NULL)
    {
        return NO;
    }
    
    BOOL isSetter = [[methodName substringFromIndex:methodName.length - 1] isEqualToString:@":"];
    
    IMP imp = NULL;
    const char *types = NULL;
    
    switch (*propertyEncoding)
    {
        case Bool:
        case Char:
        {
            if (isSetter)
            {
                imp = (IMP)rst_setBoolValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(setBoolProperty:)));
            }
            else
            {
                imp = (IMP)rst_boolValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(boolProperty)));
            }
            
            break;
        }
            
        case Float:
        {
            if (isSetter)
            {
                imp = (IMP)rst_setFloatValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(setFloatProperty:)));
            }
            else
            {
                imp = (IMP)rst_floatValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(floatProperty)));
            }
            
            break;
        }
            
        case Double:
        {
            if (isSetter)
            {
                imp = (IMP)rst_setDoubleValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(setDoubleProperty:)));
            }
            else
            {
                imp = (IMP)rst_doubleValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(doubleProperty)));
            }
            
            break;
        }
            
        case Int:
        case Long:
        case LongLong:
        {
            if (isSetter)
            {
                imp = (IMP)rst_setIntegerValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(setIntegerProperty:)));
            }
            else
            {
                imp = (IMP)rst_integerValue;
                types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(integerProperty)));
            }
            
            break;
        }
            
        case Object:
        {
            NSMutableString *propertyType = [NSMutableString stringWithUTF8String:propertyEncoding];
            [propertyType replaceOccurrencesOfString:@"@" withString:@"" options:0 range:NSMakeRange(0, propertyType.length)];
            [propertyType replaceOccurrencesOfString:@"\"" withString:@"" options:0 range:NSMakeRange(0, propertyType.length)];
            
            BOOL isURL = NO;
            
            // From NSObject.mm (-[NSObject isKindOfClass:])
            for (Class class = NSClassFromString(propertyType); class; class = class_getSuperclass(class))
            {
                if (class == [NSURL class])
                {
                    isURL = YES;
                    break;
                }
            }
            
            if (isURL)
            {
                if (isSetter)
                {
                    imp = (IMP)rst_setURLValue;
                    types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(setURLProperty:)));
                }
                else
                {
                    imp = (IMP)rst_URLValue;
                    types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(URLProperty)));
                }
            }
            else
            {
                if (isSetter)
                {
                    imp = (IMP)rst_setObjectValue;
                    types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(setObjectProperty:)));
                }
                else
                {
                    imp = (IMP)rst_objectValue;
                    types = method_getTypeEncoding(class_getInstanceMethod([RSTDummyObject class], @selector(objectProperty)));
                }
            }
            
            break;
        }
            
        default:
        {
            @throw [NSException exceptionWithName:@"Unsupported Property Type"
                                           reason:@"NSUserDefaults+DynamicProperties only supports dynamic properties of supported NSUserDefaults types. Check the NSUserDefaults documentation or header file to see what types can be directly set."
                                         userInfo:nil];
            break;
        }
    }
    
    class_addMethod(self, selector, imp, types);
    
    return YES;
}

#pragma mark - IMPs -

#pragma mark - BOOL

void rst_setBoolValue(id self, SEL _cmd, BOOL value)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    [self setBool:value forKey:propertyName];
}

BOOL rst_boolValue(id self, SEL _cmd)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self boolForKey:propertyName];
}

#pragma mark - Float

void rst_setFloatValue(id self, SEL _cmd, float value)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self setFloat:value forKey:propertyName];
}

float rst_floatValue(id self, SEL _cmd)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self floatForKey:propertyName];
}

#pragma mark - Double

void rst_setDoubleValue(id self, SEL _cmd, double value)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self setDouble:value forKey:propertyName];
}

double rst_doubleValue(id self, SEL _cmd)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self doubleForKey:propertyName];
}

#pragma mark - Integer

void rst_setIntegerValue(id self, SEL _cmd, NSInteger value)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self setInteger:value forKey:propertyName];
}

NSInteger rst_integerValue(id self, SEL _cmd)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self integerForKey:propertyName];
}

#pragma mark - URL

void rst_setURLValue(id self, SEL _cmd, NSURL *value)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self setURL:[value copy] forKey:propertyName];
}

NSURL *rst_URLValue(id self, SEL _cmd)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self URLForKey:propertyName];
}

#pragma mark - Object

void rst_setObjectValue(id self, SEL _cmd, id value)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self setObject:value forKey:propertyName];
}

id rst_objectValue(id self, SEL _cmd)
{
    NSString *propertyName = _propertyAccessorMethodsMappingDictionary[NSStringFromSelector(_cmd)];
    return [self objectForKey:propertyName];
}

@end
