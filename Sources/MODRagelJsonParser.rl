//
//  MODRagelJsonParser.m
//  MongoObjCDriver
//
//  Created by Jérôme Lebel on 01/09/2013.
//
//

#import "MODRagelJsonParser.h"
#import "MODSortedDictionary.h"
#import "MODMaxKey.h"
#import "MODMinKey.h"
#import "MODUndefined.h"
#import "MODObjectId.h"
#import "MODRegex.h"
#import "MongoObjCDriver-private.h"
#import "MODBinary.h"
#import "MODTimestamp.h"
#import "MODSymbol.h"

#pragma clang diagnostic ignored "-Wunused-variable"

@interface MODRagelJsonParser ()
@property (nonatomic, strong, readwrite) NSError *error;

@end

@implementation MODRagelJsonParser (private)

+ (BOOL)bsonFromJson:(bson_t *)bsonResult json:(NSString *)json error:(NSError **)outputError
{
    NSError *error = nil;
    id object = [self objectsFromJson:json withError:&error];
    
    if (object && !error && [object isKindOfClass:NSArray.class]) {
        object = [MODSortedDictionary sortedDictionaryWithObject:object forKey:@"array"];
    }
    if (object && !error && [object isKindOfClass:MODSortedDictionary.class]) {
        [MODClient appendObject:object toBson:bsonResult];
    }
    if (outputError) {
        *outputError = error;
    }
    return !error;
}

@end

@implementation MODRagelJsonParser

@synthesize error = _error;

+ (id)objectsFromJson:(NSString *)source withError:(NSError **)error
{
    MODRagelJsonParser *parser = [[self alloc] init];
    id result;
    
    result = [parser parseJson:source withError:error];
    MOD_RELEASE(parser);
    return result;
}

- (void)_makeErrorWithMessage:(NSString *)message atPosition:(const char *)position
{
    if (!self.error) {
        NSUInteger length;
        
        length = strlen(position);
        if (length > 10) {
            length = 10;
        }
        self.error = [NSError errorWithDomain:@"error" code:0 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: \"%@\"", message, MOD_AUTORELEASE([[NSString alloc] initWithBytes:position length:length encoding:NSUTF8StringEncoding])] }];
    }
}

%%{
    machine JSON_common;

    ws                  = [ \t\r\n];
    ignore              = ws;
    name_separator      = ':';
    value_separator     = ',';
    Vundefined          = 'undefined';
    Vnull               = 'null';
    Vfalse              = 'false';
    Vtrue               = 'true';
    VMinKey             = 'MinKey';
    VMaxKey             = 'MaxKey';
    VNumberPosInfinity  = 'Number.POSITIVE_INFINITY';
    VNumberNegInfinity  = 'Number.NEGATIVE_INFINITY';
    VNumberNan          = 'Number.NaN';
    new_keyword         = 'new';
    begin_value         = [/unftTMFBOSDN'\"\-\[\{] | digit;
    begin_object        = '{';
    end_object          = '}';
    begin_array         = '[';
    end_array           = ']';
    begin_string        = '"' | '\'';
    begin_name          = begin_string | [a-z] | [A-Z] | '$' | '_' | '#' | [0-9];
    begin_number        = digit | '-';
    begin_regexp        = '/';
    begin_object_id     = 'O';
    object_id_keyword   = 'ObjectId';
    numberlong_keyword  = 'NumberLong';
    begin_timestamp     = 'T';
    timestamp_keyword   = 'Timestamp';
    begin_bindata       = 'B';
    bin_data_keyword    = 'BinData';
    symbol_keyword      = 'Symbol';
    begin_function      = 'F';
    function_keyword    = 'Function';
    scopefunction_keyword = 'ScopeFunction';
    begin_dbref         = 'D';
    dbref_keyword       = 'DBPointer';
}%%

%%{
    machine JSON_value;
    include JSON_common;

    write data;

    action parse_null {
        *result = [NSNull null];
    }
    action parse_false {
        *result = [NSNumber numberWithBool:NO];
    }
    action parse_true {
        *result = [NSNumber numberWithBool:YES];
    }

    action parse_min_key {
        *result = MOD_AUTORELEASE([[MODMinKey alloc] init]);
    }

    action parse_max_key {
        *result = MOD_AUTORELEASE([[MODMaxKey alloc] init]);
    }
    
    action parse_undefined {
        *result = MOD_AUTORELEASE([[MODUndefined alloc] init]);
    }
    
    action parse_number_positive_infinity {
        *result = [NSNumber numberWithDouble:INFINITY];
    }
    
    action parse_number_negative_infinity {
        *result = [NSNumber numberWithDouble:-INFINITY];
    }
    
    action parse_number_nan {
        *result = [NSNumber numberWithDouble:NAN];
    }
    
    action parse_object_id {
        const char *np = [self _parseObjectIdWithPointer:fpc endPointer:pe result:result];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_string {
        const char *np = [self _parseStringWithPointer:fpc endPointer:pe result:result];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_number {
        const char *np;
        np = [self _parseFloatWithPointer:fpc endPointer:pe result:result];
        if (np != NULL) fexec np;
        np = [self _parseIntegerWithPointer:fpc endPointer:pe result:result];
        if (np != NULL) fexec np;
        fhold; fbreak;
    }

    action parse_array {
        const char *np;
        _currentNesting++;
        np = [self _parseArrayWithPointer:fpc endPointer:pe result:result];
        _currentNesting--;
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_object {
        const char *np;
        _currentNesting++;
        np = [self _parseObjectWithPointer:fpc endPointer:pe result:result];
        _currentNesting--;
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action parse_regexp {
        const char *np = [self _parseRegexpWithPointer:fpc endPointer:pe result:result];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action parse_numberlong {
        const char *np = [self _parseNumberLongWithPointer:fpc - strlen("NumberLong") + 1 endPointer:pe result:result];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action parse_timestamp {
        const char *np = [self _parseTimestampWithPointer:fpc endPointer:pe result:result];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action parse_bin_data {
        const char *np = [self _parseBinDataWithPointer:fpc endPointer:pe result:result];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }
    
    action parse_symbol {
        const char *np = [self _parseSymbolWithPointer:fpc - strlen("Symbol") + 1 endPointer:pe result:result];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }
    
    action parse_function {
        const char *np = [self _parseFunctionWithPointer:fpc endPointer:pe result:result];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }
    
    action parse_dbref {
        const char *np = [self _parseDBPointerWithPointer:fpc endPointer:pe result:result];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }
    
    action parse_scopefunction {
        const char *np = [self _parseScopeFunctionWithPointer:fpc - strlen("ScopeFunction") + 1 endPointer:pe result:result];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }
    
    action parse_javascript_object {
        const char *np = [self _parseJavascriptObjectWithPointer:fpc - 2 endPointer:pe result:result];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }

    action exit { fhold; fbreak; }

    main := (
        Vnull @parse_null |
        Vfalse @parse_false |
        Vtrue @parse_true |
        VMinKey @parse_min_key |
        VMaxKey @parse_max_key |
        Vundefined @parse_undefined |
        VNumberPosInfinity @parse_number_positive_infinity |
        VNumberNegInfinity @parse_number_negative_infinity |
        VNumberNan @parse_number_nan |
        begin_object_id >parse_object_id |
        begin_number >parse_number |
        begin_string >parse_string |
        begin_array >parse_array |
        begin_object >parse_object |
        begin_regexp >parse_regexp |
        numberlong_keyword @parse_numberlong |
        begin_timestamp >parse_timestamp |
        begin_bindata >parse_bin_data |
        scopefunction_keyword @parse_scopefunction |
        symbol_keyword @parse_symbol |
        begin_function >parse_function |
        begin_dbref >parse_dbref |
        new_keyword @parse_javascript_object
    ) %*exit;
}%%

- (const char *)_parseValueWithPointer:(const char *)p endPointer:(const char *)pe result:(id *)result
{
    int cs = 0;

    %% write init;
    %% write exec;

    if (*result == nil || cs < JSON_value_first_final) {
        [self _makeErrorWithMessage:@"cannot parse value" atPosition:p];
        return NULL;
    } else {
        return p;
    }
}

%%{
   machine JSON_integer;

   write data;

   action exit { fhold; fbreak; }

   main := '-'? ('0' | [1-9][0-9]*) (^[0-9]? @exit);
}%%

- (const char *)_parseIntegerWithPointer:(const char *)p endPointer:(const char *)pe result:(NSNumber **)result
{
    int cs = 0;
    const char *memo;

    %% write init;
    memo = p;
    %% write exec;

    if (cs >= JSON_integer_first_final) {
        NSString *buffer;
        
        buffer = [[NSString alloc] initWithBytes:(void *)memo length:p - memo encoding:NSUTF8StringEncoding];
        if (buffer.longLongValue > INT_MAX || buffer.longLongValue < INT_MIN) {
            *result = [NSNumber numberWithLongLong:buffer.longLongValue];
        } else {
            *result = [NSNumber numberWithInt:buffer.intValue];
        }
        MOD_RELEASE(buffer);
        return p + 1;
    } else {
        return NULL;
    }
}

%%{
   machine JSON_float;
   include JSON_common;

   write data;

   action exit { fhold; fbreak; }

   main := '-'? (
                 (('0' | [1-9][0-9]*) '.' [0-9]+ ([Ee] [+\-]?[0-9]+)?)
                 | (('0' | [1-9][0-9]*) ([Ee] [+\-]?[0-9]+))
                 )  (^[0-9Ee.\-]? @exit );
}%%

- (const char *)_parseFloatWithPointer:(const char *)p endPointer:(const char *)pe result:(NSNumber **)result
{
    int cs = 0;
    const char *memo;
    
    %% write init;
    memo = p;
    %% write exec;

    if (cs >= JSON_float_first_final) {
        NSUInteger length = p - memo;
        char *buffer;
        double value;
        
        buffer = malloc(length + 1);
        strncpy(buffer, memo, length);
        sscanf(buffer, "%lf", &value);
        *result = [NSNumber numberWithDouble:value];
        free(buffer);
        return p + 1;
    } else {
        return NULL;
    }
}

%%{
    machine JSON_object;
    include JSON_common;

    write data;

    action parse_value {
        id value = nil;
        const char *np = [self _parseValueWithPointer:fpc endPointer:pe result:&value];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            [dictionary setObject:value forKey:lastName];
            fexec np;
        }
    }

    action parse_name {
        const char *np;
        
        np = [self _parseWordWithPointer:fpc endPointer:pe result:&lastName];
        if (np == NULL) {
            np = [self _parseStringWithPointer:fpc endPointer:pe result:&lastName];
        }
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action exit { fhold; fbreak; }

    pair  = ignore* begin_name >parse_name ignore* name_separator ignore* begin_value >parse_value;
    next_pair   = ignore* value_separator pair;
     
    main := (
        begin_object
        (pair (next_pair)*)? ignore*
        end_object
    ) @exit;
}%%

- (const char *)_parseObjectWithPointer:(const char *)p endPointer:(const char *)pe result:(MODSortedDictionary **)result
{
    int cs = 0;
    NSString *lastName;
    MODSortedMutableDictionary *dictionary;

    if (_maxNesting && _currentNesting > _maxNesting) {
        [self _makeErrorWithMessage:[NSString stringWithFormat:@"nesting of %d is too deep", _currentNesting] atPosition:p];
    }
    
    dictionary = [MODSortedMutableDictionary sortedDictionary];
    
    %% write init;
    %% write exec;
    
    if (cs >= JSON_object_first_final) {
        MODSortedDictionary *tengen;
        
        tengen = [dictionary tengenJsonEncodedObject];
        if (tengen) {
            *result = tengen;
        } else {
            *result = dictionary;
        }
        return p + 1;
    } else {
        *result = nil;
        return NULL;
    }
}

%%{
    machine JSON_javascript_object;
    include JSON_common;

    write data;

    action parse_integer_value {
        const char *np;
        NSNumber *number;
        
        np = [self _parseIntegerWithPointer:fpc endPointer:pe result:&number];
        if (np != NULL && number) {
            [parameters addObject:number];
            np--; fexec np;
        } else {
            fhold; fbreak;
        }
    }
    
    action parse_string_value {
        const char *np;
        NSString *string = nil;
        
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&string];
        if (np != NULL && string) {
            [parameters addObject:string];
            fexec np;
        } else {
            fhold; fbreak;
        }
    }

    action exit { fhold; fbreak; }

    main := ( new_keyword ignore*
                (
                    'Date' ignore* '(' ignore* ( ( begin_string >parse_string_value ) | ( begin_number >parse_integer_value ignore* ( ',' ignore* begin_number >parse_integer_value ignore* )* ) )? ')'
//                ) | (
//                    'ISODate' ignore* '(' ignore* begin_string >parse_string_value ignore* ')'
                )
             ) @exit;
}%%

- (const char *)_parseJavascriptObjectWithPointer:(const char *)p endPointer:(const char *)pe result:(id *)result
{
    int cs = 0;
    NSMutableArray *parameters = [[NSMutableArray alloc] init];

    %% write init;
    %% write exec;

    if (cs >= JSON_javascript_object_first_final) {
        if (parameters.count == 1 && [[parameters objectAtIndex:0] isKindOfClass:NSString.class]) {
            NSDateFormatter *formater;
            
            formater = [[NSDateFormatter alloc] init];
            [formater setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
            *result = MOD_AUTORELEASE(MOD_RETAIN([formater dateFromString:[parameters objectAtIndex:0]]));
            MOD_RELEASE(formater);
        } else if (parameters.count == 1 && [[parameters objectAtIndex:0] isKindOfClass:NSNumber.class]) {
            *result = [NSDate dateWithTimeIntervalSince1970:[[parameters objectAtIndex:0] doubleValue] / 1000.0];
        }
    } else {
        *result = nil;
    }
    MOD_RELEASE(parameters);
    if (*result) {
        return p + 1;
    } else {
        [self _makeErrorWithMessage:@"cannot parse javascript object" atPosition:p];
        return NULL;
    }
}

%%{
    machine JSON_bin_data;
    include JSON_common;

    write data;
    
    action parse_data_value {
        const char *np;
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&dataStringValue];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action parse_type_value {
        const char *np;
        np = [self _parseIntegerWithPointer:fpc endPointer:pe result:&typeValue];
        if (np == NULL) { fhold; fbreak; } else { np--; fexec np; }
    }

    action exit { fhold; fbreak; }

    main := (bin_data_keyword ignore* '(' ignore* begin_number >parse_type_value ignore* ',' ignore* begin_string >parse_data_value ignore* ')') @exit;
}%%

- (const char *)_parseBinDataWithPointer:(const char *)p endPointer:(const char *)pe result:(MODBinary **)result
{
    NSString *dataStringValue = nil;
    NSNumber *typeValue = nil;
    NSData *dataValue = nil;
    int cs = 0;

    %% write init;
    %% write exec;

    dataValue = dataStringValue.mod_dataFromBase64;
    if (cs >= JSON_bin_data_first_final && dataValue && [MODBinary isValidDataType:typeValue.unsignedCharValue] ) {
        *result = MOD_AUTORELEASE([[MODBinary alloc] initWithData:dataValue binaryType:typeValue.unsignedCharValue]);
        return p + 1;
    } else {
        *result = nil;
        return NULL;
    }
}

%%{
    machine JSON_function;
    include JSON_common;

    write data;
    
    action parse_code_value {
        const char *np;
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&codeStringValue];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action exit { fhold; fbreak; }

    main := (function_keyword ignore* '(' ignore* begin_string >parse_code_value ignore* ')') @exit;
}%%

- (const char *)_parseFunctionWithPointer:(const char *)p endPointer:(const char *)pe result:(MODFunction **)result
{
    NSString *codeStringValue = nil;
    int cs = 0;

    %% write init;
    %% write exec;

    if (cs >= JSON_function_first_final && codeStringValue) {
        *result = MOD_AUTORELEASE([[MODFunction alloc] initWithFunction:codeStringValue]);
        return p + 1;
    } else {
        *result = nil;
        return NULL;
    }
}

%%{
    machine JSON_dbref;
    include JSON_common;

    write data;
    
    action parse_absolute_collection_name {
        const char *np;
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&collectionName];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action parse_document_id {
        const char *np;
        NSString *string = nil;
        
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&string];
        if (np == NULL) {
            fhold;
            fbreak;
        } else {
            if ([MODObjectId isStringValid:string]) {
                documentId = MOD_AUTORELEASE([[MODObjectId alloc] initWithString:string]);
            }
            fexec np;
        }
    }

    action exit { fhold; fbreak; }

    main := (dbref_keyword ignore* '(' ignore* begin_string >parse_absolute_collection_name ignore* ',' ignore* begin_string >parse_document_id ignore*')') @exit;
}%%

- (const char *)_parseDBPointerWithPointer:(const char *)p endPointer:(const char *)pe result:(MODDBPointer **)result
{
    NSString *collectionName = nil;
    MODObjectId *documentId = nil;
    int cs = 0;

    %% write init;
    %% write exec;

    if (cs >= JSON_dbref_first_final && collectionName && documentId) {
        *result = MOD_AUTORELEASE([[MODDBPointer alloc] initWithCollectionName:collectionName objectId:documentId]);
        return p + 1;
    } else {
        *result = nil;
        return NULL;
    }
}

%%{
    machine JSON_scopefunction;
    include JSON_common;

    write data;
    
    action parse_code_value {
        const char *np;
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&codeStringValue];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action parse_scope_value {
        const char *np;
        
        np = [self _parseObjectWithPointer:fpc endPointer:pe result:&scopeValue];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }

    action exit { fhold; fbreak; }

    main := (scopefunction_keyword ignore* '(' ignore* begin_string >parse_code_value ignore* ',' ignore* begin_object >parse_scope_value ignore* ')') @exit;
}%%

- (const char *)_parseScopeFunctionWithPointer:(const char *)p endPointer:(const char *)pe result:(MODScopeFunction **)result
{
    NSString *codeStringValue = nil;
    MODSortedDictionary *scopeValue = nil;
    int cs = 0;

    %% write init;
    %% write exec;

    if (cs >= JSON_scopefunction_first_final && codeStringValue) {
        *result = MOD_AUTORELEASE([[MODScopeFunction alloc] initWithFunction:codeStringValue scope:scopeValue]);
        return p + 1;
    } else {
        *result = nil;
        return NULL;
    }
}

%%{
    machine JSON_object_id;
    include JSON_common;

    write data;
    
    action parse_id_value {
        const char *np;
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&idStringValue];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action exit { fhold; fbreak; }

    main := (object_id_keyword ignore* '(' ignore* begin_string >parse_id_value ignore* ')') @exit;
}%%

- (const char *)_parseObjectIdWithPointer:(const char *)p endPointer:(const char *)pe result:(MODObjectId **)result
{
    NSString *idStringValue = nil;
    int cs = 0;

    %% write init;
    %% write exec;

    if (cs >= JSON_object_id_first_final && [MODObjectId isStringValid:idStringValue]) {
        *result = MOD_AUTORELEASE([[MODObjectId alloc] initWithString:idStringValue]);
        return p + 1;
    } else {
        *result = nil;
        return NULL;
    }
}

- (const char *)_parseRegexpWithPointer:(const char *)string endPointer:(const char *)stringEnd result:(MODRegex **)result
{
    const char *bookmark, *cursor;
    BOOL backslashJustBefore = NO;
    
    cursor = string + 1;
    bookmark = cursor;
    while (cursor < stringEnd && *cursor != '/' && !backslashJustBefore) {
        if (*cursor == '\\') {
            backslashJustBefore = YES;
        } else {
            backslashJustBefore = NO;
        }
        cursor++;
    }
    if (*cursor == '/') {
        NSString *buffer;
        NSString *options;
        
        buffer = [[NSString alloc] initWithBytes:(void *)bookmark length:cursor - bookmark encoding:NSUTF8StringEncoding];
        cursor++;
        
        bookmark = cursor;
        while (cursor < stringEnd && strchr("imsx", *cursor) != NULL) {
            cursor++;
        }
        options = [[NSString alloc] initWithBytes:(void *)bookmark length:cursor - bookmark encoding:NSUTF8StringEncoding];
        
        *result = MOD_AUTORELEASE([[MODRegex alloc] initWithPattern:buffer options:options]);
        MOD_RELEASE(buffer);
        MOD_RELEASE(options);
    } else {
        [self _makeErrorWithMessage:@"cannot find end of regex" atPosition:cursor];
        cursor = NULL;
    }
    return cursor;
}

%%{
    machine JSON_numberlong;
    include JSON_common;
    
    write data;
    
    action parse_numberlong_value {
        const char *np;
        np = [self _parseIntegerWithPointer:fpc endPointer:pe result:&numberValue];
        if (strcmp(numberValue.objCType, @encode(long long)) != 0) {
            numberValue = [NSNumber numberWithLongLong:numberValue.longLongValue];
        }
        np--; // WHY???
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    action exit { fhold; fbreak; }
    
    main := (numberlong_keyword ignore* '(' ignore* begin_number >parse_numberlong_value ignore* ')') @exit;
    
}%%

- (const char *)_parseNumberLongWithPointer:(const char *)p endPointer:(const char *)pe result:(NSNumber **)result
{
    NSNumber *numberValue = nil;
    int cs = 0;
    
    %% write init;
    %% write exec;
    
    if (cs >= JSON_numberlong_first_final && numberValue) {
        *result = numberValue;
        return p + 1; // why + 1 ???
    } else {
        *result = nil;
        return NULL;
    }
}

%%{
    machine JSON_timestamp;
    include JSON_common;

    write data;

    action parse_time_value {
        const char *np;
        np = [self _parseIntegerWithPointer:fpc endPointer:pe result:&timeNumber];
        np--; // WHY???
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_increment_value {
        const char *np;
        np = [self _parseIntegerWithPointer:fpc endPointer:pe result:&incrementNumber];
        if (np == NULL) { fhold; fbreak; } else { np--; fexec np; }
    }

    action exit { fhold; fbreak; }

    main := (timestamp_keyword ignore* '(' ignore* begin_number >parse_time_value ignore* ',' ignore* begin_number >parse_increment_value ignore* ')') @exit;
}%%

- (const char *)_parseTimestampWithPointer:(const char *)p endPointer:(const char *)pe result:(MODTimestamp **)result
{
    NSNumber *timeNumber = nil;
    NSNumber *incrementNumber = nil;
    int cs = 0;
    
    %% write init;
    %% write exec;
    
    if (cs >= JSON_timestamp_first_final && timeNumber && incrementNumber) {
        *result = MOD_AUTORELEASE([[MODTimestamp alloc] initWithTValue:timeNumber.intValue iValue:incrementNumber.intValue]);
        return p + 1; // why + 1 ???
    } else {
        *result = nil;
        return NULL;
    }
}

%%{
    machine JSON_symbol;
    include JSON_common;

    write data;

    action parse_string_value {
        const char *np;
        np = [self _parseStringWithPointer:fpc endPointer:pe result:&symbol];
        if (np == NULL) { fhold; fbreak; } else { fexec np; }
    }

    action exit { fhold; fbreak; }

    main := (symbol_keyword ignore* '(' ignore* begin_string >parse_string_value ignore* ')') @exit;
}%%

- (const char *)_parseSymbolWithPointer:(const char *)p endPointer:(const char *)pe result:(MODSymbol **)result
{
    NSString *symbol = nil;
    int cs = 0;
    
    %% write init;
    %% write exec;
    
    if (cs >= JSON_symbol_first_final && symbol) {
        *result = MOD_AUTORELEASE([[MODSymbol alloc] initWithValue:symbol]);
        return p + 1; // why + 1 ???
    } else {
        *result = nil;
        return NULL;
    }
}

- (const char *)_parseWordWithPointer:(const char *)string endPointer:(const char *)stringEnd result:(NSString **)result
{
    NSString *buffer;
    const char *cursor;
    NSCharacterSet *wordCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890_$#"];
    NSCharacterSet *numberCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"1234567890"];
    BOOL digitOnly = [numberCharacterSet characterIsMember:string[0]];
    
    cursor = string;
    while (cursor < stringEnd && ((digitOnly && [numberCharacterSet characterIsMember:cursor[0]]) || (!digitOnly && [wordCharacterSet characterIsMember:cursor[0]]))) {
        cursor++;
    }
    if (cursor == string) {
        cursor = NULL;
        *result = NULL;
    } else {
        buffer = [[NSString alloc] initWithBytes:(void *)string length:cursor - string encoding:NSUTF8StringEncoding];
        *result = buffer;
        MOD_AUTORELEASE2(buffer);
    }
    return cursor;
}

- (const char *)_parseStringWithPointer:(const char *)string endPointer:(const char *)stringEnd result:(NSString **)result
{
    NSMutableString *mutableResult;
    const char *unescape, *bookmark, *cursor;
    int unescapeLength;
    char quoteString;
    NSString *buffer;
    
    mutableResult = [[NSMutableString alloc] init];
    quoteString = string[0];
    cursor = string + 1;
    bookmark = cursor;
    while (cursor < stringEnd && *cursor != quoteString) {
        if (*cursor == '\\') {
            unescape = (char *) "?";
            unescapeLength = 1;
            if (cursor > bookmark) {
                // if the string starts with a \, there is no need to add anything
                buffer = [[NSString alloc] initWithBytes:(void *)bookmark length:cursor - bookmark encoding:NSUTF8StringEncoding];
                [mutableResult appendString:buffer];
                MOD_RELEASE(buffer);
            }
            switch (*++cursor) {
                case 'n':
                    unescape = (char *) "\n";
                    break;
                case 'r':
                    unescape = (char *) "\r";
                    break;
                case 't':
                    unescape = (char *) "\t";
                    break;
                case '"':
                    unescape = (char *) "\"";
                    break;
                case '\'':
                    unescape = (char *) "'";
                    break;
                case '\\':
                    unescape = (char *) "\\";
                    break;
                case 'b':
                    unescape = (char *) "\b";
                    break;
                case 'f':
                    unescape = (char *) "\f";
                    break;
                default:
                    // take it as a regular character
                    bookmark = cursor;
                    continue;
            }
            buffer = [[NSString alloc] initWithBytes:(void *)unescape length:unescapeLength encoding:NSUTF8StringEncoding];
            [mutableResult appendString:buffer];
            MOD_RELEASE(buffer);
            bookmark = ++cursor;
        } else {
            cursor++;
        }
    }
    if (*cursor == quoteString) {
        buffer = [[NSString alloc] initWithBytes:(void *)bookmark length:cursor - bookmark encoding:NSUTF8StringEncoding];
        [mutableResult appendString:buffer];
        MOD_RELEASE(buffer);
        *result = MOD_AUTORELEASE(mutableResult);
        cursor++;
    } else {
        cursor = NULL;
        [self _makeErrorWithMessage:@"cannot find end of string" atPosition:cursor];
    }
    return cursor;
}

%%{
    machine JSON_array;
    include JSON_common;
    
    write data;
    
    action parse_value {
        id value;
        const char *np = [self _parseValueWithPointer:fpc endPointer:pe result:&value];
        if (np == NULL) {
            fhold; fbreak;
        } else {
            [*result addObject:value];
            fexec np;
        }
    }
    
    action exit { fhold; fbreak; }
    
    next_element  = value_separator ignore* begin_value >parse_value;
    
    main := begin_array ignore*
    ((begin_value >parse_value ignore*)
     (ignore* next_element ignore*)*)?
    end_array @exit;
}%%

- (const char *)_parseArrayWithPointer:(const char *)p endPointer:(const char *)pe result:(NSMutableArray **)result
{
    int cs = 0;
    
    if (_maxNesting && _currentNesting > _maxNesting) {
        [self _makeErrorWithMessage:[NSString stringWithFormat:@"nesting of %d is too deep", _currentNesting] atPosition:p];
    }
    *result = MOD_AUTORELEASE([[NSMutableArray alloc] init]);
    
    %% write init;
    %% write exec;
    
    if(cs >= JSON_array_first_final) {
        return p + 1;
    } else {
        [self _makeErrorWithMessage:@"Unexpected character" atPosition:p];
        return NULL;
    }
}

%%{
    machine JSON;

    write data;

    include JSON_common;

    action parse_object {
        const char *np;
        _currentNesting = 1;
        np = [self _parseObjectWithPointer:fpc endPointer:pe result:&result];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_array {
        const char *np;
        _currentNesting = 1;
        np = [self _parseArrayWithPointer:fpc endPointer:pe result:&result];
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }
    
    main := ignore* (
        begin_object >parse_object |
        begin_array >parse_array
    ) ignore*;
}%%

- (id)parseJson:(NSString *)source withError:(NSError **)error
{
    const char *p, *pe;
    id result = nil;
    int cs = 0;
    
    self.error = nil;
    _cStringBuffer = [source UTF8String];
    %% write init;
    p = _cStringBuffer;
    pe = p + strlen(p);
    %% write exec;
    
    if (cs < JSON_first_final || p != pe) {
        result = nil;
        if (!self.error) {
            [self _makeErrorWithMessage:@"unexpected token" atPosition:p];
        }
    }
    if (error) {
        *error = self.error;
    }
    return result;
}

@end
