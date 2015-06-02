#!/usr/bin/env perl
use strict;
use warnings;

use Time::Piece ':override';
use Time::Seconds;

use experimental qw(signatures);
use feature      qw(say);

BEGIN {
    Time::Piece->use_locale();
}

sub boxed($n) { sprintf( ">%3s", int($n) ); }

sub color( $day, $color_code ) {
    return "\${color $color_code}$day\${color}";
}

sub centered($text) {
    return "\${alignc}$text";    # Centered format
}

sub grayed_out($text) {
    color( $text, 'grey' );
}

our $today = localtime;

sub wday($d) { $d->wday; }

my $f = $today;
while (1) {
    $f -= ONE_DAY;
    next if $f->mon == $today->mon;
    next if $f->wday != 1;
    last;
}

my @t = ();
my @w = ();

push( @t, [ centered( $today->fullmonth ) ] );
push( @t, [ map { sprintf( "%4s", $_ ) } localtime->day_list() ] );

sub next_day($c) {
    my $n = $c + ONE_DAY;
    if ( $c->mday == $n->mday ) {
        $n += 60 * 60;
    }
    $n;
}

for (
    my $c = $f ;
    !( $c->mon > $today->mon && wday($c) == 1 ) ;
    $c = next_day($c)
  )
{

    my $o = sprintf( "%4s", $c->mday );

    if ( $c->mon != $today->mon ) {
        $o = grayed_out($o);
    }
    if ( $c->mday == $today->mday && $c->mon == $today->mon ) {
        $o = boxed($o);
    }
    if ( wday($c) == 1 && $c->mon == $today->mon ) {
        $o = color( $o, 'ea3333' );
    }
    if ( wday($c) == 7 && $c->mon == $today->mon ) {
        $o = color( $o, 'aa3333' );
    }
    push( @w, $o );

    if ( wday($c) == 7 ) {
        push( @t, [@w] );
        @w = ();
    }
}

say "\${alignc}${_}" for map {
    join( ' ', map { sprintf( "%s", $_ ) } @$_ )
} @t;

