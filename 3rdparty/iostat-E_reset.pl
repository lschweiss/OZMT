#!/usr/bin/perl

# Oracle Corp Inc.
#
# This script uses mdb to reset the error counters of a LUN as described in the %types
# hash table below.
#
# This script supports Solaris versions 10 and 11.
#
# The following document is the reference for this script.
# (Doc ID 1012731.1) How to Reset the iostat -E Error Counters Without Rebooting
#
# THIS SCRIPT MODIFIES THE RUNNING KERNEL - USE IS AT YOUR OWN RISK.
#
# Date: 1/8/2014

use strict;
use integer;
use IPC::Open3;

my $mdb = "/usr/bin/mdb";
my $os_rev = `/usr/bin/uname -r`;
my $drv;
my $inst;
my $mdb_resp;
my $soft_state;
my $errstats;
my $ks_data;
my $ks_type;
my %types =
(
 "hard"   => 0,     # Hard Errors
 "illrq"  => 0,     # Illegal Request Errors
 "media"  => 0,     # Media Errors
 "nodev"  => 0,     # No Device Errors
 "ntrdy"  => 0,     # Device Not Ready Errors
 "pfa"    => 0,     # Predictive Failure Analysis Errors
 "recov"  => 0,     # Recoverable Errors
 "soft"   => 0,     # Soft Errors
 "tran"   => 0,     # Transport Errors
 "all"    => 0,     # Reset all of the above
 "io"     => 0      # Reset hard, soft, and tran errors
);
my %trans =
(
 "hard"   => "sd_harderrs",
 "illrq"  => "sd_rq_illrq_err",
 "media"  => "sd_rq_media_err",
 "nodev"  => "sd_rq_nodev_err",
 "ntrdy"  => "sd_rq_ntrdy_err",
 "pfa"    => "sd_rq_pfa_err",
 "recov"  => "sd_rq_recov_err",
 "soft"   => "sd_softerrs",
 "tran"   => "sd_transerrs"
);

chomp($os_rev);

sub usage {
  printf STDERR "Usage: iostat-E_reset.pl <sd|ssd> <instance number> <type> [type]...\n";
  printf STDERR "       type values are hard, illrq, media, nodev, ntrdy, pfa recov, soft, and tran,\n";
  printf STDERR "       type \"all\" can be used to reset all of the above\n";
  printf STDERR "       type \"io\" can be used to reset soft, hard, and tran errors\n";
  exit 22;
}

usage() if @ARGV < 3 or $ARGV[0] !~ /^s?sd$/ or $ARGV[1] !~ /^\d+$/;

$drv = $ARGV[0];  shift;
$inst = $ARGV[0]; shift;

while (@ARGV > 0) {
  usage() if ! defined $types{$ARGV[0]};
  $types{$ARGV[0]} = 1;
  shift;
}

if ($os_rev !~ /^5\.(10|11)/) {
  die "Solaris version $os_rev is not supported.\n";
}

if ($> != 0) {
  die "You must be user root to run this script.\n";
}

open3(*MDB_WRT, *MDB_RD, "", "$mdb -kw") or die "Cannot execute mdb";

print MDB_WRT "*${drv}_state::softstate 0t${inst}\n";
$mdb_resp = <MDB_RD>;
if ($mdb_resp =~ /^(\p{XDigit}+)$/) {
  $soft_state = $1;
} elsif ($mdb_resp =~ /^mdb: instance \p{XDigit}+ unused$/) {
  die "ERROR: Instance $inst is unused\n";
} else {
  print STDERR "ERROR: Reading softstate pointer for instance $inst\n";
  die "        Response: $mdb_resp\n";
}
print MDB_WRT "${soft_state}::print struct sd_lun un_errstats\n";
$mdb_resp = <MDB_RD>;
if ($mdb_resp =~ /^un_errstats = 0x(\p{XDigit}+)$/) {
  $errstats = $1;
} else {
  print STDERR "ERROR: Reading un_errstats pointer for softstate $soft_state\n";
  die "        Response: $mdb_resp\n";
}
print MDB_WRT "${errstats}::print kstat_t ks_data\n";
$mdb_resp = <MDB_RD>;
if ($mdb_resp =~ /^ks_data = 0x(\p{XDigit}+)$/) {
  $ks_data = $1;
} else {
  print STDERR "ERROR: Reading ks_data pointer for un_errstats $errstats softstate $soft_state\n";
  die "        Response: $mdb_resp\n";
}

if ($types{"all"}) {
  foreach my $type (keys %trans) {
    reset_counter($trans{$type});
  }
  exit 0;
}

if ($types{"io"}) {
  $types{"hard"} = 1;
  $types{"soft"} = 1;
  $types{"tran"} = 1;
}

foreach my $type (keys %types) {
  next if $type eq "all";
  next if $type eq "io";
  reset_counter($trans{$type}) if $types{$type};
}
exit 0;

sub reset_counter {
  print MDB_WRT "${ks_data}::print struct sd_errstats $_[0].data_type\n";
  $mdb_resp = <MDB_RD>;
  if ($mdb_resp =~ /^$_[0]\.data_type = (0x\p{XDigit}+)$/) {
    $ks_type = $1;
    if ($ks_type ne "0x2") {
      die "ERROR: Unsupported kstat data type $ks_type for $_[0]\n";
    }
  } else {
    print STDERR "ERROR: Reading data_type value for ks_data $ks_data un_errstats $errstats softstate $soft_state\n";
    die "        Response: $mdb_resp\n";
  }
  print MDB_WRT "${ks_data}::print -a struct sd_errstats $_[0].value.ui32\n";
  $mdb_resp = <MDB_RD>;
  if ($mdb_resp =~ /^(\p{XDigit}+) $_[0]\.value\.ui32 = (?:0x)?(\p{XDigit}+)$/) {
    my $kstat_addr = $1;
    printf("Resetting %-15s for instance %5s, current value 0x%x\n", $_[0], $inst, $2);
    print MDB_WRT "${kstat_addr}/W 0\n";
    $mdb_resp = <MDB_RD>;
    if ($mdb_resp !~ /^0x${kstat_addr}:\s+(?:0x)?\p{XDigit}+\s+=\s+0x0$/) {
      print STDERR "ERROR: Failed to write kstat counter address $kstat_addr,\n";
      print STDERR "       ks_data $ks_data un_errstats $errstats softstate $soft_state\n";
      die "        Response: $mdb_resp\n";
    }
  } else {
    print STDERR "ERROR: Unable to obtain kstat counter address for $_[0] reset,\n";
    print STDERR "       ks_data $ks_data un_errstats $errstats softstate $soft_state\n";
    die "        Response: $mdb_resp\n";
  }
}
