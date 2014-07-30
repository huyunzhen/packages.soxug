##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify mapper script general purpose module for Mac OS X.
#
##############################################################################

use strict;

package CentrifyDC::GP::Mac;
my $VERSION = '1.0';
require 5.000;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(CF_BOOL CF_INTEGER CF_REAL CF_STRING CF_DATE CF_DICTIONARY CF_ARRAY CF_DATA
                IsCF ToCF ToString
                GetObjectFromNSDictionary GetKeysFromNSDictionary UpdateNSMutableDictionary
                CreateNSMutableDictionaryFromHash CreateNSMutableArrayFromArray
                CreateHashFromNSDictionary CreateArrayFromNSArray
                GetMacOSVersion GetByHostIdentifier);
%EXPORT_TAGS = (
    'system'    => [qw(GetMacOSVersion GetByHostIdentifier)],
    'objc'      => [qw(CF_BOOL CF_INTEGER CF_REAL CF_STRING CF_DATE CF_DICTIONARY CF_ARRAY CF_DATA IsCF ToCF ToString CreateNSMutableDictionaryFromHash CreateNSMutableArrayFromArray CreateHashFromNSDictionary CreateArrayFromNSArray GetObjectFromNSDictionary GetKeysFromNSDictionary UpdateNSMutableDictionary)]);

use Foundation;

use CentrifyDC::GP::General qw(:debug IsEmpty RunCommand);

use constant {
    CF_BOOL         => 1,
    CF_INTEGER      => 2,
    CF_REAL         => 3,
    CF_STRING       => 4,
    CF_DATE         => 5,
    CF_DICTIONARY   => 6,
    CF_ARRAY        => 7,
    CF_DATA         => 8,
};

# system
sub GetMacOSVersion();
sub GetByHostIdentifier();

# objc
sub IsCF($;$);
sub ToCF($;$);
sub ToString($);
sub CreateNSMutableDictionaryFromHash($);
sub CreateNSMutableArrayFromArray($);
sub CreateHashFromNSDictionary($;$);
sub CreateArrayFromNSArray($;$);
sub GetObjectFromNSDictionary($$);
sub GetKeysFromNSDictionary($$);
sub UpdateNSMutableDictionary($$$$);

# private
sub _GetMacAddress($);
sub _CreateCFObjectFromString($;$);
sub _CreateCFDataFromBase64String($);


# >>> SYSTEM >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# get Mac OS X version based on uname -r
#       
# The sw_vers program can hang on 10.5, so don't use it.
# Instead, rely on the correlation between the kernel version
# and the OS version - the kernel version has been 4 higher
# than the OS minor version (e.g. 10.4.x is kernel version 8.x)
# from at least 10.2 through 10.5 - hopefully Apple won't change
# that on us.
#
#   return: hash reference of version
#               'major' => major version
#               'minor' => minor version
#               'trivia' => trivia version
#
sub GetMacOSVersion()
{
    my %ver = ();

    my $kernel_ver = `uname -r`;

    $kernel_ver =~ m/(\d*)\.(\d*)\.(\d)*/;

    $ver{'major'}  = '10.' . ($1 - 4);
    $ver{'minor'}  = $2;
    $ver{'trivia'} = $3;

    TRACE_OUT("Mac OS X version: major: [$ver{'major'}] minor: [$ver{'minor'}] trivia: [$ver{'trivia'}]");

    return \%ver;
}

#
# get ByHost plist file's identifier
#
# this identifier is in the filename of byhost plist:
#   ~username/Library/Preferences/ByHost/com.apple.screensaver.<identifier>.plist
#
# in 10.3/10.4/10.5 it's MAC address of en0.
#
# it is said that new ByHost files will use different schema (UUID), so
# we may need to update this function in the future.
#
# to get the UUID, use
#
#   ioreg -rd1 -c IOPlatformExpertDevice | grep UUID
#
#   return: string  - mac address (format: 000a0b0c0d0e)
#           undef   - failed
#
sub GetByHostIdentifier()
{
    my $identifier = _GetMacAddress('en0');

    if (defined($identifier))
    {
        TRACE_OUT("ByHost preference identifier: [$identifier]");
    }
    else
    {
        ERROR_OUT("Cannot get ByHost preference identifier");
    }

    return $identifier;
}

# <<< SYSTEM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> OBJC >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# check if an object is Core Foundation object.
#
# if type is specified, check if CF object is specified type
#
#   $_[0]:  object
#   $_[1]:  type (optional)
#
#   return: 0       no
#           1       yes
#           undef   failed
#
sub IsCF($;$)
{
    my ($object, $type) = @_;

    defined($object) or return 0;

    my $data_type = ref($object);

    $data_type or return 0;
    # On 10.7 the plist data type is __NS*
    # Prior 10.7, the plist data type is __NSCF
    # Therefore, we allow NS object as well in order to make our current
    # GPs work
    index($data_type, 'NS') >= 0 or return 0;

    # no need to check type if type not specified
    $type or return 1;

    if ($type == CF_BOOL)
    {
        # on 10.7 date type is __NSCFBoolean
        # DO NOT use objCType, it's implementation dependent
        index($data_type, 'NSCFBoolean') >= 0 and return 1;
    }
    elsif ($type == CF_REAL or $type == CF_INTEGER)
    {
        # on 10.7 date type is __NSCFNumber
        index($data_type, 'NSCFNumber') >= 0 and return 1;
    }
    elsif ($type == CF_DATE)
    {
        # on 10.5 date type is __NSCFDate
        ($object->isKindOfClass_(NSDate->class)) and return 1;
    }
    elsif ($type == CF_STRING)
    {
        # on 10.7 date type is __NSString
        ($object->isKindOfClass_(NSString->class)) and return 1;
        #($data_type eq 'NSCFString') and return 1;
    }
    elsif ($type == CF_DICTIONARY)
    {
        # on 10.7 date type is __NSCFDictionary
        ($object->isKindOfClass_(NSDictionary->class)) and return 1;
        #($data_type eq 'NSCFDictionary') and return 1;
    }
    elsif ($type == CF_ARRAY)
    {
        # on 10.7 date type is __NSArrayM
        ($object->isKindOfClass_(NSArray->class)) and return 1;
        #($data_type eq 'NSCFArray') and return 1;
    }
    elsif ($type == CF_DATA)
    {
        index($data_type, 'NSCFData') >= 0 and return 1;
    }
    else
    {
        ERROR_OUT("IsCF: unknown type: [$type]");
        return undef;
    }

    return 0;
}

#
# convert perl object to Core Foundation object
#
# if perl object is a hash/array, make sure that its members' data type are set
# correctly, else all its member will be converted to CFString.
#
#   $_[0]:  perl object (string/hash/array/scalar)
#   $_[1]:  type (optional for hash/array/string)
#
#   return: Core Foundation object
#           undef   - failed or source object is undef
#
sub ToCF($;$)
{
    my ($data, $type) = @_;

    defined($data) or return undef;

    # already a Core Foundation object
    IsCF($data) and return $data;

    my $data_type = ref($data);

    if (! $data_type)
    {
        return _CreateCFObjectFromString("$data", $type);
    }
    elsif($data_type eq 'HASH')
    {
        return CreateNSMutableDictionaryFromHash($data);
    }
    elsif($data_type eq 'ARRAY')
    {
        return CreateNSMutableArrayFromArray($data);
    }
    elsif ($data_type eq 'SCALAR')
    {
        return _CreateCFObjectFromString($$data, $type);
    }
    else
    {
        ERROR_OUT("ToCF: unknown data type: [$data_type]");
        return undef;
    }
}

#
# convert Core Foundation object to perl string. return original object if
# it's not a Core Foundation object.
#
#   $_[0]:  Core Foundation object
#
#   return: string  - converted string
#           undef   - failed or source object is undef
#
sub ToString($)
{
    my $object = $_[0];

    IsCF($object) or return $object;

    my $ret;
    eval
    {
        $ret = $object->description()->UTF8String();
    };
    if ($@)
    {
        ERROR_OUT("Cannot convert Core Foundation object to string: $@");
        return undef;
    }

    return "$ret";
}

#
# create NSMutableDictionary from a hash reference
#
#   $_[0]:  hash reference
#
#   return: NSMutableDictionary - successful
#           undef               - source hash is undef
#
sub CreateNSMutableDictionaryFromHash($)
{
    my $source_hash = $_[0];

    defined($source_hash) or return undef;

    my $dict = NSMutableDictionary->dictionary();

    while (my ($key, $value) = each(%$source_hash))
    {
        if (defined($value))
        {
            my $type = ref($value);
            if (! $type)
            {
                # strings
                $dict->setObject_forKey_("$value", $key);
            }
            elsif ($type eq 'HASH')
            {
                $dict->setObject_forKey_(CreateNSMutableDictionaryFromHash($value), $key);
            }
            elsif ($type eq 'ARRAY')
            {
                $dict->setObject_forKey_(CreateNSMutableArrayFromArray($value), $key);
            }
            elsif ($type eq 'SCALAR')
            {
                $dict->setObject_forKey_($$value, $key);
            }
            elsif (index($type, 'NS') >= 0)
            {
                # core foundation type
                $dict->setObject_forKey_($value, $key);
            }
            else
            {
                TRACE_OUT("create NSMutableDictionary: skip unknown data type: [$type]");
            }
        }
        else
        {
            TRACE_OUT("create NSMutableDictionary: skip undefined value: key: [$key]");
        }
    }

    return $dict;
}

#
# create NSMutableArray from an array reference
#
#   $_[0]:  array reference
#
#   return: NSMutableArray  - successful
#           undef           - source array is undef;
#
sub CreateNSMutableArrayFromArray($)
{
    my $source_array = $_[0];

    defined($source_array) or return undef;

    my $array = NSMutableArray->array();

    foreach my $value (@$source_array)
    {
        if (defined $value)
        {
            my $type = ref($value);
            if (! $type)
            {
                # strings
                $array->addObject_("$value");
            }
            elsif ($type eq 'HASH')
            {
                $array->addObject_(CreateNSMutableDictionaryFromHash($value));
            }
            elsif ($type eq 'ARRAY')
            {
                $array->addObject_(CreateNSMutableArrayFromArray($value));
            }
            elsif ($type eq 'SCALAR')
            {
                $array->addObject_($$value);
            }
            elsif (index($type, 'NS') >= 0)
            {
                # core foundation type
                $array->addObject_($value);
            }
            else
            {
                TRACE_OUT("create NSMutableArray: skip unknown data type: [$type]");
            }
        }
        else
        {
            TRACE_OUT("create NSMutableArray: skip undefined value");
        }
    }

    return $array;
}

#
# create hash reference from a NSDictionary
#
# this function can convert everything in NSDictionary to string, or only
# convert NSString and reserve other Core Foundation types.
#
#   $_[0]:  NSDictionary
#   $_[1]:  (optional) convert NSString only?
#           1:       only convert NSString to string and reserve other Core
#                    Foundation type.
#           0/undef: convert all to string
#
#   return: hash reference  - successful
#           undef           - failed or source NSDictionary is undef
#
sub CreateHashFromNSDictionary($;$)
{
    my ($source_dict, $convert_nsstring_only) = @_;

    IsCF($source_dict, CF_DICTIONARY) or return undef;

    my %hash = ();
    my $enumerator = $source_dict->keyEnumerator();
    my $key;

    while ($key = $enumerator->nextObject() and $$key)
    {
        my $value = $source_dict->objectForKey_($key);
        if ($value)
        {
            my $key_string = ToString($key);
            if (IsCF($value, CF_ARRAY))
            {
                my $subarray = CreateArrayFromNSArray($value, $convert_nsstring_only);
                $hash{$key_string} = $subarray;
            }
            elsif (IsCF($value, CF_DICTIONARY))
            {
                my $subhash = CreateHashFromNSDictionary($value, $convert_nsstring_only);
                $hash{$key_string} = $subhash;
            }
            else
            {
                if (! IsCF($value, CF_STRING) and $convert_nsstring_only)
                {
                    $hash{$key_string} = $value;
                }
                else
                {
                    $hash{$key_string} = ToString($value);
                }
            }
        }
    }

    return \%hash;
}

#
# create array reference from a NSArray
#
# this function can convert everything in NSArray to string, or only convert
# NSString and reserve other Core Foundation types.
#
#   $_[0]:  NSArray
#   $_[1]:  (optional) convert NSString only?
#           1:       only convert NSString to string and reserve other Core
#                    Foundation type.
#           0/undef: convert all to string
#
#   return: array reference - successful
#           undef           - failed or source NSArray is undef
#
sub CreateArrayFromNSArray($;$)
{
    my ($source_array, $convert_nsstring_only) = @_;

    IsCF($source_array, CF_ARRAY) or return undef;
    
    my @array = ();
    my $enumerator = $source_array->objectEnumerator();
    my $value;

    while ($value = $enumerator->nextObject() and $$value)
    {
        if (IsCF($value, CF_ARRAY))
        {
            my $subarray = CreateArrayFromNSArray($value, $convert_nsstring_only);
            push @array, $subarray;
        }
        elsif (IsCF($value, CF_DICTIONARY))
        {
            my $subhash = CreateHashFromNSDictionary($value, $convert_nsstring_only);
            push @array, $subhash;
        }
        else
        {
            if (! IsCF($value, CF_STRING) and $convert_nsstring_only)
            {
                push @array, $value;
            }
            else
            {
                push @array, ToString($value);
            }
        }
    }

    return \@array;
}

#
# get Core Foundation object from NSDictionary or NSMutableDictionary based on
# a give key array
#
#    to get "data" in the following dictionary:
#    {
#        key1 = {
#            key2 = {
#                key3 = "data"; 
#            }; 
#        }; 
#    }
#
#    the key array reference should be:
#    [
#            key1,
#            key2,
#            key3,
#    ];
#
#   $_[0]:  NSDictionary
#   $_[1]:  keys array reference. all array elements should be string
#           if undef, return the original object
#
#   return: Core Foundation object - successful
#           undef                  - no such object or failed
#
sub GetObjectFromNSDictionary($$)
{
    my ($object, $r_keys) = @_;

    if (! IsCF($object))
    {
        ERROR_OUT("Cannot get CF object: source object is not CF object");
        return undef;
    }

    if (IsEmpty($r_keys))
    {
        TRACE_OUT("get CF object from NSDictionary: keys not specified. return original object");
        return $object;
    }

    my $allkeys = join(' -> ', @$r_keys);
    TRACE_OUT("get CF object from NSDictionary: keys: [$allkeys]");

    foreach my $key (@$r_keys)
    {
        # skip empty key
        (defined($key) and $key ne '') or next;
        if (IsCF($object, CF_ARRAY))
        {
            $object = $object->objectAtIndex_($key);
        }
        elsif (IsCF($object, CF_DICTIONARY))
        {
            $object = $object->objectForKey_($key);
        }
        else
        {
            my $type_string = ToString($object->class());
            ERROR_OUT("Cannot get CF object: source object is not an array or a dictionary: key: [$key] type: [$type_string]");
            return undef;
        }

        if (! defined($object))
        {
            ERROR_OUT("Cannot get CF object: a Cocoa error occured: key: [$key]");
            return undef;
        }
        elsif (! $$object)
        {
            # should not be treated as error
            TRACE_OUT('get CF object from NSDictionary:  CF object not exist');
            return undef;
        }
    }

    TRACE_OUT('CF object: ['. ToString($object) . ']');

    return $object;
}

#
# get key array from NSDictionary or NSMutableDictionary based on
# a give key array
#
#    to get all keys under key2 (key3, key4) in the following dictionary:
#    {
#        key1 = {
#            key2 = {
#                key3 = "data1"; 
#                key4 = "data2"; 
#            }; 
#        }; 
#    }
#
#    the key array reference should be:
#    [
#            key1,
#            key2,
#    ];
#
#   $_[0]:  NSDictionary
#   $_[1]:  keys array reference. all array elements should be string
#           if undef, return the original object
#
#   return: array reference - successful
#           undef           - failed
#
sub GetKeysFromNSDictionary($$)
{
    my ($object, $r_keys) = @_;

    if (! IsCF($object))
    {
        ERROR_OUT("Cannot get keys: source object is not CF object");
        return undef;
    }

    if (! IsEmpty($r_keys))
    {
        my $allkeys = join(' -> ', @$r_keys);
        TRACE_OUT("get keys from NSDictionary: parent keys: [$allkeys]");

        foreach my $key (@$r_keys)
        {
            # skip empty key
            (defined($key) and $key ne '') or next;
            if (IsCF($object, CF_ARRAY))
            {
                $object = $object->objectAtIndex_($key);
            }
            elsif (IsCF($object, CF_DICTIONARY))
            {
                $object = $object->objectForKey_($key);
            }
            else
            {
                my $type_string = ToString($object->class());
                ERROR_OUT("Cannot get keys: object is not an array or a dictionary: key: [$key] type: [$type_string]");
                return undef;
            }

            if (! defined($object))
            {
                ERROR_OUT("Cannot get keys: a Cocoa error occured while getting object: key: [$key]");
                return undef;
            }
            elsif (! $$object)
            {
                TRACE_OUT('get keys from NSDictionary: parent key [$key] not exist');
                return undef;
            }
        }
    }
    else
    {
        TRACE_OUT("get keys from NSDictionary:");
    }

    # check if object is retrieved and is valid
    if (! IsCF($object, CF_DICTIONARY))
    {
        ERROR_OUT("Cannot get keys: object is not NSDictionary: type: " . ref($object));
        return undef;
    }

    my $trace_str = "key: [ ";

    my $enumerator = $object->keyEnumerator();
    my $key;
    my @array = ();

    while ($key = $enumerator->nextObject() and $$key)
    {
        my $key_string = ToString($key);
        push @array, $key_string;
        $trace_str .= "$key_string ";
    }

    $trace_str .= "]";
    TRACE_OUT($trace_str);

    return \@array;
}

#
# update NSMutableDictionary based on a given key array and a key/data pair
#
# the key array includes all parent keys of the key that need to be updated
#    to update "data" in the following dictionary:
#    {
#        key1 = {
#            key2 = {
#                key3 = "data"; 
#            }; 
#        }; 
#    }
#
#    the key array reference should be:
#    [
#            key1,
#            key2,
#    ];
#
# if key in key array doesn't exist in NSDictionary, it will be created
#
#   $_[0]:  NSMutableDictionary
#   $_[1]:  keys array reference. all array elements should be string
#   $_[2]:  key
#   $_[3]:  data (if undef, remove key)
#
#   return: 1       - successful
#           2       - no need to update (for example, try to remove a key
#                     that doesn't exist)
#           undef   - failed
#
sub UpdateNSMutableDictionary($$$$)
{
    my ($object, $r_keys, $key, $data) = @_;

    my $allkeys;

    if (IsTraceOn())
    {
        my $trace_str = 'update NSMutableDictionary:  action: ';
        $trace_str .= defined($data) ? 'modify  ' : 'remove  ';
        if (defined($r_keys))
        {
            $allkeys = join(' -> ', @$r_keys);
            $trace_str .= "parent keys: [$allkeys]  ";
        }
        $trace_str .= "key: [$key]  ";
        defined($data) and $trace_str .= "data: [" . ToString($data) . "]";
        TRACE_OUT($trace_str);
    }

    if (! IsCF($object, CF_DICTIONARY))
    {
        if (defined($data))
        {
            ERROR_OUT("Cannot update NSMutableDictionary: target object is not a NSMutableDictionary");
            return undef;
        }
        else
        {
            TRACE_OUT("no need to update NSMutableDictionary");
            return 2;
        }
    }

    # get parent object
    foreach my $k (@$r_keys)
    {
        # skip empty key
        (defined($k) and $k ne '') or next;
        if (IsCF($object, CF_ARRAY))
        {
            my $child_object = $object->objectAtIndex_($k);
            if ($child_object and $$child_object)
            {
                $object = $child_object;
            }
            else
            {
                # create an empty dictionary if not exist
                $child_object = NSMutableDictionary->dictionary();
                $object->addObject_($child_object);
                $object = $child_object;
            }
        }
        elsif (IsCF($object, CF_DICTIONARY))
        {
            my $child_object = $object->objectForKey_($k);
            if ($child_object and $$child_object)
            {
                $object = $child_object;
            }
            else
            {
                # create an empty dictionary if not exist
                TRACE_OUT("update NSMutableDictionary: key [$k] not exist. create an empty NSMutableDictionary");
                $child_object = NSMutableDictionary->dictionary();
                $object->setObject_forKey_($child_object, $k);
                $object = $child_object;
            }
        }
        else
        {
            if (defined($data))
            {
                my $type_string = ToString($object->class());
                ERROR_OUT("Cannot add new object: [$k] is not an array or a dictionary. type: [$type_string]");
                return undef;
            }
            else
            {
                TRACE_OUT("no need to update NSMutableDictionary");
                return 2;
            }
        }

        if (! IsCF($object))
        {
            if (defined($data))
            {
                # if no such object, create an empty NSMutableDictionary
                TRACE_OUT("update NSMutableDictionary: key [$key] not exist. create an empty NSMutableDictionary");
                $object = NSMutableDictionary->dictionary();
            }
            else
            {
                TRACE_OUT("no need to update NSMutableDictionary");
                return 2;
            }
        }
    }

    # add or remove object under parent object
    eval
    {
        if (defined($data))
        {
            $object->setObject_forKey_($data, $key);
        }
        else
        {
            $object->removeObjectForKey_($key);
        }
    };
    if ($@)
    {
        ERROR_OUT("Cannot update NSMutableDictionary: $@");
        return undef;
    }

    return 1;
}

# <<< OBJC <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> PRIVATE >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# get mac address of specified network card
#
sub _GetMacAddress($)
{
    my $nic = $_[0];

    defined($nic) or $nic = 'en0';

    my $cmd = "ifconfig $nic ether";

    my ($ret, $data) = RunCommand($cmd);
    if (! defined($ret) or ! defined($data))
    {
        ERROR_OUT("Cannot get mac address of [$nic]");
        return undef;
    }

    $data =~ m/ether ([0-9a-f][0-9a-f]):([0-9a-f][0-9a-f]):([0-9a-f][0-9a-f]):([0-9a-f][0-9a-f]):([0-9a-f][0-9a-f]):([0-9a-f][0-9a-f])/gs;
    my $address = "$1$2$3$4$5$6";

    TRACE_OUT("Mac address of $nic: [$address]");

    return $address;
}

#
# create Core Foundation object from a string
#
#   $_[0]:  string
#   $_[1]:  type (optional, default is CF_STRING)
#
#   return: Core Foundation object
#
sub _CreateCFObjectFromString($;$)
{
    my ($data, $type) = @_;

    $type or $type = CF_STRING;

    my $ret;
    eval
    {
        if ($type == CF_BOOL)
        {
            $ret = NSNumber->numberWithBool_($data);
        }
        elsif ($type == CF_INTEGER)
        {
            $ret = NSNumber->numberWithLong_($data);
        }
        elsif ($type == CF_REAL)
        {
            $ret = NSNumber->numberWithFloat_($data);
        }
        elsif ($type == CF_DATE)
        {
            $ret = NSDate->dateWithString_($data);
        }
        elsif ($type == CF_STRING)
        {
            $ret = NSString->stringWithString_($data);
        }
        elsif ($type == CF_DATA)
        {
            $ ret = _CreateCFDataFromBase64String($data);
        }
        else
        {
            ERROR_OUT("Cannot convert string [$data] to Core Foundation object: unknown type: [$type]");
            return undef;
        }
    };
    if ($@)
    {
        ERROR_OUT("Cannot convert string [$data] to Core Foundation object: $@");
        return undef;
    }

    return $ret;
}

#
# Create Core Foundation CFData object from a base64 string
#
# The base64 string input here should come from the output of  cli tool
# /usr/share/centrifydc/libexec/cdcdefaults -base64 byteString
# and byteString is the actual data represented in hex number 
# characters 0-9, a-f.
# The output of the cdcdefaults cli tool should be a string, which is
# base64 encoded string, which should only contain characters 0-9,
# a-z, A-Z, +, / and =
#
#   $_[0]:  base64 encoded data string
#   
#   return: Core Foundation CFData object
#
sub _CreateCFDataFromBase64String($)
{
    my $base64 = $_[0];
    
    $base64 =~ s/[\n\r\t ]//g;
    if ($base64 !~ /^[0-9a-zA-Z\+\/]+\=*$/)
    {
        DEBUG_OUT("inputted string is not base64!");
        return;
    }
    
    $base64 = ("<plist version=\"1.0\"><data>$base64</data></plist>");
    my $nsstring = NSString->stringWithFormat_($base64);
    my $data = $nsstring->dataUsingEncoding_(4);
    
    my $format;
    my $error;
    my $plist = NSPropertyListSerialization->propertyListWithData_options_format_error_($data, 2, \$format, \$error);
    if ($plist and $$plist)
    {
        if ($plist->isKindOfClass_(NSData->class))
        {
            return $plist;
        }
        else
        {
            DEBUG_OUT("object created is not nsdata");
        }
    }
    else
    {
        DEBUG_OUT("Could not convert string to nsdata plist");
    }
}

# <<< PRIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

1;
