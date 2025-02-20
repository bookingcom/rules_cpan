#!/usr/bin/env perl

use v5.36;
use Module::CoreList;
use JSON::PP qw//;

my $out;

for my $version (keys %Module::CoreList::version) {
    $out->{ $version } = $Module::CoreList::version{ $version };
}

my $json = JSON::PP->new->ascii->pretty->allow_nonref;

my $filename = $ARGV[0] || '/dev/stdout';

open my $fh, '>', $filename or die "Can't open $ARGV[0]: $!";

say $fh $json->encode($out);

close($fh);
