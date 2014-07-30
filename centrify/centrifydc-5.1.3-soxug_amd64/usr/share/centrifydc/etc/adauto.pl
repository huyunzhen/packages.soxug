#!/bin/sh /usr/share/centrifydc/perl/run
 
# executable map file for automount
# it is passed the mount point name and returns the map entry for it
# or returns nothing if it cannot find an entry
# the map data comes from AD NIS map data
# the map name is derived from the executable name, so the correct thing to do is symlink 
# from /usr/share/centrifydc/etc/adauto.pl to /etc/auto.mymap
# note that this script must run as root (or at least somebody with read rights to the krb5.keytab)
# because it uses our -m option on the ldapsearch command
# our ldap package must be installed

# complete rewrite for 4.5
# use new Ldap library
# store map in local DBM file
# only reload it when the local file is too old
# even then - avoid reload if we cant talk to a DC
# load a config script
# if run with no key value then reload - this is used to do asynch reload

use strict;
use Getopt::Long;
Getopt::Long::Configure("bundling", "no_ignore_case");

use lib "../perl";
use lib '/usr/share/centrifydc/perl';
use File::Spec;
use File::Temp "tempfile";
use CentrifyDC::GP::General;

our $DBM_DIR = "/var/centrifydc/auto_maps"; 
our $TIMESTAMP_KEY = "\$\$\$";
  
my $map = (File::Spec->splitpath($0))[2];
my $key = $ARGV[0]; 

our %opts;
GetOptions( "g|debug" => \$opts{g},
            "h|help"  => \$opts{h} );
my $verbose;
$verbose = 1 if $opts{g};
if ($opts{h}) 
{
    do_usage();
    exit;
}

our $RELOAD_TIME = $CentrifyDC::Config::properties{"adauto.reloadtime"} || 60 * 30;
mkdir(${DBM_DIR}) unless stat(${DBM_DIR}); # just in case

our %map_dbm;
dbmopen(%map_dbm, "${DBM_DIR}/${map}", 0666);

if (not $key) # we are calling ourselves to do async reload
{
   loadmap($map);
   exit;
}

#get timestamp
my $ts = $map_dbm{$TIMESTAMP_KEY};
if(not $ts or $verbose) {
   # reload if no timestamp (initial load)
   # or if too old
   loadmap($map);
}
elsif (time - $ts > $RELOAD_TIME)
{
   system "$0 &";
}

my $v = $map_dbm{$key};
$v = $map_dbm{"*"} unless $v; 
dbmclose %map_dbm;
#$v = eval("\"$v\"");
print ${v}."\n" if $v;
exit; 

sub do_usage
{
    print <<EOF;
usage:
    Create a symbolic link with map name(eg: auto.host) under /etc to adauto.pl.
    Get map value: \t\t/etc/auto.host key
    Reload local cache map:\tadauto.pl  
    options:
         -g, --debug                print debug information
         -h, --help                 print this help information and exit
EOF
}

sub loadmap
{

   my $ade = <<EOF;
bind -machine [adinfo domain]
if [catch {set f [open /var/centrifydc/kset.automap]} rcx] {
    set zb [adinfo zone]
} else {
    set zb [gets \$f];
    close \$f;
}
slz \$zb

while {1} {
   catch {select_nis_map $map; list_nis_map; exit 0}
   set p ""
   catch {set p [gzf parent]}
   if {\$p != ""} {
      slz \$p
   } else {
     exit 1
     }
}
EOF
   my ($handle, $fname) = tempfile();
   print $handle $ade;
   my @mapinfo = `adedit $fname`;
   my $rc = $?;
   unlink($fname);	
   return if $rc;

   for ( keys %map_dbm ) {
       delete $map_dbm{$_};
   }

   $map_dbm{"\$\$\$"} = time;
   foreach my $line (@mapinfo)
   {
      chomp $line;
      $line =~ m/^(.*):\d+: (.*)$/;
      $map_dbm{$1} = $2;
   }
}

