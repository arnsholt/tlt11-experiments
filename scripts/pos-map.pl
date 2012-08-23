#!/usr/bin/env perl

use strict;
use warnings;
use v5.12;
use warnings  qw(FATAL utf8);    # fatalize encoding glitches
use open      qw(:std :utf8);    # undeclared streams in UTF-8
use charnames qw(:full :short);  # unneeded in v5.16
use utf8;
use lib qw{interset/lib};

use Getopt::Long;

use tagset::common;
use tagset::da::conll;
use tagset::no::conll;
use tagset::sv::mamba;

my %sources = (
    da => \&tagset::da::conll::decode,
    no => \&tagset::no::conll::decode,
    sv => \&tagset::sv::mamba::decode,
);

my ($source);
my $result = GetOptions('source=s' => \$source);

usage(die => 1) if not $result or not defined $source or not exists $sources{$source};

sub usage {
    my %args = @_;
    say STDERR "Usage: $0 --source=(da|no|sv) FILE";
    exit($args{die} // 0);
}

open my $file, '<', $ARGV[0] or die "Couldn't open $ARGV[0] for reading: $!\n";

local $, = "\t";
while(my $line = <$file>) {
    chomp $line;
    if(not $line) {
        say "";
        next;
    }


    my @fields = split m/\s+/o, $line;
    die "Wrong no. of fields: " . join '/', @fields if @fields != 10;
    my $tag = $sources{$source}->($source ne 'sv'? join ' ', @fields[3, 4, 5] : $fields[3]);
    my $pos = $tag->{pos} // 'undefined';
    my $feats = join '|', map {"$_=$tag->{$_}"} grep {$_ ne 'pos' and $_ ne 'tagset'} keys %$tag;
    $feats ||= '_';
    @fields[3, 4, 5, 7] = ($pos, $pos, $feats, 'dep');
    say @fields;
}
