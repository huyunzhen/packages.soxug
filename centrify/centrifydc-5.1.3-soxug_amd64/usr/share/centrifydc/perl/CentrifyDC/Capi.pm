use strict;

##############################################################################
#
# Copyright (C) 2014 Centrify Corporation. All rights reserved.
#
##############################################################################

package CentrifyDC::Capi;
require Exporter;
our $VERSION = 1.00;
use CentrifyDC::Lrpc2;
our @ISA = qw( Exporter );
our @EXPORT = qw(
   GROUP_TYPE_UNIX
   GROUP_TYPE_WINDOWS
   GROUP_TYPE_ANY
   LDAP_SCOPE_BASE
   LDAP_SCOPE_ONE
   LDAP_SCOPE_TREE
);

use constant
{
   GROUP_TYPE_UNIX => 0,
   GROUP_TYPE_WINDOWS => 1,
   GROUP_TYPE_ANY => 2,

   LDAP_SCOPE_BASE => 0,
   LDAP_SCOPE_ONE => 1,
   LDAP_SCOPE_TREE => 2,

};


#{ CAPIGetObjectByName, "CAPIGetObjectByName", AUTH_REQ, "ssu", "iiiiiii?(siS)*" },  /* 901 */
#{ CAPILdapFetch, "CAPILdapFetch", AUTH_REQ, "ssSu", "iiiiiii?(siS)*" },  /* 908 */
#{ CAPILdapPagedSearch, "CAPILdapPagedSearch", AUTH_REQ, "sssSiuuu", "iiiiii(ubi)?" },  /* 909 */
#{ CAPILdapPagedSearchClose, "CAPILdapPagedSearchClose", AUTH_REQ, "i", "iiiiii" },  /* 914 */
#{ CAPIValidateUserGroup, "CAPIValidateUserGroup", AUTH_REQ, "sSi", "iiiiii" },  /* 916 */
#{ CAPILdapPagedSearchGetNext, "CAPILdapPagedSearchGetNext", AUTH_REQ, "iu", "iiiiiiu?b?i?(siS)*" },  /* 910 */
 
#/// The group name parameter is a Unix name.
#define CDC_GROUP_NAME_TYPE_UNIX    0

#/// The group name parameter is a Windows name.
#define CDC_GROUP_NAME_TYPE_WINDOWS 1

#/// Check all possible name formats.
#define CDC_GROUP_NAME_TYPE_ANY     2
sub open
{
   shift;
   my $self={};
   bless $self;
   my $lrpc = CentrifyDC::Lrpc2->open("/var/centrifydc/daemon2");
   $lrpc->send(917, "iiii", 2,2,2,2);
   $self->{lrpc} = $lrpc;
   return $self;
}

sub validateUserGroup {
   my ($self, %args) = @_;
   my $s = $self->{lrpc};
   if($args{groups} == 1){
      $args{groups} = [$args{groups}];
   }
   $s->send(916, "sSi", $args{user}, $args{groups}, $args{type});
   my $ret = $s->getInt32();
   return ($ret == 0);
}

sub ldapSearch{
   my ($self, %args) = @_;
   my $domain = $args{domain} || "";
   my $filter = $args{filter} || "(objectclass=*)";
   my $options = $args{options} || 0;
   my $attrs = $args{attrs} || [];
   my $scope = $args{scope} || LDAP_SCOPE_BASE;
   my $base = $args{base} || "";

   my $s = $self->{lrpc};
   $s->send(909, "sssSiuuu", $domain, $filter, $base, $attrs, $scope, 0, 0, $options);
   my $ret = getErrorCodes($s);
    if($ret == 0)
   {
     my $count = $s->getUint32();
     my $last = $s->getBool();
     my $handle = $s->getInt32();

      my @objects;
      while(1)
      {
         $s->send(910, "iu", $handle, $args{options});
         $ret = getErrorCodes($s);
         last if($ret != 0);
         $count = $s->getUint32();
         $last = $s->getBool();
         push @objects, loadObject($s);
      }
      $s->send(914, "i", $handle);
      return @objects;
   }
   else
   {
      return undef;
   }

}

sub getErrorCodes {
   my $session = shift;
   my $ret =  $session->getInt32();
   $session->getInt32();
   $session->getInt32();
   $session->getInt32();
   $session->getInt32();
   $session->getInt32();
   return $ret;
}

sub loadObject {
   my $session = shift;
   my %obj;
   my $attrs = $session->getInt32();
   for(my $i = 0; $i < $attrs; $i++)
   {
      my $attr = $session->getString();
      my $count = $session->getInt32();
      my @a = $session->getStringSet();
      @obj{$attr} = @a;
   }
   return \%obj;
}
1;
