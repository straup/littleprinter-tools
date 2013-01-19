#!/usr/bin/env perl

use strict;
use Imager;

{
    &main();
    exit;
}

sub main {

    my $infile = $ARGV[0];
    my $outfile = $ARGV[1];

    dither($infile, $outfile);
    return 1;
}

sub dither {
    my $infile = shift;
    my $outfile = shift;

    my @threshold = ();
    push @threshold, (0) x 128;
    push @threshold, (255) x 128;

    my $im = Imager->new();
    $im->read(file => $infile);

    $im = $im->convert(preset => 'gray');

    my $height = $im->getheight();
    my $width = $im->getwidth();

    for (my $y=0; $y < $height; $y++){

	for (my $x=0; $x < $width; $x++){

	    my $old = $im->getpixel(x => $x, y => $y);
	    print $old->rgba() . "\n";
	}
    }

    # $im = $im->convert(preset => 'rgba');
    # $im->save($outfile);

}
