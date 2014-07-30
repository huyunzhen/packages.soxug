TRUE=0
FALSE=1
SUCCESS=0
FAILURE=1



CENTRIFY_TMP_DIR=/var/centrify/tmp

# TODO: make a function for getting perm str (replace "cut -c 1-10" on "ls -dl")
# Getting perm str is tricky. There may be a extra trailing char. 
# For example SELinux, there will be a "." at the end. 
# See POSIX: http://pubs.opengroup.org/onlinepubs/9699919799/utilities/ls.html
# Solution is to extract the first 10 char from ls -dl, which is the permission string exclude the extra char.
# Example: "-rwxrwxr-x. <other info>" will become "-rwxrwxr-x"



#########
# IsValidPerms
# Param: 9 character permission string
# Return: $FALSE if input format is not valid
#         $TRUE otherwise
#
IsValidPerms()
{
    ISVALIDPERMS_INPUT_STRING="$1"
    ISVALIDPERMS_TMP_STRING=`echo $ISVALIDPERMS_INPUT_STRING | grep '^[r-][w-][x-][r-][w-][x-][r-][w-][x-]$'`
    ISVALIDPERMS_RETVAL=$?
    
    if [ $ISVALIDPERMS_RETVAL -ne 0 ]; then
        return $FALSE
    else
        return $TRUE
    fi
}

OctalPermsHelper()
{
	echo $1 | sed -e 's/^---.*/0/g' \
				  -e 's/^--x.*/1/g' \
				  -e 's/^-w-.*/2/g' \
				  -e 's/^-wx.*/3/g' \
				  -e 's/^r--.*/4/g' \
				  -e 's/^r-x.*/5/g' \
				  -e 's/^rw-.*/6/g' \
				  -e 's/^rwx.*/7/g'
}

#########
# PrintPermsInOctalDigits
# Param: 9-character_permission_string
#       file_type_and_permissions: character representation 
# Return: $FAILURE if the permission string cannot be converted to 3-integer octal digits
#         $SUCCESS otherwise
# Stdout: permission modifying string for chmod
#
PrintPermsInOctalDigits()
{
    PRINTPERMSINOCTALDIGITS_PERMS_STR="$1"
    IsValidPerms "$PRINTPERMSINOCTALDIGITS_PERMS_STR"
    RETVAL=$?
    if [ $RETVAL -ne $TRUE ]; then
        return $FAILURE
    fi
    
    PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP="$PRINTPERMSINOCTALDIGITS_PERMS_STR"
    PRINTPERMSINOCTALDIGITS_CHMOD_MODE=""
	# First digit
	PRINTPERMSINOCTALDIGITS_CHMOD_MODE="$PRINTPERMSINOCTALDIGITS_CHMOD_MODE`OctalPermsHelper "$PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP"`"
	# Remove string belongs to first digit
	PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP=`echo $PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP | sed -e 's/^...//g'`
	# Second digit
	PRINTPERMSINOCTALDIGITS_CHMOD_MODE="$PRINTPERMSINOCTALDIGITS_CHMOD_MODE`OctalPermsHelper "$PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP"`"
	# Remove string belongs to second digit
	PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP=`echo $PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP | sed -e 's/^...//g'`
	# Third digit
	PRINTPERMSINOCTALDIGITS_CHMOD_MODE="$PRINTPERMSINOCTALDIGITS_CHMOD_MODE`OctalPermsHelper "$PRINTPERMSINOCTALDIGITS_PERMS_STR_TMP"`"
    
    
    PRINTPERMSINOCTALDIGITS_TMP_STRING=`echo "$PRINTPERMSINOCTALDIGITS_CHMOD_MODE" | \
                            sed -n '/[0-7][0-7][0-7]/p'`
    if [ "X$PRINTPERMSINOCTALDIGITS_TMP_STRING" != "X$PRINTPERMSINOCTALDIGITS_CHMOD_MODE" ]; then
        return $FAILURE
    else
        echo "$PRINTPERMSINOCTALDIGITS_CHMOD_MODE"
        return $SUCCESS
    fi
}

#########
# IsFileRightsMatched
# Param: file_type_and_permissions file_owner file_name
#       file_type_and_permissions: 10-character representation 
# Return: $FALSE if the file is insecure
#         $TRUE otherwise
#
# Ensure the fidelity the file
#
IsFileRightsMatched()
{
    ISFILERIGHTSMATCHED_FILE_TYPE_PERMS="$1"
    ISFILERIGHTSMATCHED_FILE_OWNER="$2"
    ISFILERIGHTSMATCHED_FILE_NAME="$3"

    ISFILERIGHTSMATCHED_LS_FILE=`ls -dl "$ISFILERIGHTSMATCHED_FILE_NAME"`
    ISFILERIGHTSMATCHED_LS_FILE_TYPE_PERMS=`echo $ISFILERIGHTSMATCHED_LS_FILE | cut -c 1-10`
    ISFILERIGHTSMATCHED_LS_FILE_OWNER=`echo $ISFILERIGHTSMATCHED_LS_FILE | awk '{print $3}'`
    if [ "X$ISFILERIGHTSMATCHED_LS_FILE_TYPE_PERMS" != "X$ISFILERIGHTSMATCHED_FILE_TYPE_PERMS" \
        -o "X$ISFILERIGHTSMATCHED_LS_FILE_OWNER" != "X$ISFILERIGHTSMATCHED_FILE_OWNER" \
        ]; then
        return $FALSE
    else
        return $TRUE
    fi
}

#########
# IsOwnerMatched
# Param: file_owner file_path
# Return: $FALSE if the file is not owned by the stated owner
#         $TRUE otherwise
#
IsOwnerMatched()
{
    ISOWNERMATCHED_EXPECTED_OWNER="$1"
    ISOWNERMATCHED_TARGET_FILE="$2"
    
    ISOWNERMATCHED_LS_FILE=`ls -dl "$ISOWNERMATCHED_TARGET_FILE"`
    ISOWNERMATCHED_LS_FILE_OWNER=`echo "$ISOWNERMATCHED_LS_FILE" | awk '{print $3}'`
    
    if [ "X$ISOWNERMATCHED_LS_FILE_OWNER" != "X$ISOWNERMATCHED_EXPECTED_OWNER" ]; then
        return $FALSE
    else
        return $TRUE
    fi
}

#########
# IsNotWritableByGroupNorOthers
# Param: file_path
# Return: $FALSE if the file is writable by group or others
#         $TRUE otherwise
#
# Check whether the file is not writable by group nor others
#
IsNotWritableByGroupNorOthers()
{
    ISNOTWRITABLEBYGROUPNOROTHERS_TARGET_FILE="$1"
    
    ISNOTWRITABLEBYGROUPNOROTHERS_LS_FILE=`ls -dl "$ISNOTWRITABLEBYGROUPNOROTHERS_TARGET_FILE"`
    ISNOTWRITABLEBYGROUPNOROTHERS_LS_FILE_TYPE_PERMS=`echo $ISNOTWRITABLEBYGROUPNOROTHERS_LS_FILE | cut -c 1-10`
    
    echo "$ISNOTWRITABLEBYGROUPNOROTHERS_LS_FILE_TYPE_PERMS" | grep '^.[r-][w-][x-][r-][-][x-][r-][-][x-]$' >/dev/null 2>&1
    ISNOTWRITABLEBYGROUPNOROTHERS_RETVAL=$?
    if [ $ISNOTWRITABLEBYGROUPNOROTHERS_RETVAL -ne 0 ]; then
        return $FALSE
    else
        return $TRUE
    fi
}

#########
# IsSubDirsPermsMatched
# Param: dir_permissions dir_owner target_dir check_mode
#       dir_permissions: 9-char permissions
#       check_mode: if "strict", ensure all sub-directories have the given rights
#               if "loose", dir_permissions is skipped. All dirs are only checked against the writability of group users and other users
#               otherwise, return $FALSE
# Return: $FALSE if the file is not owned by the stated owner
#         $TRUE otherwise
#
IsSubDirsPermsMatched()
{
    ISSUBDIRSRIGHTSMATCHED_PERMS="$1"
    ISSUBDIRSRIGHTSMATCHED_OWNER="$2"
    ISSUBDIRSRIGHTSMATCHED_TARGET_DIR="$3"
    ISSUBDIRSRIGHTSMATCHED_CHECK_MODE="$4"
    
    ISSUBDIRSRIGHTSMATCHED_CUR_DIR="$ISSUBDIRSRIGHTSMATCHED_TARGET_DIR"
    
    while [ "X$ISSUBDIRSRIGHTSMATCHED_CUR_DIR" != "X/" ]; do
        if [ "X$ISSUBDIRSRIGHTSMATCHED_CUR_DIR" = "X/var" ]; then
            break
        fi
        
        if [ -h $ISSUBDIRSRIGHTSMATCHED_CUR_DIR ]; then
            return $FALSE
        fi
        if [ "X$ISSUBDIRSRIGHTSMATCHED_CHECK_MODE" = "Xstrict" ]; then
            IsFileRightsMatched "d$ISSUBDIRSRIGHTSMATCHED_PERMS" "$ISSUBDIRSRIGHTSMATCHED_OWNER" "$ISSUBDIRSRIGHTSMATCHED_CUR_DIR"
            ISSUBDIRSRIGHTSMATCHED_RETVAL=$?
            if [ $ISSUBDIRSRIGHTSMATCHED_RETVAL -ne $TRUE ]; then
                return $FALSE
            fi
        elif [ "X$ISSUBDIRSRIGHTSMATCHED_CHECK_MODE" = "Xloose" ]; then
            if [ -d "$ISSUBDIRSRIGHTSMATCHED_CUR_DIR" ]; then
                IsOwnerMatched "$ISSUBDIRSRIGHTSMATCHED_OWNER" "$ISSUBDIRSRIGHTSMATCHED_CUR_DIR"
                ISSUBDIRSRIGHTSMATCHED_RETVAL=$?
                if [ $ISSUBDIRSRIGHTSMATCHED_RETVAL -ne $TRUE ]; then
                    return $FALSE
                fi
                IsNotWritableByGroupNorOthers "$ISSUBDIRSRIGHTSMATCHED_CUR_DIR"
                ISSUBDIRSRIGHTSMATCHED_RETVAL=$?
                if [ $ISSUBDIRSRIGHTSMATCHED_RETVAL -ne $TRUE ]; then
                    return $FALSE
                fi
            else
                return $FALSE
            fi
        else
            return $FALSE
        fi
        
        ISSUBDIRSRIGHTSMATCHED_CUR_DIR=`dirname $ISSUBDIRSRIGHTSMATCHED_CUR_DIR`
    done
    
    return $TRUE
}

#########
# IsFileExists
# Param: file_path
# Return: $FALSE if the file is not owned by the stated owner
#         $TRUE otherwise
#
# Check the existence of a file
#
IsFileExists()
{
    ISFILEEXISTS_TARGET_FILE="$1"
    if [ "X`uname -s`" = "XSunOS" ]; then
        if [ -b "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -c "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -d "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -f "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -g "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -h "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -k "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -p "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -r "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -s "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -u "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -w "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        elif [ -x "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        else
            return $FALSE
        fi
    else
        if [ -e "$ISFILEEXISTS_TARGET_FILE" ]; then
            return $TRUE
        else
            return $FALSE
        fi
    fi
}

#########
# MakeTmpDirImpl
# Param: dir_permissions dir_owner dir_name creation_mode removal_mode
#               creation_mode: "file", all sub-dirs are only check whether they are writable
#                              "dir", the deepest level sub-dir is check against dir_permissions, 
#                                       other sub-dirs are only check whether they are writable
#               removal_mode: "force"
# Return: $FAILURE if the directory is insecure
#         $SUCCESS otherwise
#
MakeTmpDirImpl()
{
    MAKETMPDIRIMPL_TARGET_DIR_PERMS="$1"
    MAKETMPDIRIMPL_TARGET_DIR_OWNER="$2"
    MAKETMPDIRIMPL_TARGET_DIR="$3"
    MAKETMPDIRIMPL_CREATION_MODE="$4"
    MAKETMPDIRIMPL_REMOVAL_MODE="$5"
    MAKETMPDIRIMPL_RETVAL=""
    
    if [ "X$MAKETMPDIRIMPL_CREATION_MODE" != "Xdir" \
        -a "X$MAKETMPDIRIMPL_CREATION_MODE" != "Xfile" \
        ]; then
        return $FAILURE
    fi
    
    if [ "X$MAKETMPDIRIMPL_REMOVAL_MODE" = "Xforce" ]; then
        rm -fr "$MAKETMPDIRIMPL_TARGET_DIR"
    fi
    
    if [ -h "$MAKETMPDIRIMPL_TARGET_DIR" ]; then
        return $FAILURE
    fi
    
    if [ ! -d "$MAKETMPDIRIMPL_TARGET_DIR" ]; then
        IsFileExists "$MAKETMPDIRIMPL_TARGET_DIR"
        MAKETMPDIRIMPL_RETVAL=$?
        if [ $MAKETMPDIRIMPL_RETVAL -eq $TRUE ]; then
            return $FAILURE
        else
            mkdir -p "$MAKETMPDIRIMPL_TARGET_DIR"
            chown "$MAKETMPDIRIMPL_TARGET_DIR_OWNER" "$MAKETMPDIRIMPL_TARGET_DIR"
            MAKETMPDIRIMPL_PERM_OCTAL_DIGITS=`PrintPermsInOctalDigits "$MAKETMPDIRIMPL_TARGET_DIR_PERMS"`
            MAKETMPDIRIMPL_RETVAL=$?
            if [ $MAKETMPDIRIMPL_RETVAL -ne $SUCCESS ]; then
                return $FAILURE
            fi
            chmod "$MAKETMPDIRIMPL_PERM_OCTAL_DIGITS" "$MAKETMPDIRIMPL_TARGET_DIR"
        fi
    fi
    
    # Check creation mode, allowed values are "dir" and "file"
    if [ "X$MAKETMPDIRIMPL_CREATION_MODE" = "Xdir" ]; then
        IsFileRightsMatched "d$MAKETMPDIRIMPL_TARGET_DIR_PERMS" "$MAKETMPDIRIMPL_TARGET_DIR_OWNER" "$MAKETMPDIRIMPL_TARGET_DIR"
        MAKETMPDIRIMPL_RETVAL=$?
        if [ $MAKETMPDIRIMPL_RETVAL -ne $TRUE ]; then
            return $FAILURE
        fi
    fi
    IsSubDirsPermsMatched "$MAKETMPDIRIMPL_TARGET_DIR_PERMS" "$MAKETMPDIRIMPL_TARGET_DIR_OWNER" "$MAKETMPDIRIMPL_TARGET_DIR" "loose"
    MAKETMPDIRIMPL_RETVAL=$?
    if [ $MAKETMPDIRIMPL_RETVAL -ne $TRUE ]; then
        return $FAILURE
    else
        return $SUCCESS
    fi
}

########
# MakeTmpFileImpl
# Param: dir_permissions dir_owner dir_name dir_removal_mode file_perms file_owner file_name file_removeal_mode
# Return: $FAILURE if the file is insecure, or the directory does not have correct permissions
#         $SUCCESS otherwise
#
MakeTmpFileImpl()
{
    MAKETMPFILEIMPL_TARGET_DIRECTORY_PERMS="$1"
    MAKETMPFILEIMPL_TARGET_DIRECTORY_OWNER="$2"
    MAKETMPFILEIMPL_TARGET_DIRECTORY="$3"
    MAKETMPFILETMPL_TARGET_DIRECTORY_REMOVAL_MODE="$4"
    MAKETMPFILEIMPL_TARGET_FILE_PERMS="$5"
    MAKETMPFILEIMPL_TARGET_FILE_OWNER="$6"
    MAKETMPFILEIMPL_TARGET_FILE="$MAKETMPFILEIMPL_TARGET_DIRECTORY/$7"
    MAKETMPFILETMPL_TARGET_FILE_REMOVAL_MODE="$8"
    MAKETMPFILEIMPL_RETVAL=""

    MakeTmpDirImpl "$MAKETMPFILEIMPL_TARGET_DIRECTORY_PERMS" "$MAKETMPFILEIMPL_TARGET_DIRECTORY_OWNER" "$MAKETMPFILEIMPL_TARGET_DIRECTORY" "file" "$MAKETMPFILETMPL_TARGET_DIRECTORY_REMOVAL_MODE"
    MAKETMPFILEIMPL_RETVAL=$?
    if [ $MAKETMPFILEIMPL_RETVAL -ne $SUCCESS ]; then
        return $FAILURE
    fi

    if [ "X$MAKETMPFILETMPL_TARGET_FILE_REMOVAL_MODE" = "Xforce" ]; then
        rm -fr "$MAKETMPFILEIMPL_TARGET_FILE"
    fi
    
    IsFileExists "$MAKETMPFILEIMPL_TARGET_FILE"
    MAKETMPFILEIMPL_RETVAL=$?
    if [ $MAKETMPFILEIMPL_RETVAL -ne $FALSE ]; then
        return $FAILURE
    fi
    touch "$MAKETMPFILEIMPL_TARGET_FILE"
    chown "$MAKETMPFILEIMPL_TARGET_FILE_OWNER" "$MAKETMPFILEIMPL_TARGET_FILE"
    MAKETMPFILEIMPL_PERM_OCTAL_DIGITS=`PrintPermsInOctalDigits "$MAKETMPFILEIMPL_TARGET_FILE_PERMS"`
    MAKETMPFILEIMPL_RETVAL=$?
    if [ $MAKETMPFILEIMPL_RETVAL -ne $SUCCESS ]; then
        return $FAILURE
    fi
    chmod "$MAKETMPFILEIMPL_PERM_OCTAL_DIGITS" "$MAKETMPFILEIMPL_TARGET_FILE"
    
    IsFileRightsMatched "-$MAKETMPFILEIMPL_TARGET_FILE_PERMS" "$MAKETMPFILEIMPL_TARGET_FILE_OWNER" "$MAKETMPFILEIMPL_TARGET_FILE"
    MAKETMPFILEIMPL_RETVAL=$?
    if [ $MAKETMPFILEIMPL_RETVAL -ne $SUCCESS ]; then
        return $FAILURE
    else
        return $SUCCESS
    fi
}

IsContainDotOperator()
{
    ISCONTAINDOTOPERATOR_TARGET_FILE="$1"

    ISCONTAINDOTOPERATOR_TMP_STRING=`echo "$ISCONTAINDOTOPERATOR_TARGET_FILE" | grep '\.\.'`
    ISCONTAINDOTOPERATOR_RETVAL=$?
    if [ $ISCONTAINDOTOPERATOR_RETVAL -eq 0 ]; then
        echo "ERROR: Paths with '..' is not allowed"
        return $TRUE
    fi
    ISCONTAINDOTOPERATOR_TMP_STRING=`echo "$ISCONTAINDOTOPERATOR_TARGET_FILE" | grep '\/\.\/'`
    ISCONTAINDOTOPERATOR_RETVAL=$?
    if [ $ISCONTAINDOTOPERATOR_RETVAL -eq 0 ]; then
        echo "ERROR: Paths with '/./' is not allowed"
        return $TRUE
    fi
    ISCONTAINDOTOPERATOR_TMP_STRING=`echo "$ISCONTAINDOTOPERATOR_TARGET_FILE" | grep '^\.\/'`
    ISCONTAINDOTOPERATOR_RETVAL=$?
    if [ $ISCONTAINDOTOPERATOR_RETVAL -eq 0 ]; then
        echo "ERROR: Paths starting with './' is not allowed"
        return $TRUE
    fi
    ISCONTAINDOTOPERATOR_TMP_STRING=`echo "$ISCONTAINDOTOPERATOR_TARGET_FILE" | grep '^\.$'`
    ISCONTAINDOTOPERATOR_RETVAL=$?
    if [ $ISCONTAINDOTOPERATOR_RETVAL -eq 0 ]; then
        echo "ERROR: Single '.' is not allowed"
        return $TRUE
    fi
    
    return $FALSE

}

#########
# MakeTmpDir
# Param: dir_permissions dir_name removal_mode
#               removal_mode: value:=[force|none|]
# Return: $FAILURE if the directory is insecure
#         $SUCCESS otherwise
# Stdout: the complete dir path
# Wrapper to MakeTmpDir, setting the temporary directory
#
MakeTmpDir()
{
    MAKETMPDIR_TARGET_DIR_PERMS="$1"
    MAKETMPDIR_TARGET_DIR="$CENTRIFY_TMP_DIR/$2"
    MAKETMPDIR_REMOVAL_MODE="$3"
    MAKETMPDIR_RETVAL=""
    
    IsContainDotOperator "$MAKETMPDIR_TARGET_DIR" >/dev/null 2>&1
    MAKETMPDIR_RETVAL=$?
    if [ $MAKETMPDIR_RETVAL -ne $FALSE ]; then
        return $FAILURE
    fi
    
    MakeTmpDirImpl "$MAKETMPDIR_TARGET_DIR_PERMS" "root" "$MAKETMPDIR_TARGET_DIR" "dir" "$MAKETMPDIR_REMOVAL_MODE" >/dev/null 2>&1
    MAKETMPDIR_RETVAL=$?
    if [ $MAKETMPDIR_RETVAL -ne $SUCCESS ]; then
        return $FAILURE
    else
        echo "$MAKETMPDIR_TARGET_DIR"
        return $SUCCESS
    fi
}

########
# MakeTmpFile
# Param: file_permissions file_name removal_mode
#               file_name: must contains at least 1 character
#                          must not end with "/"
#               removal_mode: value:=[force|none|]
# Return: $FAILURE if the file is insecure, or the directory does not have correct permissions
#         $SUCCESS otherwise
# Stdout: the full path to the tmp file
#
# Prepare a secure tmp file
#
MakeTmpFile()
{
    MAKETMPFILE_TARGET_FILE_PERMS="$1"
    MAKETMPFILE_TARGET_FILE="$2"
    MAKETMPFILE_REMOVAL_MODE="$3"
    MAKETMPFILE_RETVAL=""
    
    IsContainDotOperator "$MAKETMPFILE_TARGET_FILE" >/dev/null 2>&1
    MAKETMPFILE_RETVAL=$?
    if [ $MAKETMPFILE_RETVAL -ne $FALSE ]; then
        return $FAILURE
    fi
    
    MAKETMPFILE_FILE_DIR=`dirname "$MAKETMPFILE_TARGET_FILE"`
    if [ "X$MAKETMPFILE_FILE_DIR" = "X." ]; then
        MAKETMPFILE_FILE_DIR="$CENTRIFY_TMP_DIR"
    else
        MAKETMPFILE_FILE_DIR="$CENTRIFY_TMP_DIR/$MAKETMPFILE_FILE_DIR"
    fi
    
    # Extract the file name, only needs string after the last slash
    MAKETMPFILE_FILE_NAME=`echo $MAKETMPFILE_TARGET_FILE | sed -e "s_^.*/__"`
    
    MakeTmpFileImpl "rwxr-xr-x" "root" "$MAKETMPFILE_FILE_DIR" "none" "$MAKETMPFILE_TARGET_FILE_PERMS" "root" "$MAKETMPFILE_FILE_NAME" "$MAKETMPFILE_REMOVAL_MODE" >/dev/null 2>&1
    MAKETMPFILE_RETVAL=$?
    if [ $MAKETMPFILE_RETVAL -ne $SUCCESS ]; then
        return $FAILURE
    else
        echo "$MAKETMPFILE_FILE_DIR/$MAKETMPFILE_FILE_NAME"
        return $SUCCESS
    fi
}


