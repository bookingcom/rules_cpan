#!/usr/bin/env perl

use v5.36;

use Config;
use Cwd qw/cwd/;
use File::Basename qw/dirname/;
use File::Find qw/find/;

select(STDERR);
$|=1;            # Autoflush STDERR.
select(STDOUT);  # This doesn't undo STDERR's autoflushing.
$|=1;            # Autoflush STDOUT.

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

my $original_cwd = cwd();

chdir(dirname($ARGV[0]));

my $install_base = "$original_cwd/" . dirname($ARGV[1]);

$ENV{MAKE}="$original_cwd/$ENV{MAKE}" if $ENV{MAKE} !~ m{^/};
$ENV{LD}="${original_cwd}/$ENV{LD}" if $ENV{LD} !~ m{^/};
$ENV{CC}="${original_cwd}/$ENV{CC}" if $ENV{CC} !~ m{^/};
$ENV{CPP}="${original_cwd}/$ENV{CPP}" if $ENV{CPP} !~ m{^/};

my @args = (
    "CC=$ENV{CC}",
    "INSTALL_BASE=${install_base}",
    "INSTALLARCHLIB=${install_base}/perl5",
    "INSTALLBIN=${install_base}/bin",
    "INSTALLMAN1DIR=none",
    "INSTALLMAN3DIR=none",
    "INSTALLPRIVLIB=${install_base}/perl5",
    "INSTALLSCRIPT=${install_base}/bin",
    "LD=$ENV{LD}",
    "NO_PACKLIST=1",
    "OPTIMIZE=-O3",
);

use Data::Dumper;

# drop -fstack-protector as it's not compatible with zig linker
#my $config = read_file($INC{'Config.pm'});
#$config =~ s/-fstack-protector//g;
#$config =~ s{-L/usr/local/lib}{}g;
#write_file('Config.pm', $config);

my @perl5lib = split(':', $ENV{PERL5LIB});
@perl5lib = (cwd(), @perl5lib);

if ($ENV{EXTRA_PERL5LIB}) {
    my @paths = split(':', $ENV{EXTRA_PERL5LIB});
    @paths = map { "${original_cwd}/$_" } @paths;
    @perl5lib = (@perl5lib, @paths);
}

$ENV{PERL5LIB} = join(':', @perl5lib);

say STDERR Dumper(\%ENV);

my $args = join(" ", @args);

say STDERR "Running: $^X Makefile.PL $args";

if (-e 'Makefile.PL') {
    system("$^X Makefile.PL $args >> /dev/stderr") == 0 or
        die "Failed to execute MakeMaker ($args): $!";

    say STDERR "Running: $ENV{MAKE} pure_install $args";
    system("$ENV{MAKE} pure_install $args >> /dev/stderr") == 0 or
        die "Failed to execute Make pure_install: $!";
} elsif (-e 'Build.PL') {
    system("$^X Build.PL $args >> /dev/stderr") == 0 or
        die "Failed to execute Module::Build ($args): $!";

    say STDERR "Running: Build install $args";
    system("$^X ./Build build $args >> /dev/stderr") == 0 or
        die "Failed to execute ./Build install: $!";
    system("$^X ./Build install $args >> /dev/stderr") == 0 or
        die "Failed to execute ./Build install: $!";

} else {
    die "Makefile.PL nor Build.PL found";
}

1;
