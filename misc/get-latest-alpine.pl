#!/usr/bin/env perl
use v5.14;

use strict;
use warnings;
use feature qw(say);

use HTTP::Tiny;
use CPAN::Meta::YAML;

our $base_url =
  'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64';

our $client = HTTP::Tiny->new;

my $response = $client->get("$base_url/latest-releases.yaml");

die("Failed to fetch data: $response->{status} - $response->{reason}\n")
  unless ( $response->{success} );

my $yaml = CPAN::Meta::YAML->read_string( $response->{content} )
  or die( CPAN::Meta::YAML->errstr );

my $prefered_flavour = shift || 'alpine-virt';
for my $x ( map { @$_ } @$yaml ) {
    if ( $x->{flavor} eq $prefered_flavour ) {
        say "${base_url}/" . $x->{iso};
        exit(0);
    }
}
exit(1);
