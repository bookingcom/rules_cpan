#!/usr/bin/env perl

use v5.36;

use Cwd qw/cwd abs_path/;
use File::Basename qw/dirname basename/;
use File::Copy qw/copy/;
use File::Path qw(make_path);

my $CWD = cwd;
use Data::Dumper;

chdir(dirname($ENV{PATH_TO_SCRIPT}));

say STDERR Dumper(\%ENV);
say STDERR abs_path('.');
say STDERR $^X;
die 1;

system("$^X Makefile.PL SITELIBEXP=foo > /dev/stderr") == 0 or die "ERROR: Makefile.PL failed: $!";

#my @lines = path('Makefile')->lines_utf8;

#@lines = map { my @parts = split() } @lines;



for my $path (@ARGV) {
    my $file = basename($path);
    my $dirname = dirname($path);
    make_path("${CWD}/${dirname}") unless -e "${CWD}/${dirname}";

    copy($file, "${CWD}/${path}") or die "ERRROR: failed to copy ${path}: $!";
}

1;
