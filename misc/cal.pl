#!/usr/bin/perl
use strict;
use warnings;
use feature 'say';
use Time::Piece ':override';
use Time::Seconds;

BEGIN {
    Time::Piece->use_locale()
}


sub boxed {
    sprintf(">%3s", int(shift));
}

sub color {
    my ($day, $color_code) = @_;
    return "\${color $color_code}$day\${color}";  
}

sub centered {
    my $text = shift;
    return "\${alignc}$text";  # Centered format
}

sub grayed_out {
    color(shift, 'grey');
}


our $today = localtime;

sub wday {shift->wday;}

my $f = $today; 
while (1) {
    $f -= ONE_DAY;
    next if $f->mon  == $today->mon;
    next if $f->wday != 1;
    last;
}

my @t= ();
my @w= ();

push(@t, [centered($today->fullmonth)]);
push(@t, [map {sprintf("%4s",$_)} localtime->day_list()]);
for (my $c = $f; !($c->mon > $today->mon && wday($c) == 1); $c += ONE_DAY ) {

    my $o = sprintf("%4s", $c->mday);  

    if ($c->mon != $today->mon) {
        $o = grayed_out($o);
    }
    if ($c->mday == $today->mday && $c->mon == $today->mon) {
        $o = boxed($o);
    }
    if (wday($c) == 1 && $c->mon == $today->mon) {
        $o = color($o, 'ea3333');
    }
    if (wday($c) == 7 && $c->mon == $today->mon) {
        $o = color($o, 'aa3333');
    } 

    push(@w, $o);
    
    if (wday($c) == 7) {
        push(@t, [@w]);
        @w = ();
    }
}

say "\${alignc}${_}" for map {join(' ', map { sprintf("%s", $_) } @$_)} @t;

