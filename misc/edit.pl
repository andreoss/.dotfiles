#!/usr/bin/env perl
use strict;
use warnings;
use autodie;

use File::Temp qw/tempfile/;
use File::Copy qw/move copy/;

use feature qw/say/;

use English;

die("Usage: $0 '/where/' 'line to add' 'file'") unless @ARGV == 3;

my ( $where, $insert, $file ) = @ARGV;

if ( $insert =~ /\\n/ ) {
    $insert =~ s/\\n/\n/xgms;
}

if ( $where eq '-flip' ) {
    $where = $insert =~ s/=.*$//rx;
    $where = "^${where}";
}
elsif ( $where eq '-uncomment' ) {
    $where = "^[#]?${insert}";
}

open( my $input, '<', $file );
my $output = File::Temp->new();

my $inserted = 0;
{

    for my $line (<$input>) {
        chomp($line);
        my $match = $line =~ $where;

        unless ($match) {
            $output->say($line);
            next;
        }
        if ( $match && !$inserted ) {
            if ( $line eq $insert ) {
                *STDERR->say("Found `$insert' at $file:$NR");
                $inserted = -1;
                next;
            }
            *STDERR->say("Replaced `$line` with `$insert' at $file:$NR");
            $output->say($insert);
            $inserted = 1;
            next;
        }
        if ($match) {
            *STDERR->say("Removed `$line' at  $file:$NR");
        }

    }
    if ( $inserted == 0 ) {
        $output->say($insert);
        *STDERR->say("Appended `$insert' at $file:$NR");
        $inserted = 1;
    }
}
$input->close();
$output->close();

copy( $output->filename, $file ) if $inserted > 0;
