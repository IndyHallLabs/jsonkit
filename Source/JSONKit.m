/*
 * Copyright (c) 2008, IndyHall Labs
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the "IndyHall Labs" nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY IndyHall Labs ''AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL IndyHall Labs BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#import <JSONKit/JSONKit.h>

#pragma mark Encoding

typedef struct {
    CFMutableDataRef data;
    CFIndex flag;
} DataAndFlag;

static void appendStringToData(CFTypeRef object, CFMutableDataRef data);
static void appendArrayElementToData(CFTypeRef element, DataAndFlag* dataAndFlag);
static void appendKeyValuePairToData(CFTypeRef key, CFTypeRef value, DataAndFlag* dataAndFlag);
static void appendNumberToData(CFTypeRef number, CFMutableDataRef data);
static void appendObjectToData(CFTypeRef object, CFMutableDataRef data);

void appendStringToData(CFTypeRef string, CFMutableDataRef data)
{
    CFDataAppendBytes(data, (uint8_t*)&"\"", 1);
    CFIndex count = CFStringGetLength(string);
    int i;
    for (i = 0; i < count; i++) {
        UniChar c = CFStringGetCharacterAtIndex(string, i);
        if ('\"' == c) {
            CFDataAppendBytes(data, (uint8_t*)&"\\\"", 2);
        } else if ('/' == c) {
            CFDataAppendBytes(data, (uint8_t*)&"\\/", 2);
        } else if ('\b' == c) {
            CFDataAppendBytes(data, (uint8_t*)&"\\b", 2);
        } else if ('\f' == c) {
            CFDataAppendBytes(data, (uint8_t*)&"\\f", 2);
        } else if ('\n' == c) {
            CFDataAppendBytes(data, (uint8_t*)&"\\n", 2);
        } else if ('\r' == c) {
            CFDataAppendBytes(data, (uint8_t*)&"\\r", 2);
        } else if ('\t' == c) {
            CFDataAppendBytes(data, (uint8_t*)&"\\t", 2);
        } else if (c > 0x1F && c < 0x7F) {
            uint8_t byte = c & 0xFF;
            CFDataAppendBytes(data, &byte, 1);
        } else {
            const static uint8_t HEX_CHARS[] = "0123456789abcdef";
            uint8_t buffer[0x06];
            buffer[0] = '\\';
            buffer[1] = 'u';
            int i;
            for (i = 6 - 1; i > 1; i--) {
                buffer[i] = HEX_CHARS[c & 0x0F];
                c >>= 4;
            }
            CFDataAppendBytes(data, buffer, 6);
        }
    }
    CFDataAppendBytes(data, (uint8_t*)&"\"", 1);
}

void appendArrayElementToData(CFTypeRef element, DataAndFlag* dataAndFlag)
{
    appendObjectToData(element, dataAndFlag->data);
    if (--dataAndFlag->flag > 0) {
        CFDataAppendBytes(dataAndFlag->data, (uint8_t*)&",", 1);
    }
}

void appendKeyValuePairToData(CFTypeRef key, CFTypeRef value, DataAndFlag* dataAndFlag)
{
    if (CFGetTypeID(key) != CFStringGetTypeID()) {
        [NSException raise:NSInvalidArgumentException format:@"The keys of a dictionary must be strings."];
    }
    appendStringToData(key, dataAndFlag->data);
    CFDataAppendBytes(dataAndFlag->data, (uint8_t*)&":", 1);
    appendObjectToData(value, dataAndFlag->data);
    if (--dataAndFlag->flag > 0) {
        CFDataAppendBytes(dataAndFlag->data, (uint8_t*)&",", 1);
    }
}

void appendNumberToData(CFTypeRef number, CFMutableDataRef data)
{
    CFStringRef string = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@"), number);
    char buffer[0x100];
    CFStringGetCString(string, buffer, sizeof(buffer), kCFStringEncodingUTF8);
    CFDataAppendBytes(data, (void*)buffer, strlen(buffer));
    CFRelease(string);
}

void appendObjectToData(CFTypeRef object, CFMutableDataRef data)
{
    CFTypeID type = CFGetTypeID(object);
    if (CFArrayGetTypeID() == type) {
        DataAndFlag dataAndFlag = {
            data,
            CFDictionaryGetCount(object)
        };
        CFDataAppendBytes(data, (uint8_t*)&"[", 1);
        CFIndex count = CFArrayGetCount(object);
        if (count) {
            CFArrayApplyFunction(object, CFRangeMake(0, count), (CFArrayApplierFunction)&appendArrayElementToData, &dataAndFlag);
        }
        CFDataAppendBytes(data, (uint8_t*)&"]", 1);
    } else if (CFDictionaryGetTypeID() == type) {
        DataAndFlag dataAndFlag = {
            data,
            CFDictionaryGetCount(object)
        };
        CFDataAppendBytes(data, (uint8_t*)&"{", 1);
        CFDictionaryApplyFunction(object, (CFDictionaryApplierFunction)&appendKeyValuePairToData, &dataAndFlag);
        CFDataAppendBytes(data, (uint8_t*)&"}", 1);
    } else if (CFBooleanGetTypeID() == type) {
        if (kCFBooleanTrue == object) {
            CFDataAppendBytes(data, (uint8_t*)&"true", 4);
        } else {
            CFDataAppendBytes(data, (uint8_t*)&"false", 5);
        }
    } else if (CFNullGetTypeID() == type) {
        CFDataAppendBytes(data, (uint8_t*)&"null", 4);
    } else if (CFNumberGetTypeID() == type) {
        appendNumberToData(object, data);
    } else if (CFStringGetTypeID() == type) {
        appendStringToData(object, data);
    } else {
        [NSException raise:NSInvalidArgumentException format:@"Unsupported object-type encountered (%@).  Supported types are: NSArray, NSDictionary, NSNumber, NSNull and NSString.", (__bridge_transfer NSString*)CFCopyTypeIDDescription(type)];
    }
}

@implementation NSData (JSONKit)

+ (id) dataWithObjectAsJSON:(id)object
{
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    appendObjectToData((__bridge CFTypeRef)object, data);
    return CFBridgingRelease(data);
}

@end

@implementation NSString (JSONKit)

+ (id) stringWithObjectAsJSON:(id)object
{
    NSString* result = nil;
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    if (data) {
        appendObjectToData((__bridge CFTypeRef)object, data);
        result = [[NSString alloc] initWithData:(__bridge NSData*)data encoding:NSUTF8StringEncoding];
        CFRelease(data);
    }
    return result;
}

@end

#pragma mark Decoding
 
static NSInteger nextToken(CFStringRef json, CFIndex jsonLength, CFIndex* jsonIndex, CFTypeRef* object);
static CFArrayRef createArrayByParsingJSON(CFStringRef json, CFIndex jsonLength, CFIndex* jsonIndex);
static CFDictionaryRef createDictionaryByParsingJSON(CFStringRef json, CFIndex jsonLength, CFIndex* jsonIndex);

enum {
    T_EOF,
    /**/
    T_COLON,
    T_COMMA,
    T_LBRACKET,
    T_RBRACKET,
    T_LBRACE,
    T_RBRACE,
    T_NUMBER,
    T_STRING,
    T_TRUE,
    T_FALSE,
    T_NULL,
};

NSInteger nextToken(CFStringRef json, CFIndex jsonLength, CFIndex* jsonIndex, CFTypeRef* object)
{
    CFIndex i = *jsonIndex;
    if (jsonLength <= i) {
        return T_EOF;
    }
    int c = CFStringGetCharacterAtIndex(json, i++);
    while (' ' == c || '\t' == c || '\v' == c || '\f' == c || '\n' == c || '\r' == c) {
        if (jsonLength <= i) {
            return T_EOF;
        }
        c = CFStringGetCharacterAtIndex(json, i++);
    }
    switch (c) {
        case ':': {
            *jsonIndex = i;
            return T_COLON;
        }
        
        case ',': {
            *jsonIndex = i;
            return T_COMMA;
        }

        case '[': {
            *jsonIndex = i;
            return T_LBRACKET;
        }
        
        case ']': {
            *jsonIndex = i;
            return T_RBRACKET;
        }

        case '{': {
            *jsonIndex = i;
            return T_LBRACE;
        }
        
        case '}': {
            *jsonIndex = i;
            return T_RBRACE;
        }
        
        case '\"': {
            const int bufferLength = 0x1000;
            int bufferPosition = 0;
            UniChar buffer[bufferLength];
            CFMutableStringRef string = CFStringCreateMutable(NULL, 0);
            c = CFStringGetCharacterAtIndex(json, i++);
            while ('\"' != c) {
                if ('\\' == c) {
                    c = CFStringGetCharacterAtIndex(json, i++);
                    switch (c) {
                        case '\"':
                        case '\\':
                        case '/': {
                            break;
                        }
                        
                        case 'b': {
                            c = '\b';
                            break;
                        }
                        
                        case 'f': {
                            c = '\f';
                            break;
                        }
                        
                        case 'n': {
                            c = '\n';
                            break;
                        }
                        
                        case 'r': {
                            c = '\r';
                            break;
                        }
                        
                        case 't': {
                            c = '\t';
                            break;
                        }
                        
                        case 'u': {
                            c = 0;
                            int j;
                            for (j = 0; j < 4; j++) {
                                c <<= 4;
                                int digit = CFStringGetCharacterAtIndex(json, i++);
                                if ('0' <= digit && '9' >= digit) {
                                    c |= (digit - '0');
                                } else if ('A' <= digit && 'F' >= digit) {
                                    c |= ((digit - 'A') + 10);
                                } else if ('a' <= digit && 'f' >= digit) {
                                    c |= ((digit - 'a') + 10);
                                } else {
                                    *jsonIndex = i;
                                    CFRelease(string);
                                    [NSException raise:NSCharacterConversionException format:@"%s(%d)", __FILE__, __LINE__];
                                }
                            }
                            break;
                        }
                    }
                }
                buffer[bufferPosition++] = c;
                if (bufferPosition >= bufferLength) {
                    CFStringAppendCharacters(string, buffer, bufferPosition);
                    bufferPosition = 0;
                }
                c = CFStringGetCharacterAtIndex(json, i++);
            }
            if (bufferPosition) {
                CFStringAppendCharacters(string, buffer, bufferPosition);
            }
            if ('\"' != c) {
                CFRelease(string);
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
            *jsonIndex = i;
            if (object) {
                *object = string;
            } else {
                CFRelease(string);
            }
            return T_STRING;
        }
                
        case '-':
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9': {
            uint32_t digit = c - '0';
            uint32_t neg = '-' == c;
            if (neg) {
                digit = (c = CFStringGetCharacterAtIndex(json, i++)) - '0';
                if (digit > 9) {
                    *jsonIndex = i;
                    [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
                }
            }
            uint64_t l = digit;
            digit = (c = CFStringGetCharacterAtIndex(json, i++)) - '0';
            while (digit <= 9) {
                l = l * 10 + digit;
                digit = (c = CFStringGetCharacterAtIndex(json, i++)) - '0';
            }
            if ('.' == c || 'e' == c || 'E' == c) {
                double d = l;
                if ('.' == c) {
                    double f = 1.0;
                    l = 0;
                    digit = (c = CFStringGetCharacterAtIndex(json, i++)) - '0';
                    while (digit <= 9) {
                        l = l * 10 + digit;
                        f /= 10;
                        digit = (c = CFStringGetCharacterAtIndex(json, i++)) - '0';
                    }
                    d += (f * l);
                }
                if ('e' == c || 'E' == c) {
                    c = CFStringGetCharacterAtIndex(json, i++);
                    int eneg = '-' == c;
                    if (eneg || '+' == c) {
                        c = CFStringGetCharacterAtIndex(json, i++);
                    }
                    digit = c - '0';
                    if (digit > 9) {
                        *jsonIndex = i;
                        [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
                    }
                    int e = digit;
                    digit = (c = CFStringGetCharacterAtIndex(json, i++)) - '0';
                    while (digit <= 9) {
                        e = e * 10 + digit; 
                        digit = (c = CFStringGetCharacterAtIndex(json, i++)) - '0';
                    }
                    d = d * pow(10, eneg ? -e : e);
                }
                if (neg) {
                    d = -d;
                }
                if (object) {
                    *object = CFNumberCreate(NULL, kCFNumberDoubleType, &d);
                }
            } else {
                if (neg) {
                    l = -l;
                }
                if (object) {
                    *object = CFNumberCreate(NULL, kCFNumberLongLongType, &l);
                }
            }
            *jsonIndex = i - 1;
            return T_NUMBER;
        }
        
        case 't': {
            if ('r' != CFStringGetCharacterAtIndex(json, i++) || 'u' != CFStringGetCharacterAtIndex(json, i++) || 'e' != CFStringGetCharacterAtIndex(json, i++)) {
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
            if (i < jsonLength && isalnum(CFStringGetCharacterAtIndex(json, i))) {
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
            *jsonIndex = i;
            if (object) {
                *object = kCFBooleanTrue;
            }
            return T_TRUE;
        }
        
        case 'f': {
            if ('a' != CFStringGetCharacterAtIndex(json, i++) || 'l' != CFStringGetCharacterAtIndex(json, i++) || 's' != CFStringGetCharacterAtIndex(json, i++) || 'e' != CFStringGetCharacterAtIndex(json, i++)) {
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
            if (i < jsonLength && isalnum(CFStringGetCharacterAtIndex(json, i))) {
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
            *jsonIndex = i;
            if (object) {
                *object = kCFBooleanFalse;
            }
            return T_FALSE;
        }
        
        case 'n': {
            if ('u' != CFStringGetCharacterAtIndex(json, i++) || 'l' != CFStringGetCharacterAtIndex(json, i++) || 'l' != CFStringGetCharacterAtIndex(json, i++)) {
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
            if (i < jsonLength && isalnum(CFStringGetCharacterAtIndex(json, i))) {
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
            *jsonIndex = i;
            if (object) {
                *object = kCFNull;
            }
            return T_NULL;
        }
    }
    
    *jsonIndex = i;
    [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
    return T_EOF;
}

CFArrayRef createArrayByParsingJSON(CFStringRef json, CFIndex jsonLength, CFIndex* jsonIndex)
{
    NSUInteger token;
    CFTypeRef object = NULL;
    CFMutableArrayRef array = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (T_RBRACKET != (token = nextToken(json, jsonLength, jsonIndex, &object))) {
        do {
            switch (token) {
                case T_LBRACE: {
                    object = createDictionaryByParsingJSON(json, jsonLength, jsonIndex);
                    break;
                }

                case T_LBRACKET: {
                    object = createArrayByParsingJSON(json, jsonLength, jsonIndex);
                    break;
                }
                
                case T_TRUE:
                case T_FALSE:
                case T_NULL:
                case T_NUMBER:
                case T_STRING: {
                    /* nothing to do */
                    break;
                }
                
                default: {
                    [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
                }
            }
            CFArrayAppendValue(array, object);
            CFRelease(object);
            token = nextToken(json, jsonLength, jsonIndex, NULL);
            if (T_RBRACKET == token) {
                break;
            } else if (T_COMMA == token) {
                token = nextToken(json, jsonLength, jsonIndex, &object);
            } else {
                [NSException raise:NSParseErrorException format:@"Comma expected"];
            }
        } while (T_RBRACKET != token);
    }
    return array;
}

CFDictionaryRef createDictionaryByParsingJSON(CFStringRef json, CFIndex jsonLength, CFIndex* jsonIndex)
{
    CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef key;
    NSUInteger token;
    while (T_RBRACE != (token = nextToken(json, jsonLength, jsonIndex, &key))) {
        if (T_STRING != token) {
            [NSException raise:NSParseErrorException format:@"String/Key expected"];
        }
        if (T_COLON != (token = nextToken(json, jsonLength, jsonIndex, NULL))) {
            [NSException raise:NSParseErrorException format:@"Colon expected"];
        }
        CFTypeRef object;
        switch (token = nextToken(json, jsonLength, jsonIndex, &object)) {
            case T_LBRACE: {
                object = createDictionaryByParsingJSON(json, jsonLength, jsonIndex);
                break;
            }

            case T_LBRACKET: {
                object = createArrayByParsingJSON(json, jsonLength, jsonIndex);
                break;
            }
            
            case T_TRUE:
            case T_FALSE:
            case T_NULL:
            case T_NUMBER:
            case T_STRING: {
                /* nothing to do */
                break;
            }
            
            default: {
                [NSException raise:NSParseErrorException format:@"%s(%d)", __FILE__, __LINE__];
            }
        }
        CFDictionarySetValue(dictionary, key, object);
        CFRelease(object);
        CFRelease(key);
        token = nextToken(json, jsonLength, jsonIndex, NULL);
        if (T_RBRACE == token) {
            break;
        } else if (T_COMMA != token) {
            [NSException raise:NSParseErrorException format:@"Comma expected"];
        }
    }
    return dictionary;
}

@implementation NSDictionary (JSONKit)

+ (id) dictionaryWithJSON:(NSString*)json;
{
    CFIndex jsonLength = [json length];
    CFIndex jsonIndex = 0;
    if (T_LBRACE != nextToken((__bridge CFStringRef)json, jsonLength, &jsonIndex, NULL)) {
        return nil;
    }
    return CFBridgingRelease(createDictionaryByParsingJSON((__bridge CFStringRef)json, jsonLength, &jsonIndex));
}

@end

@implementation NSArray (JSONKit)

+ (id) arrayWithJSON:(NSString*)json
{
    CFIndex jsonLength = [json length];
    CFIndex jsonIndex = 0;
    if (T_LBRACKET != nextToken((__bridge CFStringRef)json, jsonLength, &jsonIndex, NULL)) {
        return nil;
    }
    return CFBridgingRelease(createArrayByParsingJSON((__bridge CFStringRef)json, jsonLength, &jsonIndex));
}

@end

@implementation NSObject (JSONKit)

+ (id) objectWithJSON:(NSString*)json
{
    CFIndex jsonLength = [json length];
    CFIndex jsonIndex = 0;
    CFTypeRef object = NULL;
    NSUInteger token = nextToken((__bridge CFStringRef)json, jsonLength, &jsonIndex, &object);
    switch (token) {
        case T_LBRACE: {
            object = createDictionaryByParsingJSON((__bridge CFStringRef)json, jsonLength, &jsonIndex);
            break;
        }

        case T_LBRACKET: {
            object = createArrayByParsingJSON((__bridge CFStringRef)json, jsonLength, &jsonIndex);
            break;
        }
        
        case T_TRUE:
        case T_FALSE:
        case T_NULL:
        case T_NUMBER:
        case T_STRING: {
            /* nothing to do */
            return nil;
        }
        
        default: {
            if (object) {
                CFRelease(object);
            }
            return nil;
        }
    }
    return CFBridgingRelease(object);
}

@end
