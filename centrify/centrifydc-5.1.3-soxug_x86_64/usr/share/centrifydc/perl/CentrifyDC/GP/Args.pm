##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl mapper script args module.
#
# This module get args from ARGV and validate. If args are invalid, it
# will print usage and exit 2.
#
#
# For machine mapper script, the valid format should be:
#
#   mapper_script_name <map|unmap> mode
#
# For user mapper script, the valid format should be:
#
#   mapper_script_name <map|unmap> username mode
#
#
# To create a new Args for machine mapper:
#
#   my $args = CentrifyDC::GP::Args->new('machine');
#
# To create a new Args for a mapper that can be both machine and user mapper:
#
#   my $args = CentrifyDC::GP::Args->new();
#
# To get class:
#
#   $args->class();
#
# To get user:
#
#   $args->user();
#
# To get mode:
#
#   $args->mode();
#
# To get action:
#
#   $args->action();
#
# To check if action is map:
#
#   $args->isMap();
#
##############################################################################

use strict;

package CentrifyDC::GP::Args;
my $VERSION = '1.0';
require 5.000;

use File::Basename qw(basename);

sub new($;$);
sub class($);
sub user($);
sub mode($);
sub action($);
sub isMap($);
sub _isvalid($$);
sub _usage($$);



#
# create instance
#
#   $_[0]:  self
#   $_[1]:  class (machine/user, will validate args based it. Optional.)
#
#   return: self    - successful
#
#   exit 2: failed
#
sub new($;$)
{
    my ($invocant, $expected_class) = @_;
    my $class = ref($invocant) || $invocant;

    my $args_action = $ARGV[0];
    my $args_mode   = $ARGV[2] ? $ARGV[2] : $ARGV[1];
    my $args_user   = $ARGV[2] ? $ARGV[1] : undef;
    my $args_class  = $args_user ? 'user' : 'machine';

    my $self = {
        action  => $args_action,
        mode    => $args_mode,
        user    => $args_user,
        class   => $args_class,
    };
    _isvalid($self, $expected_class) or _usage($self, $expected_class);

    bless($self, $class);

    return $self;
}

#
# get class
#
#   $_[0]:  self
#
#   return: string  - class
#
sub class($)
{
    return $_[0]->{class};
}

#
# get user
#
#   $_[0]:  self
#
#   return: string  - user
#
sub user($)
{
    return $_[0]->{user};
}

#
# get mode
#
#   $_[0]:  self
#
#   return: string  - mode
#
sub mode($)
{
    return $_[0]->{mode};
}

#
# get action
#
#   $_[0]:  self
#
#   return: string  - action
#
sub action($)
{
    return $_[0]->{action};
}

#
# check if action is map
#
#   $_[0]:  self
#
#   return: 0       - no
#           1       - yes
#
sub isMap($)
{
    ($_[0]->{action} eq 'map') ? (return 1) : (return 0);
}

#
# validate args based on expected class
#
# certain mapper script may be run as both machine and user script. in this
# case, class should be undef.
#
# action: must be map/unmap
# mode:   cannot be undef if action is map
# user:   cannot be undef if class is user
# class:  cannot be undef. compare with $_[1]
#
#   $_[0]:  self
#   $_[1]:  expected class (machine/user/undef)
#
#   return: 1 - valid
#           0 - invalid
#
sub _isvalid($$)
{
    my ($self, $class) = @_;

    $self->{action} or return 0;
    ($self->{action} eq 'map' or $self->{action} eq 'unmap') or return 0;
    ($self->{action} eq 'map' and ! $self->{mode}) and return 0;

    $self->{class} or return 0;
    ($class and $class ne $self->{class}) and return 0;

    ($self->{class} eq 'user' and ! $self->{user}) and return 0;

    return 1;
}

#
# print usage based on class and then exit 2
#
# certain mapper script may be run as both machine and user script. in this
# case, class should be undef.
#
#   $_[0]:  self
#   $_[1]:  class (machine/user/undef)
#
#   exit:   2
#
sub _usage($$)
{
    my $class = $_[1];

    my $program_name = basename $0;

    if (! $class)
    {
        print(STDERR "Usage: as machine mapper: $program_name <map|unmap> mode\n");
        print(STDERR "       as user mapper:    $program_name <map|unmap> username mode\n");
    }
    elsif ($class eq 'machine')
    {
        print(STDERR "Usage: $program_name <map|unmap> mode\n");
    }
    elsif ($class eq 'user')
    {
        print(STDERR "Usage: $program_name <map|unmap> username mode\n");
    }

    exit(2);
}

1;
