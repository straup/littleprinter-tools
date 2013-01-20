#!/usr/bin/env perl

use strict;
use Imager;

use Data::Dumper;

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

	    # http://search.cpan.org/~tonyc/Imager-0.94/lib/Imager/Color.pm

	    my $px = $im->getpixel(x => $x, y => $y, type => '8bit');
	    my @c = $px->rgba();

	    my $old = grayscale(@c);
	    my $new = $threshold[$old];

	    my $err = ($old - $new) >> 3;

	    $im->setpixel(x => $x, y => $y, color => [ $new, $new, $new ]);
	}
    }

    $im->write(file => $outfile);
}

sub grayscale {
    my ($r, $g, $b) = @_;

    # See also:
    # http://www.johndcook.com/blog/2009/08/24/algorithms-convert-color-grayscale/

    my $s = 0.15 * $r + 0.55 * $g + 0.30 * $b;
    return int($s);
}
