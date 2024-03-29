#!/usr/bin/perl

$| = 1;
use warnings;
use strict;
use locale; # for sort

use Getopt::Std;
use AptPkg::Config '$_config';
use AptPkg::Cache;

our ($opt_n, $opt_d, $opt_c) = (0, 
				'/afs/athena.mit.edu/system/athena10/thirdparty',
				'/var/lib/debathena-thirdparty');

getopts('nd:c:');

sub debug {
    if ($opt_n) {
	print join(' ', 'D:', @_, "\n");
    }
}


my $codename = `/usr/bin/lsb_release -sc`;
die "Can't determine codename" unless ($? == 0);
chomp($codename);

(-d $opt_d) || die "$opt_d is not a directory";
(-d $opt_c) || die "$opt_c is not a directory";

# Initialize the APT configuration
$_config->init;
my $cache = AptPkg::Cache->new;
my $policy = $cache->policy;

my %packages = ();
my %depends = ();

open(COMMON, join('/', $opt_d, 'common')) || die "Can't open $opt_d/common";
debug("Reading 'common' file...");
while (<COMMON>) {
    chomp;
    s/^\s+//;
    s/\s+$//;
    next if /^#/;
    next unless /\S/;
    if (/^-/) {
	warn "Ignoring invalid package exclusion in the common file, line $.";
	next;
    } 
    if (/^(\S+) \| (\S+)$/) {
	debug("Examining conditional line: $_");
	foreach my $p ($1, $2) {
	    debug("Checking for $p");
	    if ($cache->{$p} && $cache->{$p}->{VersionList}) {
		debug("Adding $p to dependencies");
		$packages{$p} = 1;
		last;
	    }
	}
	unless (exists($packages{$1}) || exists($packages{$2})) {
	    warn "Could not satisfy conditional dependency: $_!";
	}
    } elsif (/^(\S+)(?: (\S+))+$/) {
	my ($pkg1, @rest) = (split(' ', $_));
	$packages{$pkg1} = 1;
	$depends{$pkg1} = \@rest;
    } elsif (/^\?(\S+)$/) {
	debug("Adding $1 to recommendations");
	$packages{$1} = 2;
    } else {
	debug("Adding $_ to dependencies");
	$packages{$_} = 1;
    }
}
close(COMMON);

open(DIST, join('/', $opt_d, $codename)) || die "Can't open $opt_d/$codename";
debug("Reading distro-specific file");
while (<DIST>) {
    chomp;
    s/^\s+//;
    s/\s+$//;
    next if /^#/;
    next unless /\S/;
    if (/^-(\S+)$/) {
	if (exists($packages{$1})) {
	    debug("Deleting $1 from package list.");
	    delete($packages{$1});
	} else {
	    warn("Package $1 is not in package list, so can't remove it.");
	}
    } elsif (/^\?(\S+)$/) {
	debug("Adding $1 to recommendations");
	$packages{$1} = 2;
    } else {
	debug("Adding $_ to dependencies");
	$packages{$_} = 1;
    }
}
close(DIST);

foreach my $pkgname (sort(keys(%packages))) {
    my $pkg = $cache->{$pkgname};
    if (! $pkg) {
	debug("Removing $pkgname as it can't be found in the APT cache.");
	delete($packages{$pkgname});
	if (exists($depends{$pkgname})) {
	    foreach (@{$depends{$pkgname}}) {
		debug("Removing $_ because we removed $pkgname");
		delete($packages{$_});
	    }
	}
	next;
    }
    if (! $pkg->{VersionList}) {
	debug("Removing $pkgname as it has no version candidate");
	delete($packages{$pkgname});
	if (exists($depends{$pkgname})) {
	    foreach (@{$depends{$pkgname}}) {
		debug("Removing $_ because we removed $pkgname");
		delete($packages{$_});
	    }
	}
	next;
    }
}

debug("Writing out lists");
open(DEPS, '>', join('/', $opt_c, 'dependencies')) || die "Can't open $opt_c/dependencies for writing";
open(RECS, '>', join('/', $opt_c, 'recommendations')) || die "Can't open $opt_c/dependencies for writing";
foreach (sort(keys(%packages))) {
    if ($packages{$_} == 2) {
	print RECS "$_\n";
    } else {
	print DEPS "$_\n";
    }
}
close(DEPS);
close(RECS);
exit 0;
	
