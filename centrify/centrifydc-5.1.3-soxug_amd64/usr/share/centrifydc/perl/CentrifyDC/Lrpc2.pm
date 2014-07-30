use strict;

##############################################################################
#
# Copyright (C) 2014 Centrify Corporation. All rights reserved.
#
##############################################################################

require Exporter;
our $VERSION = 1.00;
package CentrifyDC::Lrpc2;
use IO::Socket;

sub open()
{
   shift;
   my $self={};
   bless $self;
   $self->{session} = lrpc2Connect(shift);
   return $self;
}



sub send() {
   my $self=shift;
   my $type = shift;
   my $map = shift;
   my $msg = newMsg($type);
   for (my $i = 0; $i < length($map); $i++) {
      my $m = substr $map, $i, 1;
      if($m eq "i") {$msg = addInt($msg, shift);}
      elsif($m eq "s") {$msg = addString($msg, shift);}
      elsif($m eq "B") {$msg = addBlob($msg, shift);}
      elsif($m eq "u") {$msg = addUInt($msg, shift);}
      elsif($m eq "Q") {$msg = addQuad($msg, shift);}
      elsif($m eq "S") {my $a = shift;$msg = addStringSet($msg, @$a);}
      else {die( "bad map char");};
   }
   my $repcode = lrpc2Send($self, $msg);
   if($repcode == 1)
   {
      $repcode= doAuth($self);
   }
   return $repcode;
}

sub getString{ 
   my $self = shift;
   my $msg = shift;
   my $off = $self->{offset};
   my ($t, $s) = unpack("x${off}CI/Z", $self->{currmsg});
   die unless $t == 4;
   $self->{offset} = $off + length($s) + 5;
   return $s;
}

sub getStringSet{
    
   my $self = shift;
   my $msg = shift;
   my $off = $self->{offset};
   my ($t, $c) = unpack("x${off}CI", $self->{currmsg});
   die unless $t == 7;
   $off += 5;
   my @vals;
   for(my $i = 0; $i < $c ; $i++)
   {
      my ($v) = unpack("x${off}I/Z", $self->{currmsg});
      push @vals, $v;
      $off += (4 + length($v));
   }
   $self->{offset} = $off;
   return @vals;
}
sub getUint32{ 
   my $self = shift;
   my $msg = shift;
   my $off = $self->{offset};
   my ($t, $s) = unpack("x${off}CL", $self->{currmsg});
   die unless $t == 3;
   $self->{offset} = $off + 5;
   return $s;
}

sub getInt32{ 
   my $self = shift;
   my $msg = shift;
   my $off = $self->{offset};
   my ($t, $s) = unpack("x${off}Cl", $self->{currmsg});
   die unless $t == 2;
   $self->{offset} = $off + 5;
   return $s;
}
sub getBool {
   my $self = shift;
   my $msg = shift;
   my $off = $self->{offset};
   my ($t, $b) = unpack("x${off}CC", $self->{currmsg});
   die unless $t == 1;
   $self->{offset} = $off + 2;
   return $b;

}

sub doAuth {
   my $self = shift;
   my $repcode= $self->send(1, "uu", $<, $) + 0);
   my $ufile = $self->getString();
   my $gfile = $self->getString();
   my $urand = getBytes($ufile);
   my $grand = getBytes($gfile);
   $repcode = $self->send(2, "BB", $urand, $grand);
   return $repcode;
}

sub getBytes {
   my $file = shift;
   my $size = (stat($file))[7];
   open F, $file;
   my $b;
   my $len = read(F, $b, $size);
   die unless $len == $size;
   return $b;
}

sub newMsg($)
   {
    my ($type) = @_;
    return pack("S", $type);
}

sub addInt($$)
    {
       my ($msg, $val) = @_;
       return $msg .= pack("CL", 2, $val);
}
sub addStringSet
    {
       my $msg = shift(@_);
       $msg .= pack("CL", 7, @_ + 0);
       for my $val (@_) {
          $msg .= pack("L/a*", $val);
       }
       return $msg;
}
sub addUInt($$)
    {
       my ($msg, $val) = @_;
       return $msg .= pack("CL", 3, $val);
}
sub addQuad($$)
    {
       my ($msg, $val) = @_;
       $msg = addUInt($msg, 0);
       $msg = addUInt($msg, $val);
}
sub addString($$)
    {
       my ($msg, $val) = @_;
       return $msg .= pack("CL/a*",4, $val);
}

sub addBlob($$)
    {
       my ($msg, $val) = @_;
       return $msg .= pack("CL/a*",6, $val);
}
sub lrpc2Connect()
{
   my $path = shift;
   my $client = IO::Socket::UNIX->new(Peer  => $path,
                                Type      => SOCK_STREAM,
                                Timeout   => 10 ) or die $@;
   my $ver = pack("L", 2);
   $client->send($ver);
   $client->recv(my $buf, 4);
   die "bad reply from daemon" unless unpack("L", $buf) == 1;
   return $client;  
}

sub lrpc2Send($$)
{
   my ($self, $data) = @_;
   my $client = $self->{session};
   my $hdr = pack("LLA*x", 0xabcd8012, length($data) + 9, $data);
   $client->send($hdr);
   my $len = $client->recv(my $buf, 10);
   my ($magic, $length, $repcode) = unpack("LLS", $buf);
   die unless $magic == 0xabcd8012;
   $client->recv(my $buf2, $length - 8);
   $self->{currmsg} = $buf2;
   $self->{offset} = 0;
   return $repcode;
}

1;
