#import <CoreFoundation/CoreFoundation.h>
#import <os/lock.h>
#import "PrivateAPI.h"

@interface _IOHIDSensorChannelCache : NSObject
@property (nonatomic, assign) IOHIDEventSystemClientRef client;
@property (nonatomic, assign) CFArrayRef services;
@property (nonatomic, strong) NSArray<NSString *> *serviceNames;
@end

@implementation _IOHIDSensorChannelCache

- (void)dealloc {
    if (_services != NULL) {
        CFRelease(_services);
        _services = NULL;
    }
    if (_client != NULL) {
        CFRelease(_client);
        _client = NULL;
    }
}

@end

static os_unfair_lock sIOHIDCacheLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, _IOHIDSensorChannelCache *> *sIOHIDChannelCaches = nil;

static _IOHIDSensorChannelCache * _Nullable _IOHIDBuildChannelCache(int32_t page, int32_t usage) {
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (system == NULL) {
        return nil;
    }

    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(page),
        @"PrimaryUsage": @(usage),
    };
    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == NULL) {
        CFRelease(system);
        return nil;
    }

    CFIndex count = CFArrayGetCount(services);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    NSMutableSet<NSString *> *seenNames = [NSMutableSet setWithCapacity:(NSUInteger)count];

    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        NSString *entryName = @"";
        if (service != NULL) {
            CFTypeRef prop = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
            if (prop != NULL) {
                if (CFGetTypeID(prop) == CFStringGetTypeID()) {
                    NSString *candidate = [(__bridge NSString *)prop copy];
                    if (candidate.length > 0 && ![seenNames containsObject:candidate]) {
                        [seenNames addObject:candidate];
                        entryName = candidate;
                    }
                }
                CFRelease(prop);
            }
        }
        [names addObject:entryName];
    }

    _IOHIDSensorChannelCache *cache = [[_IOHIDSensorChannelCache alloc] init];
    cache.client = system;
    cache.services = services;
    cache.serviceNames = [names copy];
    return cache;
}

static NSMutableDictionary<NSString *, NSNumber *> * _Nonnull _IOHIDCollectFromCache(
    _IOHIDSensorChannelCache *cache,
    int64_t eventType,
    int32_t eventField
) {
    CFArrayRef services = cache.services;
    NSArray<NSString *> *names = cache.serviceNames;
    CFIndex count = CFArrayGetCount(services);
    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)count];

    for (CFIndex i = 0; i < count; i++) {
        NSString *name = names[(NSUInteger)i];
        if (name.length == 0) {
            continue;
        }
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        if (service == NULL) {
            continue;
        }
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, eventType, 0, 0);
        if (event != NULL) {
            double value = IOHIDEventGetFloatValue(event, eventField);
            result[name] = @(value);
            CFRelease(event);
        }
    }

    return result;
}

NSDictionary<NSString *, NSNumber *> * _Nonnull IOHIDReadSensorValues(
    int32_t page,
    int32_t usage,
    int64_t eventType,
    int32_t fieldBase
) {
    uint64_t packedKey = (((uint64_t)(uint32_t)page) << 32) | (uint64_t)(uint32_t)usage;
    NSNumber *cacheKey = @(packedKey);
    int32_t eventField = IOHIDEventFieldBase(fieldBase);

    os_unfair_lock_lock(&sIOHIDCacheLock);

    if (sIOHIDChannelCaches == nil) {
        sIOHIDChannelCaches = [NSMutableDictionary dictionary];
    }

    _IOHIDSensorChannelCache *cache = sIOHIDChannelCaches[cacheKey];
    BOOL wasCached = (cache != nil);
    if (cache == nil) {
        cache = _IOHIDBuildChannelCache(page, usage);
        if (cache != nil) {
            sIOHIDChannelCaches[cacheKey] = cache;
        }
    }

    NSMutableDictionary<NSString *, NSNumber *> *result = nil;
    if (cache != nil) {
        result = _IOHIDCollectFromCache(cache, eventType, eventField);
        if (result.count == 0 && wasCached) {
            // Auto-heal if HID services reset while app stayed alive
            _IOHIDSensorChannelCache *rebuilt = _IOHIDBuildChannelCache(page, usage);
            if (rebuilt != nil) {
                sIOHIDChannelCaches[cacheKey] = rebuilt;
                result = _IOHIDCollectFromCache(rebuilt, eventType, eventField);
            } else {
                [sIOHIDChannelCaches removeObjectForKey:cacheKey];
            }
        }
    }

    os_unfair_lock_unlock(&sIOHIDCacheLock);

    return result != nil ? [result copy] : @{};
}
