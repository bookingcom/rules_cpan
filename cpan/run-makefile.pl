#!/usr/bin/env perl

use v5.36;

use Cwd qw/cwd abs_path/;
use File::Basename qw/dirname basename/;
use File::Copy qw/copy/;
use File::Path qw(make_path);
use Config qw/config_vars/;
use Config;

BEGIN {
    push @INC, dirname(__FILE__);
}

use PerlToolchain qw/PERL_TOOLCHAIN_PATH/;

sub read_file($filename) {
    open(my $f, '<', $filename) or die "OPENING $filename: $!\n";
    local $/;
    return <$f>;
}

sub write_file($filename, $string) {
    open(my $f, '>', $filename) or die "OPENING $filename: $!\n";
    print $f $string;
    close($f);
}

my $CWD = cwd;

chdir(dirname($ENV{PATH_TO_SCRIPT}));

system("$^X Makefile.PL PREFIX=$ENV{BINDIR}/lib/perl5") == 0 or die "ERROR: Makefile.PL failed: $!";

( my $perl_toolchain = PERL_TOOLCHAIN_PATH ) =~ s!^external/!!g;
$perl_toolchain =~ s/\+/\\+/g;

( my $external_path = $INC{'Config.pm'} ) =~ s{(.*/external)(/?.*)}{$1}g;

my $makefile = read_file('Makefile');
$makefile =~ s!(${external_path}/${perl_toolchain}/)!$ENV{BINDIR}/lib/perl5/!gm;

write_file('Makefile', $makefile);

for my $path (@ARGV) {
    my $file = basename($path);
    my $dirname = dirname($path);
    make_path("${CWD}/${dirname}") unless -e "${CWD}/${dirname}";
    copy($file, "${CWD}/${path}") or die "ERRROR: failed to copy ${path}: $!";
}

1;
