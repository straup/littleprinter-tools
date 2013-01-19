#!/usr/bin/env perl

use strict;
use Imager;

{
    &main();
    exit;
}

sub main {

    my $infile = $ARGV[1];
    my $im = Imager->new(file => $infile);

}
