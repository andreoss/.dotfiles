#!/usr/bin/env perl
use strict;
use warnings;
use IO::File;
use autodie;
use feature qw(say);

my $f = shift;

die "Not .aria2: $f"       unless $f =~ /\.aria2\z/;
die "Not found:  $f"       unless -r $f;
die "Not invalid size: $f" unless -s $f;

my $fh = IO::File->new( $f, O_RDONLY );
binmode $fh;

local $/;
my $buffer;
{
    local $/ = undef;
    $buffer = <$fh>;
}
$fh->close;

my $len        = unpack( "N", substr( $buffer, 6, 4 ) );
my $hash_bytes = substr( $buffer, 10, $len );
my $hash =
  join( '', map { sprintf "%02x", ord($_) } split //, $hash_bytes );
say "magnet:?xt=urn:btih:$hash";
