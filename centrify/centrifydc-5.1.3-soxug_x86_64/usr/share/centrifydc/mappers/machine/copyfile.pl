#!/bin/sh /usr/share/centrifydc/perl/run

# Copyright (C) 2007-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script to copy file from Domain Control SYSVOL to a
# specified location on the Unix file system
#

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug);
use CentrifyDC::GP::GPIsolation qw(GP_REG_FILE_CURRENT);
use CentrifyDC::GP::Lock;
use CentrifyDC::GP::Registry;
use CentrifyDC::SMB;
use File::stat;
use File::Path;
use File::Basename;
use File::Copy;
use File::Find;

#
#some paths to the registry store on the unix box. 
#
my $registrykey = "software/policies/centrify/unixsettings";
my $backupprefix = ".orig";
my $stagingprefix = ".staging";
my $stagepathmachine = "/var/centrifydc/reg/machine";
my $sysvolpath = "gpdata/"; # where the files comes from on the sysvol share
my $ROOT = "/var/centrifydc/reg/machine/software/policies/centrify/unixsettings/filecopy";
my $SUB_ROOT="/var/centrifydc/reg/machine/";

#
# Registry related definitions
#
my %REGKEY_FILECOPY_ENABLED = ();
$REGKEY_FILECOPY_ENABLED{"machine"} = $registrykey;

my $REGKEY_ITEM_FILECOPY_ENABLED ="filecopy.enabled";
my $REGKEY_ITEM_SOURCE_FILENAME_SOURCE_DOMAIN="source.fqdn";
my $REGKEY_ITEM_SOURCE_FILENAME_SOURCE="source";
my $REGKEY_ITEM_SOURCE_FILENAME_DESTINATION="destination";
my $REGKEY_ITEM_USE_EXISTING_PERM="use.existing.perms";
my $REGKEY_ITEM_USE_SELECTED_PERM="use.selected.perms";
my $REGKEY_ITEM_FILE_OWNER="owner.uid";
my $REGKEY_ITEM_FILE_GROUP_OWNER="owner.gid";
my $REGKEY_ITEM_FILE_BINARY_COPIED="binary.copied";

#
# declare global variables 
#
#
# list of all registry key source files names as specified in the GP 
# For example, software/policies/centrify/unixsettings/filecopy/destination_path/.../
#
my @SOURCE_REGISTRY_KEYS;
#
# Map of software/policies/centrify/unixsettings/filecopy/source1..N-->destination data map
# Destination data is a Map
# The key registry key source name 
# The value of the source key is another map with values
#
# { 'hosts' ----->   'destination'--><value>
#                             ' owner.gid'-------><value>
#                             'ower.uid'---------->value>
#                             'use.existing.perms'->value
#                             'use.selected.perms'->value
#                             'source'--->value
#
my %DESTINATIONS = ();

#
# options for traversing directories
#
my $options = {
        no_chdir        => 1,
        wanted          => \&find_all_keys,
};

sub extract_key($) 
{
    my ($stg) = @_;
    my $l = length($SUB_ROOT);
    my $key = substr($stg, $l);
    return $key;
}

sub find_all_keys() 
{
   my $bname = basename($File::Find::name);
   if ($bname eq GP_REG_FILE_CURRENT)
    {
       my $key = extract_key($File::Find::dir);
       if ($key) 
       {
           push(@SOURCE_REGISTRY_KEYS, $key);
       }
    }
    else
    {
        # Not our kind of path.
        return;
    }
    return 1;
}

sub initRegistrySourceKeys() 
{

    find($options, $ROOT);
}

sub initRegistryValues($) 
{
        my ($cls) = @_;
        my @snames;
        my @dnames;
        my @existing_perm_values;
        my @selected_perm_values;
        my @user_owner_values;
        my @group_owner_values;
        my $copy_as_binary;
        my $source_domain;
        my $src;
        my $cnt=1;
        
        initRegistrySourceKeys();
        foreach my $registryfckey (@SOURCE_REGISTRY_KEYS)
         {
            #
            # Get the flag of the existing permissions if set
            #
            @existing_perm_values = CentrifyDC::GP::Registry::Query($cls,
                                                      $registryfckey,
                                                      "current",
                                                      $REGKEY_ITEM_USE_EXISTING_PERM);
            #
            # Get the value for  the selected  permissions if set
            #
            @selected_perm_values = CentrifyDC::GP::Registry::Query($cls,
                                                       $registryfckey,
                                                      "current",
                                                      $REGKEY_ITEM_USE_SELECTED_PERM);
            #
            # Get the uid of the selected  permissions if was elected
            #
            @user_owner_values = CentrifyDC::GP::Registry::Query($cls,
                                                       $registryfckey,
                                                      "current",
                                                      $REGKEY_ITEM_FILE_OWNER);
            #
            # Get the gid of the selected  permissions if was elected
            #
            @group_owner_values = CentrifyDC::GP::Registry::Query($cls,
                                                      $registryfckey,
                                                      "current",
                                                      $REGKEY_ITEM_FILE_GROUP_OWNER);
            #
            # Get the source domain name
            # 
            $source_domain = (CentrifyDC::GP::Registry::Query($cls, $registryfckey, "current", $REGKEY_ITEM_SOURCE_FILENAME_SOURCE_DOMAIN))[1];
            #
            # Get the source file name
            #
             @snames = CentrifyDC::GP::Registry::Query($cls,
                                                      $registryfckey,
                                                      "current",
                                                       $REGKEY_ITEM_SOURCE_FILENAME_SOURCE);
            #
            # Get the destination directory
            #
             @dnames = CentrifyDC::GP::Registry::Query($cls,
                                                      $registryfckey,
                                                      "current",
                                                       $REGKEY_ITEM_SOURCE_FILENAME_DESTINATION);
                                                       
            #
            # Get the file type
            #
             $copy_as_binary = (CentrifyDC::GP::Registry::Query($cls,
                                                      $registryfckey,
                                                      "current",
                                                       $REGKEY_ITEM_FILE_BINARY_COPIED))[1];
                                                                                                              
            #
            # insert values into the hash of hash for each source entry
            #
            $src = $snames[1];
            #
            # if value present then only update the hash of hashes
            #
            if ($src) 
            {
                # replace backslash with slash
                $src =~ s#\\#/#g;
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_SOURCE_FILENAME_SOURCE_DOMAIN} = $source_domain;
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_SOURCE_FILENAME_SOURCE} = $src;
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_SOURCE_FILENAME_DESTINATION} = $dnames[1];
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_USE_SELECTED_PERM} = $selected_perm_values[1];
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_USE_EXISTING_PERM} = $existing_perm_values[1];
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_FILE_OWNER} = $user_owner_values[1];
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_FILE_GROUP_OWNER} = $group_owner_values[1];
                $DESTINATIONS{$registryfckey}{$REGKEY_ITEM_FILE_BINARY_COPIED} = $copy_as_binary;
            }
        }
}

      

#################################################
#
#             FUNCTION DEFINTIONS
#
#################################################

#
# Boolean method to ascertain if the GP for filecopy is enabled
# Parameters in: 
# string - class
# RETURN 1 if filecopy.enabled = 1
# RETURN 0 if filecopy.enabled = 0
# 
sub is_filecopy_enabled($)
{
    my ($cls) = @_;
    my  @tmp = CentrifyDC::GP::Registry::Query($cls,
                                              $REGKEY_FILECOPY_ENABLED{$cls},
                                              "current",
                                              $REGKEY_ITEM_FILECOPY_ENABLED);
    return 0 unless defined $tmp[1]; #filecopy.enabled not set in registry
    return $tmp[1] eq "1";
}

#
#
# Method to copy files from the source in the sysvol to the destination
# input parametes: 
# parameter 1 - string class type (machine)
# parameter 2 - string username 
# return 1  - succesful operation
# return  0   unsuccessful
#
sub copy_files_to_destination($)
{
    my ($cls) = @_;
    my $rcode;
    my $nfiles = 0;

    initRegistryValues($cls);
    #
    # Iterate over the list of files to process
    #
    foreach my $source_key_fname (@SOURCE_REGISTRY_KEYS) {
        #
        # set up SMB instance
        #
        my $source_domain = $DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_SOURCE_FILENAME_SOURCE_DOMAIN};
        my $smb = CentrifyDC::SMB->new($source_domain);
        $smb->convertCRLF(1);
        $smb->directory(1);
        $smb->recurse(0);
        $smb->removeDeleted(1);
        $smb->mode(0755);        
        #
        # retrieve each source data from the hash map
        #       
        my $source_fname = $DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_SOURCE_FILENAME_SOURCE};
        if($source_fname) {
            $nfiles++;
            my $destination_dir = expand_variables($DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_SOURCE_FILENAME_DESTINATION});
            my $destination_file = $destination_dir."/". basename($source_fname);
            my $backupfile = $destination_file.$backupprefix;
            my $mode = oct($DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_USE_SELECTED_PERM});
            my $uid = $DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_FILE_OWNER};
            my $gid = $DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_FILE_GROUP_OWNER};
            my $use_existing_perms = $DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_USE_EXISTING_PERM};
            my $copy_as_binary = $DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_FILE_BINARY_COPIED};
           
            #
            # policy is enabled so copy the file over from sysvol into the staging area
            #
            my $stage_path_file = "$stagepathmachine/$source_fname$stagingprefix";
            my $stage_path_dir  = dirname($stage_path_file);
            my $stage_path_dir_stat = stat($stage_path_dir);
            #
            # make sure that the directory where the staging files will be copied to exists.
            # If not create one before using smb because smb will not create the local directory
            # for you; it expects the fully qualified directory path to the local file already exist.
            #
            if (!$stage_path_dir_stat) {
                eval { mkpath($stage_path_dir, 0, 0755)};
                if ($@) {
                    ERROR_OUT("Mkdir of staging directory path $stage_path_dir failed.");
                    return 0;
                }
            }
            #
            # check the file type before copying it, and restore to default value after finish copying.
            #
            if ($copy_as_binary)
            {
                $smb->convertCRLF(0);
            } else
            {
                $smb->convertCRLF(1);                
            }    
            DEBUG_OUT("Copy file $sysvolpath$source_fname from sysvol to $stage_path_file");      
            $smb->GetMod($sysvolpath.$source_fname, $stage_path_file);

            #
            # check if smb copy successed
            #
            my $stage_stat = stat($stage_path_file);
            if (! $stage_stat) {
                ERROR_OUT("Smb copy from sysvol to staging area $stage_path_file failed. Aborting..");
                return 0;
            }
            #
            # check if directory path on the destination exists; if not create one
            #
            my $destdir_stat = stat($destination_dir);
            if (! $destdir_stat) {
                #
                # destination directory does not exist; create one
                #
                eval { mkpath($destination_dir, 0, 0755)};
                if ($@) {
                    ERROR_OUT("Mkdir of destination directory $destination_dir failed.");
                    return 0;
                }
            }
            # current file
            my $destdir_file_stat = stat($destination_file);
            #backup file
            my $destdir_backup_file_stat = stat($backupfile);
            #just some default mode
            my $current_mode = 0440;
            if ($destdir_file_stat) {
                #
                # current file exists; retain the mode
                #
                $current_mode = $destdir_file_stat->mode;
            }
            #
            # if no backup and current file exists then make a backup
            #
            if (!$destdir_backup_file_stat && $destdir_file_stat) {
                copy($destination_file, $backupfile);
                chmod $current_mode, $backupfile;
                chown $destdir_file_stat->uid, $destdir_file_stat->gid, $backupfile;
            }
            #
            # copy file from the staging area to the destination area
            #
            $rcode = copy($stage_path_file, $destination_file);
            if (!$rcode) {
                #
                # Copy failed abort
                #
                ERROR_OUT("Copy of $stage_path_file to $destination_file failed. Aborting!");
                return 0;
            }
            #
            # use the permissions specified in the GP
            #
            if ($use_existing_perms) {
                chmod $current_mode, $destination_file;
                if ($destdir_file_stat) {
                    chown $destdir_file_stat->uid, $destdir_file_stat->gid, $destination_file;
                }
            } else {
                #
                # use the permissions specified in the GP
                #
                chmod $mode, $destination_file;
                chown $uid, $gid, $destination_file;
            }
        } 
    }
    DEBUG_OUT("Total of $nfiles files were processed");
   return 1
}

#
# Method to replace environment variables within 
# the path
# input parameters - destination path.
# return - path with subsituted enviroment variables
#
sub expand_variables($)
{
    my ($path) = @_;
    $path =~ s/\$(\w+)/$ENV{$1}/g;
    return $path;
}

#
# rollback back up files
# input parametes: 
# parameter 1 - string class type (machine, user)
# parameter 2 - string username 
#
sub rollback ($)
{
    my ($cls)  = @_;
    my $rcode;
    my $nfiles = 0;
    my @stage_file_lst=();

    initRegistryValues($cls);

   DEBUG_OUT("Rolling back or restoring files");
    #
    # Iterate over the list of files to process
    #
   foreach my $source_key_fname (@SOURCE_REGISTRY_KEYS) {
        my $source_fname = $DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_SOURCE_FILENAME_SOURCE};
        if ($source_fname) { 
            $nfiles++;
            my $destination_dir = expand_variables($DESTINATIONS{$source_key_fname}->{$REGKEY_ITEM_SOURCE_FILENAME_DESTINATION});
            my $destination_file = $destination_dir."/".basename($source_fname);
            my $backupfile = $destination_file.$backupprefix;
            my $stage_path_file = "$stagepathmachine/$source_fname$stagingprefix";
            #
            # put back our original file when we leave the domain
            #
            my $backfile = stat($backupfile);
            my $curfile = stat($destination_file);
            my $stagefile = stat($stage_path_file);
            push(@stage_file_lst, $stage_path_file);
            if($backfile)
            {
                #
                # backup file exists; restore it
                #
                copy($backupfile, $destination_file);
                DEBUG_OUT("Restored backfile $backupfile to the original file.");
                #
                # Restore back the permissions
                #
                chmod $backfile->mode, $destination_file;
                chown $backfile->uid, $backfile->gid, $destination_file;
                unlink $backupfile;
            } 
            elsif ($stagefile) {
                #
                #originally there was no file - so delete it
                #
                unlink $destination_file;
            }
        }
    }
    #
    # if machine policy then we are leaving the domain remove the staging files
    #
    if ($cls eq "machine") {
        foreach my $sfn (@stage_file_lst) {
        DEBUG_OUT("Unmapping machine policy. Therefore removing the staging file $sfn");
            unlink $sfn;
        }
    }
    DEBUG_OUT("Total of $nfiles files were processed");
}



#############################################################
#                                                                                                                                                    #                                             
#                                                 MAIN PROGRAM                                                                   #
#                                                                                                                                                    #
#############################################################

my $args = CentrifyDC::GP::Args->new('machine');

CentrifyDC::GP::Registry::Load(undef);

if ($args->isMap())
{
    if (is_filecopy_enabled($args->class()))
    {
        my $lock = CentrifyDC::GP::Lock->new('gp.smbgetfile');
        if (! defined($lock))
        {
            FATAL_OUT("Cannot obtain lock");
        }

        copy_files_to_destination($args->class()) or FATAL_OUT("Copy mapping operation failed!");
    }
}
else
{
    if (is_filecopy_enabled($args->class()))
    {
        rollback($args->class());
    }
}

