#!/usr/bin/env perl

use strict;
use warnings;
use v5.12;

### TODO: CODE ###
local $, = "\t";
for my $f (@ARGV) {
    open my $fh, '<', $f or die "Couldn't open $f for reading: $!\n";
    my $file = join '', <$fh>;
    say $f, ($file =~ m/(\d+\.\d+) \s* % $/msxg);
}
